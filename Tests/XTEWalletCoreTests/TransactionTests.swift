import XCTest
@testable import XTEWalletCore

/// Decoys are real curve points so ring signatures are well formed.
struct LocalDecoys: DecoySource {
    func randomOutputs(amounts: [UInt64], count: UInt64) async throws -> [RandomOutputs] {
        amounts.map { a in
            RandomOutputs(amount: a, outs: (0..<count).map { _ in
                RandomOutputEntry(globalAmountIndex: UInt64.random(in: 0..<10_000), outKey: CNCrypto.generateKeys().publicKey)
            })
        }
    }
}

extension RandomOutputs {
    init(amount: UInt64, outs: [RandomOutputEntry]) {
        self = try! JSONDecoder().decode(RandomOutputs.self, from: JSONSerialization.data(withJSONObject: [
            "amount": amount,
            "outs": outs.map { ["global_amount_index": $0.globalAmountIndex, "out_key": $0.outKey.hex] },
        ]))
    }
}

extension RandomOutputEntry {
    init(globalAmountIndex: UInt64, outKey: PublicKey) {
        self = try! JSONDecoder().decode(RandomOutputEntry.self, from: JSONSerialization.data(withJSONObject: [
            "global_amount_index": globalAmountIndex, "out_key": outKey.hex,
        ]))
    }
}

/// Builds a transaction paying `amounts` to `to`, exactly like an external sender would.
func payment(to: XTEAddress, amounts: [UInt64], startGlobalIndex: UInt64, unlockTime: UInt64 = 0) throws -> SyncTransaction {
    let txKey = CNCrypto.generateKeys()
    let d = try CNCrypto.generateKeyDerivation(to.publicViewKey, txKey.secretKey)
    var outs: [SyncKeyOutput] = []
    for (i, a) in amounts.enumerated() {
        let key = try CNCrypto.derivePublicKey(d, outputIndex: UInt64(i), base: to.publicSpendKey)
        outs.append(SyncKeyOutput(key: key, amount: a, globalIndex: startGlobalIndex + UInt64(i)))
    }
    return SyncTransaction(hash: CNCrypto.fastHash(CNCrypto.randomBytes(32)), txPublicKey: txKey.publicKey,
                           unlockTime: unlockTime, outputs: outs, inputs: [], paymentID: "")
}

func block(_ height: UInt64, _ txs: [SyncTransaction]) -> SyncBlock {
    SyncBlock(blockHeight: height, blockHash: CNCrypto.fastHash(Varint.encode(height) + CNCrypto.randomBytes(8)),
              blockTimestamp: 1_700_000_000 + height * 45, coinbaseTX: nil, transactions: txs)
}

final class TransactionTests: XCTestCase {
    let noIndexes: (UInt64) async throws -> [Hash32: [UInt64]] = { _ in [:] }

