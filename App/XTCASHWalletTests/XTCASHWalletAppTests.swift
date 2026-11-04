import XCTest
import XTEWalletCore
@testable import XTCASHWallet

final class XTCASHWalletAppTests: XCTestCase {
    func testQRCodeForAddress() throws {
        let keys = WalletKeys.generate()
        let image = try XCTUnwrap(QRCode.image(for: keys.address.encoded()))
        XCTAssertGreaterThan(image.size.width, 100)
    }

    func testSidebarHasAllScreens() {
        XCTAssertEqual(SidebarItem.allCases.map(\.title), ["Wallet", "Send", "Receive", "Transactions", "Node", "Settings"])
    }

    func testWalletFileRoundTripHasNoSecrets() throws {
        let keys = WalletKeys.generate()
        let file = WalletFile(address: keys.address.encoded(), state: WalletState(startHeight: 5))
        let data = try JSONEncoder().encode(file)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains(keys.privateSpendKey.hex))
        XCTAssertFalse(json.contains(keys.privateViewKey.hex))
        XCTAssertEqual(try JSONDecoder().decode(WalletFile.self, from: data).state.startHeight, 5)
    }

    func testInfoPlist() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertEqual(info["CFBundleShortVersionString"] as? String, "1.0.0")
        XCTAssertNotNil(info["NSFaceIDUsageDescription"])
        let types = info["CFBundleURLTypes"] as? [[String: Any]]
        let schemes = types?.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } ?? []
        XCTAssertEqual(schemes, ["xtcash"])
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "XTCASH")
        XCTAssertEqual(Bundle.main.bundleIdentifier, "io.traaitt.xtcash.ipad")
    }
}
