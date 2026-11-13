import Foundation

struct SourceDescriptor: Identifiable, Sendable {
    let id: String
    let name: String
    let valueNames: [String]
}

struct SourceSnapshot: Sendable {
    let sourceID: String
    let updatedAt: Date
    let values: [String: Double]

    func isFresh(at date: Date = Date(), for duration: TimeInterval) -> Bool {
        date.timeIntervalSince(updatedAt) >= 0 && date.timeIntervalSince(updatedAt) < duration
    }
}

struct SourceEvent: Identifiable, Sendable {
    let id: String
    let sourceID: String
    let kind: String
    let occurredAt: Date
}

enum PatternControl: String, Codable, CaseIterable, Identifiable, Sendable {
    case strength = "Strength"
    case rhythm = "Rhythm"
    case band1 = "Band 1 gain"
    case band2 = "Band 2 gain"
    case band3 = "Band 3 gain"
    case band4 = "Band 4 gain"
    var id: String { rawValue }
}

struct ValueMapping: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var valueName: String
    var control: PatternControl
    var inputMin: Double
    var inputMax: Double
    var outputMin: Double
    var outputMax: Double

    func output(for input: Double) -> Double {
        guard inputMax > inputMin else { return outputMin }
        let fraction = min(1, max(0, (input - inputMin) / (inputMax - inputMin)))
        return outputMin + fraction * (outputMax - outputMin)
    }
}

struct AmbientLayer: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var patternID: UUID
    var enabled = true
    var strength = 0.3
    var mappings: [ValueMapping] = []
}

struct SourceConfiguration: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var enabled = true
    var layers: [AmbientLayer] = []
    var cuePatternIDs: [String: UUID] = [:]
}

enum SourceCatalogue {
    static let descriptors = [
        SourceDescriptor(id: "weather", name: "Weather", valueNames: ["rain", "wind", "gust"]),
        SourceDescriptor(id: "outlook", name: "Outlook", valueNames: ["unreadCount", "messagesPerHour"]),
        SourceDescriptor(id: "slack", name: "Slack", valueNames: ["messagesPerHour"]),
        SourceDescriptor(id: "sample", name: "Sample source", valueNames: ["level"])
    ]

    static func initialConfigurations(patterns: [HapticPattern]) -> [SourceConfiguration] {
        func id(_ name: String) -> UUID { patterns.first(where: { $0.name == name })?.id ?? patterns[0].id }
        let rain = AmbientLayer(patternID: id("Light rain"), mappings: [
            ValueMapping(valueName: "rain", control: .strength, inputMin: 0, inputMax: 10, outputMin: 0, outputMax: 0.6),
            ValueMapping(valueName: "rain", control: .rhythm, inputMin: 0, inputMax: 10, outputMin: 1, outputMax: 10)
        ])
        let wind = AmbientLayer(patternID: id("Wind"), mappings: [
            ValueMapping(valueName: "wind", control: .strength, inputMin: 0, inputMax: 20, outputMin: 0, outputMax: 0.5)
        ])
        return [
            SourceConfiguration(id: "weather", layers: [rain, wind]),
            SourceConfiguration(id: "outlook", layers: [AmbientLayer(patternID: id("Wind"), enabled: false)], cuePatternIDs: ["newEmail": id("Outlook email")]),
            SourceConfiguration(id: "slack", layers: [AmbientLayer(patternID: id("Wind"), enabled: false)], cuePatternIDs: ["directMessage": id("Slack message")]),
            SourceConfiguration(id: "sample", layers: [AmbientLayer(patternID: id("Wind"), enabled: false)])
        ]
    }
}

enum PatternMapper {
    static func apply(_ pattern: HapticPattern, mappings: [ValueMapping], values: [String: Double]) -> HapticPattern {
        var result = pattern
        for mapping in mappings {
            guard let input = values[mapping.valueName] else { continue }
            let output = mapping.output(for: input)
            switch mapping.control {
            case .strength: result.strength = output
            case .rhythm: result.rhythmHz = output
            case .band1: if result.bands.count > 0 { result.bands[0].gain = output }
            case .band2: if result.bands.count > 1 { result.bands[1].gain = output }
            case .band3: if result.bands.count > 2 { result.bands[2].gain = output }
            case .band4: if result.bands.count > 3 { result.bands[3].gain = output }
            }
        }
        return result.limited()
    }
}
