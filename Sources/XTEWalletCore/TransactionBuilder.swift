// Copyright (c) 2018-2019, The TurtleCoin Developers
// Copyright (c) 2020-2026, TRRXITTE Int., incorporate
// Licensed under AGPL-3.0.
//
// Port of traaitt/src/walletbackend/Transfer.cpp (sendTransactionAdvanced / makeTransaction).

import Foundation

public enum TransferError: Error, Equatable, LocalizedError {
    case viewOnlyWallet
    case invalidAddress
    case paymentIDConflict
    case invalidPaymentID
    case amountZero
    case feeTooSmall
    case mixinOutOfRange(min: UInt64, max: UInt64)
    case notEnoughFunds(available: UInt64, required: UInt64)
    case notEnoughFakeOutputs(amount: UInt64)
    case missingGlobalIndex
    case invalidGeneratedKeyImage
    case ringSignatureFailed
    case amountsNotPretty
    case unexpectedFee
    case tooLarge(size: Int, max: Int)
    case extraTooLarge
    case overflow

    public var errorDescription: String? {
        switch self {
        case .viewOnlyWallet: return "This is a view-only wallet and cannot send."
        case .invalidAddress: return "The destination address is not a valid XTE address."
        case .paymentIDConflict: return "An integrated address already contains a payment ID."
        case .invalidPaymentID: return "Payment ID must be 64 hexadecimal characters."
        case .amountZero: return "Amount must be greater than zero."
        case .feeTooSmall: return "Fee is below the network minimum (\(Amount.format(XTEConfig.minimumFee)))."
        case .mixinOutOfRange(let a, let b): return "Mixin must be between \(a) and \(b)."
        case .notEnoughFunds(let a, let r): return "Not enough unlocked funds: \(Amount.format(a)) available, \(Amount.format(r)) required."
        case .notEnoughFakeOutputs(let a): return "The node could not supply enough decoy outputs for \(Amount.format(a)). Try sending a different amount or with a lower mixin."
        case .missingGlobalIndex: return "An input is missing its global output index; resync the wallet."
        case .invalidGeneratedKeyImage: return "Derived key did not match the ring member (wallet keys/inputs inconsistent)."
        case .ringSignatureFailed: return "Failed to create a valid ring signature."
        case .amountsNotPretty: return "Internal error: output amounts are not valid denominations."
        case .unexpectedFee: return "Internal error: fee does not match."
        case .tooLarge(let s, let m): return "Transaction is too large (\(s) bytes, max \(m)). Send a smaller amount."
        case .extraTooLarge: return "Transaction extra data is too large."
        case .overflow: return "Amount overflow."
        }
    }
}

public struct Destination: Equatable, Sendable {
    public var address: XTEAddress
    public var amount: UInt64
    public init(address: XTEAddress, amount: UInt64) {
        self.address = address
        self.amount = amount
    }
}

/// Supplies decoy outputs for ring signatures (normally the daemon's /getrandom_outs).
public protocol DecoySource {
    func randomOutputs(amounts: [UInt64], count: UInt64) async throws -> [RandomOutputs]
}

public struct DaemonDecoySource: DecoySource {
    let daemon: DaemonAPI
    public init(daemon: DaemonAPI) { self.daemon = daemon }
    public func randomOutputs(amounts: [UInt64], count: UInt64) async throws -> [RandomOutputs] {
        try await daemon.randomOutputs(amounts: amounts, count: count)
    }
}

public struct PreparedTransaction: Sendable {
    public let transaction: CNTransaction
    public let hash: Hash32
    public let hex: String
    public let fee: UInt64
    public let nodeFee: UInt64
    public let amount: UInt64
    public let change: UInt64
    public let inputs: [OwnedOutput]
    public let txPrivateKey: SecretKey
    public let paymentID: String?
}

public enum TransactionBuilder {
    /// Transfer.cpp splitAmountIntoDenominations(amount, preventTooLargeOutputs = true)
    public static func splitIntoDenominations(_ amount: UInt64) -> [UInt64] {
        var result: [UInt64] = []
        var amount = amount
        var multiplier: UInt64 = 1
        while amount > 0 {
            let denomination = multiplier * (amount % 10)
            if denomination > XTEConfig.maxOutputSizeClient {
                var numSplit: UInt64 = 10
                var splitAmount = denomination / 10
                while splitAmount > XTEConfig.maxOutputSizeClient {
                    splitAmount /= 10
                    numSplit *= 10
                }
                result += Array(repeating: splitAmount, count: Int(numSplit))
            } else if denomination != 0 {
                result.append(denomination)
            }
            amount /= 10
            if amount > 0 { multiplier = multiplier &* 10 }
        }
        return result
    }

