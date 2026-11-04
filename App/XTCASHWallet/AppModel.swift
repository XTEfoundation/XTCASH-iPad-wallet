// Copyright (c) 2026, TRRXITTE Int., incorporate. Licensed under AGPL-3.0.

import Foundation
import SwiftUI
import XTEWalletCore

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable { case onboarding, locked, unlocked }

    @Published private(set) var phase: Phase
    @Published private(set) var address: String = ""
    @Published private(set) var state = WalletState()
    @Published private(set) var daemonInfo: DaemonInfo?
    @Published private(set) var nodeError: String?
    @Published private(set) var syncError: String?
    @Published private(set) var isSyncing = false
    @Published var node: NodeInfo { didSet { Settings.selectedNode = node; restartSync() } }
    @Published var nodes: [NodeInfo] = [XTEConfig.defaultNode]
    @Published var pendingURI: PaymentURI?
    @Published var lastError: String?

    private var keys: WalletKeys?
    private var syncTask: Task<Void, Never>?

    init() {
        node = Settings.selectedNode
        if let file = WalletStore.load() {
            address = file.address
            state = file.state
            phase = .locked
        } else {
            phase = .onboarding
        }
    }

    var daemon: DaemonClient { DaemonClient(node: node) }

    var networkHeight: UInt64 { daemonInfo?.networkTopHeight ?? state.lastKnownBlockHeight }

    var balance: (unlocked: UInt64, locked: UInt64) { state.balance(currentHeight: networkHeight) }

    var syncProgress: Double {
        guard let top = daemonInfo?.networkTopHeight, top > 0 else { return 0 }
        return min(1, Double(state.lastKnownBlockHeight) / Double(top))
    }

    var isWalletSynced: Bool {
        guard let top = daemonInfo?.networkTopHeight else { return false }
        return state.lastKnownBlockHeight + 1 >= top
    }

    // MARK: Wallet lifecycle

    func createWallet(_ newKeys: WalletKeys, scanHeight: UInt64?) throws {
        try KeychainStore.save(newKeys)
        var s = WalletState()
        if let h = scanHeight {
            s.startHeight = h
        } else {
            // Brand new wallet: nothing can exist before now.
            s.startTimestamp = UInt64(Date().timeIntervalSince1970) - 600
        }
        keys = newKeys
        address = newKeys.address.encoded()
        state = s
        try persist()
        phase = .unlocked
        restartSync()
    }

    func unlock() {
        do {
            let k = try KeychainStore.load(reason: "Unlock your XTCASH wallet")
            guard k.address.encoded() == address else {
                lastError = "Keychain keys do not match this wallet."
                return
            }
            keys = k
            phase = .unlocked
            restartSync()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func lock() {
        syncTask?.cancel()
        syncTask = nil
        keys = nil
        if phase == .unlocked { phase = .locked }
    }

    func deleteWallet() throws {
        lock()
        try KeychainStore.delete()
        WalletStore.delete()
        state = WalletState()
        address = ""
        phase = .onboarding
    }

    /// Requires a fresh Face ID / Touch ID / passcode check, then returns the keys for display.
    func keysForBackup() async throws -> WalletKeys {
        try await KeychainStore.authenticate(reason: "Show your private keys and mnemonic seed")
        if let keys { return keys }
        return try KeychainStore.load(reason: "Show your private keys and mnemonic seed")
    }

    func rescan(from height: UInt64) {
        state = WalletState(startHeight: height)
        try? persist()
        restartSync()
    }

    private func persist() throws {
        try WalletStore.save(WalletFile(address: address, state: state))
    }

    // MARK: Node

    func refreshNodeList() async {
        do {
            var list = try await DaemonClient.fetchNodeList()
            if !list.contains(XTEConfig.defaultNode) { list.insert(XTEConfig.defaultNode, at: 0) }
            nodes = list
        } catch {
            nodeError = "Could not load node list: \(error.localizedDescription)"
        }
    }

    func refreshInfo() async {
        do {
            daemonInfo = try await daemon.info()
            nodeError = nil
        } catch {
            daemonInfo = nil
            nodeError = error.localizedDescription
            // The built-in default node is unreachable: fail over once to the first public
            // node from the official list that answers. A node the user picked is never replaced.
            if node == XTEConfig.defaultNode, let alternative = await firstReachablePublicNode() {
                nodeError = nil
                node = alternative   // didSet persists the choice and restarts sync
            }
        }
    }

    private func firstReachablePublicNode() async -> NodeInfo? {
        if nodes.count <= 1 { await refreshNodeList() }
        for candidate in nodes where candidate != XTEConfig.defaultNode {
            if (try? await DaemonClient(node: candidate, timeout: 10).info()) != nil { return candidate }
        }
        return nil
    }

    // MARK: Sync

    func restartSync() {
        syncTask?.cancel()
        guard phase == .unlocked, let keys else { return }
        let synchronizer = WalletSynchronizer(scanner: BlockScanner(keys: keys))
        let client = daemon
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshInfo()
                var caughtUp = false
                do {
                    self.isSyncing = true
                    var rounds = 0
                    while !Task.isCancelled && rounds < 50 {
                        var working = self.state
                        caughtUp = try await synchronizer.syncOnce(daemon: client, state: &working)
                        rounds += 1
                        if Task.isCancelled { return }
                        self.merge(working)
                        if caughtUp { break }
                        if rounds % 5 == 0 { try? self.persist() }
                    }
                    let pending = self.state.pendingTransactionHashes
                    if !pending.isEmpty, let status = try? await client.transactionsStatus(hashes: pending), !Task.isCancelled {
                        var s = self.state
                        s.applyStatus(status)
                        self.state = s
                    }
                    try? self.persist()
                    self.syncError = nil
                } catch is CancellationError {
                    return
                } catch {
                    self.syncError = error.localizedDescription
                }
                self.isSyncing = false
                if caughtUp || self.syncError != nil {
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                }
            }
        }
    }

    /// Adopts a freshly synced state while keeping sends that were broadcast during the network call.
    private func merge(_ synced: WalletState) {
        var s = synced
        for t in state.transactions where !t.isConfirmed && !s.transactions.contains(where: { $0.hash == t.hash }) {
            s.transactions.insert(t, at: 0)
        }
        for o in state.outputs where o.pendingSpendTxHash != nil {
            if let i = s.outputs.firstIndex(where: { $0.key == o.key }), s.outputs[i].spendHeight == nil {
                s.outputs[i].pendingSpendTxHash = o.pendingSpendTxHash
            }
        }
        state = s
    }

    // MARK: Send

    struct SendRequest {
        var destination: XTEAddress
        var amount: UInt64
        var paymentID: String?
        var fee: UInt64
        var mixin: UInt64
    }

    /// Builds and signs; does not broadcast. Shown to the user for confirmation.
    func prepare(_ request: SendRequest) async throws -> PreparedTransaction {
        guard let keys else { throw TransferError.viewOnlyWallet }
        let client = daemon
        let info = try await client.info()
        daemonInfo = info
        var nodeFee: (address: XTEAddress, amount: UInt64)?
        if let fee = try? await client.fee(), fee.amount > 0, let addr = try? XTEAddress.decode(fee.address) {
            nodeFee = (address: addr, amount: fee.amount)
        }
        return try await TransactionBuilder.build(
            keys: keys,
            destinations: [Destination(address: request.destination, amount: request.amount)],
            paymentID: request.paymentID, fee: request.fee, mixin: request.mixin,
            nodeFee: nodeFee,
            spendable: state.spendableOutputs(currentHeight: info.networkTopHeight),
            networkHeight: info.networkTopHeight,
            decoys: DaemonDecoySource(daemon: client))
    }

    func broadcast(_ tx: PreparedTransaction) async throws {
        try await daemon.sendRawTransaction(hex: tx.hex)
        state.recordSent(tx)
        try? persist()
    }
}
