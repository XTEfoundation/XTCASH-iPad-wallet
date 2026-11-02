// Copyright (c) 2026, TRRXITTE Int., incorporate. Licensed under AGPL-3.0.

import Foundation

/// An output that belongs to this wallet.
public struct OwnedOutput: Codable, Equatable, Sendable {
    /// One-time output public key (from the transaction).
    public var key: PublicKey
    public var amount: UInt64
    public var parentTransactionHash: Hash32
    public var transactionPublicKey: PublicKey
    /// Index of the output inside its transaction.
    public var transactionIndex: UInt64
    public var globalOutputIndex: UInt64?
    public var blockHeight: UInt64
    public var unlockTime: UInt64
    /// Nil for view-only wallets.
    public var keyImage: KeyImage?
    public var spendHeight: UInt64?
    /// Set when we used this output in a not-yet-confirmed outgoing transaction.
    public var pendingSpendTxHash: Hash32?

    public var isSpent: Bool { spendHeight != nil }

    public init(key: PublicKey, amount: UInt64, parentTransactionHash: Hash32, transactionPublicKey: PublicKey,
                transactionIndex: UInt64, globalOutputIndex: UInt64?, blockHeight: UInt64, unlockTime: UInt64,
                keyImage: KeyImage?, spendHeight: UInt64? = nil, pendingSpendTxHash: Hash32? = nil) {
        self.key = key
        self.amount = amount
        self.parentTransactionHash = parentTransactionHash
        self.transactionPublicKey = transactionPublicKey
        self.transactionIndex = transactionIndex
        self.globalOutputIndex = globalOutputIndex
        self.blockHeight = blockHeight
        self.unlockTime = unlockTime
        self.keyImage = keyImage
        self.spendHeight = spendHeight
        self.pendingSpendTxHash = pendingSpendTxHash
    }
}

public struct WalletTransaction: Codable, Equatable, Identifiable, Sendable {
    public var hash: Hash32
    /// Net change to the wallet balance (negative for outgoing, includes the fee).
    public var amount: Int64
    public var fee: UInt64
    /// 0 while unconfirmed.
    public var blockHeight: UInt64
    public var timestamp: UInt64
    public var paymentID: String
    public var unlockTime: UInt64
    public var isCoinbase: Bool

    public var id: String { hash.hex }
    public var isConfirmed: Bool { blockHeight > 0 }
}

public struct WalletState: Codable, Equatable, Sendable {
    /// Height of the next block to request.
    public var startHeight: UInt64
    /// Unix time to scan from when no checkpoints exist yet (new wallets).
    public var startTimestamp: UInt64
    /// Most recent block hashes (newest first, max 100).
    public var lastKnownBlockHashes: [Hash32]
    /// Sparse checkpoints every 5000 blocks (newest first).
    public var blockHashCheckpoints: [Hash32]
    public var lastKnownBlockHeight: UInt64
    public var outputs: [OwnedOutput]
    public var transactions: [WalletTransaction]

    public init(startHeight: UInt64 = 0, startTimestamp: UInt64 = 0) {
        self.startHeight = startHeight
        self.startTimestamp = startTimestamp
        self.lastKnownBlockHashes = []
        self.blockHashCheckpoints = []
        self.lastKnownBlockHeight = 0
        self.outputs = []
        self.transactions = []
    }

    public var checkpoints: [Hash32] { lastKnownBlockHashes + blockHashCheckpoints }

    /// Unspent, not pending, and unlocked at `height`.
    public func spendableOutputs(currentHeight: UInt64, now: UInt64 = UInt64(Date().timeIntervalSince1970)) -> [OwnedOutput] {
        outputs.filter { !$0.isSpent && $0.pendingSpendTxHash == nil && $0.keyImage != nil
            && WalletState.isUnlocked(unlockTime: $0.unlockTime, currentHeight: currentHeight, now: now) }
    }