    func testScanSendAndSpendDetection() async throws {
        let me = WalletKeys.generate()
        let friend = WalletKeys.generate()
        let stranger = WalletKeys.generate()

        // 1. Receive 1234.56 XTE (pretty outputs) plus a payment to someone else.
        let incoming = try payment(to: me.address, amounts: [100000, 20000, 3000, 400, 50, 6], startGlobalIndex: 500)
        let other = try payment(to: stranger.address, amounts: [700], startGlobalIndex: 900)
        var state = WalletState()
        let sync = WalletSynchronizer(scanner: BlockScanner(keys: me))
        try await sync.process(blocks: [block(1_200_000, [incoming, other])], state: &state, fetchIndexes: noIndexes)

        XCTAssertEqual(state.outputs.count, 6)
        XCTAssertEqual(state.balance(currentHeight: 1_200_010).unlocked, 123456)
        XCTAssertEqual(state.transactions.count, 1)
        XCTAssertEqual(state.transactions[0].amount, 123456)
        XCTAssertEqual(state.startHeight, 1_200_001)
        XCTAssertTrue(state.outputs.allSatisfy { $0.keyImage != nil })

        // A view-only scanner sees the outputs but cannot compute key images.
        let viewOnly = BlockScanner(publicSpendKey: me.publicSpendKey, privateViewKey: me.privateViewKey, privateSpendKey: nil)
        XCTAssertEqual(viewOnly.ownedOutputs(of: incoming, blockHeight: 1).count, 6)
        XCTAssertTrue(viewOnly.ownedOutputs(of: incoming, blockHeight: 1).allSatisfy { $0.keyImage == nil })

        // 2. Send 250.00 XTE to friend with a payment ID, mixin 8, fee 1.00.
        let pid = String(repeating: "c4", count: 32)
        let prepared = try await TransactionBuilder.build(
            keys: me, destinations: [Destination(address: friend.address, amount: 25000)],
            paymentID: pid, fee: 100, mixin: 8, nodeFee: nil,
            spendable: state.spendableOutputs(currentHeight: 1_200_010), networkHeight: 1_200_010,
            decoys: LocalDecoys())

        let tx = prepared.transaction
        XCTAssertEqual(tx.version, 1)
        XCTAssertTrue(tx.inputs.allSatisfy { $0.keyOffsets.count == 9 })
        XCTAssertEqual(tx.paymentID, pid)
        XCTAssertTrue(tx.outputs.allSatisfy { TransactionBuilder.isPretty($0.amount) })
        XCTAssertEqual(tx.outputs.map(\.amount), tx.outputs.map(\.amount).sorted())
        let inSum = tx.inputs.reduce(0) { $0 + $1.amount }
        let outSum = tx.outputs.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(inSum - outSum, 100)

        // Serialization round-trip and independent signature verification.
        let parsed = try CNTransaction.parse([UInt8](Data(hex: prepared.hex)!))
        XCTAssertEqual(parsed, tx)
        XCTAssertEqual(parsed.hash, prepared.hash)
        XCTAssertNotNil(parsed.transactionPublicKey)
        for (i, input) in parsed.inputs.enumerated() {
            XCTAssertTrue(state.outputs.contains { $0.keyImage == input.keyImage }, "key image must be one of ours")
            // Absolute offsets are strictly increasing.
            var abs: [UInt64] = []
            for (j, o) in input.keyOffsets.enumerated() { abs.append(j == 0 ? o : abs[j - 1] + o) }
            XCTAssertEqual(abs, abs.sorted())
            XCTAssertEqual(parsed.signatures[i].count, 9)
        }

        // 3. Recipient scans the transaction and finds exactly 250.00 XTE + the payment ID.
        let asSync = SyncTransaction(
            hash: prepared.hash, txPublicKey: parsed.transactionPublicKey!, unlockTime: 0,
            outputs: parsed.outputs.enumerated().map { SyncKeyOutput(key: $0.element.key, amount: $0.element.amount, globalIndex: 2000 + UInt64($0.offset)) },
            inputs: parsed.inputs.map { SyncKeyInput(amount: $0.amount, keyImage: $0.keyImage) },
            paymentID: parsed.paymentID ?? "")
        let friendOuts = BlockScanner(keys: friend).ownedOutputs(of: asSync, blockHeight: 1_200_020)
        XCTAssertEqual(friendOuts.reduce(0) { $0 + $1.amount }, 25000)

        // 4. Our wallet: pending -> confirmed, spent inputs and change detected.
        state.recordSent(prepared)
        XCTAssertEqual(state.transactions.first?.isConfirmed, false)
        let pendingBalance = state.balance(currentHeight: 1_200_010)
        XCTAssertEqual(pendingBalance.unlocked, 123456 - prepared.inputs.reduce(0) { $0 + $1.amount })

        try await sync.process(blocks: [block(1_200_020, [asSync])], state: &state, fetchIndexes: noIndexes)
        XCTAssertEqual(state.balance(currentHeight: 1_200_030).unlocked, 123456 - 25000 - 100)
        XCTAssertEqual(state.transactions.count, 2)
        let sent = try XCTUnwrap(state.transactions.first { $0.hash == prepared.hash })
        XCTAssertTrue(sent.isConfirmed)
        XCTAssertEqual(sent.amount, -25100)
        XCTAssertEqual(sent.fee, 100)
        XCTAssertTrue(state.outputs.filter { $0.pendingSpendTxHash != nil }.isEmpty)
    }

