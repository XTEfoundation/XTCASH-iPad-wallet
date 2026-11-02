// Copyright (c) 2018-2019, The TurtleCoin Developers
// Copyright (c) 2020-2026, TRRXITTE Int., incorporate
// Licensed under AGPL-3.0.
//
// Scans blocks from /getwalletsyncdata for outputs that belong to this wallet,
// following traaitt/src/walletbackend/WalletSynchronizer.cpp.

import Foundation

public struct BlockScanner: Sendable {
    public let publicSpendKey: PublicKey
    public let privateViewKey: SecretKey
    public let privateSpendKey: SecretKey?

    public init(keys: WalletKeys) {
        publicSpendKey = keys.publicSpendKey
        privateViewKey = keys.privateViewKey
        privateSpendKey = keys.privateSpendKey
    }

    public init(publicSpendKey: PublicKey, privateViewKey: SecretKey, privateSpendKey: SecretKey?) {
        self.publicSpendKey = publicSpendKey
        self.privateViewKey = privateViewKey
        self.privateSpendKey = privateSpendKey
    }

    /// Outputs of `tx` that are ours.
    public func ownedOutputs(of tx: SyncTransaction, blockHeight: UInt64) -> [OwnedOutput] {
        guard let derivation = try? CNCrypto.generateKeyDerivation(tx.txPublicKey, privateViewKey) else { return [] }
        var result: [OwnedOutput] = []
        for (i, out) in tx.outputs.enumerated() {
            guard let spendKey = try? CNCrypto.underivePublicKey(derivation, outputIndex: UInt64(i), derivedKey: out.key),
                  spendKey == publicSpendKey else { continue }
            var keyImage: KeyImage?
            if let sk = privateSpendKey,
               let ephemeralSecret = try? CNCrypto.deriveSecretKey(derivation, outputIndex: UInt64(i), base: sk) {
                keyImage = try? CNCrypto.generateKeyImage(publicKey: out.key, secretKey: ephemeralSecret)
            }
            result.append(OwnedOutput(
                key: out.key, amount: out.amount, parentTransactionHash: tx.hash,
                transactionPublicKey: tx.txPublicKey, transactionIndex: UInt64(i),
                globalOutputIndex: out.globalIndex, blockHeight: blockHeight, unlockTime: tx.unlockTime,
                keyImage: keyImage, spendHeight: nil, pendingSpendTxHash: nil))
        }
        return result
    }
}

public enum SyncError: Error, Equatable, LocalizedError {
    case missingGlobalIndexes(Hash32)

    public var errorDescription: String? {
        switch self {
        case .missingGlobalIndexes(let h): return "Node did not return global output indexes for \(h.hex.prefix(12))…"
        }
    }
}

/// Applies a batch of blocks to the wallet state.
public struct WalletSynchronizer: Sendable {
    public let scanner: BlockScanner

    public init(scanner: BlockScanner) { self.scanner = scanner }

    /// Processes blocks. `globalIndexes` is used to fill in output indexes the daemon does not include.
    /// `fetchIndexes` is called lazily with a block height when one of our outputs lacks a global index.
    public func process(blocks: [SyncBlock], state: inout WalletState,
                        fetchIndexes: (UInt64) async throws -> [Hash32: [UInt64]]) async throws {
        guard let first = blocks.first else { return }
        // Fork / re-org: daemon gave us blocks we already processed.
        if first.blockHeight < state.startHeight && !state.lastKnownBlockHashes.isEmpty {
            state.rewind(to: first.blockHeight)
        }

        var keyImageIndex: [KeyImage: Int] = [:]
        for (i, o) in state.outputs.enumerated() { if let ki = o.keyImage { keyImageIndex[ki] = i } }

        for block in blocks {
            if block.blockHeight < state.startHeight && !state.lastKnownBlockHashes.isEmpty { continue }
            var cachedIndexes: [Hash32: [UInt64]]?

            var txs: [(SyncTransaction, Bool)] = []
            if let cb = block.coinbaseTX { txs.append((cb, true)) }
            txs += block.transactions.map { ($0, false) }

            for (tx, isCoinbase) in txs {
                var received: UInt64 = 0
                var spent: UInt64 = 0

                var mine = scanner.ownedOutputs(of: tx, blockHeight: block.blockHeight)
                for j in mine.indices where mine[j].globalOutputIndex == nil {
                    if cachedIndexes == nil { cachedIndexes = try await fetchIndexes(block.blockHeight) }
                    guard let idx = cachedIndexes?[tx.hash], idx.count > Int(mine[j].transactionIndex) else {
                        throw SyncError.missingGlobalIndexes(tx.hash)
                    }
                    mine[j].globalOutputIndex = idx[Int(mine[j].transactionIndex)]
                }
                for o in mine {
                    // Ignore duplicates (e.g. re-processing after a partial batch).
                    if state.outputs.contains(where: { $0.key == o.key }) { continue }
                    received += o.amount
                    state.outputs.append(o)
                    if let ki = o.keyImage { keyImageIndex[ki] = state.outputs.count - 1 }
                }

                for input in tx.inputs {
                    guard let idx = keyImageIndex[input.keyImage] else { continue }
                    if state.outputs[idx].spendHeight == nil {
                        state.outputs[idx].spendHeight = block.blockHeight
                        state.outputs[idx].pendingSpendTxHash = nil
                        spent += state.outputs[idx].amount
                    }
                }

                guard received > 0 || spent > 0 else { continue }

                let inputSum = tx.inputs.reduce(UInt64(0)) { $0 + $1.amount }
                let outputSum = tx.outputs.reduce(UInt64(0)) { $0 + $1.amount }
                let fee = (isCoinbase || spent == 0 || inputSum < outputSum) ? 0 : inputSum - outputSum
                let record = WalletTransaction(
                    hash: tx.hash, amount: Int64(received) - Int64(spent), fee: fee,
                    blockHeight: block.blockHeight, timestamp: block.blockTimestamp,
                    paymentID: tx.paymentID, unlockTime: tx.unlockTime, isCoinbase: isCoinbase)
                if let existing = state.transactions.firstIndex(where: { $0.hash == tx.hash }) {
                    state.transactions[existing] = record
                } else {
                    state.transactions.append(record)
                }
            }
            state.recordBlockHash(block.blockHash, height: block.blockHeight)
        }
        state.transactions.sort { ($0.blockHeight == 0 ? UInt64.max : $0.blockHeight) > ($1.blockHeight == 0 ? UInt64.max : $1.blockHeight) }
    }

    /// One round-trip to the daemon. Returns true when the wallet is at the daemon's top block.
    public func syncOnce(daemon: DaemonAPI, state: inout WalletState, blockCount: UInt64 = XTEConfig.blocksPerSyncRequest) async throws -> Bool {
        let checkpoints = state.checkpoints
        let response = try await daemon.walletSyncData(
            checkpoints: checkpoints,
            startHeight: checkpoints.isEmpty ? state.startHeight : 0,
            startTimestamp: checkpoints.isEmpty ? state.startTimestamp : 0,
            blockCount: blockCount,
            skipCoinbase: false)
        if response.items.isEmpty {
            if let top = response.topBlock {
                state.lastKnownBlockHeight = max(state.lastKnownBlockHeight, top.height)
            }
            return response.synced ?? true
        }
        try await process(blocks: response.items, state: &state) { height in
            let lower = height - height % 10
            return try await daemon.globalIndexes(startHeight: lower, endHeight: lower + 10)
        }
        return false
    }
}
