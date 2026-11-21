import AVFoundation
import XCTest
@testable import VoiceCatalog

final class VoiceCatalogTests: XCTestCase {
    func testSelectedFileSnapshotRejectsMissingAndOversizedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("test.safetensors")
        XCTAssertThrowsError(try MacVoiceStore.snapshotSelectedFile(file))
        let draft = Data(repeating: 42, count: 128 * 1024)
        try draft.write(to: file)
        let snapshot = try MacVoiceStore.snapshotSelectedFile(file)
        try Data(repeating: 0, count: 4 * 1024 * 1024 + 1).write(to: file)
        XCTAssertThrowsError(try MacVoiceStore.snapshotSelectedFile(file))
        XCTAssertEqual(snapshot, draft)
    }

    private var catalogue: [VoiceDefinition] {
        get throws {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            return try JSONDecoder().decode([VoiceDefinition].self,
                from: Data(contentsOf: root.appendingPathComponent("Resources/voices.json")))
        }
    }

    func testCharacterVoicesRegisterUnderRegionalEnglish() throws {
        let characters = try catalogue.filter { $0.locale == "characters" }
        XCTAssertEqual(characters.count, 12)
        for voice in characters {
            XCTAssertEqual(voice.providerVoice.primaryLanguages, ["en-US"], voice.name)
            XCTAssertEqual(voice.providerVoice.supportedLanguages, ["en-US"], voice.name)
            XCTAssertEqual(voice.providerVoice.name, "Phonon \(voice.name)")
            XCTAssertEqual(voice.providerVoice.identifier, voice.id)
            XCTAssertEqual(voice.locale, "characters")
            XCTAssertEqual(voice.language, "en")
            XCTAssertTrue(voice.isCharacterVoice)
        }
    }

    func testGenericEnglishMetadataUsesTheSameRegistration() {
        let voice = VoiceDefinition(name: "Example", locale: "en")
        XCTAssertEqual(voice.providerVoice.primaryLanguages, ["en-US"])
        XCTAssertEqual(voice.language, "en")
        XCTAssertEqual(voice.locale, "en")
    }

    func testOtherVoiceLocalesAreUnchanged() throws {
        let voices = try catalogue
        XCTAssertEqual(voices.count, 102)
        XCTAssertEqual(Set(voices.map(\.id)).count, 102)
        for voice in voices where voice.locale != "characters" {
            XCTAssertEqual(voice.providerVoice.primaryLanguages, [voice.locale], voice.name)
            XCTAssertEqual(voice.providerVoice.supportedLanguages, [voice.locale], voice.name)
        }
    }

    func testPublishedCatalogueAndStableIdentifiersRoundTrip() throws {
        for voice in try catalogue {
            let restored = try JSONDecoder().decode(VoiceDefinition.self,
                from: JSONEncoder().encode(voice))
            XCTAssertEqual(restored, voice)
            XCTAssertEqual(restored.id, voice.id)
            let expected = "com.onj.phononmac.voice." +
                voice.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            XCTAssertEqual(voice.providerVoice.identifier, expected)
        }
    }
}
