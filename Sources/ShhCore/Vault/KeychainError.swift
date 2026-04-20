import Foundation
import Security

public enum KeychainError: Error, LocalizedError, Equatable {
    case unhandledStatus(OSStatus)
    case itemNotFound
    case userCancelled
    case authenticationFailed
    case duplicateItem
    case accessControlCreationFailed
    case dataConversionFailed

    public var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            return "Keychain error \(status): \(msg)"
        case .itemNotFound:
            return "Keychain item not found."
        case .userCancelled:
            return "Touch ID or password prompt cancelled."
        case .authenticationFailed:
            return "Authentication failed."
        case .duplicateItem:
            return "A key with this id already exists in the vault."
        case .accessControlCreationFailed:
            return "Failed to create Keychain access-control policy."
        case .dataConversionFailed:
            return "Failed to convert secret between UTF-8 and raw data."
        }
    }
}
