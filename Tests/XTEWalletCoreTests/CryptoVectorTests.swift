import XCTest
@testable import XTEWalletCore

final class CryptoVectorTests: XCTestCase {
    func k(_ s: Substring) -> Key32 { Key32(hex: String(s))! }

    func testUpstreamCryptoNoteVectors() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "crypto-tests", withExtension: "txt", subdirectory: "Vectors"))
        let text = try String(contentsOf: url, encoding: .utf8)
        var counts: [String: Int] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let t = line.split(separator: " ")
            let cmd = String(t[0])
            counts[cmd, default: 0] += 1
            switch cmd {
            case "check_key":
                XCTAssertEqual(CNCrypto.checkKey(k(t[1])), t[2] == "true", String(line))
            case "secret_key_to_public_key":
                let r = try? CNCrypto.secretKeyToPublicKey(k(t[1]))
                XCTAssertEqual(r != nil, t[2] == "true", String(line))
                if let r { XCTAssertEqual(r.hex, String(t[3])) }
            case "generate_key_derivation":
                let r = try? CNCrypto.generateKeyDerivation(k(t[1]), k(t[2]))
                XCTAssertEqual(r != nil, t[3] == "true", String(line))
                if let r { XCTAssertEqual(r.hex, String(t[4])) }
            case "derive_public_key":
                let r = try? CNCrypto.derivePublicKey(k(t[1]), outputIndex: UInt64(t[2])!, base: k(t[3]))
                XCTAssertEqual(r != nil, t[4] == "true", String(line))
                if let r { XCTAssertEqual(r.hex, String(t[5])) }
            case "derive_secret_key":
                let r = try CNCrypto.deriveSecretKey(k(t[1]), outputIndex: UInt64(t[2])!, base: k(t[3]))
                XCTAssertEqual(r.hex, String(t[4]))
            case "generate_key_image":
                let r = try CNCrypto.generateKeyImage(publicKey: k(t[1]), secretKey: k(t[2]))
                XCTAssertEqual(r.hex, String(t[3]))
            case "check_signature":
                let sig = [UInt8](Data(hex: String(t[3]))!)
                XCTAssertEqual(CNCrypto.checkSignature(prefixHash: k(t[1]), publicKey: k(t[2]), signature: sig), t[4] == "true", String(line))
            case "hash_to_scalar":
                XCTAssertEqual(CNCrypto.hashToScalar([UInt8](Data(hex: String(t[1]))!)).hex, String(t[2]))
            case "check_ring_signature":
                let n = Int(t[3])!
                let pubs = (0..<n).map { k(t[4 + $0]) }
                guard let raw = Data(hex: String(t[4 + n])), raw.count == 64 * n else {
                    XCTAssertEqual(t[5 + n], "false"); continue
                }
                let sigs = (0..<n).map { [UInt8](raw[(64 * $0)..<(64 * $0 + 64)]) }
                XCTAssertEqual(CNCrypto.checkRingSignature(prefixHash: k(t[1]), keyImage: k(t[2]), publicKeys: pubs, signatures: sigs),
                               t[5 + n] == "true", String(line))
            default:
                XCTFail("unknown vector \(cmd)")
            }
        }
        XCTAssertEqual(counts.count, 9)
        XCTAssertGreaterThanOrEqual(counts.values.reduce(0, +), 300)
    }

    func testRingSignatureRoundTripAndTamper() throws {
        var pubs: [PublicKey] = []
        var secret: SecretKey!
        for i in 0..<8 {
            let kp = CNCrypto.generateKeys()
            pubs.append(kp.publicKey)
            if i == 5 { secret = kp.secretKey }
        }
        let prefix = CNCrypto.fastHash(Array("xte".utf8))
        let image = try CNCrypto.generateKeyImage(publicKey: pubs[5], secretKey: secret)
        var sigs = try CNCrypto.generateRingSignatures(prefixHash: prefix, keyImage: image, publicKeys: pubs, secretKey: secret, realIndex: 5)
        XCTAssertTrue(CNCrypto.checkRingSignature(prefixHash: prefix, keyImage: image, publicKeys: pubs, signatures: sigs))
        sigs[2][7] ^= 1
        XCTAssertFalse(CNCrypto.checkRingSignature(prefixHash: prefix, keyImage: image, publicKeys: pubs, signatures: sigs))
    }

    func testSignatureRoundTrip() throws {
        let kp = CNCrypto.generateKeys()
        let h = CNCrypto.fastHash([1, 2, 3])
        let sig = CNCrypto.generateSignature(prefixHash: h, publicKey: kp.publicKey, secretKey: kp.secretKey)
        XCTAssertTrue(CNCrypto.checkSignature(prefixHash: h, publicKey: kp.publicKey, signature: sig))
        XCTAssertFalse(CNCrypto.checkSignature(prefixHash: CNCrypto.fastHash([4]), publicKey: kp.publicKey, signature: sig))
    }

    func testKeccakEmpty() {
        // Keccak-256 (original padding) of the empty string.
        XCTAssertEqual(CNCrypto.fastHash([]).hex, "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
    }

    func testUnderiveIsInverseOfDerive() throws {
        let view = CNCrypto.generateKeys()
        let spend = CNCrypto.generateKeys()
        let txKey = CNCrypto.generateKeys()
        let d1 = try CNCrypto.generateKeyDerivation(view.publicKey, txKey.secretKey)
        let d2 = try CNCrypto.generateKeyDerivation(txKey.publicKey, view.secretKey)
        XCTAssertEqual(d1, d2)
        let out = try CNCrypto.derivePublicKey(d1, outputIndex: 7, base: spend.publicKey)
        XCTAssertEqual(try CNCrypto.underivePublicKey(d2, outputIndex: 7, derivedKey: out), spend.publicKey)
        let sec = try CNCrypto.deriveSecretKey(d2, outputIndex: 7, base: spend.secretKey)
        XCTAssertEqual(try CNCrypto.secretKeyToPublicKey(sec), out)
    }
}
