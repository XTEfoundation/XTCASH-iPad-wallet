import XCTest
@testable import XTEWalletCore

final class UtilityTests: XCTestCase {
    let addr = "XT2spqycEh2YFB67qoiRp7bSZ64NTkx8h6P5tNxrgVt1KShrMcFBaS33aVG7jm4YVaSyE7rrsaprdKD86ECGLwah1kCSrB5qP"
    let pid = "b23df6e84c1dd619d3601a28e5948d92a0d096aea1621969c591a90e986794a0"
    let integrated = "XT2FEkMPdQZHvxUQLgxbnM9EY6yAxT51r9QCb1DdjEFMAZt5DaAyzdTHHs5HLmC7gtA53TYZ3Me5W96VmhHVg9UXHFsDuJc5Nn8YFB67qoiRp7bSZ64NTkx8h6P5tNxrgVt1KShrMcFBaS33aVG7jm4YVaSyE7rrsaprdKD86ECGLwah1kCVyRK29"

    func testVarint() {
        for v: UInt64 in [0, 1, 127, 128, 300, 1334, 16384, UInt64.max] {
            let e = Varint.encode(v)
            let d = Varint.decode(e)
            XCTAssertEqual(d?.0, v)
            XCTAssertEqual(d?.1, e.count)
        }
        XCTAssertEqual(Varint.encode(1334), [0xb6, 0x0a])
        XCTAssertNil(Varint.decode([0x80]))
    }

    func testBase58RoundTrip() {
        for n in [0, 1, 7, 8, 9, 16, 69, 133] {
            let bytes = CNCrypto.randomBytes(n)
            XCTAssertEqual(Base58.decode(Base58.encode(bytes)), bytes)
        }
        XCTAssertNil(Base58.decode("0OIl"))
    }

    func testAmountFormatting() {
        XCTAssertEqual(Amount.format(0, withTicker: false), "0.00")
        XCTAssertEqual(Amount.format(1, withTicker: false), "0.01")
        XCTAssertEqual(Amount.format(123456789, withTicker: false), "1,234,567.89")
        XCTAssertEqual(Amount.format(100), "1.00 XTE")
        XCTAssertEqual(Amount.parse("1.5"), 150)
        XCTAssertEqual(Amount.parse("1,234.56"), 123456)
        XCTAssertEqual(Amount.parse("0.01"), 1)
        XCTAssertNil(Amount.parse("0.001"))
        XCTAssertNil(Amount.parse("abc"))
        XCTAssertNil(Amount.parse("-1"))
    }

    func testURIParsing() throws {
        let plain = try PaymentURI.parse(addr)
        XCTAssertEqual(plain.address, addr)
        XCTAssertNil(plain.amount)

        let u = try PaymentURI.parse("xte://\(addr)?amount=12345&name=Coffee%20Shop&paymentid=\(pid)")
        XCTAssertEqual(u.address, addr)
        XCTAssertEqual(u.amount, 12345)
        XCTAssertEqual(u.name, "Coffee Shop")
        XCTAssertEqual(u.paymentID, pid)

        let u2 = try PaymentURI.parse("traaitt:\(addr)?amount=100")
        XCTAssertEqual(u2.amount, 100)

        XCTAssertEqual(try PaymentURI.parse(u.uriString()), u)

        XCTAssertThrowsError(try PaymentURI.parse("bitcoin:\(addr)"))
        XCTAssertThrowsError(try PaymentURI.parse("xte://notanaddress"))
        XCTAssertThrowsError(try PaymentURI.parse("xte://\(addr)?amount=abc"))
        XCTAssertThrowsError(try PaymentURI.parse("xte://\(addr)?paymentid=1234"))
        XCTAssertThrowsError(try PaymentURI.parse("xte://\(integrated)?paymentid=\(pid)"))
        XCTAssertNoThrow(try PaymentURI.parse("xte://\(integrated)"))
    }

