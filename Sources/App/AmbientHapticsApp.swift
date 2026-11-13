import SwiftUI
import CoreAudio

@main
struct AmbientHapticsApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Ambient Haptics", systemImage: "waveform.path") {
            MenuContentView(model: model)
        }

        Window("Ambient Haptics", id: "editor") {
            PatternEditorView(model: model)
        }
        .defaultSize(width: 800, height: 720)
    }
}

private struct MenuContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppModel

    var body: some View {
        Button("Open Editor") { openWindow(id: "editor"); NSApp.activate() }
        Button("Test Pulse") { model.playTestPulse() }
        Button(model.isPaused ? "Resume Haptics" : "Pause All") { model.togglePause() }
        if model.outputMode == .trackpad {
            Toggle("Sandy scrolling", isOn: Binding(
                get: { model.sandyScrollingEnabled },
                set: { model.setSandyScrollingEnabled($0) }
            ))
            Toggle("Drag ticks", isOn: Binding(
                get: { model.dragTicksEnabled },
                set: { model.setDragTicksEnabled($0) }
            ))
            Toggle("Splash clicks", isOn: Binding(
                get: { model.splashClicksEnabled },
                set: { model.setSplashClicksEnabled($0) }
            ))
        }
        Button("Stop All") { model.stop() }
        Divider()
        Text(model.status)
        if model.outputMode == .audio {
            Text(model.weatherStatus)
            Text(model.outlookStatus)
            Text(model.slackStatus)
        }
        Button("Quit") { NSApp.terminate(nil) }
    }
}
