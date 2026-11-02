// Copyright (c) 2012-2017, The CryptoNote developers, The Bytecoin developers
// Copyright (c) 2018-2019, The TurtleCoin Developers
// Copyright (c) 2020-2026, TRRXITTE Int., incorporate
//
// CryptoNote block-wise Base58 (8-byte blocks -> 11 chars), ported from
// traaitt/src/common/Base58.cpp.

import Foundation

public enum Base58 {
    static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
    static let encodedBlockSizes = [0, 2, 3, 5, 6, 7, 9, 10, 11]
    static let fullBlockSize = 8
    static let fullEncodedBlockSize = 11

    static let reverse: [Int8] = {
        var t = [Int8](repeating: -1, count: 256)
        for (i, c) in alphabet.enumerated() { t[Int(c)] = Int8(i) }
        return t
    }()

    static func uint8beTo64(_ data: ArraySlice<UInt8>) -> UInt64 {
        var res: UInt64 = 0
        for b in data { res = res << 8 | UInt64(b) }
        return res
    }

    static func encodeBlock(_ block: ArraySlice<UInt8>, into out: inout [UInt8]) {
        let size = block.count
        let encodedSize = encodedBlockSizes[size]
        var num = uint8beTo64(block)
        var chars = [UInt8](repeating: alphabet[0], count: encodedSize)
        var i = encodedSize - 1
        while num > 0 {
            let rem = Int(num % 58)
            num /= 58
            chars[i] = alphabet[rem]
            i -= 1
        }
        out.append(contentsOf: chars)
    }

    public static func encode(_ data: [UInt8]) -> String {
        var out = [UInt8]()
        let fullBlocks = data.count / fullBlockSize
        for i in 0..<fullBlocks {
            encodeBlock(data[(i * fullBlockSize)..<((i + 1) * fullBlockSize)], into: &out)
        }
        let rem = data.count % fullBlockSize
        if rem > 0 {
            encodeBlock(data[(fullBlocks * fullBlockSize)...], into: &out)
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func decodeBlock(_ block: ArraySlice<UInt8>, into out: inout [UInt8]) -> Bool {
        let size = block.count
        guard size >= 1, size <= fullEncodedBlockSize,
              let resSize = encodedBlockSizes.firstIndex(of: size), resSize > 0 else { return false }
        var resNum: UInt64 = 0
        var order: UInt64 = 1
        for c in block.reversed() {
            let digit = reverse[Int(c)]
            if digit < 0 { return false }
            let (product, overflow1) = UInt64(digit).multipliedReportingOverflow(by: order)
            if overflow1 { return false }
            let (sum, overflow2) = resNum.addingReportingOverflow(product)
            if overflow2 { return false }
            resNum = sum
            order = order &* 58
        }
        if resSize < fullBlockSize && (UInt64(1) << (8 * UInt64(resSize))) <= resNum { return false }
        var bytes = [UInt8](repeating: 0, count: resSize)
        var n = resNum
        for i in stride(from: resSize - 1, through: 0, by: -1) {
            bytes[i] = UInt8(n & 0xff)
            n >>= 8
        }
        out.append(contentsOf: bytes)
        return true
    }

    public static func decode(_ string: String) -> [UInt8]? {
        let enc = Array(string.utf8)
        if enc.isEmpty { return [] }
        let fullBlocks = enc.count / fullEncodedBlockSize
        let lastSize = enc.count % fullEncodedBlockSize
        if lastSize > 0 && !encodedBlockSizes.contains(lastSize) { return nil }
        var out = [UInt8]()
        for i in 0..<fullBlocks {
            if !decodeBlock(enc[(i * fullEncodedBlockSize)..<((i + 1) * fullEncodedBlockSize)], into: &out) { return nil }
        }
        if lastSize > 0 {
            if !decodeBlock(enc[(fullBlocks * fullEncodedBlockSize)...], into: &out) { return nil }
        }
        return out
    }
}
