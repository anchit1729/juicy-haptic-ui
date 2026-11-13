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
            Text("Adds a tap after each short drag distance. The app limits added taps to ten per second.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Splash clicks", isOn: Binding(
                get: { model.splashClicksEnabled },
                set: { model.setSplashClicksEnabled($0) }
            ))
            Text("A single click gets two trailing ripples. A double click gets three wider ripples. Dragging never starts a click splash.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Cursor accents", isOn: Binding(
                get: { model.cursorEffectsEnabled },
                set: { model.setCursorEffectsEnabled($0) }
            ))
            Text("Sand grains follow scroll taps. Drag ticks flash as small marks. Click taps spread coloured rings from the click point.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Visuals appear only with enabled interaction effects. They leave the system cursor and pointer input alone.")
                .font(.caption).foregroundStyle(.secondary)
            Text("The app reads only scroll, drag, and click events. It does not read keys or screen content.")
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
