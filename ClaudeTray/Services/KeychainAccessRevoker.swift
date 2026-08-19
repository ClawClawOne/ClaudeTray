import Foundation
import Security

/// Retire ClaudeTray de la liste d'applications de confiance de l'item de trousseau
/// `Claude Code-credentials`, c'est-à-dire annule le « Toujours autoriser » accordé une fois
/// pour toutes par l'utilisateur.
///
/// Il n'existe aucun équivalent moderne : `SecItem*` sait lire et écrire un item, pas modifier
/// sa liste de confiance. Seule l'API `SecKeychain`, dépréciée depuis 10.10 mais toujours
/// fonctionnelle sur le trousseau de session, permet cette opération — d'où les avertissements
/// de dépréciation à la compilation de ce fichier, qui sont attendus.
///
/// Prudence imposée : l'item appartient à Claude Code. On ne retire QUE les entrées qui
/// désignent ClaudeTray, jamais les autres, et on n'écrit rien s'il n'y a rien à retirer.
enum KeychainAccessRevoker {

    enum Outcome {
        /// Nombre d'entrées de confiance retirées.
        case revoked(Int)
        case nothingToRevoke
        case failed(OSStatus)
    }

    static let service = "Claude Code-credentials"

    /// Chemins considérés comme « nous » : le bundle courant, plus les builds de développement
    /// du même nom laissés dans DerivedData par les compilations successives.
    static func isSelf(_ path: String) -> Bool {
        let bundle = Bundle.main.bundlePath
        if path == bundle || path.hasPrefix(bundle + "/") { return true }
        return path.hasSuffix("/ClaudeTray.app")
    }

    static func revokeSelf() -> Outcome {
        revoke(matching: isSelf)
    }

    /// `matching` reçoit le chemin de chaque application de confiance et décide de son retrait.
    static func revoke(matching shouldRemove: (String) -> Bool) -> Outcome {
        var item: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        let found = SecItemCopyMatching(query as CFDictionary, &item)
        // Pas d'item : rien à révoquer, ce n'est pas une erreur.
        if found == errSecItemNotFound { return .nothingToRevoke }
        guard found == errSecSuccess, let ref = item else { return .failed(found) }
        let keychainItem = ref as! SecKeychainItem

        var access: SecAccess?
        let accessStatus = SecKeychainItemCopyAccess(keychainItem, &access)
        guard accessStatus == errSecSuccess, let access else { return .failed(accessStatus) }

        var list: CFArray?
        let listStatus = SecAccessCopyACLList(access, &list)
        guard listStatus == errSecSuccess, let acls = list as? [SecACL] else { return .failed(listStatus) }

        var removed = 0
        for acl in acls {
            var applications: CFArray?
            var description: CFString?
            var prompt = SecKeychainPromptSelector()
            let contents = SecACLCopyContents(acl, &applications, &description, &prompt)
            guard contents == errSecSuccess,
                  let trusted = applications as? [SecTrustedApplication] else { continue }

            let kept = trusted.filter { !shouldRemove(path(of: $0) ?? "") }
            guard kept.count != trusted.count else { continue }

            let status = SecACLSetContents(acl, kept as CFArray, description ?? "" as CFString, prompt)
            guard status == errSecSuccess else { return .failed(status) }
            removed += trusted.count - kept.count
        }

        guard removed > 0 else { return .nothingToRevoke }

        // L'écriture peut demander le mot de passe de session : changer la liste de confiance
        // d'un item est une opération plus sensible que le lire.
        let saved = SecKeychainItemSetAccess(keychainItem, access)
        guard saved == errSecSuccess else { return .failed(saved) }
        return .revoked(removed)
    }

    /// Le blob renvoyé par `SecTrustedApplicationCopyData` commence par le chemin de
    /// l'application, terminé par un octet nul, suivi de données de signature.
    private static func path(of application: SecTrustedApplication) -> String? {
        var data: CFData?
        guard SecTrustedApplicationCopyData(application, &data) == errSecSuccess,
              let bytes = data as Data? else { return nil }
        let head = bytes.prefix(while: { $0 != 0 })
        let path = String(decoding: head, as: UTF8.self)
        return path.isEmpty ? nil : path
    }
}
