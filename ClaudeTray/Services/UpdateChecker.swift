import Foundation

/// Vérification quotidienne d'une nouvelle version publiée sur GitHub.
///
/// Deuxième et dernière destination sortante de l'app, après `api.anthropic.com`.
/// Requête anonyme, une fois par 24 h au plus, désactivable dans les réglages :
/// aucune donnée d'usage, aucun identifiant, aucun paramètre n'est envoyé.
enum UpdateChecker {
    /// Endpoint public des releases. Le dépôt est le seul recours pour connaître la
    /// dernière version : l'app ne dispose d'aucun serveur.
    private static let endpoint = URL(string: "https://api.github.com/repos/ClawClawOne/ClaudeTray/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/ClawClawOne/ClaudeTray/releases/latest")!
    static let interval: TimeInterval = 24 * 60 * 60

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    /// Version compilée, telle qu'elle apparaît dans `Info.plist`.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Issue d'une vérification. « Échec » et « à jour » étaient autrefois confondus dans un
    /// même `nil`, ce qui faisait annoncer « ClaudeTray est à jour » alors que la requête
    /// n'avait tout simplement pas abouti.
    enum Outcome: Equatable {
        case upToDate
        case newer(version: String, url: URL)
        case failed
    }

    static func check() async -> Outcome {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeTray/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .ephemeral)
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data) else { return .failed }

        let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        guard isNewer(latest, than: currentVersion) else { return .upToDate }
        let url = release.htmlURL.flatMap(URL.init(string:)) ?? releasesPage
        return .newer(version: latest, url: url)
    }

    /// Comparaison numérique composant par composant : « 1.10 » est plus récent que « 1.9 ».
    static func isNewer(_ candidate: String, than reference: String) -> Bool {
        let lhs = components(candidate)
        let rhs = components(reference)
        guard !lhs.isEmpty else { return false }
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").compactMap { Int($0.prefix(while: \.isNumber)) }
    }
}
