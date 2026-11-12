import XCTest
@testable import VoiceCatalog

final class PreviewSampleTests: XCTestCase {
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
        preview.edit("My own text")
        preview.follow("fr-FR")
        XCTAssertEqual(preview.text, "My own text")
        preview.edit("")
        preview.follow("de-DE")
        XCTAssertEqual(preview.text, "")
        XCTAssertTrue(preview.isCustom)
        preview.reset("de-DE")
        XCTAssertEqual(preview.text, "Guten Tag! So klingt Phonon auf Deutsch.")
        XCTAssertFalse(preview.isCustom)
    }
}