    func testDenominations() {
        XCTAssertEqual(TransactionBuilder.splitIntoDenominations(1234567).sorted(), [7, 60, 500, 4000, 30000, 200000, 1000000])
        XCTAssertEqual(TransactionBuilder.splitIntoDenominations(1010).sorted(), [10, 1000])
        XCTAssertEqual(TransactionBuilder.splitIntoDenominations(0), [])
        let big: UInt64 = 5 * XTEConfig.maxOutputSizeClient * 10 + 3
        let parts = TransactionBuilder.splitIntoDenominations(big)
        XCTAssertEqual(parts.reduce(0, +), big)
        XCTAssertTrue(parts.allSatisfy { $0 <= XTEConfig.maxOutputSizeClient && TransactionBuilder.isPretty($0) })
        XCTAssertTrue(TransactionBuilder.isPretty(9000))
        XCTAssertFalse(TransactionBuilder.isPretty(9100))
        XCTAssertFalse(TransactionBuilder.isPretty(0))
    }

    func testUnlockRules() {
        XCTAssertTrue(WalletState.isUnlocked(unlockTime: 0, currentHeight: 1, now: 0))
        XCTAssertTrue(WalletState.isUnlocked(unlockTime: 100, currentHeight: 99, now: 0))
        XCTAssertFalse(WalletState.isUnlocked(unlockTime: 100, currentHeight: 98, now: 0))
        XCTAssertFalse(WalletState.isUnlocked(unlockTime: 1_700_000_000, currentHeight: 10, now: 1_699_999_000))
        XCTAssertTrue(WalletState.isUnlocked(unlockTime: 1_700_000_000, currentHeight: 10, now: 1_699_999_960))
    }

    func testMixinLimits() {
        XCTAssertEqual(XTEConfig.mixinLimits(height: 1_200_000).defaultMixin, 8)
        XCTAssertEqual(XTEConfig.mixinLimits(height: 900_000).maximum, 5)
        XCTAssertEqual(XTEConfig.mixinLimits(height: 500_000).maximum, 4)
        XCTAssertEqual(XTEConfig.mixinLimits(height: 10).defaultMixin, 3)
    }

    func testNodeListParsing() throws {
        let json = """
        {"nodes":[{"name":"eu","url":"eu.trrxitte.com","port":14485,"ssl":false,"cache":false},
                  {"name":"main","url":"main.trrxitte.com","port":443,"ssl":true}]}
        """
        let nodes = try NodeList.parse(Data(json.utf8))
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].baseURL.absoluteString, "http://eu.trrxitte.com:14485")
        XCTAssertEqual(nodes[1].baseURL.absoluteString, "https://main.trrxitte.com")
        let rt = try JSONDecoder().decode(NodeInfo.self, from: JSONEncoder().encode(nodes[0]))
        XCTAssertEqual(rt, nodes[0])
    }

    func testDaemonJSONDecoding() throws {
        let info = try JSONDecoder().decode(DaemonInfo.self, from: Data("""
        {"height":1500001,"network_height":1500003,"incoming_connections_count":2,"outgoing_connections_count":8,"difficulty":1234,"synced":true,"status":"OK"}
        """.utf8))
        XCTAssertEqual(info.localHeight, 1_500_000)
        XCTAssertEqual(info.networkTopHeight, 1_500_002)
        XCTAssertEqual(info.peers, 10)

        let h = String(repeating: "ab", count: 32)
        let sync = try JSONDecoder().decode(WalletSyncResponse.self, from: Data("""
        {"status":"OK","synced":false,"items":[{"blockHeight":5,"blockHash":"\(h)","blockTimestamp":1700000000,
          "coinbaseTX":{"outputs":[{"key":"\(h)","amount":100}],"hash":"\(h)","txPublicKey":"\(h)","unlockTime":45},
          "transactions":[{"outputs":[],"hash":"\(h)","txPublicKey":"\(h)","unlockTime":"0","paymentID":"","inputs":[{"amount":10,"key_offsets":[1,2],"k_image":"\(h)"}]}]}]}
        """.utf8))
        XCTAssertEqual(sync.items.count, 1)
        XCTAssertEqual(sync.items[0].coinbaseTX?.unlockTime, 45)
        XCTAssertEqual(sync.items[0].transactions[0].inputs[0].amount, 10)
    }
}
