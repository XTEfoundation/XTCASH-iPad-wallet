import XCTest
@testable import XTEWalletCore

/// Key vectors generated with turtlecoin-utils 3.x (the reference JS implementation used by the
/// TurtleCoin/traaitt wallets). The XTCASH addresses (prefix 925524, "cash...") were produced by
/// traaittcash-wallet-backend (CryptoUtils, the JS crypto of the XTCASH React Native wallet,
/// XTEfoundation/XTCASH-wallet) from the same seeds/keys. The XTE (1334) and upstream (8411)
/// addresses stay as cross-checks that the core encodes any prefix identically.
final class AddressMnemonicTests: XCTestCase {
    let seed = "skulls woozy ouch summon gifts huts waffle ourselves obtains hexagon tadpoles hacksaw dormant hence abort listen history atom cadets stylishly snout vegan girth guest history"
    let privSpend = "d61a57a59318d70ff77cc7f8ad7f62887c828da1d5d3f3b0d2f7d3fa596c2904"
    let privView = "688e5229df6463ec4c27f6ee11c3f1d3d4b4d2480c0aabe64fb807182cfdc801"
    let pubSpend = "abab87df609dbacc45494c6a8954cde81f934ddd6c32202b62f174798bc66e43"
    let pubView = "ba03787382200f68b89d7f82984d9b42d0d2c2d8f7026cdd51634a99bcc256bf"
    let cashAddress = "cashUGq532XTPBBHRdFJMnFBi5GV4d8BV9PHLgKDVMzraC2YLfkjyBX6N2PoUXXyN7Dyt3prMAq1p1QXd8nRaxZy8N9RN2XyuW"
    let xteAddress = "XT2spqycEh2YFB67qoiRp7bSZ64NTkx8h6P5tNxrgVt1KShrMcFBaS33aVG7jm4YVaSyE7rrsaprdKD86ECGLwah1kCSrB5qP"
    let trtlAddress = "TRTLv1s9JQeHAJFoHvcqVBPyHYom2ynKeK6dpYptbp8gQNzdzE73ZDkNmNurqfhhcMSUXpS1ZGEJKiKJUcPCyw7vYaCc354DCN1"
    let pid = "b23df6e84c1dd619d3601a28e5948d92a0d096aea1621969c591a90e986794a0"
    let integrated = "cashKz3PZhfA6hoGpD7U4TA4jWsqJcMNQHFvdTeR5jxTHmHysQtbD68A6ZPr6J7X84Aa2XKVffuttAZoiGMgEA4G9m9ba7ohajRTPBBHRdFJMnFBi5GV4d8BV9PHLgKDVMzraC2YLfkjyBX6N2PoUXXyN7Dyt3prMAq1p1QXd8nRaxZy8N9RKpV2yV"

    func testMnemonicToKeysAndAddress() throws {
        let keys = try WalletKeys.fromMnemonic(seed)
        XCTAssertEqual(keys.privateSpendKey.hex, privSpend)
        XCTAssertEqual(keys.privateViewKey.hex, privView)
        XCTAssertEqual(keys.publicSpendKey.hex, pubSpend)
        XCTAssertEqual(keys.publicViewKey.hex, pubView)
        XCTAssertTrue(keys.isDeterministic)
        XCTAssertEqual(keys.address.encoded(), cashAddress)
        XCTAssertEqual(cashAddress.count, XTEConfig.standardAddressLength)
        XCTAssertEqual(XTEAddress(publicSpendKey: keys.publicSpendKey, publicViewKey: keys.publicViewKey, prefix: 1334).encoded(), xteAddress)
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
        let a = try XTEAddress.decode(cashAddress)
        XCTAssertEqual(a.publicSpendKey.hex, pubSpend)
        XCTAssertEqual(a.publicViewKey.hex, pubView)
        XCTAssertEqual(a.prefix, 925524)
        XCTAssertNil(a.paymentID)
        XCTAssertTrue(XTEAddress.isValid(cashAddress))
        // An XTE address for the same keys is not an XTCASH address.
        XCTAssertEqual(try? XTEAddress.decode(xteAddress, expectedPrefix: 1334), XTEAddress(publicSpendKey: a.publicSpendKey, publicViewKey: a.publicViewKey, prefix: 1334))
        XCTAssertThrowsError(try XTEAddress.decode(xteAddress)) { XCTAssertEqual($0 as? AddressError, .wrongPrefix(1334)) }
        XCTAssertFalse(XTEAddress.isValid(xteAddress))
    }

    func testIntegratedAddress() throws {
        let a = XTEAddress(publicSpendKey: Key32(hex: pubSpend)!, publicViewKey: Key32(hex: pubView)!, paymentID: pid)
        XCTAssertEqual(a.encoded(), integrated)
        XCTAssertEqual(integrated.count, XTEConfig.integratedAddressLength)
        let d = try XTEAddress.decode(integrated)
        XCTAssertEqual(d.paymentID, pid)
        XCTAssertEqual(d.standard.encoded(), cashAddress)
        XCTAssertFalse(XTEAddress.isValid(integrated, allowIntegrated: false))
    }