    public func balance(currentHeight: UInt64, now: UInt64 = UInt64(Date().timeIntervalSince1970)) -> (unlocked: UInt64, locked: UInt64) {
        var unlocked: UInt64 = 0
        var locked: UInt64 = 0
        for o in outputs where !o.isSpent && o.pendingSpendTxHash == nil {
            if WalletState.isUnlocked(unlockTime: o.unlockTime, currentHeight: currentHeight, now: now) {
                unlocked += o.amount
            } else {
                locked += o.amount
            }
        }
        return (unlocked, locked)
    }

    /// traaitt/src/utilities/Utilities.cpp isInputUnlocked
    public static func isUnlocked(unlockTime: UInt64, currentHeight: UInt64, now: UInt64) -> Bool {
        if unlockTime == 0 { return true }
        if unlockTime >= XTEConfig.maxBlockNumber {
            return now + XTEConfig.lockedTxAllowedDeltaSeconds >= unlockTime
        }
        return currentHeight + XTEConfig.lockedTxAllowedDeltaBlocks >= unlockTime
    }

    mutating func recordBlockHash(_ hash: Hash32, height: UInt64) {
        lastKnownBlockHashes.insert(hash, at: 0)
        if lastKnownBlockHashes.count > 100 { lastKnownBlockHashes.removeLast() }
        if height % 5000 == 0 {
            blockHashCheckpoints.insert(hash, at: 0)
        }
        lastKnownBlockHeight = height
        startHeight = height + 1
    }

    /// Drops everything at or above `height` (chain reorganisation).
    mutating func rewind(to height: UInt64) {
        outputs.removeAll { $0.blockHeight >= height }
        for i in outputs.indices {
            if let s = outputs[i].spendHeight, s >= height { outputs[i].spendHeight = nil }
        }
        transactions.removeAll { $0.blockHeight >= height && $0.blockHeight != 0 }
        // We don't keep the hashes per height, so drop the recent cache; sparse checkpoints remain valid if below.
        lastKnownBlockHashes.removeAll()
        startHeight = height
        lastKnownBlockHeight = height > 0 ? height - 1 : 0
    }
}

// MARK: - Outgoing (unconfirmed) transactions

extension WalletState {
    /// Records a broadcast transaction: locks its inputs and adds an unconfirmed history entry.
    public mutating func recordSent(_ tx: PreparedTransaction, timestamp: UInt64 = UInt64(Date().timeIntervalSince1970)) {
        let used = Set(tx.inputs.map(\.key))
        for i in outputs.indices where used.contains(outputs[i].key) {
            outputs[i].pendingSpendTxHash = tx.hash
        }
        let spent = tx.inputs.reduce(UInt64(0)) { $0 + $1.amount }
        transactions.insert(WalletTransaction(
            hash: tx.hash, amount: Int64(tx.change) - Int64(spent), fee: tx.fee,
            blockHeight: 0, timestamp: timestamp, paymentID: tx.paymentID ?? "",
            unlockTime: tx.transaction.unlockTime, isCoinbase: false), at: 0)
    }

    public var pendingTransactionHashes: [Hash32] {
        transactions.filter { !$0.isConfirmed }.map(\.hash)
    }

    /// Applies /get_transactions_status: transactions the node no longer knows were dropped,
    /// so their inputs become spendable again (WalletSynchronizer::checkLockedTransactions).
    public mutating func applyStatus(_ status: TransactionsStatus) {
        let unknown = Set(status.transactionsUnknown)
        guard !unknown.isEmpty else { return }
        transactions.removeAll { !$0.isConfirmed && unknown.contains($0.hash) }
        for i in outputs.indices {
            if let h = outputs[i].pendingSpendTxHash, unknown.contains(h) {
                outputs[i].pendingSpendTxHash = nil
            }
        }
    }

    /// Balance of outputs locked by our own unconfirmed sends is not counted;
    /// this is the amount of change we expect back once they confirm.
    public var pendingOutgoing: UInt64 {
        transactions.filter { !$0.isConfirmed && $0.amount < 0 }.reduce(UInt64(0)) { $0 + UInt64(-$1.amount) }
    }
}
