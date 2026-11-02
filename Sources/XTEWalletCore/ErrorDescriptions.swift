// Copyright (c) 2026, TRRXITTE Int., incorporate. Licensed under AGPL-3.0.

import Foundation

extension AddressError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBase58: return "The address contains invalid characters."
        case .invalidChecksum: return "The address checksum is wrong (typo?)."
        case .wrongPrefix: return "This is not an XTE address."
        case .invalidLength: return "The address has the wrong length."
        case .invalidKeys: return "The address contains invalid keys."
        case .invalidPaymentID: return "The integrated address has an invalid payment ID."
        }
    }
}

extension MnemonicError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .wrongLength(let n): return "A mnemonic seed has 25 words; you entered \(n)."
        case .invalidWord(let w): return "\"\(w)\" is not a mnemonic seed word."
        case .invalidChecksum: return "The mnemonic seed checksum is wrong. Check the words and their order."
        case .invalidMnemonic: return "Invalid mnemonic seed."
        }
    }
}

extension WalletKeysError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidSpendKey: return "Invalid private spend key."
        case .invalidViewKey: return "Invalid private view key."
        case .notDeterministic: return "This wallet has no mnemonic seed (imported from keys)."
        }
    }
}

extension CryptoError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidKey: return "Invalid key."
        case .derivationFailed: return "Key derivation failed."
        case .ringSignatureFailed: return "Ring signature failed."
        }
    }
}

extension PaymentURI.ParseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAURI: return "Not an XTE payment link."
        case .invalidAddress: return "The payment link contains an invalid address."
        case .invalidAmount: return "The payment link contains an invalid amount."
        case .invalidPaymentID: return "The payment link contains an invalid payment ID."
        case .paymentIDWithIntegratedAddress: return "An integrated address cannot carry a second payment ID."
        }
    }
}
