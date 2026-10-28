import Foundation
import PhononTTS

public actor NativeEngine {
    private let loading: Task<Phonon, Error>
    private var tail: Task<Void, Never>?

    public init(models: URL) {
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
        let loading = self.loading
        // Actors are reentrant at await points. Serialize the whole operation,
        // not just each native setter, so concurrent requests cannot swap voices.
        let operation = Task {
            await predecessor?.value
            try Task.checkCancellation()
            let engine = try await loading.value
            try Task.checkCancellation()
            if engine.voice != voice { try await engine.setVoice(voice) }
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
