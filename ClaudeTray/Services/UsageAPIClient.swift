import Foundation

enum UsageAPIError: Error {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case unexpectedSchema
    case http(status: Int)
    case network(String)
    case token(TokenError)

    func message(_ loc: Loc) -> String {
        switch self {
        case .unauthorized:
            return loc.errorUnauthorized
        case .rateLimited(let retryAfter):
            return loc.errorRateLimited(retryAfter.map { Int($0.rounded()) })
        case .unexpectedSchema:
            return loc.errorUnexpectedSchema
        case .http(let status):
            return loc.errorHTTP(status)
        case .network(let detail):
            return loc.errorNetwork(detail)
        case .token(let error):
            return error.message(loc)
        }
    }

    /// Délai imposé par le serveur, s'il en a donné un.
    var serverRetryAfter: TimeInterval? {
        if case .rateLimited(let retryAfter) = self { return retryAfter }
        return nil
    }
}

/// Seule sortie réseau de l'application. Aucune autre requête, aucune télémétrie.
struct UsageAPIClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Header beta obligatoire : sans lui l'endpoint répond 401.
    private static let betaHeader = "oauth-2025-04-20"

    private let session: URLSession
    private let resolver = TokenResolver()

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    /// Un appel = une résolution de token. Le token du trousseau expire en ~1 h,
    /// il ne doit jamais être conservé en mémoire entre deux appels.
    func fetch() async throws -> (snapshot: UsageSnapshot, source: TokenSource) {
        let token: ResolvedToken
        do {
            token = try resolver.resolve()
        } catch let error as TokenError {
            throw UsageAPIError.token(error)
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("ClaudeTray", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageAPIError.unexpectedSchema
        }

        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw UsageAPIError.unauthorized
        case 429:
            throw UsageAPIError.rateLimited(retryAfter: Self.retryAfter(from: http))
        default:
            throw UsageAPIError.http(status: http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeISODate)

        guard let raw = try? decoder.decode(RawUsageResponse.self, from: data), !raw.hasNoKnownWindow else {
            throw UsageAPIError.unexpectedSchema
        }

        return (UsageSnapshot(raw: raw, fetchedAt: Date()), token.source)
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)) { return seconds }
        // Variante HTTP-date du header.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: header) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }

    /// `resets_at` arrive tantôt sans fraction de seconde, tantôt avec 6 décimales.
    /// Les deux doivent passer, sinon le décodage casse au hasard des réponses.
    /// Les formateurs sont créés à la volée : deux dates par appel réseau, aucun état partagé.
    @Sendable
    static func decodeISODate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        if let date = withFraction.date(from: string) ?? plain.date(from: string) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container,
                                               debugDescription: "Date ISO 8601 non reconnue : \(string)")
    }
}
