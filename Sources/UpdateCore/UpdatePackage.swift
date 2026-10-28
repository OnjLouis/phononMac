import CryptoKit
import Darwin
import Foundation

public enum UpdatePackage {
    public static func verifyApp(_ app: URL, version: String, requireNotarization: Bool = true) throws {
        let provider = app.appendingPathComponent("Contents/PlugIns/" + UpdatePolicy.providerName)
        guard app.lastPathComponent == UpdatePolicy.appName,
              let bundle = Bundle(url: app), bundle.bundleIdentifier == UpdatePolicy.bundleID,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version,
              Bundle(url: provider)?.bundleIdentifier == UpdatePolicy.providerID else {
            throw UpdateFailure.invalid("The update has the wrong application, speech provider or version.")
        }
        guard let files = FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw UpdateFailure.invalid("The update could not be inspected.")
        }
        for case let file as URL in files {
            guard try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false else {
                throw UpdateFailure.invalid("The update contains an unexpected symbolic link.")
            }
        }
        let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(UpdatePolicy.teamID)\" and identifier \"\(UpdatePolicy.bundleID)\""
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--test-requirement", "=\(requirement)", app.path])
        if requireNotarization { try run("/usr/bin/xcrun", ["stapler", "validate", app.path]) }
    }

    public static func extract(_ archive: URL, to directory: URL, version: String) throws -> URL {
        try ZipInventory.validate(archive)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path], timeout: 60)
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard entries.count == 1, entries[0].lastPathComponent == UpdatePolicy.appName else {
            throw UpdateFailure.invalid("The update contains unexpected files or folders.")
        }
        try verifyApp(entries[0], version: version)
        return entries[0]
    }

    /// Runs on an updater worker, never the main actor or a speech/audio callback.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Phonon-command-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: file)
        defer { try? output.close(); try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output; process.standardError = output
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            let limit = Date().addingTimeInterval(2)
            while process.isRunning && Date() < limit { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw UpdateFailure.invalid("The update verification tool did not respond in time.")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let reader = try FileHandle(forReadingFrom: file)
            defer { try? reader.close() }
            let size = try reader.seekToEnd()
            try reader.seek(toOffset: size > 8192 ? size - 8192 : 0)
            let detail = String(data: try reader.readToEnd() ?? Data(), encoding: .utf8) ?? "Verification failed."
            throw UpdateFailure.invalid(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
