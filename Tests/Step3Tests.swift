import XCTest
@testable import AmbientHaptics

final class Step3Tests: XCTestCase {
    func testWeatherConversionAndSceneMappings() throws {
        let data = Data(#"{"current":{"rain":0.5,"wind_speed_10m":12,"wind_gusts_10m":21}}"#.utf8)
        let time = Date(timeIntervalSince1970: 1_000)
        let snapshot = try OpenMeteoWeatherSource.decode(data, fetchedAt: time)
        XCTAssertEqual(snapshot.values["rain"], 2)
        XCTAssertEqual(snapshot.values["wind"], 12)
        XCTAssertEqual(snapshot.values["gust"], 21)
        XCTAssertTrue(snapshot.isFresh(at: time.addingTimeInterval(60), for: 1800))
        XCTAssertFalse(snapshot.isFresh(at: time.addingTimeInterval(1800), for: 1800))

        let config = SourceCatalogue.initialConfigurations(patterns: StarterPatterns.all)[0]
        let rain = PatternMapper.apply(StarterPatterns.all[0], mappings: config.layers[0].mappings, values: snapshot.values)
        XCTAssertEqual(rain.strength, 0.12, accuracy: 0.0001)
        XCTAssertEqual(rain.rhythmHz, 2.8, accuracy: 0.0001)
    }
}
