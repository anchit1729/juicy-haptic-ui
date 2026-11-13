import Foundation

struct PatternStore {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = support.appendingPathComponent("AmbientHaptics/patterns.json")
        }
    }

    func load() throws -> [HapticPattern] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return StarterPatterns.all }
        return try JSONDecoder().decode([HapticPattern].self, from: Data(contentsOf: fileURL))
    }

    func save(_ patterns: [HapticPattern]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(patterns.map { $0.limited() }).write(to: fileURL, options: .atomic)
    }
}
