import Foundation
import UserNotifications

/// Notifications locales à 80 % et 95 %, une seule fois par fenêtre.
/// Le ré-armement est piloté par `resets_at` : dès que la date de reset change,
/// la fenêtre est considérée comme neuve et les deux seuils redeviennent disponibles.
@MainActor
final class NotificationManager {
    /// Clé = identifiant de fenêtre ; valeur = (reset observé, seuils déjà notifiés).
    private var fired: [UsageWindowID: (reset: Date?, thresholds: Set<Int>)] = [:]
    private var authorizationRequested = false

    func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// À appeler à chaque instantané reçu.
    func evaluate(snapshot: UsageSnapshot, enabled: Bool, loc: Loc) {
        for window in snapshot.windows {
            var state = fired[window.id] ?? (reset: window.resetsAt, thresholds: [])
            if state.reset != window.resetsAt {
                // Nouvelle fenêtre : on ré-arme les deux seuils.
                state = (reset: window.resetsAt, thresholds: [])
            }

            for threshold in [Int(Thresholds.critical), Int(Thresholds.warning)] {
                guard window.percentUsed >= Double(threshold),
                      !state.thresholds.contains(threshold) else { continue }
                state.thresholds.insert(threshold)
                if enabled {
                    post(window: window, threshold: threshold, loc: loc)
                }
            }
            fired[window.id] = state
        }
    }

    private func post(window: UsageWindow, threshold: Int, loc: Loc) {
        let content = UNMutableNotificationContent()
        content.title = loc.notificationTitle(window.title(loc), threshold)
        let relative = RelativeDateTimeFormatter()
        relative.locale = loc.locale
        relative.unitsStyle = .full
        content.body = loc.notificationBody(
            percent: Int(window.percentUsed.rounded()),
            reset: window.resetsAt.map { relative.localizedString(for: $0, relativeTo: Date()) })
        content.sound = .default

        let request = UNNotificationRequest(identifier: "\(window.id.key)-\(threshold)-\(window.resetsAt?.timeIntervalSince1970 ?? 0)",
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
