import Foundation
import Security

/// D'où vient le token utilisé pour le dernier appel réussi.
enum TokenSource: String {
    case manual = "Token manuel"
    case keychain = "Trousseau macOS"
    case credentialsFile = "~/.claude/.credentials.json"

    var detail: String {
        switch self {
        case .manual: return "Application Support/ClaudeTray/token"
        case .keychain: return "service « Claude Code-credentials »"
        case .credentialsFile: return "fichier de credentials Claude Code"
        }
    }
}

struct ResolvedToken {
    let value: String
    let source: TokenSource
}

enum TokenError: LocalizedError {
    case notFound
    case keychainDenied(OSStatus)
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Aucun token trouvé. Colle un token manuel (issu de « claude setup-token ») ou lance Claude Code pour peupler le trousseau."
        case .keychainDenied(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "code \(status)"
            return "Accès au trousseau refusé (\(message)). Autorise ClaudeTray, ou colle un token manuel."
        case .malformed(let where_):
            return "Token illisible depuis \(where_) : structure JSON inattendue."
        }
    }
}

/// Résout le token à chaque appel réseau. Ne met jamais rien en cache :
/// le token du trousseau expire en ~1 h et Claude Code le réécrit tout seul.
struct TokenResolver {

    /// Emplacement du token manuel collé dans l'app.
    static var manualTokenURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ClaudeTray", isDirectory: true)
            .appendingPathComponent("token", isDirectory: false)
    }

    /// Ordre imposé : token manuel, puis trousseau, puis fichier de credentials.
    func resolve() throws -> ResolvedToken {
        var keychainError: TokenError?

        if let manual = readManualToken() {
            return ResolvedToken(value: manual, source: .manual)
        }

        do {
            if let keychain = try readKeychainToken() {
                return ResolvedToken(value: keychain, source: .keychain)
            }
        } catch let error as TokenError {
            keychainError = error
        }

        if let file = try readCredentialsFileToken() {
            return ResolvedToken(value: file, source: .credentialsFile)
        }

        throw keychainError ?? TokenError.notFound
    }

    // MARK: - Source 1 : token manuel

    private func readManualToken() -> String? {
        guard let data = try? Data(contentsOf: Self.manualTokenURL),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func writeManualToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = manualTokenURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        if trimmed.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try Data(trimmed.utf8).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func manualTokenExists() -> Bool {
        FileManager.default.fileExists(atPath: manualTokenURL.path)
    }

    // MARK: - Source 2 : trousseau macOS

    private func readKeychainToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw TokenError.malformed("le trousseau") }
            return try Self.accessToken(fromCredentialsJSON: data, origin: "le trousseau")
        case errSecItemNotFound:
            return nil
        default:
            throw TokenError.keychainDenied(status)
        }
    }

    // MARK: - Source 3 : ~/.claude/.credentials.json

    private func readCredentialsFileToken() throws -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configDir: URL
        if let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !override.isEmpty {
            configDir = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            configDir = home.appendingPathComponent(".claude", isDirectory: true)
        }
        let url = configDir.appendingPathComponent(".credentials.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try Self.accessToken(fromCredentialsJSON: data, origin: url.path)
    }

    // MARK: - Décodage commun

    private struct CredentialsFile: Decodable {
        struct OAuth: Decodable { let accessToken: String? }
        let claudeAiOauth: OAuth?
    }

    private static func accessToken(fromCredentialsJSON data: Data, origin: String) throws -> String {
        guard let decoded = try? JSONDecoder().decode(CredentialsFile.self, from: data),
              let token = decoded.claudeAiOauth?.accessToken,
              !token.isEmpty else {
            throw TokenError.malformed(origin)
        }
        return token
    }
}
