import Foundation

protocol WeatherProviding: Sendable {
    func current(latitude: Double, longitude: Double) async throws -> SourceSnapshot
}

struct OpenMeteoWeatherSource: WeatherProviding {
    func current(latitude: Double, longitude: Double) async throws -> SourceSnapshot {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw WeatherError.invalidCoordinates
        }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "rain,wind_speed_10m,wind_gusts_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "timezone", value: "UTC")
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw WeatherError.serverResponse
        }
        return try Self.decode(data, fetchedAt: Date())
    }

    static func decode(_ data: Data, fetchedAt: Date) throws -> SourceSnapshot {
        let response = try JSONDecoder().decode(WeatherResponse.self, from: data)
        return SourceSnapshot(
            sourceID: "weather",
            updatedAt: fetchedAt,
            values: [
                // Open-Meteo reports current rain over the preceding 15 minutes.
                "rain": response.current.rain * 4,
                "wind": response.current.windSpeed,
                "gust": response.current.windGust
            ]
        )
    }
}

private struct WeatherResponse: Decodable {
    struct Current: Decodable {
        let rain: Double
        let windSpeed: Double
        let windGust: Double

        enum CodingKeys: String, CodingKey {
            case rain
            case windSpeed = "wind_speed_10m"
            case windGust = "wind_gusts_10m"
        }
    }

    let current: Current
}

enum WeatherError: Error {
    case invalidCoordinates
    case serverResponse
}
