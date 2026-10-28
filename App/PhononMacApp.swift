import AVFoundation
import SwiftUI
import SpeechCore
import PhononTTS
import OSLog

@MainActor final class AppModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var status = "Preparing voices..."
    @Published var ready = false
    @Published var speaking = false
    @Published var locale = "en-GB"
    @Published var selectedName = "Freya"
    @Published var text = "Hello. This is Phonon speaking on your Mac."
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private let logger = Logger(subsystem: "com.onj.phononmac", category: "app")
    var locales: [String] { Set(VoiceCatalog.all.map(\.locale)).sorted() }
    var voices: [VoiceDefinition] { VoiceCatalog.all.filter { $0.locale == locale } }

    override init() {
        super.init()
        synthesizer.delegate = self
        Task { await prepare() }
    }
    func changeLanguage() {
        if !voices.contains(where: { $0.name == selectedName }) { selectedName = voices.first?.name ?? "" }
    }
    func refresh() {
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        status = "Voice list refreshed."
    }
    func prepare() async {
        do {
            guard let source = Bundle.main.url(forResource: "Models", withExtension: nil) else {
                throw RequestError.modelUnavailable
            }
            let models = try PhononModels.install(bundled: source, to: VoiceCatalog.modelDirectory())
            let engine = NativeEngine(models: models)
            let info = try await engine.ready()
            guard Set(VoiceCatalog.all.map(\.name)).isSubset(of: Set(info.voices)), info.languages.count == 5 else {
                throw RequestError.modelUnavailable
            }
            ready = true
            AVSpeechSynthesisProviderVoice.updateSpeechVoices()
            status = "Ready: \(VoiceCatalog.all.count) voices, five languages."
            logger.info("Model preparation complete; 102 voices are ready")
        } catch {
            status = "Voices could not be prepared: \(error.localizedDescription)"
            logger.error("Model preparation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    func test() {
        stop()
        guard let definition = voices.first(where: { $0.name == selectedName }),
              let voice = AVSpeechSynthesisVoice.speechVoices().first(where: {
                  $0.identifier == definition.id || $0.identifier.hasSuffix(definition.id)
              }) else {
            status = "The system has not registered this voice yet. Refresh voices and try again."
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        activeUtterance = utterance
        speaking = true; status = "Speaking with \(definition.name)."
        synthesizer.speak(utterance)
    }
    func stop() {
        activeUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        speaking = false
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.activeUtterance === utterance else { return }
            self.activeUtterance = nil
            self.speaking = false; self.status = "Ready."
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.activeUtterance === utterance else { return }
            self.activeUtterance = nil; self.speaking = false
        }
    }
}

@main struct PhononMacApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updater = UpdateService()
    @AppStorage("updateFrequency") private var updateFrequency = "daily"
    var body: some Scene {
        WindowGroup("Phonon for Mac") {
            Form {
                Text("Phonon for Mac \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.headline)
                Picker("Language", selection: $model.locale) {
                    ForEach(model.locales, id: \.self) { locale in
                        Text(locale == "en" ? "English Character Voices" :
                            (Locale.current.localizedString(forIdentifier: locale) ?? locale)).tag(locale)
                    }
                }.onChange(of: model.locale) { _, _ in model.changeLanguage() }
                Picker("Voice", selection: $model.selectedName) {
                    ForEach(model.voices) { voice in Text(voice.name).tag(voice.name) }
                }
                TextField("Test text", text: $model.text, axis: .vertical).lineLimit(3...6)
                HStack {
                    Button("Test Voice") { model.test() }.disabled(!model.ready || model.text.isEmpty)
                    Button("Stop") { model.stop() }.disabled(!model.speaking)
                    Button("Refresh Voices") { model.refresh() }.disabled(!model.ready)
                    Button("Open Manual") {
                        if let url = Bundle.main.url(forResource: "Manual", withExtension: "html") { NSWorkspace.shared.open(url) }
                    }
                }
                Text(model.status).textSelection(.enabled).accessibilityLabel("Status: \(model.status)")
                Divider()
                Picker("Check for updates", selection: $updateFrequency) {
                    ForEach(UpdateFrequency.allCases) { value in Text(value.title).tag(value.rawValue) }
                }
                Button("Check Now") { updater.check() }.disabled(updater.busy)
                if !updater.status.isEmpty { Text(updater.status).textSelection(.enabled) }
            }.padding(20).frame(minWidth: 540, idealWidth: 600, minHeight: 340)
                .task { updater.start() }
        }.windowResizability(.contentSize)
    }
}
