import Foundation

/// Métrique affichée dans la barre de menu.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case fiveHour
    case weekly
    case mostConstrained

    var id: String { rawValue }

    /// Intitulé court affiché au-dessus du pourcentage dans la barre de menu.
    var compactLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "Week"
        case .mostConstrained: return "Max"
        }
    }

    var label: String {
        switch self {
        case .fiveHour: return "Fenêtre 5 h"
        case .weekly: return "Hebdomadaire"
        case .mostConstrained: return "La plus contrainte"
        }
    }
}

/// Cadence de rafraîchissement choisie dans les réglages.
enum RefreshInterval: String, CaseIterable, Identifiable {
    case auto
    case minute1
    case minute5
    case minute15
    case minute30
    case hour1

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .minute1: return "1 min"
        case .minute5: return "5 min"
        case .minute15: return "15 min"
        case .minute30: return "30 min"
        case .hour1: return "1 h"
        }
    }

    /// Délai fixe, ou nil en mode auto (cadence adaptée à l'activité de la fenêtre 5 h).
    var seconds: TimeInterval? {
        switch self {
        case .auto: return nil
        case .minute1: return 60
        case .minute5: return 300
        case .minute15: return 900
        case .minute30: return 1800
        case .hour1: return 3600
        }
    }
}

enum PreferenceKey {
    static let metric = "menuBarMetric"
    static let showRemaining = "showRemaining"
    static let showBothWindows = "showBothWindows"
    static let percentColor = "percentColorHex"
    static let refreshInterval = "refreshInterval"
    static let notificationsEnabled = "notificationsEnabled"
}

enum Thresholds {
    /// Seuils d'alerte, en pourcentage consommé.
    static let warning: Double = 80
    static let critical: Double = 95
    /// Au-delà, les données affichées sont marquées comme périmées.
    static let staleAfter: TimeInterval = 15 * 60
}
