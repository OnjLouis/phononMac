import Accelerate
import Foundation

struct MacVoiceStore {
    static let locales = ["en-GB", "en-US", "fr-FR", "de-DE", "es-ES", "es-MX", "pt-BR"]
    private static let maxBytes = 4 * 1024 * 1024
    private static let width = 512
    let root: URL
    let models: URL

    struct Entry: Codable {
        let key: UUID
        let name: String
        let locale: String
        var stem: String { "imported-" + key.uuidString.lowercased() }
    }

    enum Failure: LocalizedError {
        case unsupported, name, limit, unavailable
        var errorDescription: String? {
            switch self {
            case .unsupported: return "Choose a compatible Phonon voice file."
            case .name: return "Enter a voice name and select its language."
            case .limit: return "Phonon can store up to 64 imported voices."
            case .unavailable: return "Phonon could not read this file. If it is stored in the cloud, make it available offline and try again."
            }
        }
    }

    private struct Tensor: Codable {
        let dtype: String
        let shape: [Int]
        let data_offsets: [Int]
    }

    private func metadata(_ url: URL) -> Entry? {
        guard let data = try? Self.read(url, limit: 4096),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              url.lastPathComponent == entry.stem + ".json", Self.locales.contains(entry.locale),
              !entry.name.isEmpty, entry.name.count <= 80,
              FileManager.default.isReadableFile(atPath: tensor(entry).path) else { return nil }
        return entry
    }

