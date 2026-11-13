import CoreAudio
import SwiftUI

struct PatternEditorView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Juicy Haptic UI").font(.largeTitle.bold())
                outputControls
                Divider()
                if model.outputMode == .trackpad {
                    TrackpadEnhancementsView(model: model)
                } else {
                    patternControls
                    FrequencyBandChart(pattern: $model.draftPattern)
                        .frame(height: 220)
                    bandControls
                    rhythmControls
                    Divider()
                    WeatherControlsView(model: model)
                    Divider()
                    SourceSettingsView(model: model)
                    Divider()
                    ConnectionSettingsView(model: model)
                }
                HStack {
                    Button("Stop") { model.stop() }
                    if model.outputMode == .audio {
                        Button("Play") { model.playPreview() }
                            .disabled(!model.outputReady)
                        Button("Save Pattern") { model.savePattern() }
                    }
                    Spacer()
                    Text(model.status).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 680, minHeight: 660)
    }

    private var outputControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Output", selection: Binding(
                get: { model.outputMode },
                set: { model.selectOutputMode($0) }
            )) {
                ForEach(HapticOutputMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            HStack {
                if model.outputMode == .audio {
                    Picker("Haptic audio output", selection: Binding(
                        get: { model.selectedDeviceID },
                        set: { model.selectDevice($0) }
                    )) {
                        Text("Choose a device").tag(AudioDeviceID(0))
                        ForEach(model.devices) { Text($0.name).tag($0.id) }
                    }
                    Button("Refresh") { model.refreshDevices() }
                }
                Button("Test") { model.playTestPulse() }
                    .disabled(!model.outputReady)
                Button(model.isPaused ? "Resume" : "Pause All") { model.togglePause() }
            }
        }
    }

    private var patternControls: some View {
        HStack {
            Picker("Pattern", selection: Binding(
                get: { model.selectedPatternID },
                set: { model.choosePattern($0) }
            )) {
                ForEach(model.patterns) { Text($0.name).tag($0.id) }
            }
            TextField("Name", text: $model.draftPattern.name)
                .frame(width: 180)
            Button("Save Copy") { model.saveCopy() }
        }
    }

    private var bandControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Frequency bands").font(.headline)
                Spacer()
                Button("Add Band") { model.addBand() }
                    .disabled(model.draftPattern.bands.count >= 4)
            }
            ForEach(model.draftPattern.bands.indices, id: \.self) { index in
                HStack {
                    Text("Band \(index + 1)").frame(width: 60, alignment: .leading)
                    Picker("Signal", selection: $model.draftPattern.bands[index].signal) {
                        ForEach(BandSignal.allCases) { signal in Text(signal.rawValue).tag(signal) }
                    }
                    .labelsHidden()
                    Text("\(Int(model.draftPattern.bands[index].lowHz))–\(Int(model.draftPattern.bands[index].highHz)) Hz")
                        .monospacedDigit().frame(width: 110)
                    Slider(value: $model.draftPattern.bands[index].gain, in: 0...1)
                    Toggle("Mute", isOn: $model.draftPattern.bands[index].muted)
                    Button("Remove") { model.removeBand(index) }
                }
            }
        }
    }

    private var rhythmControls: some View {
        VStack {
            HStack {
                Text("Pulse rate")
                Slider(value: $model.draftPattern.rhythmHz, in: 0...12)
                Text(model.draftPattern.rhythmHz.formatted(.number.precision(.fractionLength(1))) + " Hz")
                    .frame(width: 60)
                Text("Variation")
                Slider(value: $model.draftPattern.variation, in: 0...1)
            }
            HStack {
                Text("Pulse length")
                Slider(value: $model.draftPattern.pulseLength, in: 0.01...1)
                Text(model.draftPattern.pulseLength.formatted(.number.precision(.fractionLength(2))) + " s")
                    .frame(width: 60)
                Text("Pattern strength")
                Slider(value: $model.draftPattern.strength, in: 0...1)
            }
            if model.outputMode == .audio {
                HStack {
                    Text("Output strength")
                    Slider(value: $model.outputStrength, in: 0...1)
                        .onChange(of: model.outputStrength) { _, _ in model.updateOutputStrength() }
                    Text("Start with the N22 volume low.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Output level")
                    ProgressView(value: model.outputLevel)
                        .frame(maxWidth: .infinity)
                    Text("Relative to the software limit")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct FrequencyBandChart: View {
    @Binding var pattern: HapticPattern
    private let minHz = 20.0
    private let maxHz = 300.0

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 32)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary.opacity(0.4))
                ForEach([20.0, 50, 100, 200, 300], id: \.self) { frequency in
                    let x = 16 + position(frequency, width: width)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 28))
                        path.addLine(to: CGPoint(x: x, y: geometry.size.height - 12))
                    }
                    .stroke(.secondary.opacity(0.2), lineWidth: 1)
                    Text("\(Int(frequency))")
                        .font(.caption2)
                        .position(x: x, y: 15)
                }
                ForEach(pattern.bands.indices, id: \.self) { index in
                    bandRow(index: index, width: width)
                }
            }
            .coordinateSpace(name: "frequencyChart")
        }
    }

    private func bandRow(index: Int, width: CGFloat) -> some View {
        let band = pattern.bands[index]
        let left = 16 + position(band.lowHz, width: width)
        let right = 16 + position(band.highHz, width: width)
        let y = CGFloat(58 + index * 38)
        return ZStack {
            Capsule()
                .fill(Color.accentColor.opacity(band.muted ? 0.2 : 0.5))
                .frame(width: max(8, right - left), height: 24)
                .position(x: (left + right) / 2, y: y)
            handle(x: left, y: y)
                .gesture(DragGesture(coordinateSpace: .named("frequencyChart")).onChanged { value in
                    pattern.bands[index].lowHz = min(pattern.bands[index].highHz - 1, frequency(value.location.x - 16, width: width))
                })
            handle(x: right, y: y)
                .gesture(DragGesture(coordinateSpace: .named("frequencyChart")).onChanged { value in
                    pattern.bands[index].highHz = max(pattern.bands[index].lowHz + 1, frequency(value.location.x - 16, width: width))
                })
        }
    }

    private func handle(x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(.white).stroke(Color.accentColor, lineWidth: 2)
            .frame(width: 18, height: 18).position(x: x, y: y)
    }

    private func position(_ frequency: Double, width: CGFloat) -> CGFloat {
        CGFloat(log(max(minHz, min(maxHz, frequency)) / minHz) / log(maxHz / minHz)) * width
    }

    private func frequency(_ x: CGFloat, width: CGFloat) -> Double {
        min(maxHz, max(minHz, minHz * pow(maxHz / minHz, Double(max(0, min(width, x)) / width))))
    }
}
