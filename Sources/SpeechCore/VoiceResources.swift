import Foundation
import CryptoKit

public enum VoiceResources {
    static func storageName(for displayName: String) -> String {
        let canonical = Data(displayName.precomposedStringWithCanonicalMapping.utf8)
        return "voice-" + SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }

    public static func resolve(_ displayName: String, available: [String]) -> String? {
        let resource = storageName(for: displayName)
        // Keep already-prepared model data usable without replacing a live cache.
        return available.first { $0 == resource } ?? available.first { $0 == displayName }
    }
}
