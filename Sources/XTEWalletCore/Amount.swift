// Copyright (c) 2026, TRRXITTE Int., incorporate. Licensed under AGPL-3.0.

import Foundation

public enum Amount {
    /// 12345 atomic -> "123.45 XTE"
    public static func format(_ atomic: UInt64, withTicker: Bool = true) -> String {
        let divisor = pow10(XTEConfig.decimalPlaces)
        let whole = atomic / divisor
        let frac = atomic % divisor
        var wholeStr = String(whole)
        // thousands separators
        var groups: [String] = []
        while wholeStr.count > 3 {
            groups.insert(String(wholeStr.suffix(3)), at: 0)
            wholeStr = String(wholeStr.dropLast(3))
        }
        groups.insert(wholeStr, at: 0)
        var fracStr = String(frac)
        while fracStr.count < XTEConfig.decimalPlaces { fracStr = "0" + fracStr }
        let s = groups.joined(separator: ",") + "." + fracStr
        return withTicker ? "\(s) \(XTEConfig.ticker)" : s
    }

    /// Parses a user-entered decimal ("12.5", "1,000.25") into atomic units. Rejects extra precision.
    public static func parse(_ text: String) -> UInt64? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let wholePart = parts[0].isEmpty ? "0" : String(parts[0])
        guard wholePart.allSatisfy(\.isNumber), let whole = UInt64(wholePart) else { return nil }
        var frac: UInt64 = 0
        if parts.count == 2 {
            let f = String(parts[1])
            guard f.count <= XTEConfig.decimalPlaces, f.allSatisfy(\.isNumber) else { return nil }
            let padded = f + String(repeating: "0", count: XTEConfig.decimalPlaces - f.count)
            frac = UInt64(padded) ?? 0
        }
        let (m, o1) = whole.multipliedReportingOverflow(by: pow10(XTEConfig.decimalPlaces))
        let (r, o2) = m.addingReportingOverflow(frac)
        guard !o1, !o2 else { return nil }
        return r
    }

    static func pow10(_ n: Int) -> UInt64 {
        var r: UInt64 = 1
        for _ in 0..<n { r *= 10 }
        return r
    }
}
