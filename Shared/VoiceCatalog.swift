import AVFoundation
import Foundation

struct VoiceDefinition: Codable, Identifiable, Hashable {
    let name: String
    let locale: String
    var id: String { "com.onj.phononmac.voice." + name.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! }
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
    static func modelDirectory() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw NSError(domain: "PhononMac", code: 1, userInfo: [NSLocalizedDescriptionKey: "The shared voice folder is unavailable."])
        }
        return container.appendingPathComponent("Models", isDirectory: true)
    }
}
