import Foundation
import Security

/// D'où vient le token utilisé pour le dernier appel réussi.
enum TokenSource {
    case manual
    case keychain
    case credentialsFile

    func label(_ loc: Loc) -> String {
        switch self {
        case .manual: return loc.sourceManual
        case .keychain: return loc.sourceKeychain
        case .credentialsFile: return loc.sourceFile
        }
    }
}

struct ResolvedToken {
    let value: String
    let source: TokenSource
}

enum TokenError: Error {
    case notFound
    case keychainDenied(OSStatus)
    case malformed(String)

    func message(_ loc: Loc) -> String {
        switch self {
        case .notFound:
            return loc.errorNoToken
        case .keychainDenied(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "code \(status)"
            return loc.errorKeychainDenied(detail)
        case .malformed(let origin):
            return loc.errorMalformedToken(origin)
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
        let url = Self.manualTokenURL
        guard let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8) else { return nil }

        // Si les droits ont dérivé (copie, restauration de sauvegarde, édition manuelle),
        // on les resserre avant d'utiliser le token plutôt que de faire confiance au fichier.
        if let mode = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber,
           mode.int16Value & 0o077 != 0 {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func writeManualToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = manualTokenURL
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(),
                                    withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        if trimmed.isEmpty {
            try? manager.removeItem(at: url)
            return
        }

        // Le fichier est créé vide en 0600 AVANT d'y écrire quoi que ce soit. Un
        // `write(options: .atomic)` suivi d'un `chmod` laisserait le token lisible par
        // tout le monde pendant l'intervalle entre les deux opérations.
        if !manager.fileExists(atPath: url.path) {
            guard manager.createFile(atPath: url.path,
                                     contents: nil,
                                     attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        } else {
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        // Écriture sans `.atomic` : tronque le fichier existant et conserve donc ses droits.
        try Data(trimmed.utf8).write(to: url)
    }

    static func manualTokenExists() -> Bool {
        FileManager.default.fileExists(atPath: manualTokenURL.path)
    }

    // MARK: - Source 2 : trousseau macOS

    /// Lecture via `/usr/bin/security`, comme le fait Claude Code lui-même. À chaque
    /// rafraîchissement du token, Claude Code réécrit l'item et ramène sa liste de partitions
    /// à `apple-tool:` : un `SecItemCopyMatching` depuis ClaudeTray redemande alors l'accès,
    /// même après « Toujours autoriser ». `security` est dans cette partition et dans les
    /// applications de confiance de l'item : sa lecture reste silencieuse, quelle que soit la
    /// signature de ClaudeTray.
    private func readKeychainToken() throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        // Lecture du pipe en parallèle : l'item dépasse déjà 39 Ko et un pipe plein
        // bloquerait `security` avant sa sortie.
        var data = Data()
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            throw TokenError.keychainDenied(errSecInternalComponent)
        }

        // Si macOS finit par afficher un dialogue malgré tout, la lecture abandonne au bout de
        // 10 s et le cycle de polling suivant réessaie. `UsageStore` résout le token hors du
        // thread principal : l'interface ne se fige pas pendant cette attente.
        if exited.wait(timeout: .now() + 10) == .timedOut {
            process.terminate()
            readDone.wait()
            throw TokenError.keychainDenied(errSecInteractionNotAllowed)
        }
        readDone.wait()

        // `security` sort avec l'octet de poids faible de l'OSStatus : 44 pour errSecItemNotFound.
        switch process.terminationStatus {
        case 0:
            return try Self.accessToken(fromCredentialsJSON: Self.decodeSecurityOutput(data),
                                        origin: "le trousseau")
        case 44:
            return nil
        case 36:
            throw TokenError.keychainDenied(errSecInteractionNotAllowed)
        case 128:
            throw TokenError.keychainDenied(errSecUserCanceled)
        default:
            throw TokenError.keychainDenied(errSecAuthFailed)
        }
    }

    /// Sortie de `security -w` : texte brut, ou hexadécimal sans préfixe dès qu'un octet de l'item
    /// n'est pas imprimable (UTF-8 non ASCII, saut de ligne). Un JSON commence par `{`, qui n'est
    /// pas un chiffre hexadécimal : le texte brut ne peut pas être pris pour de l'hexadécimal.
    private static func decodeSecurityOutput(_ data: Data) -> Data {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count % 2 == 0, text.allSatisfy(\.isHexDigit) else { return data }
        var bytes = [UInt8]()
        bytes.reserveCapacity(text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return data }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
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
