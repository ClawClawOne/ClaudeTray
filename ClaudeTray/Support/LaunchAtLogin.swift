import Foundation
import ServiceManagement

/// Enregistrement de l'app comme agent de démarrage via SMAppService.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Renvoie le message d'erreur si l'opération a échoué, nil sinon.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "Lancement au démarrage : \(error.localizedDescription)"
        }
    }
}
