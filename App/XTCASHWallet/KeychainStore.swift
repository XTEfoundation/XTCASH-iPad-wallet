// Copyright (c) 2026, TRRXITTE Int., incorporate. Licensed under AGPL-3.0.

import Foundation
import LocalAuthentication
import Security
import XTEWalletCore

/// Stores the private spend/view keys in the iOS Keychain. Items are bound to this device
/// (never synced to iCloud) and every read requires Face ID / Touch ID or the device passcode.
enum KeychainStore {
    static let service = "io.traaitt.xtcash.ipad.wallet"
    static let account = "primary-wallet-keys"

    struct StoredKeys: Codable {
        let privateSpendKey: String
        let privateViewKey: String
    }

    enum KeychainError: LocalizedError {
        case status(OSStatus)
        case accessControl
        case corrupt

        var errorDescription: String? {
            switch self {
            case .status(let s):
                if s == errSecUserCanceled { return "Authentication cancelled." }
                if s == errSecAuthFailed { return "Authentication failed." }
                return (SecCopyErrorMessageString(s, nil) as String?) ?? "Keychain error \(s)"
            case .accessControl: return "Could not create keychain access control."
            case .corrupt: return "Stored wallet keys are unreadable."
            }
        }
    }

    static func save(_ keys: WalletKeys) throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &error) else {
            throw KeychainError.accessControl
        }
        let payload = try JSONEncoder().encode(StoredKeys(privateSpendKey: keys.privateSpendKey.hex,
                                                          privateViewKey: keys.privateViewKey.hex))
        try? delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessControl as String: access,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecValueData as String: payload,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    /// Prompts for biometrics / passcode, then returns the keys.
    static func load(reason: String) throws -> WalletKeys {
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError.status(status) }
        guard let stored = try? JSONDecoder().decode(StoredKeys.self, from: data) else { throw KeychainError.corrupt }
        return try WalletKeys.fromKeys(privateSpendKeyHex: stored.privateSpendKey, privateViewKeyHex: stored.privateViewKey)
    }

    static func exists() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: context,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }

    /// Re-authenticates the user without reading keys (used before showing secrets).
    static func authenticate(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? KeychainError.accessControl
        }
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}
