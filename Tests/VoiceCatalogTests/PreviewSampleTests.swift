import XCTest
@testable import VoiceCatalog

final class PreviewSampleTests: XCTestCase {
    func testEditorEchoDoesNotMarkBuiltInSampleAsCustom() {
        var preview = PreviewSample()
        let displayedSample = preview.text
        let oldRevision = preview.revision
        preview.edit(displayedSample, revision: oldRevision)
        preview.follow("de-DE")
        preview.edit(displayedSample, revision: oldRevision)
        XCTAssertEqual(preview.text, "Guten Tag! So klingt Phonon auf Deutsch.")
        XCTAssertFalse(preview.isCustom)
    }

    func testEveryOfferedLocaleGetsItsOwnLanguageSample() {
        let examples = ["en-GB": "Hello!", "en-US": "Hello!", "en": "Hello!", "characters": "Hello!",
                        "de-DE": "Guten Tag!", "fr-FR": "Bonjour !", "pt-BR": "Olá!",
                        "es-ES": "¡Hola!", "es-MX": "¡Hola!"]
        var preview = PreviewSample()
        for (locale, beginning) in examples {
            preview.follow(locale)
            XCTAssertTrue(preview.text.hasPrefix(beginning), locale)
            XCTAssertFalse(preview.isCustom)
        }
    }

    func testLanguageChangesDoNotOverwriteEditsAndResetUsesCurrentLanguage() {
        var preview = PreviewSample()
        preview.edit("My own text", revision: preview.revision)
        preview.follow("fr-FR")
        XCTAssertEqual(preview.text, "My own text")
        preview.edit("", revision: preview.revision)
        preview.follow("de-DE")
        XCTAssertEqual(preview.text, "")
        XCTAssertTrue(preview.isCustom)
        preview.reset("de-DE")
        XCTAssertEqual(preview.text, "Guten Tag! So klingt Phonon auf Deutsch.")
        XCTAssertFalse(preview.isCustom)
    }
}
