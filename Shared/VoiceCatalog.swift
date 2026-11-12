import AVFoundation
import Foundation

struct VoiceDefinition: Codable, Identifiable, Hashable {
    let name: String
    let locale: String
    let importedStem: String?
    init(name: String, locale: String, importedStem: String? = nil) {
        self.name = name
        self.locale = locale
        self.importedStem = importedStem
    }
    var selection: String { importedStem ?? name }
    var id: String { "com.onj.phononmac.voice." + (importedStem ?? name.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!) }
    var isCharacterVoice: Bool { locale == "characters" || locale == "en" }
    // The character group is catalogue metadata, not a language macOS can list.
    var providerLocale: String { isCharacterVoice ? "en-US" : locale }
    var language: String { String(providerLocale.prefix(2)) }
    var providerVoice: AVSpeechSynthesisProviderVoice {
        AVSpeechSynthesisProviderVoice(name: "Phonon \(name)", identifier: id,
                                      primaryLanguages: [providerLocale], supportedLanguages: [providerLocale])
    }
}

enum VoiceCatalog {
    static let group = "83NN3HS237.group.com.onj.phononmac"
    static let all: [VoiceDefinition] = {
        guard let url = Bundle.main.url(forResource: "voices", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let voices = try? JSONDecoder().decode([VoiceDefinition].self, from: data) else { return [] }
        return voices.sorted { ($0.locale, $0.name) < ($1.locale, $1.name) }
    }()
    static func importStore() throws -> MacVoiceStore {
        let models = try modelDirectory()
        return MacVoiceStore(root: models.deletingLastPathComponent().appendingPathComponent("Imported Voices"), models: models)
    }
    static func imported() -> [VoiceDefinition] {
        ((try? importStore().entries()) ?? []).map { VoiceDefinition(name: $0.name, locale: $0.locale, importedStem: $0.stem) }
    }
    static func resolve(_ identifier: String) -> VoiceDefinition? {
        if let stock = all.first(where: { identifier.hasSuffix($0.id) }) { return stock }
        guard let range = identifier.range(of: ".voice.imported-", options: .backwards),
              identifier[..<range.lowerBound].hasSuffix("com.onj.phononmac") else { return nil }
        let stem = String(identifier[range.lowerBound...].dropFirst(".voice.".count))
        if let entry = try? importStore().entry(for: stem) {
            return VoiceDefinition(name: entry.name, locale: entry.locale, importedStem: entry.stem)
        }
        return all.first { $0.name == "Freya" }
    }
    static func modelDirectory() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw NSError(domain: "PhononMac", code: 1, userInfo: [NSLocalizedDescriptionKey: "The shared voice folder is unavailable."])
        }
        return container.appendingPathComponent("Models", isDirectory: true)
    }
}
