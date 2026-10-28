import XCTest
@testable import SpeechCore

final class VoiceResourceTests: XCTestCase {
    private let accented = ["D\u{e9}bora", "Fl\u{e1}via", "H\u{e9}l\u{e8}ne", "Kau\u{e3}",
                            "Luc\u{ed}a-Sol", "Ma\u{eb}lys", "No\u{e9}mie", "Ot\u{e1}vio", "Sol\u{e8}ne"]

    func testResourcesAreASCIIAndNormalizationInvariant() {
        for name in accented {
            let key = VoiceResources.storageName(for: name)
            XCTAssertTrue(key.utf8.allSatisfy { $0 < 128 }, name)
            XCTAssertEqual(key, VoiceResources.storageName(for: name.decomposedStringWithCanonicalMapping))
            XCTAssertTrue(key.hasPrefix("voice-"))
        }
    }

    func testNoTransliterationCollisionsOrCaseFolding() {
        XCTAssertNotEqual(VoiceResources.storageName(for: "Jose"), VoiceResources.storageName(for: "Jos\u{e9}"))
        XCTAssertNotEqual(VoiceResources.storageName(for: "Freya"), VoiceResources.storageName(for: "freya"))
    }

    func testResolveNewAndExistingPreparedVoices() {
        for name in accented + ["Freya"] {
            let key = VoiceResources.storageName(for: name)
            XCTAssertEqual(VoiceResources.resolve(name, available: [key]), key)
            XCTAssertEqual(VoiceResources.resolve(name, available: [name]), name)
            XCTAssertEqual(VoiceResources.resolve(name, available: [name, key]), key)
        }
        XCTAssertNil(VoiceResources.resolve("Missing", available: ["Freya"]))
    }
}
