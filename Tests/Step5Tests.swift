import XCTest
@testable import AmbientHaptics

final class Step5Tests: XCTestCase {
    func testSourceAmbientSettingsSurviveReload() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SourceSettingsStore(fileURL: folder.appendingPathComponent("sources.json"))
        var settings = SourceCatalogue.initialConfigurations(patterns: StarterPatterns.all)
        let weatherIndex = try XCTUnwrap(settings.firstIndex(where: { $0.id == "weather" }))
        settings[weatherIndex].layers[0].enabled = false
        settings[weatherIndex].layers[0].strength = 0.17
        try store.save(settings)

        let loaded = try store.load(defaults: SourceCatalogue.initialConfigurations(patterns: StarterPatterns.all))
        let weather = try XCTUnwrap(loaded.first(where: { $0.id == "weather" }))
        XCTAssertFalse(weather.layers[0].enabled)
        XCTAssertEqual(weather.layers[0].strength, 0.17)
    }
}
