import XCTest
@testable import XTEWalletCore

/// Vectors generated with turtlecoin-utils 3.x (the reference JS implementation used by the
/// TurtleCoin/traaitt wallets) using the XTE prefix 1334; the prefix-8411 address equals the
/// upstream wallet-backend-js test vector.
final class AddressMnemonicTests: XCTestCase {
    let seed = "skulls woozy ouch summon gifts huts waffle ourselves obtains hexagon tadpoles hacksaw dormant hence abort listen history atom cadets stylishly snout vegan girth guest history"
    let privSpend = "d61a57a59318d70ff77cc7f8ad7f62887c828da1d5d3f3b0d2f7d3fa596c2904"
    let privView = "688e5229df6463ec4c27f6ee11c3f1d3d4b4d2480c0aabe64fb807182cfdc801"
    let pubSpend = "abab87df609dbacc45494c6a8954cde81f934ddd6c32202b62f174798bc66e43"
    let pubView = "ba03787382200f68b89d7f82984d9b42d0d2c2d8f7026cdd51634a99bcc256bf"
    let xteAddress = "XT2spqycEh2YFB67qoiRp7bSZ64NTkx8h6P5tNxrgVt1KShrMcFBaS33aVG7jm4YVaSyE7rrsaprdKD86ECGLwah1kCSrB5qP"
    let trtlAddress = "TRTLv1s9JQeHAJFoHvcqVBPyHYom2ynKeK6dpYptbp8gQNzdzE73ZDkNmNurqfhhcMSUXpS1ZGEJKiKJUcPCyw7vYaCc354DCN1"
    let pid = "b23df6e84c1dd619d3601a28e5948d92a0d096aea1621969c591a90e986794a0"
    let integrated = "XT2FEkMPdQZHvxUQLgxbnM9EY6yAxT51r9QCb1DdjEFMAZt5DaAyzdTHHs5HLmC7gtA53TYZ3Me5W96VmhHVg9UXHFsDuJc5Nn8YFB67qoiRp7bSZ64NTkx8h6P5tNxrgVt1KShrMcFBaS33aVG7jm4YVaSyE7rrsaprdKD86ECGLwah1kCVyRK29"

    func testMnemonicToKeysAndAddress() throws {
        let keys = try WalletKeys.fromMnemonic(seed)
        XCTAssertEqual(keys.privateSpendKey.hex, privSpend)
        XCTAssertEqual(keys.privateViewKey.hex, privView)
        XCTAssertEqual(keys.publicSpendKey.hex, pubSpend)
        XCTAssertEqual(keys.publicViewKey.hex, pubView)
        XCTAssertTrue(keys.isDeterministic)
        XCTAssertEqual(keys.address.encoded(), xteAddress)
        XCTAssertEqual(xteAddress.count, XTEConfig.standardAddressLength)
    }

    func testMnemonicRoundTrip() throws {
        let words = Mnemonic.fromPrivateKey(Key32(hex: privSpend)!)
        XCTAssertEqual(words.joined(separator: " "), seed)
        XCTAssertEqual(try Mnemonic.toPrivateKey(seed).hex, privSpend)
        for _ in 0..<20 {
            let k = WalletKeys.generate()
            let m = try k.mnemonic()
            XCTAssertEqual(m.count, 25)
            let back = try WalletKeys.fromMnemonic(m.joined(separator: " "))
            XCTAssertEqual(back.privateSpendKey, k.privateSpendKey)
            XCTAssertEqual(back.privateViewKey, k.privateViewKey)
        }
    }

    func testMnemonicRejectsBadChecksumAndWords() {
        var words = seed.split(separator: " ").map(String.init)
        words[24] = words[0] == "abbey" ? "abducts" : "abbey"
        XCTAssertThrowsError(try Mnemonic.toPrivateKey(words.joined(separator: " ")))
        words = seed.split(separator: " ").map(String.init)
        words[3] = "notaword"
        XCTAssertThrowsError(try Mnemonic.toPrivateKey(words.joined(separator: " ")))
        XCTAssertThrowsError(try Mnemonic.toPrivateKey("skulls woozy"))
    }