    /// Constants::PRETTY_AMOUNTS: d * 10^n, d in 1...9.
    public static func isPretty(_ amount: UInt64) -> Bool {
        guard amount > 0 else { return false }
        var a = amount
        while a % 10 == 0 { a /= 10 }
        return a < 10
    }

    /// Utilities::getMaxTxSize
    public static func maxTransactionSize(height: UInt64) -> Int {
        let growth = height * (100 * 1024) / (365 * 24 * 60 * 60 / XTEConfig.blockTargetSeconds)
        let x = 1_000_000 + growth
        return Int(min(x, 125_000)) - 600
    }

    /// Builds and signs a transaction. Nothing is broadcast.
    public static func build(
        keys: WalletKeys,
        destinations: [Destination],
        paymentID: String?,
        fee: UInt64,
        mixin: UInt64,
        nodeFee: (address: XTEAddress, amount: UInt64)?,
        spendable: [OwnedOutput],
        networkHeight: UInt64,
        decoys: DecoySource,
        unlockTime: UInt64 = 0
    ) async throws -> PreparedTransaction {
        guard !destinations.isEmpty else { throw TransferError.amountZero }
        guard fee >= XTEConfig.minimumFee else { throw TransferError.feeTooSmall }
        let limits = XTEConfig.mixinLimits(height: networkHeight)
        guard mixin >= limits.minimum, mixin <= limits.maximum else {
            throw TransferError.mixinOutOfRange(min: limits.minimum, max: limits.maximum)
        }

        // Resolve integrated addresses into standard address + payment ID.
        var pid = paymentID?.isEmpty == true ? nil : paymentID?.lowercased()
        if let p = pid, !isHex64(p) { throw TransferError.invalidPaymentID }
        var dests: [(XTEAddress, UInt64)] = []
        for d in destinations {
            guard d.amount > 0 else { throw TransferError.amountZero }
            if let integrated = d.address.paymentID {
                if let p = pid, p != integrated.lowercased() { throw TransferError.paymentIDConflict }
                pid = integrated.lowercased()
            }
            dests.append((d.address.standard, d.amount))
        }
        if let nf = nodeFee, nf.amount > 0 { dests.append((nf.address.standard, nf.amount)) }

        var total: UInt64 = fee
        for d in dests {
            let (s, o) = total.addingReportingOverflow(d.1)
            guard !o else { throw TransferError.overflow }
            total = s
        }

        // SubWallets::getTransactionInputsForAmount: shuffle, take until enough.
        let available = spendable.reduce(UInt64(0)) { $0 + $1.amount }
        guard available >= total else { throw TransferError.notEnoughFunds(available: available, required: total) }
        var chosen: [OwnedOutput] = []
        var found: UInt64 = 0
        for o in spendable.shuffled() {
            chosen.append(o)
            found += o.amount
            if found >= total { break }
        }
        let change = found - total
        if change > 0 { dests.append((keys.address, change)) }

        // setupDestinations
        struct Dest { let amount: UInt64; let spend: PublicKey; let view: PublicKey }
        var outs: [Dest] = []
        for (addr, amount) in dests {
            for denom in splitIntoDenominations(amount) {
                outs.append(Dest(amount: denom, spend: addr.publicSpendKey, view: addr.publicViewKey))
            }
        }

        // prepareRingParticipants
        chosen.sort { $0.amount < $1.amount }
        struct Ring { let input: OwnedOutput; var members: [(UInt64, PublicKey)]; var realIndex: Int }
        var rings: [Ring] = []
        var pool: [UInt64: [[RandomOutputEntry]]] = [:]
        if mixin > 0 {
            let fakes = try await decoys.randomOutputs(amounts: chosen.map(\.amount), count: mixin + 1)
            for f in fakes { pool[f.amount, default: []].append(f.outs) }
        }
        for input in chosen {
            guard let gi = input.globalOutputIndex else { throw TransferError.missingGlobalIndex }
            var members: [(UInt64, PublicKey)] = []
            if mixin > 0 {
                guard var list = pool[input.amount], !list.isEmpty else { throw TransferError.notEnoughFakeOutputs(amount: input.amount) }
                let candidates = list.removeFirst()
                pool[input.amount] = list
                var seen = Set<UInt64>()
                for c in candidates.sorted(by: { $0.globalAmountIndex < $1.globalAmountIndex }) {
                    if c.globalAmountIndex == gi || seen.contains(c.globalAmountIndex) { continue }
                    seen.insert(c.globalAmountIndex)
                    members.append((c.globalAmountIndex, c.outKey))
                    if UInt64(members.count) >= mixin { break }
                }
                guard UInt64(members.count) >= mixin else { throw TransferError.notEnoughFakeOutputs(amount: input.amount) }
            }
            let pos = members.firstIndex(where: { $0.0 >= gi }) ?? members.count
            members.insert((gi, input.key), at: pos)
            rings.append(Ring(input: input, members: members, realIndex: pos))
        }

        // setupInputs
        var tx = CNTransaction()
        tx.version = 1
        tx.unlockTime = unlockTime
        var ephemeralSecrets: [SecretKey] = []
        for r in rings {
            let derivation = try CNCrypto.generateKeyDerivation(r.input.transactionPublicKey, keys.privateViewKey)
            let pub = try CNCrypto.derivePublicKey(derivation, outputIndex: r.input.transactionIndex, base: keys.publicSpendKey)
            let sec = try CNCrypto.deriveSecretKey(derivation, outputIndex: r.input.transactionIndex, base: keys.privateSpendKey)
            guard pub == r.members[r.realIndex].1 else { throw TransferError.invalidGeneratedKeyImage }
            let image = try CNCrypto.generateKeyImage(publicKey: pub, secretKey: sec)
            if let known = r.input.keyImage, known != image { throw TransferError.invalidGeneratedKeyImage }
            ephemeralSecrets.append(sec)
            var offsets: [UInt64] = []
            var prev: UInt64 = 0
            for (i, m) in r.members.enumerated() {
                offsets.append(i == 0 ? m.0 : m.0 - prev)
                prev = m.0
            }
            tx.inputs.append(TxKeyInput(amount: r.input.amount, keyOffsets: offsets, keyImage: image))
        }

        // setupOutputs
        outs.sort { $0.amount < $1.amount }
        let txKey = CNCrypto.generateKeys()
        for (i, d) in outs.enumerated() {
            let derivation = try CNCrypto.generateKeyDerivation(d.view, txKey.secretKey)
            let key = try CNCrypto.derivePublicKey(derivation, outputIndex: UInt64(i), base: d.spend)
            tx.outputs.append(TxKeyOutput(amount: d.amount, key: key))
        }

        // extra: [nonce(payment id)] + pubkey
        var extra: [UInt8] = []
        if let p = pid, let pidBytes = Data(hex: p) {
            extra += [CNTransaction.extraTagNonce, 33, CNTransaction.extraNoncePaymentID]
            extra += [UInt8](pidBytes)
        }
        extra.append(CNTransaction.extraTagPubKey)
        extra += txKey.publicKey.bytes
        if networkHeight >= XTEConfig.maxExtraSizeV2Height && extra.count > XTEConfig.maxExtraSizeV2 {
            throw TransferError.extraTooLarge
        }
        tx.extra = extra

        // generateRingSignatures + verification
        let prefixHash = tx.prefixHash
        for (i, r) in rings.enumerated() {
            let keysInRing = r.members.map(\.1)
            let sigs = try CNCrypto.generateRingSignatures(prefixHash: prefixHash, keyImage: tx.inputs[i].keyImage,
                                                           publicKeys: keysInRing, secretKey: ephemeralSecrets[i], realIndex: r.realIndex)
            tx.signatures.append(sigs)
        }
        for (i, r) in rings.enumerated() {
            guard CNCrypto.checkRingSignature(prefixHash: prefixHash, keyImage: tx.inputs[i].keyImage,
                                              publicKeys: r.members.map(\.1), signatures: tx.signatures[i]) else {
                throw TransferError.ringSignatureFailed
            }
        }

        guard tx.outputs.allSatisfy({ isPretty($0.amount) }) else { throw TransferError.amountsNotPretty }
        let inSum = tx.inputs.reduce(UInt64(0)) { $0 + $1.amount }
        let outSum = tx.outputs.reduce(UInt64(0)) { $0 + $1.amount }
        guard inSum >= outSum, inSum - outSum == fee else { throw TransferError.unexpectedFee }

        let bytes = tx.serialized()
        let maxSize = maxTransactionSize(height: networkHeight)
        guard bytes.count <= maxSize else { throw TransferError.tooLarge(size: bytes.count, max: maxSize) }

        let sent = destinations.reduce(UInt64(0)) { $0 + $1.amount }
        return PreparedTransaction(
            transaction: tx, hash: CNCrypto.fastHash(bytes), hex: Data(bytes).hex,
            fee: fee, nodeFee: nodeFee?.amount ?? 0, amount: sent, change: change,
            inputs: chosen, txPrivateKey: txKey.secretKey, paymentID: pid)
    }
}
