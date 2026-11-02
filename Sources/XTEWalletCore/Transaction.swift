// Copyright (c) 2012-2017, The CryptoNote developers, The Bytecoin developers
// Copyright (c) 2018-2019, The TurtleCoin Developers
// Copyright (c) 2020-2026, TRRXITTE Int., incorporate
// Licensed under AGPL-3.0.
//
// Binary transaction format (version 1, key inputs/outputs) as serialized by
// traaitt/src/serialization/CryptoNoteSerialization.cpp.

import Foundation

public struct TxKeyInput: Equatable, Sendable {
    public var amount: UInt64
    /// Relative global output indexes of the ring members.
    public var keyOffsets: [UInt64]
    public var keyImage: KeyImage
}

public struct TxKeyOutput: Equatable, Sendable {
    public var amount: UInt64
    public var key: PublicKey
}

public struct CNTransaction: Equatable, Sendable {
    public static let inputTagKey: UInt8 = 0x02
    public static let outputTagKey: UInt8 = 0x02
    public static let extraTagPadding: UInt8 = 0x00
    public static let extraTagPubKey: UInt8 = 0x01
    public static let extraTagNonce: UInt8 = 0x02
    public static let extraNoncePaymentID: UInt8 = 0x00

    public var version: UInt64 = 1
    public var unlockTime: UInt64 = 0
    public var inputs: [TxKeyInput] = []
    public var outputs: [TxKeyOutput] = []
    public var extra: [UInt8] = []
    /// One array of 64-byte signatures per input.
    public var signatures: [[[UInt8]]] = []

    public init() {}

    public func prefixBytes() -> [UInt8] {
        var b: [UInt8] = []
        b += Varint.encode(version)
        b += Varint.encode(unlockTime)
        b += Varint.encode(UInt64(inputs.count))
        for i in inputs {
            b.append(CNTransaction.inputTagKey)
            b += Varint.encode(i.amount)
            b += Varint.encode(UInt64(i.keyOffsets.count))
            for o in i.keyOffsets { b += Varint.encode(o) }
            b += i.keyImage.bytes
        }
        b += Varint.encode(UInt64(outputs.count))
        for o in outputs {
            b += Varint.encode(o.amount)
            b.append(CNTransaction.outputTagKey)
            b += o.key.bytes
        }
        b += Varint.encode(UInt64(extra.count))
        b += extra
        return b
    }

    public func serialized() -> [UInt8] {
        var b = prefixBytes()
        for s in signatures { for sig in s { b += sig } }
        return b
    }

    public var prefixHash: Hash32 { CNCrypto.fastHash(prefixBytes()) }
    public var hash: Hash32 { CNCrypto.fastHash(serialized()) }

    public var transactionPublicKey: PublicKey? {
        // Walk the extra fields (padding / pubkey / nonce).
        var i = 0
        while i < extra.count {
            switch extra[i] {
            case CNTransaction.extraTagPubKey:
                guard i + 33 <= extra.count else { return nil }
                return Key32(bytes: Array(extra[(i + 1)..<(i + 33)]))
            case CNTransaction.extraTagNonce:
                guard i + 1 < extra.count else { return nil }
                i += 2 + Int(extra[i + 1])
            default:
                i += 1
            }
        }
        return nil
    }

    public var paymentID: String? {
        var i = 0
        while i < extra.count {
            switch extra[i] {
            case CNTransaction.extraTagPubKey: i += 33
            case CNTransaction.extraTagNonce:
                guard i + 1 < extra.count else { return nil }
                let len = Int(extra[i + 1])
                if len == 33, i + 2 + len <= extra.count, extra[i + 2] == CNTransaction.extraNoncePaymentID {
                    return Data(extra[(i + 3)..<(i + 35)]).hex
                }
                i += 2 + len
            default: i += 1
            }
        }
        return nil
    }

    public enum ParseError: Error { case truncated, unsupported }

    /// Parses a v1 transaction with key inputs/outputs (the only kind this wallet creates).
    public static func parse(_ bytes: [UInt8]) throws -> CNTransaction {
        var p = 0
        func varint() throws -> UInt64 {
            guard let (v, n) = Varint.decode(bytes[p...]) else { throw ParseError.truncated }
            p += n
            return v
        }
        func take(_ n: Int) throws -> [UInt8] {
            guard p + n <= bytes.count else { throw ParseError.truncated }
            defer { p += n }
            return Array(bytes[p..<(p + n)])
        }
        var tx = CNTransaction()
        tx.version = try varint()
        tx.unlockTime = try varint()
        let nIn = try varint()
        for _ in 0..<nIn {
            guard try take(1)[0] == inputTagKey else { throw ParseError.unsupported }
            let amount = try varint()
            let count = try varint()
            var offs: [UInt64] = []
            for _ in 0..<count { offs.append(try varint()) }
            tx.inputs.append(TxKeyInput(amount: amount, keyOffsets: offs, keyImage: Key32(unchecked: try take(32))))
        }
        let nOut = try varint()
        for _ in 0..<nOut {
            let amount = try varint()
            guard try take(1)[0] == outputTagKey else { throw ParseError.unsupported }
            tx.outputs.append(TxKeyOutput(amount: amount, key: Key32(unchecked: try take(32))))
        }
        let extraLen = try varint()
        tx.extra = try take(Int(extraLen))
        for input in tx.inputs {
            var sigs: [[UInt8]] = []
            for _ in input.keyOffsets { sigs.append(try take(64)) }
            tx.signatures.append(sigs)
        }
        guard p == bytes.count else { throw ParseError.unsupported }
        return tx
    }
}