    func testNotEnoughFundsAndValidation() async throws {
        let me = WalletKeys.generate()
        let incoming = try payment(to: me.address, amounts: [500], startGlobalIndex: 1)
        var state = WalletState()
        try await WalletSynchronizer(scanner: BlockScanner(keys: me)).process(blocks: [block(10, [incoming])], state: &state, fetchIndexes: noIndexes)
        let spendable = state.spendableOutputs(currentHeight: 100)

        do {
            _ = try await TransactionBuilder.build(keys: me, destinations: [Destination(address: me.address, amount: 500)], paymentID: nil,
                                                   fee: 100, mixin: 3, nodeFee: nil, spendable: spendable, networkHeight: 100, decoys: LocalDecoys())
            XCTFail("expected failure")
        } catch let e as TransferError {
            XCTAssertEqual(e, .notEnoughFunds(available: 500, required: 600))
        }
        do {
            _ = try await TransactionBuilder.build(keys: me, destinations: [Destination(address: me.address, amount: 100)], paymentID: nil,
                                                   fee: 10, mixin: 3, nodeFee: nil, spendable: spendable, networkHeight: 100, decoys: LocalDecoys())
            XCTFail("expected failure")
        } catch let e as TransferError { XCTAssertEqual(e, .feeTooSmall) }
        do {
            _ = try await TransactionBuilder.build(keys: me, destinations: [Destination(address: me.address, amount: 100)], paymentID: nil,
                                                   fee: 100, mixin: 9, nodeFee: nil, spendable: spendable, networkHeight: 1_200_000, decoys: LocalDecoys())
            XCTFail("expected failure")
        } catch let e as TransferError { XCTAssertEqual(e, .mixinOutOfRange(min: 0, max: 8)) }

        // Mixin 0 works and includes a node fee output.
        let nodeFeeAddr = WalletKeys.generate().address
        let p = try await TransactionBuilder.build(keys: me, destinations: [Destination(address: me.address, amount: 100)], paymentID: nil,
                                                   fee: 100, mixin: 0, nodeFee: (nodeFeeAddr, 50), spendable: spendable, networkHeight: 100, decoys: LocalDecoys())
        XCTAssertEqual(p.change, 250)
        XCTAssertEqual(p.transaction.inputs[0].keyOffsets, [1])
    }

    func testIntegratedAddressSetsPaymentID() async throws {
        let me = WalletKeys.generate()
        let incoming = try payment(to: me.address, amounts: [1000], startGlobalIndex: 42)
        var state = WalletState()
        try await WalletSynchronizer(scanner: BlockScanner(keys: me)).process(blocks: [block(10, [incoming])], state: &state, fetchIndexes: noIndexes)
        let friend = WalletKeys.generate().address
        let pid = String(repeating: "0f", count: 32)
        let integrated = XTEAddress(publicSpendKey: friend.publicSpendKey, publicViewKey: friend.publicViewKey, paymentID: pid)
        let p = try await TransactionBuilder.build(keys: me, destinations: [Destination(address: integrated, amount: 100)], paymentID: nil,
                                                   fee: 100, mixin: 3, nodeFee: nil, spendable: state.spendableOutputs(currentHeight: 20),
                                                   networkHeight: 20, decoys: LocalDecoys())
        XCTAssertEqual(p.transaction.paymentID, pid)
        do {
            _ = try await TransactionBuilder.build(keys: me, destinations: [Destination(address: integrated, amount: 100)],
                                                   paymentID: String(repeating: "aa", count: 32), fee: 100, mixin: 3, nodeFee: nil,
                                                   spendable: state.spendableOutputs(currentHeight: 20), networkHeight: 20, decoys: LocalDecoys())
            XCTFail("expected conflict")
        } catch let e as TransferError { XCTAssertEqual(e, .paymentIDConflict) }
    }

