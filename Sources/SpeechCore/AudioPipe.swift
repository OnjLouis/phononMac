import Foundation

/// A per-request bounded FIFO. Cancellation wakes both producer and offline renderer.
public final class AudioPipe: @unchecked Sendable {
    public static let sampleRate = 24_000
    private static let modelStartupTimeout: TimeInterval = 20
    private static let streamStallTimeout: TimeInterval = 5
    private let condition = NSCondition()
    private var storage: [Float]
    private var readIndex = 0, writeIndex = 0, count = 0
    private var ended = false
    private var hasAudio = false
    public let capacity: Int

    public init(capacity: Int = sampleRate * 2) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = Array(repeating: 0, count: capacity)
    }

    @discardableResult public func push(_ samples: [Float]) -> Bool {
        condition.lock(); defer { condition.unlock() }
        var source = 0
        while source < samples.count {
            while count == capacity && !ended { condition.wait() }
            if ended { return false }
            let size = min(samples.count - source, capacity - count, capacity - writeIndex)
            storage.replaceSubrange(writeIndex..<writeIndex + size, with: samples[source..<source + size])
            writeIndex = (writeIndex + size) % capacity
            count += size; source += size
            hasAudio = true
            condition.broadcast()
        }
        return !ended
    }

    /// Only Apple's offline speech render path may wait for generated frames.
    /// A fixed deadline prevents a failed producer from hanging the system host.
    public func read(into destination: UnsafeMutablePointer<Float>, frames: Int,
                     timeout: TimeInterval? = nil) -> (copied: Int, complete: Bool) {
        condition.lock(); defer { condition.unlock() }
        // Core ML may compile an ANE execution plan in a fresh sandbox. This
        // bounded startup phase must not be mistaken for a stalled audio stream.
        let deadline = Date().addingTimeInterval(timeout ?? (hasAudio ? Self.streamStallTimeout : Self.modelStartupTimeout))
        var copied = 0
        while copied < frames {
            while count == 0 && !ended {
                if !condition.wait(until: deadline) { ended = true; condition.broadcast() }
            }
            if count == 0 { break }
            let size = min(frames - copied, count, capacity - readIndex)
            storage.withUnsafeBufferPointer { source in
                destination.advanced(by: copied).update(from: source.baseAddress!.advanced(by: readIndex), count: size)
            }
            readIndex = (readIndex + size) % capacity
            count -= size; copied += size
            condition.broadcast()
        }
        if copied < frames { destination.advanced(by: copied).initialize(repeating: 0, count: frames - copied) }
        return (copied, ended && count == 0)
    }

    public func finish(discard: Bool = false) {
        condition.lock()
        ended = true
        if discard { count = 0; readIndex = writeIndex }
        condition.broadcast(); condition.unlock()
    }
}
