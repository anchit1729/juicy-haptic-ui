import Foundation

enum BandSignal: String, Codable, CaseIterable, Identifiable, Sendable {
    case tone = "Tone"
    case noise = "Noise"
    var id: String { rawValue }
}

struct FrequencyBand: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var lowHz: Double
    var highHz: Double
    var gain: Double
    var signal: BandSignal
    var muted = false

    func limited() -> Self {
        var copy = self
        copy.lowHz = min(299, max(20, lowHz))
        copy.highHz = min(300, max(copy.lowHz + 1, highHz))
        copy.gain = min(1, max(0, gain))
        return copy
    }
}

struct HapticPattern: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var bands: [FrequencyBand]
    var rhythmHz: Double
    var variation: Double
    var pulseLength: Double
    var strength: Double
    var pulseCount: Int? = nil

    func limited() -> Self {
        var copy = self
        copy.bands = Array(bands.prefix(4)).map { $0.limited() }
        copy.rhythmHz = min(12, max(0, rhythmHz))
        copy.variation = min(1, max(0, variation))
        copy.pulseLength = min(1, max(0.01, pulseLength))
        copy.strength = min(1, max(0, strength))
        if let pulseCount { copy.pulseCount = min(12, max(1, pulseCount)) }
        return copy
    }
}

enum StarterPatterns {
    static let all: [HapticPattern] = [
        HapticPattern(id: UUID(uuidString: "B910F274-160A-473F-A0A6-87151D4C2001")!, name: "Light rain", bands: [FrequencyBand(lowHz: 80, highHz: 170, gain: 0.6, signal: .noise)], rhythmHz: 3, variation: 0.8, pulseLength: 0.025, strength: 0.3),
        HapticPattern(id: UUID(uuidString: "B910F274-160A-473F-A0A6-87151D4C2002")!, name: "Heavy rain", bands: [FrequencyBand(lowHz: 55, highHz: 145, gain: 0.65, signal: .noise), FrequencyBand(lowHz: 140, highHz: 240, gain: 0.3, signal: .noise)], rhythmHz: 9, variation: 0.55, pulseLength: 0.045, strength: 0.45),
        HapticPattern(id: UUID(uuidString: "B910F274-160A-473F-A0A6-87151D4C2003")!, name: "Wind", bands: [FrequencyBand(lowHz: 35, highHz: 95, gain: 0.8, signal: .noise)], rhythmHz: 0.4, variation: 0.2, pulseLength: 0.9, strength: 0.35),
        HapticPattern(id: UUID(uuidString: "B910F274-160A-473F-A0A6-87151D4C2004")!, name: "Outlook email", bands: [FrequencyBand(lowHz: 75, highHz: 105, gain: 0.7, signal: .tone)], rhythmHz: 4, variation: 0, pulseLength: 0.09, strength: 0.35, pulseCount: 2),
        HapticPattern(id: UUID(uuidString: "B910F274-160A-473F-A0A6-87151D4C2005")!, name: "Slack message", bands: [FrequencyBand(lowHz: 115, highHz: 155, gain: 0.7, signal: .tone)], rhythmHz: 6, variation: 0, pulseLength: 0.06, strength: 0.35, pulseCount: 3)
    ]
}