    func entries() -> [Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return files.lazy.filter { $0.pathExtension == "json" }.compactMap(metadata).prefix(64)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func entry(for stem: String) -> Entry? {
        guard stem.hasPrefix("imported-"), let key = UUID(uuidString: String(stem.dropFirst(9))),
              stem == "imported-" + key.uuidString.lowercased() else { return nil }
        return metadata(root.appendingPathComponent(stem + ".json"))
    }

    private func tensor(_ entry: Entry) -> URL { root.appendingPathComponent(entry.stem + ".safetensors") }
    private func runtime(_ entry: Entry) -> URL { models.appendingPathComponent("voices/" + entry.stem + ".safetensors") }

    func restoreRuntimeVoices() throws {
        for entry in entries() where !FileManager.default.fileExists(atPath: runtime(entry).path) {
            try Self.read(tensor(entry), limit: Self.maxBytes).write(to: runtime(entry), options: .atomic)
        }
    }

    func add(_ input: URL, name: String, locale: String, projection: URL?) throws -> Entry {
        try add(Self.readSource(input), name: name, locale: locale, projection: projection)
    }

    static func readSource(_ input: URL) throws -> Data {
        guard input.pathExtension.lowercased() == "safetensors" else { throw Failure.unsupported }
        return try read(input, limit: maxBytes)
    }

    static func snapshotSelectedFile(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw Failure.unavailable }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var snapshot: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            snapshot = Result { try readSource(readable) }
        }
        guard coordinationError == nil, let snapshot else { throw Failure.unavailable }
        do { return try snapshot.get() }
        catch is CocoaError { throw Failure.unavailable }
    }

    func data(for entry: Entry) throws -> Data { try Self.read(tensor(entry), limit: Self.maxBytes) }

    func changeLanguage(_ entry: Entry, to locale: String) throws {
        guard let current = self.entry(for: entry.stem), Self.locales.contains(locale) else { throw Failure.name }
        if current.locale == locale { return }
        let changed = Entry(key: current.key, name: current.name, locale: locale)
        try JSONEncoder().encode(changed).write(to: root.appendingPathComponent(entry.stem + ".json"), options: .atomic)
    }

    func add(_ input: Data, name: String, locale: String, projection: URL?) throws -> Entry {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              Self.locales.contains(locale) else { throw Failure.name }
        guard entries().count < 64 else { throw Failure.limit }
        guard input.count <= Self.maxBytes else { throw Failure.unsupported }
        let data = try Self.project(input, projection: projection)
        let entry = Entry(key: UUID(), name: name, locale: locale)
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            try data.write(to: tensor(entry), options: .atomic)
            try data.write(to: runtime(entry), options: .atomic)
            try JSONEncoder().encode(entry).write(to: root.appendingPathComponent(entry.stem + ".json"), options: .atomic)
        } catch {
            try? manager.removeItem(at: tensor(entry))
            try? manager.removeItem(at: runtime(entry))
            throw error
        }
        return entry
    }

    func remove(_ entry: Entry) throws {
        guard self.entry(for: entry.stem) != nil else { return }
        let manager = FileManager.default
        // Unpublish before touching derived data, so a concurrent lookup uses stock speech.
        try manager.removeItem(at: root.appendingPathComponent(entry.stem + ".json"))
        if manager.fileExists(atPath: runtime(entry).path) { try manager.removeItem(at: runtime(entry)) }
        try manager.removeItem(at: tensor(entry))
    }

    private static func read(_ url: URL, limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.unsupported }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while let chunk = try file.read(upToCount: min(64 * 1024, limit + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            if data.count > limit { throw Failure.unsupported }
        }
        guard !data.isEmpty else { throw Failure.unsupported }
        return data
    }

    static func project(_ input: Data, projection: URL?) throws -> Data {
        guard input.count > 8 else { throw Failure.unsupported }
        let length = input.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
        guard length <= 16_384, length <= input.count - 8 else { throw Failure.unsupported }
        let offset = 8 + Int(length)
        guard var header = try JSONSerialization.jsonObject(with: input.subdata(in: 8..<offset)) as? [String: Any] else {
            throw Failure.unsupported
        }
        if let metadata = header.removeValue(forKey: "__metadata__") {
            guard let fields = metadata as? [String: String],
                  fields["model_ext"].map({ $0 == "ba7a5a45@300" }) != false else { throw Failure.unsupported }
        }
        guard header.count == 1, let (key, value) = header.first,
              ["emb", "audio_prompt", "speaker_wavs"].contains(key) else { throw Failure.unsupported }
        let tensor = try JSONDecoder().decode(Tensor.self, from: JSONSerialization.data(withJSONObject: value))
        let shape = tensor.shape.count == 3 && tensor.shape.first == 1 ? Array(tensor.shape.dropFirst()) : tensor.shape
        guard tensor.dtype == "F32", shape.count == 2 else { throw Failure.unsupported }
        let latent = key == "speaker_wavs"
        let frames = shape[latent ? 1 : 0]
        let bytes = input.count - offset
        guard (1...512).contains(frames), shape[latent ? 0 : 1] == width,
              bytes == frames * width * 4, tensor.data_offsets == [0, bytes] else { throw Failure.unsupported }
        let values = input.withUnsafeBytes { raw in
            (0..<(bytes / 4)).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + $0 * 4, as: UInt32.self))) }
        }
        guard values.allSatisfy(\.isFinite) else { throw Failure.unsupported }
        var output = values
        if latent {
            guard let projection else { throw Failure.unsupported }
            let matrix = try read(projection, limit: width * width * 2)
            guard matrix.count == width * width * 2 else { throw Failure.unsupported }
            let weights = matrix.withUnsafeBytes { raw in
                (0..<(width * width)).map { Float(bitPattern: UInt32(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self))) << 16) }
            }
            cblas_sgemm(CblasRowMajor, CblasTrans, CblasTrans, Int32(frames), Int32(width), Int32(width),
                        1, values, Int32(frames), weights, Int32(width), 0, &output, Int32(width))
            guard output.allSatisfy(\.isFinite) else { throw Failure.unsupported }
        }
        var json = try JSONEncoder().encode(["emb": Tensor(dtype: "F32", shape: [1, frames, width], data_offsets: [0, bytes])])
        json.append(Data(repeating: 32, count: (8 - json.count % 8) % 8))
        var headerSize = UInt64(json.count).littleEndian
        var result = withUnsafeBytes(of: &headerSize) { Data($0) }
        result.append(json)
        result.append(output.withUnsafeBytes { Data($0) })
        return result
    }
}
