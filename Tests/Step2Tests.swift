import XCTest
@testable import AmbientHaptics

final class Step2Tests: XCTestCase {
    func testToneAndNoiseStayWithinLimit() {
        for pattern in StarterPatterns.all {
            let synth = PatternSynthesizer(pattern: pattern, sampleRate: 48_000)
            var peak: Float = 0
            for _ in 0..<48_000 {
                peak = max(peak, abs(synth.nextSample()))
            }
            XCTAssertGreaterThan(peak, 0, pattern.name)
            XCTAssertLessThanOrEqual(peak, 1, pattern.name)
        }
    }

    func testPatternStoreRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PatternStore(fileURL: folder.appendingPathComponent("patterns.json"))
        try store.save(StarterPatterns.all)
        XCTAssertEqual(try store.load(), StarterPatterns.all)
    }

    func testNewSourceUsesExistingMappingCode() {
        let pattern = StarterPatterns.all[2]
        let mapping = ValueMapping(valueName: "level", control: .strength, inputMin: 0, inputMax: 100, outputMin: 0, outputMax: 1)
        let result = PatternMapper.apply(pattern, mappings: [mapping], values: ["level": 50])
        XCTAssertEqual(result.strength, 0.5)
        XCTAssertEqual(mapping.output(for: 150), 1)
    }

    func testStarterPatternIDsSupportSavedSourceMappings() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let patternStore = PatternStore(fileURL: folder.appendingPathComponent("patterns.json"))
        let sourceStore = SourceSettingsStore(fileURL: folder.appendingPathComponent("sources.json"))
        let patterns = try patternStore.load()
        let configurations = SourceCatalogue.initialConfigurations(patterns: patterns)
        try sourceStore.save(configurations)
        try patternStore.save(patterns)

        let restoredPatterns = try patternStore.load()
        let restoredSources = try sourceStore.load(defaults: SourceCatalogue.initialConfigurations(patterns: restoredPatterns))
        let ids = Set(restoredPatterns.map(\.id))
        XCTAssertTrue(restoredSources.flatMap(\.layers).allSatisfy { ids.contains($0.patternID) })
        XCTAssertTrue(restoredSources.flatMap { $0.cuePatternIDs.values }.allSatisfy(ids.contains))
    }
}
