// Copyright (c) 2026, TRRXITTE Int., incorporate. Licensed under AGPL-3.0.
//
// Exercises every daemon endpoint the iPad wallet uses against a live node:
//   /info, /fee, /getwalletsyncdata (+ scanning with a fresh wallet),
//   /get_global_indexes_for_range, /getrandom_outs, /get_transactions_status,
// and builds + verifies a fully ring-signed transaction offline using real decoys
// (it is NOT broadcast: there are no funds and no keys in CI).

import Foundation
import XTEWalletCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(msg)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
let explicitNode: NodeInfo? = {
    guard args.count > 1, !args[1].isEmpty else { return nil }
    let port = args.count > 2 ? Int(args[2]) ?? 443 : 443
    let ssl = args.count > 3 ? args[3] == "ssl" : (port == 443)
    return NodeInfo(name: args[1], host: args[1], port: port, ssl: ssl)
}()
/// Set REQUIRE_EXPLICIT_NODE=1 to fail if the requested node is down instead of trying the public list.
let strict = ProcessInfo.processInfo.environment["REQUIRE_EXPLICIT_NODE"] == "1"

func run() async {
    let list: [NodeInfo]
    do {
        list = try await DaemonClient.fetchNodeList()
        print("node list: \(list.count) nodes: \(list.map { "\($0.host):\($0.port)" }.joined(separator: ", "))")
    } catch {
        fail("node list: \(error)")
    }

    var candidates = [explicitNode ?? XTEConfig.defaultNode]
    if !strict { candidates += list.filter { !candidates.contains($0) } }

    var picked: (NodeInfo, DaemonInfo)?
    for candidate in candidates {
        do {
            let i = try await DaemonClient(node: candidate, timeout: 20).info()
            print("OK   \(candidate.baseURL) height=\(i.localHeight) network=\(i.networkTopHeight) peers=\(i.peers)")
            if picked == nil { picked = (candidate, i) }
        } catch {
            print("DOWN \(candidate.baseURL): \(error.localizedDescription)")
        }
    }
    guard let (node, info) = picked else { fail("no reachable XTE node") }
    let daemon = DaemonClient(node: node, timeout: 30)
    print("using \(node.baseURL)")
    guard info.networkTopHeight > 1000 else { fail("implausible height") }

    if let fee = try? await daemon.fee() {
        print("node fee: \(fee.amount) to \(fee.address.isEmpty ? "-" : fee.address)")
    }

    // Sync the last ~100 blocks with a brand new wallet.
    let keys = WalletKeys.generate()
    var state = WalletState(startHeight: info.localHeight > 120 ? info.localHeight - 120 : 0)
    let sync = WalletSynchronizer(scanner: BlockScanner(keys: keys))
    var amounts = Set<UInt64>()
    do {
        let r = try await daemon.walletSyncData(checkpoints: [], startHeight: state.startHeight, startTimestamp: 0, blockCount: 100, skipCoinbase: false)
        guard !r.items.isEmpty else { fail("getwalletsyncdata returned no blocks") }
        for b in r.items {
            for t in b.transactions { for o in t.outputs where TransactionBuilder.isPretty(o.amount) { amounts.insert(o.amount) } }
            if let cb = b.coinbaseTX { for o in cb.outputs where TransactionBuilder.isPretty(o.amount) { amounts.insert(o.amount) } }
        }
        try await sync.process(blocks: r.items, state: &state) { h in
            let lower = h - h % 10
            return try await daemon.globalIndexes(startHeight: lower, endHeight: lower + 10)
        }
        print("synced blocks \(r.items.first!.blockHeight)...\(r.items.last!.blockHeight); owned outputs: \(state.outputs.count)")
        guard state.outputs.isEmpty else { fail("fresh wallet found outputs") }
    } catch {
        fail("getwalletsyncdata: \(error)")
    }

    do {
        let lower = state.lastKnownBlockHeight - state.lastKnownBlockHeight % 10
        let idx = try await daemon.globalIndexes(startHeight: lower - 10, endHeight: lower)
        print("global indexes for \(lower - 10)..\(lower): \(idx.count) transactions")
        guard !idx.isEmpty else { fail("no global indexes") }
    } catch {
        fail("get_global_indexes_for_range: \(error)")
    }

    let testAmounts = Array(amounts.sorted().prefix(3))
    guard !testAmounts.isEmpty else { fail("no pretty output amounts seen in recent blocks") }
    let mixin = XTEConfig.mixinLimits(height: info.networkTopHeight).defaultMixin
    let outs: [RandomOutputs]
    do {
        outs = try await daemon.randomOutputs(amounts: testAmounts, count: mixin + 1)
        for o in outs { print("random outs for \(o.amount): \(o.outs.count)") }
        guard outs.count == testAmounts.count, outs.allSatisfy({ UInt64($0.outs.count) >= mixin }) else { fail("not enough random outs") }
    } catch {
        fail("getrandom_outs: \(error)")
    }

    do {
        let st = try await daemon.transactionsStatus(hashes: [CNCrypto.fastHash(Array("xte-node-check".utf8))])
        print("transactions status: unknown=\(st.transactionsUnknown.count)")
    } catch {
        fail("get_transactions_status: \(error)")
    }

    // Offline: build and fully verify a transaction whose ring members are real chain outputs
    // and whose input is a synthetic output paid to our fresh wallet (so it cannot be broadcast).
    do {
        let amount = testAmounts[0]
        let txKey = CNCrypto.generateKeys()
        let d = try CNCrypto.generateKeyDerivation(keys.publicViewKey, txKey.secretKey)
        let outKey = try CNCrypto.derivePublicKey(d, outputIndex: 0, base: keys.publicSpendKey)
        let ki = try CNCrypto.generateKeyImage(publicKey: outKey, secretKey: try CNCrypto.deriveSecretKey(d, outputIndex: 0, base: keys.privateSpendKey))
        let input = OwnedOutput(key: outKey, amount: amount, parentTransactionHash: Key32.zero, transactionPublicKey: txKey.publicKey,
                                transactionIndex: 0, globalOutputIndex: UInt64.max / 2, blockHeight: 1, unlockTime: 0,
                                keyImage: ki, spendHeight: nil, pendingSpendTxHash: nil)
        let fee = min(XTEConfig.minimumFee, amount)
        guard amount > fee else { print("skipping offline build: smallest amount \(amount) <= fee"); return }
        let p = try await TransactionBuilder.build(
            keys: keys, destinations: [Destination(address: WalletKeys.generate().address, amount: amount - fee)],
            paymentID: nil, fee: fee, mixin: mixin, nodeFee: nil, spendable: [input],
            networkHeight: info.networkTopHeight, decoys: DaemonDecoySource(daemon: daemon))
        let parsed = try CNTransaction.parse([UInt8](Data(hex: p.hex)!))
        print("built tx \(p.hash.hex) size=\(p.hex.count / 2) ring=\(parsed.inputs[0].keyOffsets.count) (not broadcast)")
    } catch {
        fail("offline build with live decoys: \(error)")
    }
    print("OK")
}

let sema = DispatchSemaphore(value: 0)
Task {
    await run()
    sema.signal()
}
sema.wait()
