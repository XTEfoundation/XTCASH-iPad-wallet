// Copyright (c) 2018-2019, The TurtleCoin Developers
// Copyright (c) 2020-2026, TRRXITTE Int., incorporate
// Licensed under AGPL-3.0.
//
// CryptoNote address encoding: base58(varint(prefix) || data || keccak(...)[0..<4]).
// Integrated addresses embed a 64-char hex payment id before the keys
// (same layout as traaitt/src/utilities/Addresses.cpp).

import Foundation

public enum AddressError: Error, Equatable {
    case invalidBase58
    case invalidChecksum
    case wrongPrefix(UInt64)
    case invalidLength
    case invalidKeys
    case invalidPaymentID
}

public struct XTEAddress: Equatable, Sendable {
    public let publicSpendKey: PublicKey
    public let publicViewKey: PublicKey
    public let paymentID: String?
    public let prefix: UInt64

    public init(publicSpendKey: PublicKey, publicViewKey: PublicKey, paymentID: String? = nil, prefix: UInt64 = XTEConfig.addressPrefix) {
        self.publicSpendKey = publicSpendKey
        self.publicViewKey = publicViewKey
        self.paymentID = paymentID
        self.prefix = prefix
    }

    public var isIntegrated: Bool { paymentID != nil }

    /// The base58 string. Integrated addresses are produced when `paymentID` is set.
    public func encoded() -> String {
        var body: [UInt8] = []
        if let pid = paymentID {
            body += Array(pid.lowercased().utf8)
        }
        body += publicSpendKey.bytes
        body += publicViewKey.bytes
        return XTEAddress.encodeRaw(prefix: prefix, data: body)
    }

    /// The standard (non-integrated) address for the same keys.
    public var standard: XTEAddress {
        XTEAddress(publicSpendKey: publicSpendKey, publicViewKey: publicViewKey, paymentID: nil, prefix: prefix)
    }

    static func encodeRaw(prefix: UInt64, data: [UInt8]) -> String {
        var buf = Varint.encode(prefix) + data
        let checksum = CNCrypto.fastHash(buf).bytes.prefix(4)
        buf += checksum
        return Base58.encode(buf)
    }

    public static func decode(_ string: String, expectedPrefix: UInt64 = XTEConfig.addressPrefix) throws -> XTEAddress {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Base58.decode(trimmed), raw.count > 4 else { throw AddressError.invalidBase58 }
        let payload = Array(raw.dropLast(4))
        let checksum = Array(raw.suffix(4))
        guard Array(CNCrypto.fastHash(payload).bytes.prefix(4)) == checksum else { throw AddressError.invalidChecksum }
        guard let (prefix, n) = Varint.decode(payload) else { throw AddressError.invalidBase58 }
        guard prefix == expectedPrefix else { throw AddressError.wrongPrefix(prefix) }
        let data = Array(payload[n...])
        var paymentID: String?
        let keys: [UInt8]
        switch data.count {
        case 64:
            keys = data
        case 128:
            let pidBytes = Array(data[0..<64])
            guard let pid = String(bytes: pidBytes, encoding: .ascii), isHex64(pid) else { throw AddressError.invalidPaymentID }
            paymentID = pid.lowercased()
            keys = Array(data[64...])
        default:
            throw AddressError.invalidLength
        }
        let spend = Key32(unchecked: Array(keys[0..<32]))
        let view = Key32(unchecked: Array(keys[32..<64]))
        guard CNCrypto.checkKey(spend), CNCrypto.checkKey(view) else { throw AddressError.invalidKeys }
        return XTEAddress(publicSpendKey: spend, publicViewKey: view, paymentID: paymentID, prefix: prefix)
    }

    public static func isValid(_ string: String, allowIntegrated: Bool = true) -> Bool {
        guard let a = try? decode(string) else { return false }
        return allowIntegrated || !a.isIntegrated
    }
}
