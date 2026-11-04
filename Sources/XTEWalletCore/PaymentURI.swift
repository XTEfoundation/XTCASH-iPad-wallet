// Copyright (c) 2026, TRRXITTE Int., incorporate. Licensed under AGPL-3.0.
//
// xtcash://<address>?amount=<atomic>&name=<label>&paymentid=<64 hex>
// Same format the XTCASH React Native wallet (XTEfoundation/XTCASH-wallet) produces/parses.

import Foundation

public struct PaymentURI: Equatable, Sendable {
    public var address: String
    public var amount: UInt64?
    public var name: String?
    public var paymentID: String?

    public init(address: String, amount: UInt64? = nil, name: String? = nil, paymentID: String? = nil) {
        self.address = address
        self.amount = amount
        self.name = name
        self.paymentID = paymentID
    }

    public enum ParseError: Error, Equatable {
        case notAURI
        case invalidAddress
        case invalidAmount
        case invalidPaymentID
        case paymentIDWithIntegratedAddress
    }

    public static func parse(_ input: String) throws -> PaymentURI {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bare address (e.g. a QR code that only holds the address)
        if XTEAddress.isValid(text) { return PaymentURI(address: text) }

        guard let colon = text.firstIndex(of: ":") else { throw ParseError.notAURI }
        let scheme = text[..<colon].lowercased()
        guard XTEConfig.uriSchemes.contains(scheme) else { throw ParseError.notAURI }
        var rest = text[text.index(after: colon)...]
        while rest.hasPrefix("/") { rest = rest.dropFirst() }

        let parts = rest.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let address = String(parts[0])
        guard let decoded = try? XTEAddress.decode(address) else { throw ParseError.invalidAddress }

        var uri = PaymentURI(address: address)
        if parts.count == 2 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(kv[0]).lowercased()
                let rawValue = kv.count > 1 ? String(kv[1]) : ""
                let value = (rawValue.replacingOccurrences(of: "+", with: " ").removingPercentEncoding) ?? rawValue
                switch key {
                case "amount":
                    guard let a = UInt64(value) else { throw ParseError.invalidAmount }
                    uri.amount = a
                case "name":
                    uri.name = value
                case "paymentid":
                    guard value.isEmpty || isHex64(value) else { throw ParseError.invalidPaymentID }
                    uri.paymentID = value.isEmpty ? nil : value.lowercased()
                default:
                    continue
                }
            }
        }
        if decoded.isIntegrated && uri.paymentID != nil { throw ParseError.paymentIDWithIntegratedAddress }
        return uri
    }

    /// Builds an xtcash:// URI (used for the receive QR code).
    public func uriString() -> String {
        var s = "\(XTEConfig.uriSchemes[0])://\(address)"
        var q: [String] = []
        if let amount { q.append("amount=\(amount)") }
        if let name, !name.isEmpty {
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?"))
            q.append("name=\(name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name)")
        }
        if let paymentID { q.append("paymentid=\(paymentID)") }
        if !q.isEmpty { s += "?" + q.joined(separator: "&") }
        return s
    }
}
