import Foundation

/// Identifiant stable d'une fenêtre de quota.
///
/// Les fenêtres par modèle (`weekly_scoped` dans `limits`) portent le nom que l'API
/// leur donne — « Fable », « Opus »… — et ne peuvent donc pas être une liste figée.
enum UsageWindowID: Hashable {
    case fiveHour
    case sevenDay
    case sevenDaySonnet
    case sevenDayOpus
    /// Fenêtre hebdomadaire limitée à un modèle, désigné par son nom d'affichage.
    case scopedWeekly(String)

    /// Clé stable, utilisée pour les identifiants de notification.
    var key: String {
        switch self {
        case .fiveHour: return "five_hour"
        case .sevenDay: return "seven_day"
        case .sevenDaySonnet: return "seven_day_sonnet"
        case .sevenDayOpus: return "seven_day_opus"
        case .scopedWeekly(let model): return "weekly_scoped_\(model)"
        }
    }

    func title(_ loc: Loc) -> String {
        switch self {
        case .fiveHour: return loc.metricFiveHour
        case .sevenDay: return loc.metricWeekly
        case .sevenDaySonnet: return loc.weeklyModel("Sonnet")
        case .sevenDayOpus: return loc.weeklyModel("Opus")
        case .scopedWeekly(let model): return loc.weeklyModel(model)
        }
    }

    /// Intitulé de la barre de menu, en capitales.
    var compactTitle: String {
        switch self {
        case .fiveHour: return "5H"
        case .sevenDay: return "WEEK"
        case .sevenDaySonnet: return "SONNET"
        case .sevenDayOpus: return "OPUS"
        case .scopedWeekly(let model): return model.uppercased()
        }
    }

    /// Ordre d'affichage dans le popover.
    var displayOrder: Int {
        switch self {
        case .fiveHour: return 0
        case .sevenDay: return 1
        case .scopedWeekly: return 2
        case .sevenDaySonnet: return 3
        case .sevenDayOpus: return 4
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

/// Une entrée du tableau `limits`, seule source des fenêtres par modèle.
struct RawLimit: Decodable {
    struct Scope: Decodable {
        struct Model: Decodable {
            let displayName: String?
            enum CodingKeys: String, CodingKey { case displayName = "display_name" }
        }
        let model: Model?
    }

    let kind: String?
    let percent: Double?
    let resetsAt: Date?
    let scope: Scope?

    enum CodingKeys: String, CodingKey {
        case kind, percent, scope
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
    let limits: [RawLimit]?

    enum CodingKeys: String, CodingKey {
        case limits
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

    func title(_ loc: Loc) -> String { id.title(loc) }
    var percentRemaining: Double { max(0, 100 - percentUsed) }
}

/// Instantané cohérent de l'usage, daté de sa réception.
struct UsageSnapshot: Equatable {
    let windows: [UsageWindow]
    let fetchedAt: Date

    func window(_ id: UsageWindowID) -> UsageWindow? {
        windows.first { $0.id == id }
    }

    /// Première fenêtre limitée à un modèle donné, insensible à la casse.
    func scopedWindow(named model: String) -> UsageWindow? {
        windows.first { window in
            if case .scopedWeekly(let name) = window.id {
                return name.caseInsensitiveCompare(model) == .orderedSame
            }
            return false
        }
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
        var windows: [UsageWindow] = pairs.compactMap { id, raw in
            guard let raw, let normalized = Utilization.normalize(raw.utilization) else { return nil }
            return UsageWindow(id: id, percentUsed: normalized, resetsAt: raw.resetsAt)
        }

        // Fenêtres par modèle : elles n'existent que dans `limits`, sous `weekly_scoped`.
        for limit in raw.limits ?? [] where limit.kind == "weekly_scoped" {
            guard let model = limit.scope?.model?.displayName, !model.isEmpty,
                  let normalized = Utilization.normalize(limit.percent) else { continue }
            let id = UsageWindowID.scopedWeekly(model)
            guard !windows.contains(where: { $0.id == id }) else { continue }
            windows.append(UsageWindow(id: id, percentUsed: normalized, resetsAt: limit.resetsAt))
        }

        self.windows = windows.sorted { $0.id.displayOrder < $1.id.displayOrder }
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