    func testOtherPrefix() throws {
        let a = XTEAddress(publicSpendKey: Key32(hex: pubSpend)!, publicViewKey: Key32(hex: pubView)!, prefix: 3914525)
        XCTAssertEqual(a.encoded(), trtlAddress)
        XCTAssertEqual(try XTEAddress.decode(trtlAddress, expectedPrefix: 3914525), a)
        XCTAssertThrowsError(try XTEAddress.decode(trtlAddress))
    }

    func testDecodeStandard() throws {
        let a = try XTEAddress.decode(xteAddress)
        XCTAssertEqual(a.publicSpendKey.hex, pubSpend)
        XCTAssertEqual(a.publicViewKey.hex, pubView)
        XCTAssertNil(a.paymentID)
        XCTAssertTrue(XTEAddress.isValid(xteAddress))
    }

    func testIntegratedAddress() throws {
        let a = XTEAddress(publicSpendKey: Key32(hex: pubSpend)!, publicViewKey: Key32(hex: pubView)!, paymentID: pid)
        XCTAssertEqual(a.encoded(), integrated)
        XCTAssertEqual(integrated.count, XTEConfig.integratedAddressLength)
        let d = try XTEAddress.decode(integrated)
        XCTAssertEqual(d.paymentID, pid)
        XCTAssertEqual(d.standard.encoded(), xteAddress)
        XCTAssertFalse(XTEAddress.isValid(integrated, allowIntegrated: false))
    }

    func testChecksumAndCorruption() {
        var chars = Array(xteAddress)
        chars[50] = chars[50] == "a" ? "b" : "a"
        XCTAssertFalse(XTEAddress.isValid(String(chars)))
        XCTAssertFalse(XTEAddress.isValid(""))
        XCTAssertFalse(XTEAddress.isValid(String(xteAddress.dropLast())))
        XCTAssertFalse(XTEAddress.isValid(xteAddress + "1"))
    }

    func testKeysWalletNonDeterministic() throws {
        let k = try WalletKeys.fromKeys(
            privateSpendKeyHex: "55e0aa4ca65c0ae016c7364eec313f56fc162901ead0e38a9f846686ac78560f",
            privateViewKeyHex: "1f3f6c220dd9f97619dbf44d967f79f3041b9b1c63da2c895f980f1411d5d704")
        XCTAssertEqual(k.publicSpendKey.hex, "ff9b6e048297ee435d6219005974c2c8df620a4aca9ca5c4e13f071823482029")
        XCTAssertEqual(k.address.encoded(), "XT3bd9DH4qCgrTA1Z771tPZaf13V6YHAjUjAieQfjwCb6P1eYHuMmwRcDcQ1eAs41sQrh98FjBXn257HZzh2CCwE2spGfJn63")
        let upstream = XTEAddress(publicSpendKey: k.publicSpendKey, publicViewKey: k.publicViewKey, prefix: 8411)
        XCTAssertEqual(upstream.encoded(), "dg5NZstxyAegrTA1Z771tPZaf13V6YHAjUjAieQfjwCb6P1eYHuMmwRcDcQ1eAs41sQrh98FjBXn257HZzh2CCwE2spKE2gmA")
        XCTAssertFalse(k.isDeterministic)
        XCTAssertThrowsError(try k.mnemonic())
    }

    func testFromKeysRejectsInvalid() {
        XCTAssertThrowsError(try WalletKeys.fromKeys(privateSpendKeyHex: "zz", privateViewKeyHex: privView))
        XCTAssertThrowsError(try WalletKeys.fromKeys(privateSpendKeyHex: String(repeating: "f", count: 64), privateViewKeyHex: privView))
    }

    func testGeneratedWalletIsDeterministic() {
        let k = WalletKeys.generate()
        XCTAssertTrue(k.isDeterministic)
        XCTAssertTrue(XTEAddress.isValid(k.address.encoded()))
        XCTAssertTrue(k.address.encoded().hasPrefix("XT"))
    }
}
