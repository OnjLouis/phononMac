import AppKit
import Foundation
import UpdateCore

enum UpdateFrequency: String, CaseIterable, Identifiable {
    case never, hourly, daily
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var interval: TimeInterval? { self == .never ? nil : (self == .hourly ? 3600 : 86_400) }
}

private class UpdateRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(UpdatePolicy.allows) == true ? request : nil)
    }
}

private final class DownloadLimit: UpdateRedirectPolicy, URLSessionDownloadDelegate {
    let maximum: Int64
    init(_ maximum: Int64) { self.maximum = maximum }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximum || totalBytesExpectedToWrite > maximum { downloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

@MainActor final class UpdateService: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var status = ""
    private let policy = UpdatePolicy(verificationKey: Data(base64Encoded: "qp/w3My701r/AGBe+Og05JRK2X6i80NAmO2NJkSS7Aw=")!)
    private let session: URLSession
    private var timer: Timer?
    private var checkTask: Task<Void, Never>?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: UpdateRedirectPolicy(), delegateQueue: nil)
        status = UserDefaults.standard.string(forKey: "updateInstallResult") ?? ""
        UserDefaults.standard.removeObject(forKey: "updateInstallResult")
    }
    deinit { timer?.invalidate(); checkTask?.cancel(); session.invalidateAndCancel() }

    func start() {
        checkAutomatically()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAutomatically() }
        }
    }
    func checkAutomatically() {
        let frequency = UpdateFrequency(rawValue: UserDefaults.standard.string(forKey: "updateFrequency") ?? "daily") ?? .daily
        guard let interval = frequency.interval else { return }
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= interval else { return }
        check(manual: false)
    }
    func check(manual: Bool = true) {
        guard !busy else { return }
        busy = true; status = "Checking for updates..."
        checkTask = Task {
            defer { busy = false }
            do {
                var request = URLRequest(url: UpdatePolicy.manifestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                request.setValue("Phonon for Mac updater", forHTTPHeaderField: "User-Agent")
                let (bytes, response) = try await session.bytes(for: request)
                defer { bytes.task.cancel() }
                try validate(response)
                var data = Data()
                for try await byte in bytes {
                    guard data.count < 131_072 else { throw UpdateFailure.invalid("The update feed is too large.") }
                    data.append(byte)
                }
                let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
                try policy.verify(manifest)
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
                guard UpdatePolicy.newer(manifest.version, than: current) else {
                    status = "Phonon for Mac is up to date."
                    return
                }
                status = "Version \(manifest.version) is available."
                let alert = NSAlert()
                alert.messageText = "Phonon \(manifest.version) Is Available"
                alert.informativeText = "\(manifest.notes)\n\nInstall this signed and notarized update? This settings app will close and reopen. VoiceOver can keep speaking; restart VoiceOver afterward when convenient."
                alert.addButton(withTitle: "Install"); alert.addButton(withTitle: "Not Now")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                try await install(manifest)
            } catch is CancellationError {
                status = "Update check cancelled."
            } catch {
                status = "Update check failed: \(error.localizedDescription)"
                if manual {
                    let alert = NSAlert(); alert.messageText = "Could Not Update Phonon"
                    alert.informativeText = error.localizedDescription; alert.runModal()
                }
            }
        }
    }
    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let url = http.url, UpdatePolicy.allows(url) else {
            throw UpdateFailure.invalid("The update server returned an unexpected response.")
        }
    }
    private func install(_ manifest: UpdateManifest) async throws {
        let target = Bundle.main.bundleURL
        let executable = Bundle.main.executableURL?.path ?? ""
        guard target.lastPathComponent == UpdatePolicy.appName,
              FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path),
              !executable.isEmpty else {
            throw UpdateFailure.invalid("Move Phonon to a writable Applications folder before updating it.")
        }
        let free = try FileManager.default.attributesOfFileSystem(forPath: Bundle.main.bundleURL.path)[.systemFreeSize] as? NSNumber
        guard let free, free.int64Value > manifest.size * 4 + 536_870_912 else {
            throw UpdateFailure.invalid("There is not enough free space to stage this update safely.")
        }
        status = "Downloading version \(manifest.version)..."
        let (download, response) = try await session.download(from: UpdatePolicy.packageURL, delegate: DownloadLimit(manifest.size))
        defer { try? FileManager.default.removeItem(at: download) }
        try validate(response)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhononMacUpdate-\(UUID().uuidString)")
        do {
            status = "Verifying update..."
            let staged = try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                       attributes: [.posixPermissions: 0o700])
                let archive = root.appendingPathComponent(manifest.fileName)
                try FileManager.default.copyItem(at: download, to: archive)
                try UpdatePolicy.verifyPackage(archive, manifest: manifest)
                return try UpdatePackage.extract(archive, to: root.appendingPathComponent("extract"), version: manifest.version)
            }.value
            let plan = UpdateInstallation(target: target, staged: staged, stagingRoot: root, version: manifest.version,
                                          oldPID: ProcessInfo.processInfo.processIdentifier, oldExecutable: executable)
            let script = root.appendingPathComponent("install-update.zsh")
            try plan.script().write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [script.path]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }
}
