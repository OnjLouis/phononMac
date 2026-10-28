import AVFoundation
import Foundation
import OSLog
import SpeechCore

public final class PhononSpeechAudioUnit: AVSpeechSynthesisProviderAudioUnit {
    private let bus: AUAudioUnitBus
    private var buses: AUAudioUnitBusArray!
    private let state = NSLock()
    private var pipe = AudioPipe()
    private var task: Task<Void, Never>?
    private var engine: NativeEngine?
    private var sequence = 0
    private let logger = Logger(subsystem: "com.onj.phononmac", category: "provider")

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        bus = try AUAudioUnitBus(format: AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!)
        try super.init(componentDescription: componentDescription, options: options)
        buses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [bus])
        pipe.finish()
        logger.debug("Provider initialized")
    }

    public override var outputBusses: AUAudioUnitBusArray { buses }
    public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
        get {
            guard let models = try? VoiceCatalog.modelDirectory(),
                  FileManager.default.isReadableFile(atPath: models.appendingPathComponent("bundle.json").path) else { return [] }
            return VoiceCatalog.all.map(\.providerVoice)
        }
        set {}
    }
    public override var internalRenderBlock: AUInternalRenderBlock {
        { flags, _, frameCount, _, list, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard let target = buffers.first?.mData else { return kAudio_ParamError }
            self.state.lock(); let current = self.pipe; self.state.unlock()
            let result = current.read(into: target.assumingMemoryBound(to: Float.self), frames: Int(frameCount))
            if result.complete { flags.pointee.insert(.offlineUnitRenderAction_Complete) }
            return noErr
        }
    }

    public override func synthesizeSpeechRequest(_ speech: AVSpeechSynthesisProviderRequest) {
        state.lock()
        sequence += 1
        let number = sequence
        logger.debug("Request \(number) received")
        let previous = task
        pipe.finish(discard: true)
        previous?.cancel()
        let current = AudioPipe()
        pipe = current
        let model: NativeEngine
        do {
            if let engine { model = engine }
            else {
                let models = try VoiceCatalog.modelDirectory()
                guard FileManager.default.isReadableFile(atPath: models.appendingPathComponent("bundle.json").path) else {
                    throw RequestError.modelUnavailable
                }
                model = NativeEngine(models: models)
                engine = model
            }
            let request = try SpeechRequest.parse(speech.ssmlRepresentation)
            guard let voice = VoiceCatalog.all.first(where: {
                speech.voice.identifier == $0.id || speech.voice.identifier.hasSuffix($0.id)
            }) else { throw RequestError.modelUnavailable }
            let logger = self.logger
            // Waiting for the cancelled predecessor keeps voice/language setters and
            // synthesis in one transaction; no stale task can change the new voice.
            task = Task {
                logger.debug("Request \(number) waiting for predecessor")
                await previous?.value
                logger.debug("Request \(number) predecessor finished")
                do {
                    try Task.checkCancellation()
                    if !request.text.isEmpty {
                        logger.debug("Request \(number) native start")
                        _ = try await model.speak(request, voice: voice.name, language: voice.language) { samples in
                            _ = current.push(samples)
                        }
                        logger.debug("Request \(number) native finished")
                    }
                } catch is CancellationError {
                    // Expected while navigating; the obsolete FIFO was already discarded.
                } catch {
                    logger.error("Speech generation failed: \(error.localizedDescription, privacy: .public)")
                }
                current.finish()
                logger.debug("Request \(number) task finished")
            }
        } catch {
            current.finish()
            logger.error("Speech request could not start: \(error.localizedDescription, privacy: .public)")
        }
        state.unlock()
    }

    public override func cancelSpeechRequest() {
        state.lock()
        logger.debug("Request \(self.sequence) cancelled")
        pipe.finish(discard: true)
        task?.cancel()
        state.unlock()
    }

    deinit { logger.debug("Provider released"); pipe.finish(discard: true); task?.cancel() }
}
