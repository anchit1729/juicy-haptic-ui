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
        Button("Stop Ambience") { model.stop() }
        Divider()
        Text(model.status)
        Text(model.weatherStatus)
        Text(model.outlookStatus)
        Text(model.slackStatus)
        Button("Quit") { NSApp.terminate(nil) }
    }
}
