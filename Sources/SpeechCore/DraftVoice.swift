import Foundation
import PhononTTS

public enum DraftVoice {
    public static func render(_ data: Data, models: URL, text: String, language: String,
                              onAudio: @escaping @Sendable ([Float]) -> Void) async throws {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= 4 * 1024 * 1024 else {
            throw PhononError(description: "The voice file size is not supported.")
        }
        let manager = FileManager.default
        let scratch = manager.temporaryDirectory.appendingPathComponent("phonon-preview-" + UUID().uuidString)
        try manager.createDirectory(at: scratch, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: scratch) }
        let voices = scratch.appendingPathComponent("voices")
        try manager.createDirectory(at: voices, withIntermediateDirectories: false)
        // Reuse installed weights, but expose only the draft in this engine's private catalogue.
        let modelFiles = try manager.contentsOfDirectory(at: models, includingPropertiesForKeys: nil)
        for file in modelFiles where file.pathExtension == "mlpackage" || file.pathExtension == "mlmodelc"
            || ["host.safetensors", "tokenizer.json", "bundle.json"].contains(file.lastPathComponent) {
            try manager.createSymbolicLink(at: scratch.appendingPathComponent(file.lastPathComponent),
                                           withDestinationURL: file)
        }
        let stem = "preview-" + UUID().uuidString.lowercased()
        let voiceFile = voices.appendingPathComponent(stem + ".safetensors")
        #if os(iOS)
        try data.write(to: voiceFile, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: voiceFile, options: .atomic)
        #endif
        let engine = try await Phonon.load(models: scratch, language: Language(rawValue: language) ?? .english)
        try Task.checkCancellation()
        try await engine.setVoice(stem)
        try Task.checkCancellation()
        try await engine.speak(text, onAudio: onAudio)
        try Task.checkCancellation()
    }
}
