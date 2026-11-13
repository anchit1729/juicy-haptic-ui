import SwiftUI

struct TrackpadMessageCuesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App message cues").font(.headline)
            Toggle("Enable app cues", isOn: Binding(
                get: { model.appCuesEnabled },
                set: { model.setAppCuesEnabled($0) }
            ))
            Text("Outlook mail and Slack direct messages use their own tap rhythms. Choose a pattern for each app.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.sourceConfigurations.filter { !$0.cuePatternIDs.isEmpty }) { source in
                sourceRow(source)
            }
            Text("These cues use the app connections below. They do not read macOS Notification Centre or message text.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            ConnectionSettingsView(model: model)
        }
    }

    private func sourceRow(_ source: SourceConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let name = SourceCatalogue.descriptors.first(where: { $0.id == source.id })?.name ?? source.id
            Toggle(name, isOn: Binding(
                get: { source.enabled },
                set: { model.setMessageSourceEnabled(source.id, $0) }
            ))
            ForEach(source.cuePatternIDs.keys.sorted(), id: \.self) { kind in
                HStack {
                    Picker(kind, selection: Binding(
                        get: { source.cuePatternIDs[kind] ?? model.patterns[0].id },
                        set: { model.setMessageCuePattern(source.id, kind: kind, patternID: $0) }
                    )) {
                        ForEach(model.patterns) { pattern in
                            Text(pattern.name).tag(pattern.id)
                        }
                    }
                    .disabled(!source.enabled)
                    Button("Test") { model.testCue(sourceID: source.id, kind: kind) }
                        .disabled(model.isPaused)
                }
            }
        }
    }
}
