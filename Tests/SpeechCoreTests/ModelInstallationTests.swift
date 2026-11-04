import CryptoKit
import Foundation
import PhononTTS
import XCTest

final class ModelInstallationTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }
    private func bundle(_ name: String, built: Int, content: String = "model") throws -> URL {
        let directory = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = Data(content.utf8)
        try data.write(to: directory.appendingPathComponent("model.bin"))
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let manifest: [String: Any] = ["built": built, "files": [
            ["path": "model.bin", "size": data.count, "sha256": hash]
        ]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("bundle.json"))
        return directory
    }
    func testMissingSourceFilePreservesOldInstallation() throws {
        let installed = try bundle("installed", built: 1, content: "old model")
        let source = try bundle("source", built: 2)
        try FileManager.default.removeItem(at: source.appendingPathComponent("model.bin"))
        XCTAssertThrowsError(try PhononModels.install(bundled: source, to: installed))
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("model.bin"), encoding: .utf8), "old model")
    }
    func testCorruptSourcePreservesOldInstallation() throws {
        let installed = try bundle("installed", built: 1, content: "old model")
        let source = try bundle("source", built: 2)
        try Data("other".utf8).write(to: source.appendingPathComponent("model.bin"))
        XCTAssertThrowsError(try PhononModels.install(bundled: source, to: installed))
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("model.bin"), encoding: .utf8), "old model")
    }
    func testUpgradeAndRepeatPreserveCompiledCache() throws {
        let installed = try bundle("installed", built: 1, content: "old model")
        let source = try bundle("source", built: 2, content: "new model")
        try PhononModels.install(bundled: source, to: installed)
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("model.bin"), encoding: .utf8), "new model")
        let cache = installed.appendingPathComponent("compiled.cache")
        try Data([1, 2, 3]).write(to: cache)
        try PhononModels.install(bundled: source, to: installed)
        XCTAssertEqual(try Data(contentsOf: cache), Data([1, 2, 3]))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["installed", "source"])
    }
}
