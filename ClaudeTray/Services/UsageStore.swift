import AppKit
import Security
import SwiftUI
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
    /// Erreur réseau courante, retraduite à la volée quand la langue change.
    @Published private(set) var lastError: UsageAPIError?
    /// Erreur locale (écriture du token, lancement au démarrage), stockée sous forme de closure
    /// pour être elle aussi retraduite si la langue change.
    @Published private var localError: ((Loc) -> String)?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isPaused = false
    /// Horloge locale du compte à rebours : avance chaque seconde, sans appel réseau.
    @Published private(set) var now = Date()

    /// Langue de l'interface. `system` suit macOS.
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: PreferenceKey.language) }
    }
    @Published var metric: MenuBarMetric {
        didSet { defaults.set(metric.rawValue, forKey: PreferenceKey.metric) }
    }
    @Published var showRemaining: Bool {
        didSet { defaults.set(showRemaining, forKey: PreferenceKey.showRemaining) }
    }
    /// Marge ajoutée à gauche et à droite du contenu de la barre de menu.
    @Published var edgeMargin: Double {
        didSet { defaults.set(edgeMargin, forKey: PreferenceKey.edgeMargin) }
    }
    /// Affichage du logo Claude dans la barre de menu.
    @Published var showLogo: Bool {
        didSet { defaults.set(showLogo, forKey: PreferenceKey.showLogo) }
    }
    /// Espacement entre les éléments de la barre de menu, en points.
    @Published var itemSpacing: Double {
        didSet { defaults.set(itemSpacing, forKey: PreferenceKey.itemSpacing) }
    }
    /// Cadence de rafraîchissement. Le changement est appliqué sans déclencher
    /// d'appel immédiat : le prochain appel est replanifié à partir du dernier.
    @Published var refreshInterval: RefreshInterval {
        didSet {
            defaults.set(refreshInterval.rawValue, forKey: PreferenceKey.refreshInterval)
            reschedule()
        }
    }
    /// Couleur des pourcentages sous les seuils d'alerte.
    @Published var percentColor: Color {
        didSet { defaults.set(ColorStorage.hex(from: percentColor), forKey: PreferenceKey.percentColor) }
    }
    /// Barre de menu : les deux fenêtres côte à côte, ou la seule métrique choisie.
    @Published var showBothWindows: Bool {
        didSet { defaults.set(showBothWindows, forKey: PreferenceKey.showBothWindows) }
    }
    @Published var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: PreferenceKey.notificationsEnabled)
            if notificationsEnabled { notifications.requestAuthorizationIfNeeded() }
        }
    }
    /// Vérification quotidienne des mises à jour sur GitHub. Deuxième destination sortante,
    /// donc explicitement débrayable.
    @Published var updateCheckEnabled: Bool {
        didSet {
            defaults.set(updateCheckEnabled, forKey: PreferenceKey.updateCheckEnabled)
            if updateCheckEnabled {
                checkForUpdates(force: true)
            } else {
                updateOutcome = nil
                showsCheckVerdict = false
            }
        }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != LaunchAtLogin.isEnabled else { return }
            if let error = LaunchAtLogin.setEnabled(launchAtLogin) {
                localError = { $0.errorLaunchAtLogin(error) }
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        }
    }
    /// Issue de la dernière vérification de version.
    @Published private(set) var updateOutcome: UpdateChecker.Outcome?
    /// Vérification de version en cours, pour le retour visuel du bouton manuel.
    @Published private(set) var isCheckingUpdate = false
    /// Vrai quand la dernière vérification a été demandée à la main : seule celle-là
    /// mérite un verdict écrit, une vérification automatique reste discrète.
    @Published private(set) var showsCheckVerdict = false
    /// Délai avant la prochaine tentative, tel qu'il vient d'être planifié.
    @Published private(set) var nextRetryDelay: TimeInterval?
    /// Message court affiché après une action locale (révocation), effacé au prochain succès.
    @Published private(set) var notice: ((Loc) -> String)?
    /// Vrai si un token manuel est actuellement enregistré.
    @Published private(set) var hasManualToken = TokenResolver.manualTokenExists()

    private let client = UsageAPIClient()
    private let notifications = NotificationManager()
    private let defaults = UserDefaults.standard
    private var pollTask: Task<Void, Never>?
    private var tickTimer: Timer?
    private var consecutiveFailures = 0
    private var lastAttempt: Date?
    private var pendingRetryAfter: TimeInterval?

    // Plafond du backoff : au-delà, l'app cesserait d'être utile.
    private let maxBackoff: TimeInterval = 30 * 60

    init() {
        language = AppLanguage(rawValue: defaults.string(forKey: PreferenceKey.language) ?? "") ?? .system
        let storedMetric = defaults.string(forKey: PreferenceKey.metric) ?? MenuBarMetric.mostConstrained.rawValue
        metric = MenuBarMetric(rawValue: storedMetric) ?? .mostConstrained
        showRemaining = defaults.bool(forKey: PreferenceKey.showRemaining)
        showBothWindows = defaults.object(forKey: PreferenceKey.showBothWindows) as? Bool ?? true
        edgeMargin = defaults.object(forKey: PreferenceKey.edgeMargin) as? Double
            ?? MenuBarLayout.defaultEdgeMargin
        showLogo = defaults.object(forKey: PreferenceKey.showLogo) as? Bool ?? true
        itemSpacing = defaults.object(forKey: PreferenceKey.itemSpacing) as? Double
            ?? MenuBarLayout.defaultSpacing
        // Les anciennes valeurs « auto » et « 1 min » n'existent plus : elles retombent sur 5 min,
        // la cadence la plus rapide que l'endpoint accepte sans renvoyer des 429 en série.
        refreshInterval = RefreshInterval(rawValue: defaults.string(forKey: PreferenceKey.refreshInterval) ?? "")
            ?? .minute5
        percentColor = ColorStorage.color(fromHex: defaults.string(forKey: PreferenceKey.percentColor))
            ?? ColorStorage.defaultPercentColor
        notificationsEnabled = defaults.object(forKey: PreferenceKey.notificationsEnabled) as? Bool ?? true
        updateCheckEnabled = defaults.object(forKey: PreferenceKey.updateCheckEnabled) as? Bool ?? true
        launchAtLogin = LaunchAtLogin.isEnabled

        observeSystemEvents()
        startTicking()
        if notificationsEnabled { notifications.requestAuthorizationIfNeeded() }
        startPolling()
        checkForUpdates()
    }

    /// Toutes les chaînes de l'interface, dans la langue courante.
    var loc: Loc { Loc(language) }

    /// Message d'erreur affiché, ou nil s'il n'y en a pas.
    var errorMessage: String? {
        if let lastError {
            // Sur un 429, on affiche le délai réellement appliqué, pas le `Retry-After` brut :
            // le serveur renvoie parfois 0, alors que le backoff impose bien plus.
            if case .rateLimited = lastError, let delay = nextRetryDelay {
                return loc.errorRateLimitedIn(UsageFormatting.shortDuration(delay, loc: loc))
            }
            return lastError.message(loc)
        }
        return localError?(loc)
    }

    /// Vrai dès qu'un message d'erreur est affichable : la barre de menu le signale par un
    /// pictogramme, pour ne pas obliger à ouvrir le popover pour savoir que ça coince.
    var hasError: Bool { errorMessage != nil }

    /// Message informatif (non fautif) affiché sous les erreurs.
    var noticeMessage: String? { notice?(loc) }

    /// Version plus récente détectée, sinon nil.
    var availableUpdate: (version: String, url: URL)? {
        if case .newer(let version, let url) = updateOutcome { return (version, url) }
        return nil
    }

    /// Verdict écrit d'une vérification demandée à la main : « à jour » ou « impossible ».
    var updateVerdict: String? {
        guard showsCheckVerdict else { return nil }
        switch updateOutcome {
        case .upToDate: return loc.upToDate(appVersion)
        case .failed: return loc.updateCheckFailed
        default: return nil
        }
    }

    /// Version compilée, affichée dans l'en-tête du popover.
    var appVersion: String { UpdateChecker.currentVersion }

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

    /// Fenêtres limitées à un modèle, dans l'ordre renvoyé par l'API.
    var scopedWindows: [UsageWindow] {
        (snapshot?.windows ?? []).filter { window in
            if case .scopedWeekly = window.id { return true }
            return false
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

    private func startPolling(initialDelay: TimeInterval = 0) {
        pollTask?.cancel()
        isPaused = false
        pollTask = Task { [weak self] in
            var delay = initialDelay
            while !Task.isCancelled {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    if Task.isCancelled { return }
                }
                guard let self else { return }
                await self.fetchOnce()
                delay = self.nextDelay()
            }
        }
    }

    /// Replanifie sans rappeler l'API tout de suite : on décompte depuis la dernière tentative.
    private func reschedule() {
        guard !isPaused else { return }
        let elapsed = lastAttempt.map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        startPolling(initialDelay: max(0, nextDelay() - elapsed))
    }

    private func suspendPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPaused = true
    }

    private func fetchOnce() async {
        lastAttempt = Date()
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            // La source est publiée dès la résolution : après un 401 sur un token manuel,
            // le popover doit dire « token manuel », pas la source du dernier succès.
            let token = try client.resolveToken()
            self.tokenSource = token.source
            let snapshot = try await client.fetch(using: token)
            self.snapshot = snapshot
            self.lastSuccess = snapshot.fetchedAt
            self.lastError = nil
            self.localError = nil
            self.notice = nil
            self.consecutiveFailures = 0
            self.pendingRetryAfter = nil
            self.nextRetryDelay = nil
            self.hasManualToken = TokenResolver.manualTokenExists()
            notifications.evaluate(snapshot: snapshot, enabled: notificationsEnabled, loc: loc)
            checkForUpdates()
        } catch let error as UsageAPIError {
            consecutiveFailures += 1
            pendingRetryAfter = error.serverRetryAfter
            lastError = error
            nextRetryDelay = nextDelay()
            if case .token = error { tokenSource = nil }
            hasManualToken = TokenResolver.manualTokenExists()
        } catch {
            consecutiveFailures += 1
            pendingRetryAfter = nil
            lastError = .network(error.localizedDescription)
            nextRetryDelay = nextDelay()
        }
    }

    /// Cadence normale selon l'activité de la fenêtre 5 h, backoff exponentiel après échec,
    /// et `Retry-After` prioritaire s'il est plus long que le délai calculé.
    private func nextDelay() -> TimeInterval {
        let base = refreshInterval.seconds

        guard consecutiveFailures > 0 else { return base }

        let exponential = base * pow(2, Double(consecutiveFailures - 1))
        let backoff = min(exponential, maxBackoff)
        return min(max(backoff, pendingRetryAfter ?? 0), maxBackoff)
    }

    // MARK: - Mises à jour

    /// Interroge GitHub au plus une fois par 24 h, sauf `force` (réglage réactivé).
    /// La date du dernier essai est persistée pour ne pas repartir à zéro à chaque lancement.
    func checkForUpdates(force: Bool = false) {
        // Le bouton manuel passe outre le réglage : demander explicitement une vérification
        // vaut consentement pour cette requête-là, sans la réactiver en permanence.
        guard updateCheckEnabled || force else { return }
        if !force, let last = defaults.object(forKey: PreferenceKey.lastUpdateCheck) as? Date,
           Date().timeIntervalSince(last) < UpdateChecker.interval { return }
        guard !isCheckingUpdate else { return }
        defaults.set(Date(), forKey: PreferenceKey.lastUpdateCheck)
        isCheckingUpdate = true
        showsCheckVerdict = false
        Task { @MainActor [weak self] in
            let outcome = await UpdateChecker.check()
            guard let self else { return }
            self.isCheckingUpdate = false
            // Réglage coupé pendant la requête : on ne réaffiche rien, sauf si la vérification
            // avait été demandée à la main.
            guard self.updateCheckEnabled || force else { return }
            self.updateOutcome = outcome
            self.showsCheckVerdict = force
        }
    }

    // MARK: - Token manuel

    func saveManualToken(_ token: String) {
        do {
            try TokenResolver.writeManualToken(token)
            hasManualToken = TokenResolver.manualTokenExists()
            refreshNow()
        } catch {
            let detail = error.localizedDescription
            localError = { $0.errorManualTokenWrite(detail) }
        }
    }

    func clearManualToken() {
        saveManualToken("")
    }

    /// Remet la configuration du token à zéro : suppression du token manuel, puis retrait de
    /// ClaudeTray de la liste de confiance de l'item de trousseau. Le prochain appel redemande
    /// donc l'autorisation, comme au premier lancement.
    func revokeToken() {
        try? TokenResolver.writeManualToken("")
        hasManualToken = TokenResolver.manualTokenExists()

        switch KeychainAccessRevoker.revokeSelf() {
        case .revoked(let count):
            notice = { $0.revokeDone(count) }
            localError = nil
        case .nothingToRevoke:
            notice = { $0.revokeNothing }
            localError = nil
        case .failed(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "code \(status)"
            notice = nil
            localError = { $0.revokeFailed(detail) }
        }

        tokenSource = nil
        refreshNow()
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