    func testGlobalIndexFetchAndLockedCoinbase() async throws {
        let me = WalletKeys.generate()
        var tx = try payment(to: me.address, amounts: [300], startGlobalIndex: 0, unlockTime: 60)
        tx = SyncTransaction(hash: tx.hash, txPublicKey: tx.txPublicKey, unlockTime: 60,
                             outputs: tx.outputs.map { SyncKeyOutput(key: $0.key, amount: $0.amount, globalIndex: nil) },
                             inputs: [], paymentID: "")
        var state = WalletState()
        var asked: [UInt64] = []
        try await WalletSynchronizer(scanner: BlockScanner(keys: me)).process(blocks: [block(17, [tx])], state: &state) { h in
            asked.append(h)
            return [tx.hash: [777]]
        }
        XCTAssertEqual(asked, [17])
        XCTAssertEqual(state.outputs.first?.globalOutputIndex, 777)
        XCTAssertEqual(state.balance(currentHeight: 30).locked, 300)
        XCTAssertEqual(state.balance(currentHeight: 59).unlocked, 300)
        XCTAssertTrue(state.spendableOutputs(currentHeight: 30).isEmpty)
    }

    func testDroppedPendingTransactionReleasesInputs() async throws {
        let me = WalletKeys.generate()
        let incoming = try payment(to: me.address, amounts: [1000], startGlobalIndex: 42)
        var state = WalletState()
        try await WalletSynchronizer(scanner: BlockScanner(keys: me)).process(blocks: [block(10, [incoming])], state: &state, fetchIndexes: noIndexes)
        let p = try await TransactionBuilder.build(keys: me, destinations: [Destination(address: WalletKeys.generate().address, amount: 100)],
                                                   paymentID: nil, fee: 100, mixin: 3, nodeFee: nil,
                                                   spendable: state.spendableOutputs(currentHeight: 20), networkHeight: 20, decoys: LocalDecoys())
        state.recordSent(p)
        XCTAssertEqual(state.balance(currentHeight: 20).unlocked, 0)
        XCTAssertEqual(state.pendingTransactionHashes, [p.hash])
        let json = #"{"status":"OK","transactionsInPool":[],"transactionsInBlock":[],"transactionsUnknown":["\#(p.hash.hex)"]}"#
        state.applyStatus(try JSONDecoder().decode(TransactionsStatus.self, from: Data(json.utf8)))
        XCTAssertEqual(state.balance(currentHeight: 20).unlocked, 1000)
        XCTAssertTrue(state.pendingTransactionHashes.isEmpty)
    }

    func testReorgRewinds() async throws {
        let me = WalletKeys.generate()
        let sync = WalletSynchronizer(scanner: BlockScanner(keys: me))
        var state = WalletState()
        try await sync.process(blocks: [block(10, []), block(11, [try payment(to: me.address, amounts: [5], startGlobalIndex: 1)]), block(12, [])],
                               state: &state, fetchIndexes: noIndexes)
        XCTAssertEqual(state.balance(currentHeight: 20).unlocked, 5)
        // Daemon now returns an alternative block 11 without our payment.
        try await sync.process(blocks: [block(11, []), block(12, [])], state: &state, fetchIndexes: noIndexes)
        XCTAssertEqual(state.balance(currentHeight: 20).unlocked, 0)
        XCTAssertEqual(state.startHeight, 13)
    }

    func testStateCodableRoundTrip() async throws {
        let me = WalletKeys.generate()
        var state = WalletState()
        try await WalletSynchronizer(scanner: BlockScanner(keys: me)).process(
            blocks: [block(10, [try payment(to: me.address, amounts: [5, 60], startGlobalIndex: 1)])], state: &state, fetchIndexes: noIndexes)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(WalletState.self, from: data), state)
    }
}
