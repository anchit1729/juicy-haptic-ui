import Foundation

/// Produces bounded, mono samples. The audio callback owns this instance while it renders.
final class PatternSynthesizer {
    private let sampleRate: Double
    private let pattern: HapticPattern
    private var phases: [Double]
    private var lowPass: [Double]
    private var highPass: [Double]
    private var previousNoise: [Double]
    private let highPassAlpha: [Double]
    private let lowPassAlpha: [Double]
    private var randomState: UInt64 = 0xD1B5_4A32_D192_ED03
    private var framesUntilPulse = 0
    private var pulseFramesLeft = 0
    private var pulseFramesTotal = 1
    private var pulsesPlayed = 0
    private var frame = 0

    init(pattern: HapticPattern, sampleRate: Double) {
        self.pattern = pattern.limited()
        self.sampleRate = sampleRate
        let count = self.pattern.bands.count
        phases = Array(repeating: 0, count: count)
        lowPass = Array(repeating: 0, count: count)
        highPass = Array(repeating: 0, count: count)
        previousNoise = Array(repeating: 0, count: count)
        let dt = 1 / sampleRate
        highPassAlpha = self.pattern.bands.map { band in
            let rc = 1 / (2 * Double.pi * band.lowHz)
            return rc / (rc + dt)
        }
        lowPassAlpha = self.pattern.bands.map { band in
            let rc = 1 / (2 * Double.pi * band.highHz)
            return dt / (rc + dt)
        }
    }

    var isFinished: Bool {
        guard let count = pattern.pulseCount else { return false }
        return pulsesPlayed >= count && pulseFramesLeft == 0
    }

    func nextSample() -> Float {
        let envelope = nextEnvelope()
        guard envelope > 0 else { frame += 1; return 0 }
        var mixed = 0.0
        for index in pattern.bands.indices {
            let band = pattern.bands[index]
            guard !band.muted else { continue }
            let value: Double
            switch band.signal {
            case .tone:
                let sweep = 0.5 + 0.5 * sin(Double(frame) / sampleRate * 2 * .pi * 0.35)
                let frequency = band.lowHz + (band.highHz - band.lowHz) * sweep
                phases[index] += 2 * .pi * frequency / sampleRate
                if phases[index] > 2 * .pi { phases[index] -= 2 * .pi }
                value = sin(phases[index])
            case .noise:
                let noise = randomUnit() * 2 - 1
                highPass[index] = highPassAlpha[index] * (highPass[index] + noise - previousNoise[index])
                previousNoise[index] = noise
                lowPass[index] += lowPassAlpha[index] * (highPass[index] - lowPass[index])
                value = lowPass[index] * 4
            }
            mixed += value * band.gain
        }
        frame += 1
        return Float(max(-1, min(1, mixed * envelope * pattern.strength)))
    }

    private func nextEnvelope() -> Double {
        if pattern.rhythmHz == 0 { return 1 }
        if pulseFramesLeft == 0 {
            if framesUntilPulse > 0 { framesUntilPulse -= 1; return 0 }
            if let count = pattern.pulseCount, pulsesPlayed >= count { return 0 }
            pulsesPlayed += 1
            pulseFramesTotal = max(1, Int(pattern.pulseLength * sampleRate))
            pulseFramesLeft = pulseFramesTotal
            let jitter = 1 + (randomUnit() - 0.5) * pattern.variation
            framesUntilPulse = max(0, Int(sampleRate / pattern.rhythmHz * jitter) - pulseFramesTotal)
        }
        let progress = 1 - Double(pulseFramesLeft) / Double(pulseFramesTotal)
        pulseFramesLeft -= 1
        return sin(.pi * progress) * sin(.pi * progress)
    }

    private func randomUnit() -> Double {
        randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
        return Double(randomState >> 11) / Double(1 << 53)
    }
}
