import Foundation

/// Identifiant stable d'une fenêtre de quota renvoyée par l'API.
enum UsageWindowID: String, CaseIterable, Codable {
    case fiveHour = "five_hour"
    case sevenDay = "seven_day"
    case sevenDaySonnet = "seven_day_sonnet"
    case sevenDayOpus = "seven_day_opus"

    var title: String {
        switch self {
        case .fiveHour: return "Fenêtre 5 h"
        case .sevenDay: return "Hebdomadaire"
        case .sevenDaySonnet: return "Hebdo Sonnet"
        case .sevenDayOpus: return "Hebdo Opus"
        }
    }

    /// Ordre d'affichage dans le popover.
    var displayOrder: Int {
        switch self {
        case .fiveHour: return 0
        case .sevenDay: return 1
        case .sevenDaySonnet: return 2
        case .sevenDayOpus: return 3
        }
    }
}

/// Bloc brut renvoyé par l'API pour une fenêtre. Tous les champs peuvent manquer.
struct RawUsageWindow: Decodable {
    let utilization: Double?
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

/// Réponse complète de `GET /api/oauth/usage`. On ne décode que ce qu'on affiche ;
/// les clés inconnues ou nouvelles sont ignorées sans faire échouer le décodage.
struct RawUsageResponse: Decodable {
    let fiveHour: RawUsageWindow?
    let sevenDay: RawUsageWindow?
    let sevenDaySonnet: RawUsageWindow?
    let sevenDayOpus: RawUsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
    }

    /// Vrai si l'API n'a renvoyé aucune des fenêtres attendues : signe que le schéma a changé.
    var hasNoKnownWindow: Bool {
        fiveHour == nil && sevenDay == nil && sevenDaySonnet == nil && sevenDayOpus == nil
    }
}

/// Une fenêtre prête à l'affichage : pourcentage normalisé 0–100 et date de reset telle quelle.
struct UsageWindow: Identifiable, Equatable {
    let id: UsageWindowID
    let percentUsed: Double
    let resetsAt: Date?

    var title: String { id.title }
    var percentRemaining: Double { max(0, 100 - percentUsed) }
}

/// Instantané cohérent de l'usage, daté de sa réception.
struct UsageSnapshot: Equatable {
    let windows: [UsageWindow]
    let fetchedAt: Date

    func window(_ id: UsageWindowID) -> UsageWindow? {
        windows.first { $0.id == id }
    }

    /// La fenêtre la plus contrainte entre 5 h et hebdo global.
    var mostConstrained: UsageWindow? {
        [window(.fiveHour), window(.sevenDay)]
            .compactMap { $0 }
            .max { $0.percentUsed < $1.percentUsed }
    }

    init(raw: RawUsageResponse, fetchedAt: Date) {
        let pairs: [(UsageWindowID, RawUsageWindow?)] = [
            (.fiveHour, raw.fiveHour),
            (.sevenDay, raw.sevenDay),
            (.sevenDaySonnet, raw.sevenDaySonnet),
            (.sevenDayOpus, raw.sevenDayOpus),
        ]
        self.windows = pairs.compactMap { id, raw in
            guard let raw, let normalized = Utilization.normalize(raw.utilization) else { return nil }
            return UsageWindow(id: id, percentUsed: normalized, resetsAt: raw.resetsAt)
        }
        .sorted { $0.id.displayOrder < $1.id.displayOrder }
        self.fetchedAt = fetchedAt
    }

    init(windows: [UsageWindow], fetchedAt: Date) {
        self.windows = windows
        self.fetchedAt = fetchedAt
    }
}

/// Seul endroit du code qui décide de l'échelle de `utilization`.
///
/// Vérifié sur l'API le 2026-08-18 : les valeurs sortent déjà en 0–100 (`31.0`, `33.0`).
/// Décision assumée : aucune heuristique 0–1 vs 0–100. Une bascule automatique du type
/// « si valeur ≤ 1 alors ×100 » afficherait 100 % pour un usage réel de 1 %, c'est-à-dire
/// une fausse alerte maximale dans le cas le plus fréquent. Si l'API repasse un jour en
/// 0–1, décommenter la ligne indiquée ci-dessous : c'est le seul changement à faire.
enum Utilization {
    static func normalize(_ raw: Double?) -> Double? {
        guard let raw, raw.isFinite else { return nil }
        // let raw = raw * 100  // à décommenter si l'API repasse en échelle 0–1
        return min(max(raw, 0), 100)
    }
}
