import Foundation

/// Métrique affichée dans la barre de menu.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case fiveHour
    case weekly
    case mostConstrained

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fiveHour: return "Fenêtre 5 h"
        case .weekly: return "Hebdomadaire"
        case .mostConstrained: return "La plus contrainte"
        }
    }
}

enum PreferenceKey {
    static let metric = "menuBarMetric"
    static let showRemaining = "showRemaining"
    static let notificationsEnabled = "notificationsEnabled"
}

enum Thresholds {
    /// Seuils d'alerte, en pourcentage consommé.
    static let warning: Double = 80
    static let critical: Double = 95
    /// Au-delà, les données affichées sont marquées comme périmées.
    static let staleAfter: TimeInterval = 15 * 60
}
