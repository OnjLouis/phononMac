import Foundation
import XCTest
@testable import UpdateCore

final class ArchiveTests: XCTestCase {
    private let appInfo = "Phonon for Mac.app/Contents/Info.plist"
    private let providerInfo = "Phonon for Mac.app/Contents/PlugIns/Phonon Speech Provider.appex/Contents/Info.plist"
    private func archive(_ paths: [String], flags: UInt16 = 0, mode: UInt32 = 0x81a4,
                         expanded: UInt32 = 0, localNameMismatch: Bool = false) throws -> URL {
        var file = Data(), central = Data()
        for path in paths {
            let name = Data(path.utf8), offset = file.count
            file.le32(0x04034b50); file.le16(20); file.le16(flags); file.le16(0)
            file.le16(0); file.le16(0); file.le32(0); file.le32(0); file.le32(expanded)
            file.le16(UInt16(name.count)); file.le16(0)
            file.append(localNameMismatch ? Data(repeating: 65, count: name.count) : name)
            central.le32(0x02014b50); central.le16(0x0314); central.le16(20)
            central.le16(flags); central.le16(0); central.le16(0); central.le16(0)
            central.le32(0); central.le32(0); central.le32(expanded)
            central.le16(UInt16(name.count)); central.le16(0); central.le16(0)
            central.le16(0); central.le16(0); central.le32(mode << 16); central.le32(UInt32(offset))
            central.append(name)
        }
        let offset = file.count
        file.append(central)
        file.le32(0x06054b50); file.le16(0); file.le16(0)
        file.le16(UInt16(paths.count)); file.le16(UInt16(paths.count))
        file.le32(UInt32(central.count)); file.le32(UInt32(offset)); file.le16(0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try file.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testExpectedArchiveLayoutAccepted() throws {
        XCTAssertNoThrow(try ZipInventory.validate(archive([appInfo, providerInfo])))
    }
    func testTraversalAndWrongRootRejected() throws {
        for bad in ["Phonon for Mac.app/../escape", "Other.app/Contents/Info.plist", "Phonon for Mac.app/Contents\\escape"] {
            XCTAssertThrowsError(try ZipInventory.validate(archive([appInfo, providerInfo, bad])))
        }
    }
    func testDuplicateCaseFoldedNamesRejected() throws {
        XCTAssertThrowsError(try ZipInventory.validate(archive([appInfo, providerInfo, "Phonon for Mac.app/contents/info.plist"])))
    }
    func testSymlinksAndEncryptionRejected() throws {
        XCTAssertThrowsError(try ZipInventory.validate(archive([appInfo, providerInfo], mode: 0xa1ff)))
        XCTAssertThrowsError(try ZipInventory.validate(archive([appInfo, providerInfo], flags: 1)))
    }
    func testExpansionBudgetAndLocalMismatchRejected() throws {
        XCTAssertThrowsError(try ZipInventory.validate(archive([appInfo, providerInfo], expanded: 2_000_000_000)))
        XCTAssertThrowsError(try ZipInventory.validate(archive([appInfo, providerInfo], localNameMismatch: true)))
    }
    func testRequiredProviderRejectedWhenMissing() throws {
        XCTAssertThrowsError(try ZipInventory.validate(archive([appInfo])))
    }
    func testVerifierProcessHasDeadline() {
        let start = Date()
        XCTAssertThrowsError(try UpdatePackage.run("/bin/sleep", ["5"], timeout: 0.05))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
    func testInstallerRejectsUnrelatedPaths() {
        let plan = UpdateInstallation(target: URL(fileURLWithPath: "/tmp/Other.app"),
            staged: URL(fileURLWithPath: "/tmp/PhononMacUpdate-test/Phonon for Mac.app"),
            stagingRoot: URL(fileURLWithPath: "/tmp/PhononMacUpdate-test"), version: "1.0", oldPID: 100,
            oldExecutable: "/tmp/test")
        XCTAssertThrowsError(try plan.script())
    }
}

private extension Data {
    mutating func le16(_ value: UInt16) { var value = value.littleEndian; Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) } }
    mutating func le32(_ value: UInt32) { var value = value.littleEndian; Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) } }
}
