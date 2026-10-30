import CryptoKit
import XCTest
@testable import UpdateCore

final class UpdateCoreTests: XCTestCase {
    private func manifest(_ key: Curve25519.Signing.PrivateKey, changes: [String: Any] = [:]) throws -> UpdateManifest {
        var fields: [String: Any] = ["version": "1.0.3", "fileName": "Phonon-for-Mac.zip",
            "downloadUrl": "https://github.com/OnjLouis/phononMac/releases/download/v1.0.3/Phonon-for-Mac.zip", "notes": "A test update.",
            "size": 12, "sha256": String(repeating: "a", count: 64), "published": "2026-10-28"]
        fields.merge(changes) { _, new in new }
        let payload = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
        fields["signature"] = try key.signature(for: payload).base64EncodedString()
        return try JSONDecoder().decode(UpdateManifest.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func testValidSignature() throws {
        let key = Curve25519.Signing.PrivateKey()
        XCTAssertNoThrow(try UpdatePolicy(verificationKey: key.publicKey.rawRepresentation).verify(manifest(key)))
    }
    func testOtherApplicationKeyRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let other = Curve25519.Signing.PrivateKey()
        XCTAssertThrowsError(try UpdatePolicy(verificationKey: other.publicKey.rawRepresentation).verify(manifest(key)))
    }
    func testTamperedPayloadRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signed = try manifest(key)
        var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(signed)) as! [String: Any]
        fields["notes"] = "Modified after signing"
        let changed = try JSONDecoder().decode(UpdateManifest.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertThrowsError(try UpdatePolicy(verificationKey: key.publicKey.rawRepresentation).verify(changed))
    }
    func testSignedWrongAssetAndHostRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        for changes: [String: Any] in [["fileName": "Orpheus-for-Mac.zip"],
            ["downloadUrl": "https://github.com/OnjLouis/phononMac/releases/download/v1.0.2/Phonon-for-Mac.zip"],
            ["downloadUrl": "https://example.com/programs/Phonon-for-Mac.zip"],
            ["downloadUrl": "https://3.onj.me/programs/Phonon-for-Mac.zip?other=1"],
            ["size": -1], ["size": 2_147_483_648], ["version": "v1.0"], ["sha256": "invalid"]] {
            XCTAssertThrowsError(try UpdatePolicy(verificationKey: key.publicKey.rawRepresentation).verify(manifest(key, changes: changes)))
        }
    }
    func testVersionOrder() {
        XCTAssertTrue(UpdatePolicy.newer("1.10", than: "1.9"))
        XCTAssertTrue(UpdatePolicy.newer("1.0", than: "0.1.0"))
        XCTAssertFalse(UpdatePolicy.newer("1.0.0", than: "1.0"))
        XCTAssertFalse(UpdatePolicy.newer("garbage", than: "1.0"))
        XCTAssertFalse(UpdatePolicy.newer("1.0", than: "2.0"))
    }
    func testExactAllowedEndpoints() {
        XCTAssertEqual(UpdatePolicy.manifestURL.absoluteString, "https://github.com/OnjLouis/phononMac/releases/latest/download/phononMac-update.json")
        XCTAssertTrue(UpdatePolicy.allows(UpdatePolicy.manifestURL))
        XCTAssertTrue(UpdatePolicy.allows(URL(string: "https://github.com/OnjLouis/phononMac/releases/download/v1.0.3/phononMac-update.json")!))
        XCTAssertTrue(UpdatePolicy.allows(URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/123/asset?token=example")!))
        for value in ["https://github.com/Other/phononMac/releases/download/v1.0.3/Phonon-for-Mac.zip",
            "https://github.com/OnjLouis/phononMac/releases/download/v1.0.3/Other.zip",
            "https://github.com/OnjLouis/phononMac/releases/download/v1.0.3/Phonon-for-Mac.zip?other=1",
            "https://user@release-assets.githubusercontent.com/github-production-release-asset/123/asset",
            "https://release-assets.githubusercontent.com:444/github-production-release-asset/123/asset",
            "https://release-assets.githubusercontent.com/unrelated"] {
            XCTAssertFalse(UpdatePolicy.allows(URL(string: value)!))
        }
        XCTAssertFalse(UpdatePolicy.allows(URL(string: "http://3.onj.me/programs/.PhononMac.json")!))
        XCTAssertFalse(UpdatePolicy.allows(URL(string: "https://user@3.onj.me/programs/.PhononMac.json")!))
        XCTAssertFalse(UpdatePolicy.allows(URL(string: "https://3.onj.me/programs/.OrpheusMacEmbedded.json")!))
    }
    func testTruncatedArchiveRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0, count: 64).write(to: url)
        XCTAssertThrowsError(try ZipInventory.validate(url))
    }
}
