import Foundation

/// Inspect central and local ZIP headers before allowing extraction of a signed package.
public enum ZipInventory {
    private static let maximumEntries = 1024
    private static let maximumDirectoryBytes = 2_097_152

    public static func validate(_ url: URL) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        guard size >= 22, size <= UInt64(UpdatePolicy.maximumPackageBytes) else { throw bad() }
        let tailSize = Int(min(size, 65_557))
        try file.seek(toOffset: size - UInt64(tailSize))
        let tail = try file.read(upToCount: tailSize) ?? Data()
        guard tail.count >= 22 else { throw bad() }
        guard let end = (0...(tail.count - 22)).reversed().first(where: {
            tail.u32($0) == 0x06054b50 && $0 + 22 + tail.u16($0 + 20) == tail.count
        }) else { throw bad() }
        let count = tail.u16(end + 10)
        let directorySize = tail.u32(end + 12)
        let directoryOffset = tail.u32(end + 16)
        guard tail.u16(end + 4) == 0, tail.u16(end + 6) == 0,
              tail.u16(end + 8) == count, count > 0, count <= maximumEntries,
              directorySize <= maximumDirectoryBytes,
              UInt64(directoryOffset) + UInt64(directorySize) == size - UInt64(tailSize) + UInt64(end) else { throw bad() }
        try file.seek(toOffset: UInt64(directoryOffset))
        let central = try file.read(upToCount: directorySize) ?? Data()
        guard central.count == directorySize else { throw bad() }
        var offset = 0, total: Int64 = 0
        var names = Set<String>()
        for _ in 0..<count {
            guard offset + 46 <= central.count, central.u32(offset) == 0x02014b50 else { throw bad() }
            let flags = central.u16(offset + 8), method = central.u16(offset + 10)
            let compressed = central.u32(offset + 20), uncompressed = central.u32(offset + 24)
            let length = central.u16(offset + 28), extra = central.u16(offset + 30), comment = central.u16(offset + 32)
            let endName = offset + 46 + length
            guard flags & 1 == 0, method == 0 || method == 8, length > 0,
                  endName + extra + comment <= central.count,
                  let path = String(data: central[(offset + 46)..<endName], encoding: .utf8),
                  !path.contains("\\"), !path.contains("\0"),
                  path.hasPrefix(UpdatePolicy.appName + "/"),
                  !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
                  (central.u32(offset + 38) >> 16) & 0xf000 != 0xa000 else { throw bad() }
            let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .precomposedStringWithCanonicalMapping.lowercased()
            guard names.insert(normalized).inserted else { throw bad() }
            let localOffset = central.u32(offset + 42)
            guard localOffset + 30 < directoryOffset else { throw bad() }
            try file.seek(toOffset: UInt64(localOffset))
            let local = try file.read(upToCount: 30) ?? Data()
            guard local.count == 30, local.u32(0) == 0x04034b50,
                  local.u16(6) == flags, local.u16(8) == method,
                  local.u16(26) == length,
                  Int64(localOffset) + 30 + Int64(length + local.u16(28)) + Int64(compressed) <= Int64(directoryOffset),
                  try file.read(upToCount: length) == central[(offset + 46)..<endName] else { throw bad() }
            total += Int64(uncompressed)
            guard total <= UpdatePolicy.maximumPackageBytes else { throw bad() }
            offset = endName + extra + comment
        }
        guard offset == central.count,
              names.contains((UpdatePolicy.appName + "/Contents/Info.plist").lowercased()),
              names.contains((UpdatePolicy.appName + "/Contents/PlugIns/" + UpdatePolicy.providerName + "/Contents/Info.plist").lowercased()) else { throw bad() }
    }
    private static func bad() -> UpdateFailure { .invalid("The update archive has an unsafe or unexpected layout.") }
}

private extension Data {
    func u16(_ offset: Int) -> Int { Int(self[offset]) | Int(self[offset + 1]) << 8 }
    func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }
}
