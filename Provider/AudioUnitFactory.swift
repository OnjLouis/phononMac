import CoreAudioKit
import Foundation

public final class AudioUnitFactory: NSObject, AUAudioUnitFactory {
    public func beginRequest(with context: NSExtensionContext) {}
    public func createAudioUnit(with description: AudioComponentDescription) throws -> AUAudioUnit {
        try PhononSpeechAudioUnit(componentDescription: description, options: [])
    }
}
