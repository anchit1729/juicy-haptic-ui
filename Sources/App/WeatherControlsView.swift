import SwiftUI

struct WeatherControlsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weather scene").font(.headline)
            Toggle("Use Open-Meteo weather", isOn: Binding(
                get: { model.weatherDataEnabled },
                set: { model.setWeatherDataEnabled($0) }
            ))
            .disabled(!model.hasSavedWeatherLocation)
            if !model.hasSavedWeatherLocation {
                Text("Enter and save your location before enabling weather updates.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("When enabled, this sends the saved coordinates to Open-Meteo for weather updates.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Latitude")
                TextField("Latitude", value: $model.latitude, format: .number)
                    .frame(width: 90)
                Text("Longitude")
                TextField("Longitude", value: $model.longitude, format: .number)
                    .frame(width: 90)
                Button("Save Location") { model.saveWeatherLocation() }
                Button("Refresh") { Task { await model.refreshWeather() } }
                    .disabled(!model.weatherDataEnabled)
            }
            HStack {
                Button(model.ambientPlaybackEnabled ? "Stop Ambience" : "Start Ambience") {
                    model.toggleAmbientPlayback()
                }
                .disabled(model.outputMode != .audio || model.selectedDeviceID == 0)
                Text(model.weatherStatus).foregroundStyle(.secondary)
            }
            if let snapshot = model.weatherSnapshot {
                let rain = snapshot.values["rain"] ?? 0
                let wind = snapshot.values["wind"] ?? 0
                Text("Rain: \(rain.formatted(.number.precision(.fractionLength(1)))) mm/h · Wind: \(wind.formatted(.number.precision(.fractionLength(0)))) km/h · Fetched \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
            }
            Link("Weather data: Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
                .font(.caption)
        }
        .textFieldStyle(.roundedBorder)
    }
}
