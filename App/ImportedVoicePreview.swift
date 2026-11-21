import AVFoundation
import Foundation
import OSLog
import Synchronization
import SpeechCore

@MainActor final class ImportedVoicePreview: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playing = false
    @Published private(set) var message = ""
    private var task: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var id: UUID?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Phonon", category: "voice-preview")

    func play(_ data: Data, locale: String) {
        stop()
        let token = UUID()
        id = token
        playing = true
        message = "Preparing preview."
        task = Task {
            do {
                let models = try VoiceCatalog.modelDirectory()
                let pcm = Mutex(Data())
                try await DraftVoice.render(data, models: models, text: PreviewSample.sample(for: locale),
                                            language: String(locale.prefix(2))) { samples in
                    pcm.withLock { output in
                        guard output.count + samples.count * 2 <= 24_000 * 2 * 20 else { return }
                        let shorts = samples.map { sample in
                            sample.isFinite ? Int16((min(1, max(-1, sample)) * 32767).rounded()).littleEndian : 0
                        }
                        shorts.withUnsafeBytes { output.append(contentsOf: $0) }
                    }
                }
                try Task.checkCancellation()
                guard id == token else { return }
                let audio = pcm.withLock { $0 }
                guard !audio.isEmpty else { throw CocoaError(.fileReadUnknown) }
                let wave = Self.wave(audio)
                let output = try AVAudioPlayer(data: wave)
                output.delegate = self
                player = output
                guard output.play() else { throw CocoaError(.fileReadUnknown) }
                message = "Playing preview."
            } catch is CancellationError {
            } catch {
                guard id == token else { return }
                logger.error("Draft voice preview failed")
                stop()
                message = "Phonon could not preview this voice."
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            guard let active = self.player, ObjectIdentifier(active) == finished else { return }
            stop()
            message = flag ? "Preview finished." : "Phonon could not play this preview."
        }
    }

    private static func wave(_ pcm: Data) -> Data {
        var wave = Data("RIFF".utf8)
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { wave.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { wave.append(contentsOf: $0) } }
        u32(UInt32(36 + pcm.count))
        wave.append(contentsOf: "WAVEfmt ".utf8)
        u32(16); u16(1); u16(1); u32(24_000); u32(48_000); u16(2); u16(16)
        wave.append(contentsOf: "data".utf8)
        u32(UInt32(pcm.count))
        wave.append(pcm)
        return wave
    }

    func stop() {
        id = nil
        task?.cancel()
        task = nil
        player?.stop()
        player = nil
        playing = false
        message = ""
    }

}
