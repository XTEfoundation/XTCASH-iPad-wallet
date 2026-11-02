// Copyright (c) 2026, TRRXITTE Int., incorporate. Licensed under AGPL-3.0.
//
// Swift wrappers over the vendored CryptoNote primitives (CXTECrypto).

import CXTECrypto
import Foundation

/// A 32-byte CryptoNote value (public key, secret key, key image, hash, derivation).
public struct Key32: Hashable, Codable, CustomStringConvertible, Sendable {
    public let bytes: [UInt8]

    public init?(bytes: [UInt8]) {
        guard bytes.count == 32 else { return nil }
        self.bytes = bytes
    }

    public init?(hex: String) {
        guard let d = Data(hex: hex), d.count == 32 else { return nil }
        self.bytes = [UInt8](d)
    }

    init(unchecked bytes: [UInt8]) {
        precondition(bytes.count == 32)
        self.bytes = bytes
    }

    public static let zero = Key32(unchecked: [UInt8](repeating: 0, count: 32))

    public var hex: String { Data(bytes).hex }
    public var description: String { hex }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let k = Key32(hex: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected 64 hex chars"))
        }
        self = k
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}

public typealias PublicKey = Key32
public typealias SecretKey = Key32
public typealias KeyImage = Key32
public typealias Hash32 = Key32
public typealias KeyDerivation = Key32

public struct KeyPair: Hashable, Sendable {
    public let publicKey: PublicKey
    public let secretKey: SecretKey
}

public enum CryptoError: Error, Equatable {
    case invalidKey
    case derivationFailed
    case ringSignatureFailed
}

public enum CNCrypto {
    public static func fastHash(_ data: [UInt8]) -> Hash32 {
        var out = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBufferPointer { p in
            xte_cn_fast_hash(p.baseAddress, p.count, &out)
        }
        return Hash32(unchecked: out)
    }

    public static func hashToScalar(_ data: [UInt8]) -> Key32 {
        var out = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBufferPointer { p in
            xte_hash_to_scalar(p.baseAddress, p.count, &out)
        }
        return Key32(unchecked: out)
    }

    public static func randomBytes(_ n: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: n)
        xte_random_bytes(&out, n)
        return out
    }

    public static func isValidScalar(_ k: Key32) -> Bool {
        xte_sc_check(k.bytes) == 1
    }

    public static func checkKey(_ k: PublicKey) -> Bool {
        xte_check_key(k.bytes) == 1
    }

    public static func generateKeys() -> KeyPair {
        var pub = [UInt8](repeating: 0, count: 32)
        var sec = [UInt8](repeating: 0, count: 32)
        xte_generate_keys(&pub, &sec)
        return KeyPair(publicKey: Key32(unchecked: pub), secretKey: Key32(unchecked: sec))
    }

    public static func secretKeyToPublicKey(_ sec: SecretKey) throws -> PublicKey {
        var pub = [UInt8](repeating: 0, count: 32)
        guard xte_secret_key_to_public_key(sec.bytes, &pub) == 1 else { throw CryptoError.invalidKey }
        return Key32(unchecked: pub)
    }

    /// CryptoNote deterministic view key: view_sec = sc_reduce32(keccak(spend_sec)).
    public static func generateViewFromSpend(_ spend: SecretKey) -> KeyPair {
        var vsec = [UInt8](repeating: 0, count: 32)
        var vpub = [UInt8](repeating: 0, count: 32)
        xte_generate_view_from_spend(spend.bytes, &vsec, &vpub)
        return KeyPair(publicKey: Key32(unchecked: vpub), secretKey: Key32(unchecked: vsec))
    }

    public static func generateKeyDerivation(_ pub: PublicKey, _ sec: SecretKey) throws -> KeyDerivation {
        var out = [UInt8](repeating: 0, count: 32)
        guard xte_generate_key_derivation(pub.bytes, sec.bytes, &out) == 1 else { throw CryptoError.derivationFailed }
        return Key32(unchecked: out)
    }

    public static func derivePublicKey(_ derivation: KeyDerivation, outputIndex: UInt64, base: PublicKey) throws -> PublicKey {
        var out = [UInt8](repeating: 0, count: 32)
        guard xte_derive_public_key(derivation.bytes, outputIndex, base.bytes, &out) == 1 else { throw CryptoError.derivationFailed }
        return Key32(unchecked: out)
    }

    public static func deriveSecretKey(_ derivation: KeyDerivation, outputIndex: UInt64, base: SecretKey) throws -> SecretKey {
        var out = [UInt8](repeating: 0, count: 32)
        guard xte_derive_secret_key(derivation.bytes, outputIndex, base.bytes, &out) == 1 else { throw CryptoError.invalidKey }
        return Key32(unchecked: out)
    }

    public static func underivePublicKey(_ derivation: KeyDerivation, outputIndex: UInt64, derivedKey: PublicKey) throws -> PublicKey {
        var out = [UInt8](repeating: 0, count: 32)
        guard xte_underive_public_key(derivation.bytes, outputIndex, derivedKey.bytes, &out) == 1 else { throw CryptoError.derivationFailed }
        return Key32(unchecked: out)
    }

    public static func generateKeyImage(publicKey: PublicKey, secretKey: SecretKey) throws -> KeyImage {
        var out = [UInt8](repeating: 0, count: 32)
        guard xte_generate_key_image(publicKey.bytes, secretKey.bytes, &out) == 1 else { throw CryptoError.invalidKey }
        return Key32(unchecked: out)
    }

    public static func generateSignature(prefixHash: Hash32, publicKey: PublicKey, secretKey: SecretKey) -> [UInt8] {
        var sig = [UInt8](repeating: 0, count: 64)
        xte_generate_signature(prefixHash.bytes, publicKey.bytes, secretKey.bytes, &sig)
        return sig
    }

    public static func checkSignature(prefixHash: Hash32, publicKey: PublicKey, signature: [UInt8]) -> Bool {
        guard signature.count == 64 else { return false }
        return xte_check_signature(prefixHash.bytes, publicKey.bytes, signature) == 1
    }

    /// Returns one 64-byte signature per ring member.
    public static func generateRingSignatures(prefixHash: Hash32, keyImage: KeyImage, publicKeys: [PublicKey],
                                              secretKey: SecretKey, realIndex: Int) throws -> [[UInt8]] {
        guard !publicKeys.isEmpty, realIndex >= 0, realIndex < publicKeys.count else { throw CryptoError.ringSignatureFailed }
        let flat = publicKeys.flatMap { $0.bytes }
        var sigs = [UInt8](repeating: 0, count: 64 * publicKeys.count)
        let ok = xte_generate_ring_signatures(prefixHash.bytes, keyImage.bytes, flat, publicKeys.count, secretKey.bytes, realIndex, &sigs)
        guard ok == 1 else { throw CryptoError.ringSignatureFailed }
        return stride(from: 0, to: sigs.count, by: 64).map { Array(sigs[$0..<($0 + 64)]) }
    }

    public static func checkRingSignature(prefixHash: Hash32, keyImage: KeyImage, publicKeys: [PublicKey], signatures: [[UInt8]]) -> Bool {
        guard !publicKeys.isEmpty, signatures.count == publicKeys.count, signatures.allSatisfy({ $0.count == 64 }) else { return false }
        let flat = publicKeys.flatMap { $0.bytes }
        let sigs = signatures.flatMap { $0 }
        return xte_check_ring_signature(prefixHash.bytes, keyImage.bytes, flat, publicKeys.count, sigs) == 1
    }
}
