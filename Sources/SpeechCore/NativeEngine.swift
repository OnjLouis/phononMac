import Foundation
import PhononTTS

public actor NativeEngine {
    private let models: URL
    private var loading: Task<Phonon, Error>
    private var tail: Task<Void, Never>?

    public init(models: URL) {
        self.models = models
        loading = Task { try await Phonon.load(models: models, language: .english) }
    }

    public func ready() async throws -> (voices: [String], languages: [String]) {
        let engine = try await loading.value
        return (engine.voices, engine.languages)
    }

    public func speak(_ request: SpeechRequest, voice: String, language: String,
                      onAudio: @escaping @Sendable ([Float]) -> Void) async throws -> SpeechStats {
        try Task.checkCancellation()
        let predecessor = tail
        // Actors are reentrant at await points. Serialize the whole operation,
        // not just each native setter, so concurrent requests cannot swap voices.
        let operation = Task {
            await predecessor?.value
            try Task.checkCancellation()
            var engine = try await self.loading.value
            try Task.checkCancellation()
            var selectedVoice = VoiceResources.resolve(voice, available: engine.voices)
            if selectedVoice == nil && voice.hasPrefix("imported-"),
               FileManager.default.isReadableFile(atPath: self.models.appendingPathComponent("voices/" + voice + ".safetensors").path) {
                let models = self.models
                let reload = Task { try await Phonon.load(models: models, language: .english) }
                engine = try await reload.value
                self.loading = reload
                selectedVoice = VoiceResources.resolve(voice, available: engine.voices)
            }
            try Task.checkCancellation()
            guard let selectedVoice = selectedVoice ?? (voice.hasPrefix("imported-")
                ? VoiceResources.resolve("Freya", available: engine.voices) : nil) else {
                throw PhononError(description: "The selected voice is not available in the prepared model.")
            }
            if engine.voice != selectedVoice { try await engine.setVoice(selectedVoice) }
            try Task.checkCancellation()
            let selected = Language(rawValue: language) ?? .none
            if engine.language != selected { try await engine.setLanguage(selected) }
            try Task.checkCancellation()
            let processor = try SpeechProcessor(rate: request.rate, pitch: request.pitch, volume: request.volume)
            let stats = try await engine.speak(request.text) { samples in
                onAudio(processor.process(samples))
            }
            try Task.checkCancellation()
            onAudio(processor.finish())
            return stats
        }
        tail = Task { _ = try? await operation.value }
        return try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }
}
