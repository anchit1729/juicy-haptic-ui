import AudioToolbox
import CoreAudio
import Foundation

final class HapticAudioOutput {
    struct SceneInput {
        let pattern: HapticPattern
        let strength: Double
    }

    private struct ActiveLayer {
        let synthesizer: PatternSynthesizer
        let strength: Float
    }

    private var unit: AudioUnit?
    private var deviceID: AudioDeviceID = 0
    private let lock = NSLock()
    private var scene: [ActiveLayer] = []
    private var previousScene: [ActiveLayer] = []
    private var cue: PatternSynthesizer?
    private var fadeFramesRemaining = 0
    private var fadeFramesTotal = 1
    private var sampleRate = 48_000.0
    private var outputGain: Float = 0.25
    private let maximumDigitalAmplitude: Float = 0.03
    private var lastOutputLevel: Float = 0
    private var isRunning = false

    deinit { close() }

    func playTestPulse(on id: AudioDeviceID) throws {
        let pulse = HapticPattern(name: "Output test", bands: [FrequencyBand(lowHz: 115, highHz: 125, gain: 0.8, signal: .tone)], rhythmHz: 1, variation: 0, pulseLength: 0.07, strength: 0.3, pulseCount: 1)
        try play(pulse, on: id, strength: 0.25)
    }

    func play(_ pattern: HapticPattern, on id: AudioDeviceID, strength: Double) throws {
        try prepareDevice(id)
        lock.lock()
        previousScene = []
        scene = [ActiveLayer(synthesizer: PatternSynthesizer(pattern: pattern, sampleRate: sampleRate), strength: 1)]
        cue = nil
        lastOutputLevel = 0
        fadeFramesRemaining = 0
        outputGain = Float(min(1, max(0, strength)))
        lock.unlock()
        try startIfNeeded()
    }

    func playScene(_ inputs: [SceneInput], on id: AudioDeviceID, strength: Double) throws {
        try prepareDevice(id)
        let newScene = inputs.map {
            ActiveLayer(synthesizer: PatternSynthesizer(pattern: $0.pattern, sampleRate: sampleRate), strength: Float(min(1, max(0, $0.strength))))
        }
        lock.lock()
        previousScene = scene
        scene = newScene
        fadeFramesTotal = max(1, Int(sampleRate * 0.5))
        fadeFramesRemaining = fadeFramesTotal
        outputGain = Float(min(1, max(0, strength)))
        lock.unlock()
        try startIfNeeded()
    }

    func playCue(_ pattern: HapticPattern, on id: AudioDeviceID, strength: Double) throws {
        try prepareDevice(id)
        lock.lock()
        cue = PatternSynthesizer(pattern: pattern, sampleRate: sampleRate)
        outputGain = Float(min(1, max(0, strength)))
        lock.unlock()
        try startIfNeeded()
    }

    func stop() {
        lock.lock()
        scene = []
        previousScene = []
        cue = nil
        lastOutputLevel = 0
        lock.unlock()
        if let unit, isRunning { AudioOutputUnitStop(unit) }
        isRunning = false
    }

    func setOutputStrength(_ strength: Double) {
        lock.lock()
        outputGain = Float(min(1, max(0, strength)))
        lock.unlock()
    }

    var currentOutputLevel: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(min(1, lastOutputLevel / maximumDigitalAmplitude))
    }

    private func prepareDevice(_ id: AudioDeviceID) throws {
        if unit == nil || deviceID != id { try open(id) }
    }

    private func startIfNeeded() throws {
        guard !isRunning, let unit else { return }
        try AudioDeviceManager.check(AudioOutputUnitStart(unit))
        isRunning = true
    }

    private func open(_ id: AudioDeviceID) throws {
        close()
        sampleRate = try AudioDeviceManager.sampleRate(id)
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { throw AudioDeviceError.osStatus(kAudio_ParamError) }
        var newUnit: AudioUnit?
        try AudioDeviceManager.check(AudioComponentInstanceNew(component, &newUnit))
        guard let newUnit else { throw AudioDeviceError.osStatus(kAudio_ParamError) }
        do {
            var outputEnabled: UInt32 = 1
            var inputEnabled: UInt32 = 0
            try AudioDeviceManager.check(AudioUnitSetProperty(newUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &outputEnabled, UInt32(MemoryLayout<UInt32>.size)))
            try AudioDeviceManager.check(AudioUnitSetProperty(newUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &inputEnabled, UInt32(MemoryLayout<UInt32>.size)))
            var device = id
            try AudioDeviceManager.check(AudioUnitSetProperty(newUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size)))
            var format = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
            try AudioDeviceManager.check(AudioUnitSetProperty(newUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))
            var callback = AURenderCallbackStruct(inputProc: { refCon, _, _, _, frameCount, ioData in
                guard let ioData else { return noErr }
                return Unmanaged<HapticAudioOutput>.fromOpaque(refCon).takeUnretainedValue().render(Int(frameCount), ioData)
            }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
            try AudioDeviceManager.check(AudioUnitSetProperty(newUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
            try AudioDeviceManager.check(AudioUnitInitialize(newUnit))
            unit = newUnit
            deviceID = id
        } catch {
            AudioComponentInstanceDispose(newUnit)
            throw error
        }
    }

    private func close() {
        if let unit {
            if isRunning { AudioOutputUnitStop(unit) }
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        unit = nil
        deviceID = 0
        isRunning = false
    }

    private func render(_ frames: Int, _ audio: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audio)
        guard lock.try() else {
            for buffer in buffers { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
            return noErr
        }
        defer { lock.unlock() }
        var peak: Float = 0
        for frame in 0..<frames {
            var newValue: Float = 0
            for layer in scene { newValue += layer.synthesizer.nextSample() * layer.strength }
            var sceneValue = newValue
            if fadeFramesRemaining > 0 {
                var oldValue: Float = 0
                for layer in previousScene { oldValue += layer.synthesizer.nextSample() * layer.strength }
                let progress = 1 - Float(fadeFramesRemaining) / Float(fadeFramesTotal)
                sceneValue = oldValue * (1 - progress) + newValue * progress
                fadeFramesRemaining -= 1
            }
            let cueValue: Float
            if let cue, !cue.isFinished { cueValue = cue.nextSample() }
            else { cueValue = 0 }
            let mixed = sceneValue * (cueValue == 0 ? 1 : 0.35) + cueValue
            let value = max(-1, min(1, mixed)) * maximumDigitalAmplitude * outputGain
            peak = max(peak, abs(value))
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                let channels = Int(buffer.mNumberChannels)
                for channel in 0..<channels {
                    samples[frame * channels + channel] = channel == 0 ? value : 0
                }
            }
        }
        lastOutputLevel = peak
        return noErr
    }
}
