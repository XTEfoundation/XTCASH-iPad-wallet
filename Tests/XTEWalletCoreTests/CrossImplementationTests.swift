import XCTest
@testable import XTEWalletCore

final class CrossImplementationTests: XCTestCase {
    struct Vector: Decodable {
        let hex: String
        let hash: String
        let prefixHash: String
        let keyImage: String
        let ring: [String: String]
        let paymentID: String
        let friendAmount: UInt64
    }

    func testTransactionFromTurtleCoinUtils() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "turtlecoin-utils-tx", withExtension: "json", subdirectory: "Vectors"))
        let v = try JSONDecoder().decode(Vector.self, from: Data(contentsOf: url))
        let bytes = [UInt8](try XCTUnwrap(Data(hex: v.hex)))
        let tx = try CNTransaction.parse(bytes)

        XCTAssertEqual(tx.serialized(), bytes, "re-serialization must be byte identical")
        XCTAssertEqual(tx.hash.hex, v.hash)
        XCTAssertEqual(tx.prefixHash.hex, v.prefixHash)
        XCTAssertEqual(tx.paymentID, v.paymentID)
        XCTAssertEqual(tx.inputs.count, 1)
        XCTAssertEqual(tx.inputs[0].keyImage.hex, v.keyImage)

        // Resolve relative offsets into ring keys and verify the ring signature with our crypto.
        var abs: [UInt64] = []
        for (i, o) in tx.inputs[0].keyOffsets.enumerated() { abs.append(i == 0 ? o : abs[i - 1] + o) }
        XCTAssertEqual(abs, [1001, 1003, 1005, 1007])
        let ring = abs.map { Key32(hex: v.ring[String($0)]!)! }
        XCTAssertTrue(CNCrypto.checkRingSignature(prefixHash: tx.prefixHash, keyImage: tx.inputs[0].keyImage,
                                                  publicKeys: ring, signatures: tx.signatures[0]))

        // The recipient (non-deterministic keys vector wallet) finds its 90.00 XTE.
        let friend = try WalletKeys.fromKeys(
            privateSpendKeyHex: "55e0aa4ca65c0ae016c7364eec313f56fc162901ead0e38a9f846686ac78560f",
            privateViewKeyHex: "1f3f6c220dd9f97619dbf44d967f79f3041b9b1c63da2c895f980f1411d5d704")
        let sync = SyncTransaction(hash: tx.hash, txPublicKey: try XCTUnwrap(tx.transactionPublicKey), unlockTime: tx.unlockTime,
                                   outputs: tx.outputs.map { SyncKeyOutput(key: $0.key, amount: $0.amount, globalIndex: 1) },
                                   inputs: [], paymentID: v.paymentID)
        XCTAssertEqual(BlockScanner(keys: friend).ownedOutputs(of: sync, blockHeight: 1).reduce(0) { $0 + $1.amount }, v.friendAmount)

        // The sender (mnemonic vector wallet) derives the same key image for its spent output.
        let me = try WalletKeys.fromMnemonic("skulls woozy ouch summon gifts huts waffle ourselves obtains hexagon tadpoles hacksaw dormant hence abort listen history atom cadets stylishly snout vegan girth guest history")
        let change = BlockScanner(keys: me).ownedOutputs(of: sync, blockHeight: 1)
        XCTAssertEqual(change.reduce(0) { $0 + $1.amount }, 0, "all inputs were spent to friend + fee")
    }
}
