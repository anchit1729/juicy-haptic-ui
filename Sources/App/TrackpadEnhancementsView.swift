import SwiftUI

struct TrackpadEnhancementsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Trackpad enhancements").font(.title2.bold())
            Toggle("Sandy scrolling", isOn: Binding(
                get: { model.sandyScrollingEnabled },
                set: { model.setSandyScrollingEnabled($0) }
            ))
            Text("Adds spaced taps while you scroll smoothly. Inertial scrolling stays quiet.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Grain spacing")
                Slider(value: Binding(
                    get: { model.grainSpacing },
                    set: { model.setGrainSpacing($0) }
                ), in: 8...40)
                Text("\(Int(model.grainSpacing)) pt").monospacedDigit().frame(width: 50)
            }
            .disabled(!model.sandyScrollingEnabled)
            Toggle("Drag ticks", isOn: Binding(
                get: { model.dragTicksEnabled },
                set: { model.setDragTicksEnabled($0) }
            ))
            Text("Adds a tap after each short drag distance. The app limits all texture taps to ten per second.")
                .font(.caption).foregroundStyle(.secondary)
            Text("The app reads only scroll and drag movement. It does not read keys or screen content.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Tap requests: \(model.trackpadTickRequests)")
                .font(.caption).monospacedDigit()

            Divider()
            Text("Manual pattern preview").font(.headline)
            HStack {
                Picker("Pattern", selection: Binding(
                    get: { model.selectedPatternID },
                    set: { model.choosePattern($0) }
                )) {
                    ForEach(model.patterns) { pattern in Text(pattern.name).tag(pattern.id) }
                }
                Button("Play taps") { model.playPreview() }
            }
            Text("Trackpad previews use tap count and timing. Frequency and strength controls apply to external audio.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
