// Copyright (c) 2026, TRRXITTE Int., incorporate. Licensed under AGPL-3.0.
// CryptoNote varint (LEB128), see traaitt/src/common/Varint.h

import Foundation

public enum Varint {
    public static func encode(_ value: UInt64) -> [UInt8] {
        var v = value
        var out = [UInt8]()
        while v >= 0x80 {
            out.append(UInt8(v & 0x7f) | 0x80)
            v >>= 7
        }
        out.append(UInt8(v))
        return out
    }

    /// Returns (value, bytesRead) or nil if malformed.
    public static func decode<C: Collection>(_ bytes: C) -> (UInt64, Int)? where C.Element == UInt8 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var read = 0
        for b in bytes {
            read += 1
            if shift > 63 { return nil }
            result |= UInt64(b & 0x7f) << shift
            if b & 0x80 == 0 {
                // Reject non-canonical trailing zero bytes (as upstream does).
                if read > 1 && b == 0 { return nil }
                return (result, read)
            }
            shift += 7
        }
        return nil
    }
}
