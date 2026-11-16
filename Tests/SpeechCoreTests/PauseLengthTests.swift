import XCTest
@testable import SpeechCore

final class PauseLengthTests: XCTestCase {
    func testQuietGapModesPreserveTheSpeechAndInitialSilence() {
        let speech = [Float](repeating: 0.1, count: 120)
        let initial = [Float](repeating: 0, count: 3_840)
        let quiet = [Float](repeating: 0, count: 7_200)
        let original = initial + speech + quiet + speech
        for (mode, gap) in [(PauseLength.shorter, 2_880), (.unchanged, 7_200), (.longer, 9_120)] {
            var filter = PauseFilter(mode: mode)
            var output: [Float] = []
            for start in stride(from: 0, to: original.count, by: 317) {
                output += filter.process(Array(original[start..<min(start + 317, original.count)]))
            }
            output += filter.finish()
            XCTAssertEqual(output, initial + speech + [Float](repeating: 0, count: gap) + speech)
        }
    }
}
