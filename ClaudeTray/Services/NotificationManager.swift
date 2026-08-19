import Foundation
import UserNotifications

/// Notifications locales à 80 % et 95 %, déclenchées **au franchissement** du seuil.
///
/// Règle : une notification part uniquement si le pourcentage était sous le seuil au relevé
/// précédent et l'atteint au relevé courant. Deux notifications au maximum par montée.
///
/// Le déclenchement ne s'appuie pas sur `resets_at` : la fenêtre glissante de 5 h voit sa date
/// de reset avancer à chaque appel, ce qui ré-armait les seuils et renvoyait une notification
/// à chaque rafraîchissement. Le ré-armement vient naturellement de la redescente du
/// pourcentage sous le seuil au reset de la fenêtre.
@MainActor
final class NotificationManager {
    /// Dernier pourcentage observé par fenêtre. Vide au lancement : le premier instantané
    /// sert de référence et ne notifie jamais, même s'il arrive déjà au-dessus d'un seuil.
    private var lastPercent: [UsageWindowID: Double] = [:]
    private var authorizationRequested = false

    func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// À appeler à chaque instantané reçu.
    func evaluate(snapshot: UsageSnapshot, enabled: Bool, loc: Loc) {
        for window in snapshot.windows {
            let current = window.percentUsed
            defer { lastPercent[window.id] = current }
            guard let previous = lastPercent[window.id] else { continue }

            for threshold in [Thresholds.critical, Thresholds.warning] {
                guard previous < threshold, current >= threshold else { continue }
                if enabled {
                    post(window: window, threshold: Int(threshold), loc: loc)
                }
                // Un seul message par montée : le seuil critique prime sur le seuil d'alerte.
                break
            }
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
