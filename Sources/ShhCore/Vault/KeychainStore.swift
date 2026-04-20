import Foundation
import LocalAuthentication
import Security

/// Low-level Keychain operations for the vault.
///
/// Secrets are stored as generic passwords under a single service
/// (`com.avirumapps.shh`). Preferred path is biometric-gated via
/// `kSecAttrAccessControl` + `.biometryCurrentSet`. If that fails with
/// `errSecMissingEntitlement` (-34018) — which happens in ad-hoc-signed
/// dev builds that lack the `keychain-access-groups` entitlement — the
/// code falls back to plain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// so the item still lands in the login Keychain, just without Touch ID
/// gating. Release builds signed with Developer ID + the proper access
/// group hit the biometric path and behave as designed.
public final class KeychainStore: @unchecked Sendable {
    public let service: String
    public let reuseDuration: TimeInterval

    public init(service: String = "com.avirumapps.shh", reuseDuration: TimeInterval = 300) {
        self.service = service
        self.reuseDuration = reuseDuration
    }

    /// Add a secret. Prefers biometric-gated storage; falls back to plain
    /// `accessibleWhenUnlockedThisDeviceOnly` on -34018 (missing entitlement).
    public func add(id: String, secret: String, biometricGated: Bool = true) throws {
        guard let secretData = secret.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        if biometricGated {
            do {
                try addBiometricGated(id: id, secretData: secretData)
                return
            } catch KeychainError.unhandledStatus(-34018) {
                // Entitlement missing — ad-hoc-signed dev build. Log a note
                // to stderr so it shows up in Console.app and fall through
                // to plain storage. Release builds never hit this path.
                let warning = "[shh] warning: biometric Keychain access " +
                              "requires a signed build with keychain-access-groups; " +
                              "storing \(id) without biometric gating.\n"
                FileHandle.standardError.write(Data(warning.utf8))
            }
        }

        try addUnprotected(id: id, secretData: secretData)
    }

    /// Read a secret. Triggers a Touch ID (or password) prompt if the item
    /// is biometric-gated and the LAContext reuse window has expired.
    /// Returns silently for non-biometric items. The `reason` is shown in
    /// the system auth dialog when a prompt is needed.
    public func read(id: String, reason: String) throws -> String {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = reuseDuration
        context.localizedReason = reason

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let secret = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataConversionFailed
            }
            return secret
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        case errSecUserCanceled:
            throw KeychainError.userCancelled
        case errSecAuthFailed:
            throw KeychainError.authenticationFailed
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    /// Remove a secret. Succeeds silently if the item does not exist.
    public func remove(id: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    /// Enumerate stored ids without triggering biometric prompts. Metadata
    /// only (account names); secret data is never returned by this call.
    public func allIDs() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let items = result as? [[String: Any]] else { return [] }
            return items.compactMap { $0[kSecAttrAccount as String] as? String }
        case errSecItemNotFound:
            return []
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    // MARK: - Private

    private func addBiometricGated(id: String, secretData: Data) throws {
        var cfError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &cfError
        ) else {
            throw KeychainError.accessControlCreationFailed
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecValueData as String: secretData,
            kSecAttrAccessControl as String: accessControl,
        ]
        try secItemAdd(query)
    }

    private func addUnprotected(id: String, secretData: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecValueData as String: secretData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        try secItemAdd(query)
    }

    private func secItemAdd(_ query: [String: Any]) throws {
        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            throw KeychainError.duplicateItem
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }
}
