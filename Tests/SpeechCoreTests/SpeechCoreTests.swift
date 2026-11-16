import XCTest
@testable import SpeechCore

final class SpeechCoreTests: XCTestCase {
    private var tone: [Float] { (0..<24_000).map { sin(Float($0) * 2 * .pi * 220 / 24_000) * 0.25 } }
    func testStreamingRateAndFlush() throws {
        let dsp = try SpeechProcessor(rate: 2, pitch: 1, volume: 1)
        let signal = tone
        var output: [Float] = []
        for offset in stride(from: 0, to: signal.count, by: 1920) {
            output += dsp.process(Array(signal[offset..<min(offset + 1920, signal.count)]))
        }
        output += dsp.finish()
        XCTAssertGreaterThan(output.count, 10_000); XCTAssertLessThan(output.count, 14_000)
    }
    func testStreamingVolume() throws {
        let dsp = try SpeechProcessor(rate: 1, pitch: 1, volume: 0)
        let output = dsp.process(tone) + dsp.finish()
        XCTAssertEqual(output.count, 24_000)
        XCTAssertTrue(output.allSatisfy { abs($0) < 0.000001 })
    }
    func testMarkupBoundariesAndEntities() throws {
        let r = try SpeechRequest.parse("<speak><s>Desktop</s><s>empty group &amp; more</s></speak>")
        XCTAssertEqual(r.text, "Desktop empty group & more")
    }
    func testBadMarkupRejected() {
        XCTAssertThrowsError(try SpeechRequest.parse("<speak>broken"))
    }
    func testNeutralProsody() throws {
        let r = try SpeechRequest.parse("<speak><prosody rate='100%' pitch='50%' volume='100%'>Hi</prosody></speak>")
        XCTAssertEqual(r.rate, 1); XCTAssertEqual(r.pitch, 1); XCTAssertEqual(r.volume, 1)
    }
    func testSpeechRateUsesPercentageOfNormalSpeed() throws {
        let omitted = try SpeechRequest.parse("<speak>Hi</speak>")
        XCTAssertEqual(omitted.rate, 1)
        for (rate, expected): (String, Float) in [
            ("75%", 0.75), ("110.5%", 1.105), ("200%", 2), ("250%", 2.5),
            ("0.75", 0.75), ("10%", 0.5), ("450%", 3)
        ] {
            let request = try SpeechRequest.parse("<speak><prosody rate='\(rate)'>Hi</prosody></speak>")
            XCTAssertEqual(request.rate, expected, accuracy: 0.001, rate)
        }
    }
    func testParsedRateChangesRenderedDuration() throws {
        let signal = tone
        func frames(_ rate: String) throws -> Int {
            let request = try SpeechRequest.parse("<speak><prosody rate='\(rate)'>Hi</prosody></speak>")
            let dsp = try SpeechProcessor(rate: request.rate, pitch: request.pitch, volume: request.volume)
            return dsp.process(signal).count + dsp.finish().count
        }
        let normal = try frames("100%")
        XCTAssertEqual(normal, 24_000)
        XCTAssertGreaterThan(try frames("110%"), normal * 8 / 10)
        XCTAssertLessThan(try frames("110%"), normal)
        XCTAssertLessThan(try frames("230%"), normal / 2)
    }
    func testPitchSemitonesAndMute() throws {
        let r = try SpeechRequest.parse("<speak><prosody pitch='+12st' volume='silent'>Hi</prosody></speak>")
        XCTAssertEqual(r.pitch, 2); XCTAssertEqual(r.volume, 0)
    }
    func testFIFOAndCompletion() {
        let pipe = AudioPipe(capacity: 4)
        XCTAssertTrue(pipe.push([1, 2, 3])); pipe.finish()
        var output = [Float](repeating: -1, count: 5)
        let result = output.withUnsafeMutableBufferPointer { pipe.read(into: $0.baseAddress!, frames: 5) }
        XCTAssertEqual(output, [1, 2, 3, 0, 0]); XCTAssertTrue(result.complete)
    }
    func testCancellationDiscardsAndRejectsStaleAudio() {
        let pipe = AudioPipe(capacity: 4)
        pipe.push([1, 2]); pipe.finish(discard: true)
        XCTAssertFalse(pipe.push([3]))
        var output = [Float](repeating: -1, count: 2)
        let result = output.withUnsafeMutableBufferPointer { pipe.read(into: $0.baseAddress!, frames: 2) }
        XCTAssertEqual(output, [0, 0]); XCTAssertTrue(result.complete)
    }
    func testCancelWakesBackpressuredProducer() {
        let pipe = AudioPipe(capacity: 1)
        pipe.push([1])
        let done = expectation(description: "producer stopped")
        DispatchQueue.global().async {
            XCTAssertFalse(pipe.push([2])); done.fulfill()
        }
        pipe.finish(discard: true)
        wait(for: [done], timeout: 1)
    }
    func testFailedProducerCannotWaitForever() {
        let pipe = AudioPipe()
        var output = [Float](repeating: -1, count: 1)
        let start = Date()
        let result = output.withUnsafeMutableBufferPointer { pipe.read(into: $0.baseAddress!, frames: 1, timeout: 0.01) }
        XCTAssertTrue(result.complete); XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }
}
