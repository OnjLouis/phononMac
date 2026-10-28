import Foundation
import SonicDSP

/// Per-utterance streaming DSP; never shared between requests or called by the render block.
public final class SpeechProcessor: @unchecked Sendable {
    private let stream: sonicStream
    private let muted: Bool
    public init(rate: Float, pitch: Float, volume: Float) throws {
        guard let stream = sonicCreateStream(24_000, 1) else { throw RequestError.modelUnavailable }
        self.stream = stream
        muted = volume == 0
        sonicSetSpeed(stream, max(0.5, min(3, rate)))
        sonicSetPitch(stream, max(0.5, min(2, pitch)))
        sonicSetVolume(stream, max(0, min(1, volume)))
    }
    deinit { sonicDestroyStream(stream) }

    public func process(_ samples: [Float]) -> [Float] {
        samples.withUnsafeBufferPointer { _ = sonicWriteFloatToStream(stream, $0.baseAddress, Int32($0.count)) }
        return drain()
    }
    public func finish() -> [Float] {
        sonicFlushStream(stream)
        return drain()
    }
    private func drain() -> [Float] {
        let count = Int(sonicSamplesAvailable(stream))
        guard count > 0 else { return [] }
        var output = [Float](repeating: 0, count: count)
        let copied = output.withUnsafeMutableBufferPointer {
            sonicReadFloatFromStream(stream, $0.baseAddress, Int32($0.count))
        }
        return muted ? Array(repeating: 0, count: Int(copied)) : Array(output.prefix(Int(copied)))
    }
}
