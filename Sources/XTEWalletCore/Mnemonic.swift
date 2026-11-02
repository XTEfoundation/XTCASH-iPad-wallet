// Copyright 2014-2018, The Monero Developers
// Copyright 2018-2019, The TurtleCoin Developers
// Copyright (c) 2020-2026, TRRXITTE Int., incorporate
// Licensed under AGPL-3.0.
//
// 25-word English mnemonic, ported from traaitt/src/mnemonics/Mnemonics.cpp.

import Foundation

public enum MnemonicError: Error, Equatable {
    case wrongLength(Int)
    case invalidWord(String)
    case invalidChecksum
    case invalidMnemonic
}

public enum Mnemonic {
    static let words = MnemonicWordList.english
    static let index: [String: Int] = {
        var d = [String: Int]()
        for (i, w) in MnemonicWordList.english.enumerated() { d[w] = i }
        return d
    }()

    public static func isValidWord(_ word: String) -> Bool {
        index[word.lowercased()] != nil
    }

    /// Encodes a 32-byte private spend key into 25 words (24 + checksum word).
    public static func fromPrivateKey(_ key: SecretKey) -> [String] {
        let n = UInt32(words.count)
        var out: [String] = []
        for i in stride(from: 0, to: 32, by: 4) {
            let b = key.bytes
            let val = UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
            let w1 = val % n
            let w2 = ((val / n) + w1) % n
            let w3 = (((val / n) / n) + w2) % n
            out += [words[Int(w1)], words[Int(w2)], words[Int(w3)]]
        }
        out.append(checksumWord(out))
        return out
    }

    public static func toPrivateKey(_ phrase: String) throws -> SecretKey {
        let list = phrase.split(whereSeparator: { $0.isWhitespace }).map { String($0).lowercased() }
        return try toPrivateKey(list)
    }

    public static func toPrivateKey(_ list: [String]) throws -> SecretKey {
        guard list.count == 25 else { throw MnemonicError.wrongLength(list.count) }
        var idx: [Int] = []
        for w in list {
            guard let i = index[w.lowercased()] else { throw MnemonicError.invalidWord(w) }
            idx.append(i)
        }
        let lower = list.map { $0.lowercased() }
        guard lower[24] == checksumWord(Array(lower[0..<24])) else { throw MnemonicError.invalidChecksum }
        let n = UInt64(words.count)
        var data: [UInt8] = []
        for i in stride(from: 0, to: 24, by: 3) {
            let w1 = UInt64(idx[i]), w2 = UInt64(idx[i + 1]), w3 = UInt64(idx[i + 2])
            let val64 = w1 + n * (((n - w1) + w2) % n) + n * n * (((n - w2) + w3) % n)
            let val = UInt32(truncatingIfNeeded: val64)
            guard UInt64(val) % n == w1 else { throw MnemonicError.invalidMnemonic }
            data += [UInt8(val & 0xff), UInt8((val >> 8) & 0xff), UInt8((val >> 16) & 0xff), UInt8(val >> 24)]
        }
        return Key32(unchecked: data)
    }

    static func checksumWord(_ list: [String]) -> String {
        let trimmed = list.map { String($0.prefix(3)) }.joined()
        let crc = CRC32.checksum(Array(trimmed.utf8))
        return list[Int(UInt64(crc) % UInt64(list.count))]
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in bytes { crc = (crc >> 8) ^ table[Int((crc ^ UInt32(b)) & 0xff)] }
        return crc ^ 0xFFFF_FFFF
    }
}