    func testChecksumAndCorruption() {
        var chars = Array(cashAddress)
        chars[50] = chars[50] == "a" ? "b" : "a"
        XCTAssertFalse(XTEAddress.isValid(String(chars)))
        XCTAssertFalse(XTEAddress.isValid(""))
        XCTAssertFalse(XTEAddress.isValid(String(cashAddress.dropLast())))
        XCTAssertFalse(XTEAddress.isValid(cashAddress + "1"))
        // Same corruption the XTCASH RN test uses (daemon rejected it on main.trrxitte.com).
        let fixed = "cashbvjQb3UFWfZ1R9tfUPKHQ7j2PF9cHRpV4MyP7hTbJGUHqKANqqz9wMnyZxSS5STPW2DYtsynUTzX68sDEMBR3uBc69tDHU"
        XCTAssertFalse(XTEAddress.isValid(String(fixed.dropLast()) + "V"))
    }

    func testKeysWalletNonDeterministic() throws {
        let k = try WalletKeys.fromKeys(
            privateSpendKeyHex: "55e0aa4ca65c0ae016c7364eec313f56fc162901ead0e38a9f846686ac78560f",
            privateViewKeyHex: "1f3f6c220dd9f97619dbf44d967f79f3041b9b1c63da2c895f980f1411d5d704")
        XCTAssertEqual(k.publicSpendKey.hex, "ff9b6e048297ee435d6219005974c2c8df620a4aca9ca5c4e13f071823482029")
        XCTAssertEqual(k.address.encoded(), "cashdk5rGosSQvG1gYAGELLXj9s9Ys3KoTCgHVstUqb8D4i82NkV3qz7ADzgFxD99JTXCmn6qNwgv5Xs9bi49iiV9Qd1ebE56A")
        XCTAssertEqual(XTEAddress(publicSpendKey: k.publicSpendKey, publicViewKey: k.publicViewKey, prefix: 1334).encoded(), "XT3bd9DH4qCgrTA1Z771tPZaf13V6YHAjUjAieQfjwCb6P1eYHuMmwRcDcQ1eAs41sQrh98FjBXn257HZzh2CCwE2spGfJn63")
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
        XCTAssertTrue(k.address.encoded().hasPrefix("cash"))
        XCTAssertEqual(k.address.encoded().count, 98)
    }

    /// Same fixed seed as XTCASH-wallet src/__tests__/xtcashAddress.test.js: private spend key
    /// = sc_reduce32(64 x "a"), view key = H(spend). The RN app's JS crypto
    /// (CryptoUtils.createAddressFromSeed) produces exactly these keys and this address, and the
    /// XTCASH daemon accepted the address in getblocktemplate.
    func testFixedSeedMatchesReactNativeWallet() throws {
        // The JS mnemonic for that seed encodes the raw (unreduced) seed bytes.
        let jsMnemonic = "directed dime tomorrow directed dime tomorrow directed dime tomorrow directed dime tomorrow directed dime tomorrow directed dime tomorrow directed dime tomorrow directed dime tomorrow tomorrow"
        XCTAssertEqual(try Mnemonic.toPrivateKey(jsMnemonic).hex, String(repeating: "a", count: 64))

        let k = try WalletKeys.fromKeys(
            privateSpendKeyHex: "68631009a3cbf2394b8afe4cf8e7f4d9a9aaaaaaaaaaaaaaaaaaaaaaaaaaaa0a",
            privateViewKeyHex: "e041ac7b85fc8ac6499cb5c39fdd019a4a7b0bd5fa3d4362d5acfa784bbbb80b")
        XCTAssertTrue(k.isDeterministic, "view key must be derived from the spend key exactly like the JS wallet")
        XCTAssertEqual(k.publicSpendKey.hex, "ef81d7082f56c22352270e3f046d4e299f53e018ce946197ffbb56e976673b26")
        XCTAssertEqual(k.publicViewKey.hex, "40a11ebaf1356e9f683f49605d9dc35f0b59cd950da15f72f4f81763744c84b5")
        let address = k.address.encoded()
        XCTAssertEqual(address, "cashbvjQb3UFWfZ1R9tfUPKHQ7j2PF9cHRpV4MyP7hTbJGUHqKANqqz9wMnyZxSS5STPW2DYtsynUTzX68sDEMBR3uBc69tDHU")
        XCTAssertTrue(address.hasPrefix("cash"))
        XCTAssertEqual(address.count, XTEConfig.standardAddressLength)
        XCTAssertEqual(try XTEAddress.decode(address).prefix, 925524)
        // The reduced key's own 25-word seed restores the same address.
        XCTAssertEqual(try WalletKeys.fromMnemonic(k.mnemonic().joined(separator: " ")).address.encoded(), address)

        let integrated = XTEAddress(publicSpendKey: k.publicSpendKey, publicViewKey: k.publicViewKey, paymentID: String(repeating: "b", count: 64))
        XCTAssertEqual(integrated.encoded(), "cashL1Gpki5HTTASy5qnGhHTTASy5qnGhHTTASy5qnGhHTTASy5qnGhHTTASy5qnGhHTTASy5qnGhHTTASy5qnGhHTTAitYRcc6FWfZ1R9tfUPKHQ7j2PF9cHRpV4MyP7hTbJGUHqKANqqz9wMnyZxSS5STPW2DYtsynUTzX68sDEMBR3uBc6wzbJN")
        XCTAssertEqual(integrated.encoded().count, XTEConfig.integratedAddressLength)
    }
}
