// Copyright (c) 2026, TRRXITTE Int., incorporate. Licensed under AGPL-3.0.

import Foundation

public enum WalletKeysError: Error, Equatable {
    case invalidSpendKey
    case invalidViewKey
    case notDeterministic
}

/// The secret material of a wallet. Never logged; persisted only in the Keychain by the app.
public struct WalletKeys: Codable, Equatable, Sendable {
    public let privateSpendKey: SecretKey
    public let privateViewKey: SecretKey
    public let publicSpendKey: PublicKey
    public let publicViewKey: PublicKey

    public init(privateSpendKey: SecretKey, privateViewKey: SecretKey) throws {
        guard CNCrypto.isValidScalar(privateSpendKey), let ps = try? CNCrypto.secretKeyToPublicKey(privateSpendKey) else {
            throw WalletKeysError.invalidSpendKey
        }
        guard CNCrypto.isValidScalar(privateViewKey), let pv = try? CNCrypto.secretKeyToPublicKey(privateViewKey) else {
            throw WalletKeysError.invalidViewKey
        }
        self.privateSpendKey = privateSpendKey
        self.privateViewKey = privateViewKey
        self.publicSpendKey = ps
        self.publicViewKey = pv
    }

    /// New random deterministic wallet (view key derived from spend key, so it has a 25-word seed).
    public static func generate() -> WalletKeys {
        let spend = CNCrypto.generateKeys()
        let view = CNCrypto.generateViewFromSpend(spend.secretKey)
        // generateKeys always yields a reduced scalar; force-try is safe.
        return try! WalletKeys(privateSpendKey: spend.secretKey, privateViewKey: view.secretKey)
    }

    public static func fromMnemonic(_ phrase: String) throws -> WalletKeys {
        let spend = try Mnemonic.toPrivateKey(phrase)
        guard CNCrypto.isValidScalar(spend) else { throw WalletKeysError.invalidSpendKey }
        let view = CNCrypto.generateViewFromSpend(spend)
        return try WalletKeys(privateSpendKey: spend, privateViewKey: view.secretKey)
    }

    public static func fromKeys(privateSpendKeyHex: String, privateViewKeyHex: String) throws -> WalletKeys {
        guard let s = SecretKey(hex: privateSpendKeyHex.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw WalletKeysError.invalidSpendKey }
        guard let v = SecretKey(hex: privateViewKeyHex.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw WalletKeysError.invalidViewKey }
        return try WalletKeys(privateSpendKey: s, privateViewKey: v)
    }

    /// True when the view key is derived from the spend key (wallet has a mnemonic seed).
    public var isDeterministic: Bool {
        CNCrypto.generateViewFromSpend(privateSpendKey).secretKey == privateViewKey
    }

    public func mnemonic() throws -> [String] {
        guard isDeterministic else { throw WalletKeysError.notDeterministic }
        return Mnemonic.fromPrivateKey(privateSpendKey)
    }

    public var address: XTEAddress {
        XTEAddress(publicSpendKey: publicSpendKey, publicViewKey: publicViewKey)
    }
}
