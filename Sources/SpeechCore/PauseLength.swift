import Foundation

public enum PauseLength: String, CaseIterable, Identifiable, Sendable {
    case shorter, unchanged = "default", longer

    public var id: Self { self }
    public var label: String {
        switch self {
        case .shorter: return "Shorter"
        case .unchanged: return "Default"
        case .longer: return "Longer"
        }
    }

    public static func stored(in group: String) -> Self {
        UserDefaults(suiteName: group)?.string(forKey: "pauseLength").flatMap(Self.init(rawValue:)) ?? .unchanged
    }
}

struct PauseFilter {
    private static let frameSize = 120 // 5 ms at 24 kHz
    private static let shortHead = 19
    private static let shortTail = 5
    private static let longMinimum = 24
    private static let addedSilence = [Float](repeating: 0, count: 16 * frameSize)
    let mode: PauseLength
    let threshold: Float
    private var partial: [Float] = []
    private var tail: [[Float]] = []
    private var quietFrames = 0
    private var heardSound = false

    init(mode: PauseLength, volume: Float = 1) {
        self.mode = volume == 0 ? .unchanged : mode
        threshold = (96.0 / 32767.0) * volume
    }

    mutating func process(_ samples: [Float]) -> [Float] {
        guard mode != .unchanged, !samples.isEmpty else { return samples }
        let input = partial + samples
        let size = Self.frameSize
        let end = input.count - input.count % size
        partial = Array(input[end...])
        var output: [Float] = []
        output.reserveCapacity(input.count)
        for offset in stride(from: 0, to: end, by: size) {
            let frame = input[offset..<offset + size]
            let audible = frame.contains { $0.isFinite && abs($0) > threshold }
            if audible {
                if mode == .shorter {
                    tail.forEach { output.append(contentsOf: $0) }
                    tail.removeAll(keepingCapacity: true)
                } else if quietFrames >= Self.longMinimum {
                    output.append(contentsOf: Self.addedSilence)
                }
                quietFrames = 0
                heardSound = true
            } else if heardSound {
                quietFrames += 1
                if mode == .shorter && quietFrames > Self.shortHead {
                    if tail.count == Self.shortTail { tail.removeFirst() }
                    tail.append(Array(frame))
                    continue
                }
            }
            output.append(contentsOf: frame)
        }
        return output
    }

    mutating func finish() -> [Float] {
        let remaining = tail.flatMap { $0 } + partial
        tail.removeAll()
        partial.removeAll()
        return remaining
    }
}
