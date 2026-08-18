import AppKit
import Combine
import Foundation

/// État observable de l'app : dernier instantané valide, erreur courante, cadence de polling.
///
/// Règle centrale : le dernier instantané valide reste affiché quoi qu'il arrive.
/// Une erreur n'efface jamais les données, elle ajoute un message et un marqueur d'obsolescence.
@MainActor
final class UsageStore: ObservableObject {

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var tokenSource: TokenSource?
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isPaused = false
    /// Horloge locale du compte à rebours : avance chaque seconde, sans appel réseau.
    @Published private(set) var now = Date()

    @Published var metric: MenuBarMetric {
        didSet { defaults.set(metric.rawValue, forKey: PreferenceKey.metric) }
    }
    @Published var showRemaining: Bool {
        didSet { defaults.set(showRemaining, forKey: PreferenceKey.showRemaining) }
    }
    @Published var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: PreferenceKey.notificationsEnabled)
            if notificationsEnabled { notifications.requestAuthorizationIfNeeded() }
        }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != LaunchAtLogin.isEnabled else { return }
            if let error = LaunchAtLogin.setEnabled(launchAtLogin) {
                errorMessage = error
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        }
    }
    /// Vrai si un token manuel est actuellement enregistré.
    @Published private(set) var hasManualToken = TokenResolver.manualTokenExists()

    private let client = UsageAPIClient()
    private let notifications = NotificationManager()
    private let defaults = UserDefaults.standard
    private var pollTask: Task<Void, Never>?
    private var tickTimer: Timer?
    private var consecutiveFailures = 0
    private var pendingRetryAfter: TimeInterval?

    // Cadences imposées par l'endpoint : il renvoie des 429 persistants s'il est sollicité trop souvent.
    private let activeInterval: TimeInterval = 90
    private let idleInterval: TimeInterval = 7 * 60
    private let maxBackoff: TimeInterval = 30 * 60

    init() {
        let storedMetric = defaults.string(forKey: PreferenceKey.metric) ?? MenuBarMetric.mostConstrained.rawValue
        metric = MenuBarMetric(rawValue: storedMetric) ?? .mostConstrained
        showRemaining = defaults.bool(forKey: PreferenceKey.showRemaining)
        notificationsEnabled = defaults.object(forKey: PreferenceKey.notificationsEnabled) as? Bool ?? true
        launchAtLogin = LaunchAtLogin.isEnabled

        observeSystemEvents()
        startTicking()
        if notificationsEnabled { notifications.requestAuthorizationIfNeeded() }
        startPolling()
    }

    // MARK: - Données dérivées

    /// Fenêtre utilisée pour l'affichage compact de la barre de menu.
    var menuBarWindow: UsageWindow? {
        guard let snapshot else { return nil }
        switch metric {
        case .fiveHour: return snapshot.window(.fiveHour)
        case .weekly: return snapshot.window(.sevenDay)
        case .mostConstrained: return snapshot.mostConstrained
        }
    }

    var isStale: Bool {
        guard let lastSuccess else { return snapshot != nil }
        return now.timeIntervalSince(lastSuccess) > Thresholds.staleAfter
    }

    /// Durée écoulée depuis le dernier succès, pour le marqueur « obsolète depuis X ».
    var staleFor: TimeInterval? {
        guard let lastSuccess, isStale else { return nil }
        return now.timeIntervalSince(lastSuccess)
    }

    // MARK: - Polling

    func refreshNow() {
        guard !isRefreshing else { return }
        consecutiveFailures = 0
        pendingRetryAfter = nil
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        isPaused = false
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.fetchOnce()
                let delay = self.nextDelay()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func suspendPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPaused = true
    }

    private func fetchOnce() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let (snapshot, source) = try await client.fetch()
            self.snapshot = snapshot
            self.tokenSource = source
            self.lastSuccess = snapshot.fetchedAt
            self.errorMessage = nil
            self.consecutiveFailures = 0
            self.pendingRetryAfter = nil
            self.hasManualToken = TokenResolver.manualTokenExists()
            notifications.evaluate(snapshot: snapshot, enabled: notificationsEnabled)
        } catch let error as UsageAPIError {
            consecutiveFailures += 1
            pendingRetryAfter = error.serverRetryAfter
            errorMessage = error.errorDescription
        } catch {
            consecutiveFailures += 1
            pendingRetryAfter = nil
            errorMessage = error.localizedDescription
        }
    }

    /// Cadence normale selon l'activité de la fenêtre 5 h, backoff exponentiel après échec,
    /// et `Retry-After` prioritaire s'il est plus long que le délai calculé.
    private func nextDelay() -> TimeInterval {
        let base: TimeInterval
        if let fiveHour = snapshot?.window(.fiveHour), fiveHour.percentUsed > 0 {
            base = activeInterval
        } else {
            base = idleInterval
        }

        guard consecutiveFailures > 0 else { return base }

        let exponential = activeInterval * pow(2, Double(consecutiveFailures - 1))
        let backoff = min(exponential, maxBackoff)
        return min(max(backoff, pendingRetryAfter ?? 0), maxBackoff)
    }

    // MARK: - Token manuel

    func saveManualToken(_ token: String) {
        do {
            try TokenResolver.writeManualToken(token)
            hasManualToken = TokenResolver.manualTokenExists()
            refreshNow()
        } catch {
            errorMessage = "Écriture du token manuel impossible : \(error.localizedDescription)"
        }
    }

    func clearManualToken() {
        saveManualToken("")
    }

    // MARK: - Horloge et événements système

    private func startTicking() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    /// Le polling s'arrête en veille et écran verrouillé ; il reprend par un appel immédiat.
    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        let sleepEvents: [NSNotification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        let wakeEvents: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in sleepEvents {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspendPolling() }
            }
        }
        for name in wakeEvents {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshNow() }
            }
        }

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspendPolling() }
        }
        distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
    }
}
