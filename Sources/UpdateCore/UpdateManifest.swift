import CryptoKit
import Foundation

public struct UpdateManifest: Codable, Sendable {
    public let version: String
    public let fileName: String
    public let downloadUrl: String
    public let notes: String
    public let size: Int64
    public let sha256: String
    public let published: String
    public let signature: String

    public func signedPayload() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "version": version, "fileName": fileName, "downloadUrl": downloadUrl,
            "notes": notes, "size": size, "sha256": sha256, "published": published
        ], options: [.sortedKeys, .withoutEscapingSlashes])
    }
}

public enum UpdateFailure: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public struct UpdatePolicy: Sendable {
    public static let bundleID = "com.onj.phononmac"
    public static let providerID = "com.onj.phononmac.speechprovider"
    public static let teamID = "83NN3HS237"
    public static let appName = "Phonon for Mac.app"
    public static let providerName = "Phonon Speech Provider.appex"
    private static let releaseRoot = "https://github.com/OnjLouis/phononMac/releases/"
    public static let manifestURL = URL(string: releaseRoot + "latest/download/phononMac-update.json")!
    public static let packageURL = URL(string: releaseRoot + "latest/download/Phonon-for-Mac.zip")!
    public static let maximumPackageBytes: Int64 = 1_073_741_824
    private let key: Data
    public init(verificationKey: Data) { key = verificationKey }

    public func verify(_ manifest: UpdateManifest) throws {
        guard key.count == 32, let signature = Data(base64Encoded: manifest.signature),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key),
              publicKey.isValidSignature(signature, for: try manifest.signedPayload()) else {
            throw UpdateFailure.invalid("The update signature is missing or invalid.")
        }
        guard Self.versionParts(manifest.version) != nil, manifest.notes.utf8.count <= 32_768,
              manifest.size > 0, manifest.size <= Self.maximumPackageBytes,
              manifest.fileName == Self.packageURL.lastPathComponent,
              manifest.downloadUrl == Self.releaseRoot + "download/v\(manifest.version)/Phonon-for-Mac.zip",
              manifest.sha256.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else {
            throw UpdateFailure.invalid("The signed update details are invalid or belong to another application.")
        }
    }

    public static func allows(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.user == nil, parts.password == nil,
              parts.port == nil, parts.fragment == nil else { return false }
        if parts.host == "release-assets.githubusercontent.com" {
            // GitHub's signed download redirects use this dedicated asset host.
            let path = parts.path.split(separator: "/")
            return path.count == 3 && path[0] == "github-production-release-asset" &&
                path[1].allSatisfy({ $0.isASCII && $0.isNumber }) && !path[2].isEmpty
        }
        guard parts.host == "github.com", parts.query == nil else { return false }
        if url == manifestURL || url == packageURL { return true }
        return parts.path.range(of: "^/OnjLouis/phononMac/releases/download/v[0-9]{1,9}(\\.[0-9]{1,9}){0,3}/(phononMac-update\\.json|Phonon-for-Mac\\.zip)$",
                                options: .regularExpression) != nil
    }
    public static func newer(_ version: String, than installed: String) -> Bool {
        guard let left = versionParts(version), let right = versionParts(installed) else { return false }
        for i in 0..<max(left.count, right.count) {
            let l = i < left.count ? left[i] : 0
            let r = i < right.count ? right[i] : 0
            if l != r { return l > r }
        }
        return false
    }
    private static func versionParts(_ value: String) -> [Int]? {
        guard value.range(of: "^[0-9]{1,9}(\\.[0-9]{1,9}){0,3}$", options: .regularExpression) != nil else { return nil }
        return value.split(separator: ".").compactMap { Int($0) }
    }

    public static func verifyPackage(_ url: URL, manifest: UpdateManifest) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard try file.seekToEnd() == UInt64(manifest.size) else {
            throw UpdateFailure.invalid("The downloaded update size does not match its signed details.")
        }
        try file.seek(toOffset: 0)
        var hash = SHA256()
        while let block = try file.read(upToCount: 1_048_576), !block.isEmpty { hash.update(data: block) }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == manifest.sha256.lowercased() else {
            throw UpdateFailure.invalid("The downloaded update failed its integrity check.")
        }
    }
}
