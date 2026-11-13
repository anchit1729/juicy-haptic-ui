import SwiftUI

struct ConnectionSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Message sources").font(.headline)
            outlookSettings
            Divider()
            slackSettings
        }
    }

    private var outlookSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outlook").font(.subheadline.bold())
            HStack {
                TextField("Microsoft app client ID", text: $model.microsoftClientID)
                    .frame(width: 300)
                Button("Connect") { model.connectOutlook() }
                Button("Disconnect") { model.disconnectOutlook() }
                Button("Test Cue") { model.testCue(sourceID: "outlook", kind: "newEmail") }
            }
            if !model.outlookUserCode.isEmpty {
                HStack {
                    Text("Sign-in code: \(model.outlookUserCode)").textSelection(.enabled)
                    if let url = URL(string: model.outlookVerificationURL) {
                        Link("Open Microsoft sign-in", destination: url)
                    }
                }
            }
            Text(model.outlookStatus).font(.caption).foregroundStyle(.secondary)
            Link("Set up a Microsoft public client app", destination: URL(string: "https://learn.microsoft.com/en-us/graph/tutorials/javascript")!)
                .font(.caption)
        }
    }

    private var slackSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Slack").font(.subheadline.bold())
            HStack {
                SecureField("Slack app token", text: $model.slackAppToken)
                    .frame(width: 300)
                Button("Connect") { model.connectSlack() }
                Button("Disconnect") { model.disconnectSlack() }
                Button("Test Cue") { model.testCue(sourceID: "slack", kind: "directMessage") }
            }
            HStack {
                TextField("Workspace IDs to allow, separated by commas", text: $model.slackAllowedTeams)
                Text("Leave empty for all connected workspaces.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.observedSlackTeams.isEmpty {
                Text("Seen workspace IDs: \(model.observedSlackTeams.sorted().joined(separator: ", "))")
                    .font(.caption)
            }
            Text(model.slackStatus).font(.caption).foregroundStyle(.secondary)
            Link("Set up Slack Socket Mode", destination: URL(string: "https://docs.slack.dev/apis/events-api/using-socket-mode/")!)
                .font(.caption)
        }
    }
}
