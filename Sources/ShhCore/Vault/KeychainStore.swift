import Foundation
import LocalAuthentication
import Security

/// Low-level Keychain operations for the vault.
///
/// Secrets are stored as generic passwords under a single service
/// (`com.avirumapps.shh`), biometric-gated via `kSecAttrAccessControl` and
/// `.biometryCurrentSet`. Reads require an `LAContext` whose authentication
/// is reused for a configurable window so a single session does not prompt
/// Touch ID on every request.
public final class KeychainStore: @unchecked Sendable {
    public let service: String
    public let reuseDuration: TimeInterval

    public init(service: String = "com.avirumapps.shh", reuseDuration: TimeInterval = 300) {
        self.service = service
        self.reuseDuration = reuseDuration
    }

    /// Add a secret. Default access-control requires biometric authentication
    /// for any future read; pass `biometricGated: false` for non-sensitive
    /// items or for tests without a signed biometric entitlement.
    public func add(id: String, secret: String, biometricGated: Bool = true) throws {
        guard let secretData = secret.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecValueData as String: secretData,
        ]

        if biometricGated {
            var cfError: Unmanaged<CFError>?
            guard let accessControl = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryCurrentSet,
                &cfError
            ) else {
                throw KeychainError.accessControlCreationFailed
            }
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

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

    /// Read a secret. Triggers a Touch ID (or password) prompt if the
    /// LAContext reuse window has expired. The `reason` is shown in the
    /// system auth dialog.
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
}
