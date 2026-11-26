import Foundation
import XCTest
@testable import SpeechCore

final class SystemPitchTests: XCTestCase {
    func testPreferenceIsReadPerRequestAndOnlyAffectsPitch() throws {
        let suite = "PhononSystemPitchTests." + UUID().uuidString
        let writer = try XCTUnwrap(UserDefaults(suiteName: suite))
        let reader = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { writer.removePersistentDomain(forName: suite) }

        for value in ["+12st", "-12st"] {
            let request = try SpeechRequest.parse("<speak><prosody pitch='\(value)' rate='180%' volume='63%'>Hello</prosody></speak>")
                .withPauseLength(.shorter)
            XCTAssertNotEqual(request.pitch, 1)
            XCTAssertEqual(request.withSystemPitchPreference(reader).pitch, request.pitch)
            writer.set(true, forKey: SpeechRequest.ignoreSystemPitchKey)
            let fixed = request.withSystemPitchPreference(reader)
            XCTAssertEqual(fixed.pitch, 1)
            XCTAssertEqual(fixed.rate, request.rate)
            XCTAssertEqual(fixed.volume, request.volume)
            XCTAssertEqual(fixed.text, request.text)
            XCTAssertEqual(fixed.pauseLength, request.pauseLength)
            writer.set(false, forKey: SpeechRequest.ignoreSystemPitchKey)
            XCTAssertEqual(request.withSystemPitchPreference(reader).pitch, request.pitch)
        }
    }
}
