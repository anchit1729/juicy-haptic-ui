import Foundation

struct SourceSettingsStore {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = support.appendingPathComponent("AmbientHaptics/sources.json")
        }
    }

    func load(defaults: [SourceConfiguration]) throws -> [SourceConfiguration] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return defaults }
        let saved = try JSONDecoder().decode([SourceConfiguration].self, from: Data(contentsOf: fileURL))
        return defaults.map { standard in saved.first(where: { $0.id == standard.id }) ?? standard }
    }

    func save(_ settings: [SourceConfiguration]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}
