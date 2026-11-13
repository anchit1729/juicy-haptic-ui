import CoreAudio
import Foundation
import Combine

enum HapticOutputMode: String, CaseIterable, Identifiable {
    case trackpad = "Trackpad preview"
    case audio = "External audio"

    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var devices: [OutputDevice] = []
    @Published var selectedDeviceID: AudioDeviceID = 0
    @Published var status = "Trackpad previews use brief taps. Resume haptics to test one."
    @Published var outputMode: HapticOutputMode = .trackpad
    @Published var isPaused = true
    @Published var patterns = StarterPatterns.all
    @Published var selectedPatternID = StarterPatterns.all[0].id
    @Published var draftPattern = StarterPatterns.all[0]
    @Published var outputStrength = 0.25
    @Published var outputLevel = 0.0
    @Published var sourceConfigurations: [SourceConfiguration] = []
    @Published var selectedSourceID = "weather"
    @Published var sampleLevel = 0.5
    @Published var latitude = 43.6532
    @Published var longitude = -79.3832
    @Published var weatherSnapshot: SourceSnapshot?
    @Published var weatherStatus = "Weather has not loaded."
    @Published var weatherDataEnabled = false
    @Published private(set) var hasSavedWeatherLocation = false
    @Published var ambientPlaybackEnabled = false
    @Published var sourceSnapshots: [String: SourceSnapshot] = [:]
    @Published var microsoftClientID = ""
    @Published var outlookStatus = "Outlook is not connected."
    @Published var outlookUserCode = ""
    @Published var outlookVerificationURL = ""
    @Published var slackAppToken = ""
    @Published var slackAllowedTeams = ""
    @Published var slackStatus = "Slack is not connected."
    @Published var observedSlackTeams: Set<String> = []

    private let audio = HapticAudioOutput()
    private let trackpad = TrackpadHapticOutput()
    private let store = PatternStore()
    private let sourceStore = SourceSettingsStore()
    private let weatherSource: any WeatherProviding = OpenMeteoWeatherSource()
    private let outlookSource = OutlookGraphSource()
    private let slackSource = SlackSocketSource()
    private var eventGate = EventGate()
    private var outlookTracker = OutlookInboxTracker()
    private var outlookEventTimes: [Date] = []
    private var slackEventTimes: [Date] = []
    private var outlookAccessToken = ""
    private var outlookAccessExpiresAt = Date.distantPast
    private var weatherTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var outlookTask: Task<Void, Never>?
    private var outlookAuthTask: Task<Void, Never>?
    private var slackTask: Task<Void, Never>?
    private var slackSocket: URLSessionWebSocketTask?
    private var deviceWatcher: AudioDeviceWatcher?
    private var preferredDeviceUID = ""
    private var savedWeatherLocation: (latitude: Double, longitude: Double)?

    init() {
        outputMode = HapticOutputMode(rawValue: UserDefaults.standard.string(forKey: "output.mode") ?? "") ?? .trackpad
        preferredDeviceUID = UserDefaults.standard.string(forKey: "audio.deviceUID") ?? ""
        outputStrength = UserDefaults.standard.object(forKey: "audio.strength") == nil
            ? 0.25 : UserDefaults.standard.double(forKey: "audio.strength")
        refreshDevices()
        do {
            deviceWatcher = try AudioDeviceWatcher { [weak self] in
                Task { @MainActor in self?.refreshDevices() }
            }
        } catch {
            status = "Device changes need manual refresh: \(error.localizedDescription)"
        }
        do {
            patterns = try store.load()
            if let first = patterns.first {
                selectedPatternID = first.id
                draftPattern = first
            }
        } catch {
            status = "Cannot load patterns: \(error.localizedDescription)"
        }
        do {
            sourceConfigurations = try sourceStore.load(defaults: SourceCatalogue.initialConfigurations(patterns: patterns))
        } catch {
            sourceConfigurations = SourceCatalogue.initialConfigurations(patterns: patterns)
            status = "Cannot load source settings: \(error.localizedDescription)"
        }
        if UserDefaults.standard.object(forKey: "weather.latitude") != nil,
           UserDefaults.standard.object(forKey: "weather.longitude") != nil {
            latitude = UserDefaults.standard.double(forKey: "weather.latitude")
            longitude = UserDefaults.standard.double(forKey: "weather.longitude")
            savedWeatherLocation = (latitude, longitude)
            hasSavedWeatherLocation = true
        }
        weatherDataEnabled = hasSavedWeatherLocation && UserDefaults.standard.bool(forKey: "weather.openMeteoEnabled")
        microsoftClientID = UserDefaults.standard.string(forKey: "outlook.clientID") ?? ""
        slackAppToken = KeychainSecrets.load("slack.appToken") ?? ""
        slackAllowedTeams = UserDefaults.standard.string(forKey: "slack.allowedTeams") ?? ""
        if weatherDataEnabled { startWeatherUpdates() }
        if !microsoftClientID.isEmpty && KeychainSecrets.load("outlook.refreshToken") != nil {
            startOutlookPolling()
        }
        if !slackAppToken.isEmpty {
            connectSlack()
        }
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.outputLevel = self?.audio.currentOutputLevel ?? 0
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        expiryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.expireStaleSources()
            }
        }
    }

    func refreshDevices() {
        do {
            devices = try AudioDeviceManager.outputDevices()
            if selectedDeviceID != 0 && !devices.contains(where: { $0.id == selectedDeviceID }) {
                selectedDeviceID = 0
                audio.stop()
                if outputMode == .audio {
                    isPaused = true
                    status = "The chosen device disconnected. Playback stopped."
                }
            } else if selectedDeviceID == 0,
                      let preferred = devices.first(where: { $0.uid == preferredDeviceUID }) {
                selectedDeviceID = preferred.id
                if outputMode == .audio { status = "Output reconnected. Resume haptics when ready." }
            }
        } catch {
            status = "Cannot list audio devices: \(error.localizedDescription)"
        }
    }

    func selectDevice(_ id: AudioDeviceID) {
        audio.stop()
        selectedDeviceID = id
        preferredDeviceUID = devices.first(where: { $0.id == id })?.uid ?? ""
        UserDefaults.standard.set(preferredDeviceUID, forKey: "audio.deviceUID")
        if outputMode == .audio {
            status = id == 0 ? "Select the output connected to your N22." : "Ready. Set the N22 volume low before testing."
        }
        if ambientPlaybackEnabled && !isPaused { renderAllScenes() }
    }

    var outputReady: Bool { outputMode == .trackpad || selectedDeviceID != 0 }

    func selectOutputMode(_ mode: HapticOutputMode) {
        audio.stop()
        trackpad.stop()
        ambientPlaybackEnabled = false
        outputMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "output.mode")
        status = mode == .trackpad
            ? "Trackpad previews use brief taps. Automatic scenes need external audio."
            : "Select the audio output connected to the N22."
    }

    func playTestPulse() {
        guard !isPaused else { status = "Resume haptics before testing."; return }
        if outputMode == .trackpad {
            trackpad.playTestPulse()
            status = "Trackpad test tap requested."
            return
        }
        guard selectedDeviceID != 0 else { status = "Select a haptic output first."; return }
        do {
            try audio.playTestPulse(on: selectedDeviceID)
            status = "Test pulse sent to \(devices.first(where: { $0.id == selectedDeviceID })?.name ?? "device")."
        } catch {
            status = "Playback failed: \(error.localizedDescription)"
        }
    }

    func stop() {
        audio.stop()
        trackpad.stop()
        ambientPlaybackEnabled = false
        isPaused = true
        status = "Stopped."
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            audio.stop()
            trackpad.stop()
            status = "All haptics paused."
        } else {
            status = "Haptics ready."
            if ambientPlaybackEnabled { renderAllScenes() }
        }
    }

    func updateOutputStrength() {
        outputStrength = min(1, max(0, outputStrength))
        UserDefaults.standard.set(outputStrength, forKey: "audio.strength")
        audio.setOutputStrength(outputStrength)
    }

    func choosePattern(_ id: UUID) {
        guard let pattern = patterns.first(where: { $0.id == id }) else { return }
        audio.stop()
        trackpad.stop()
        draftPattern = pattern
        selectedPatternID = id
    }

    func addBand() {
        guard draftPattern.bands.count < 4 else { return }
        draftPattern.bands.append(FrequencyBand(lowHz: 65, highHz: 140, gain: 0.3, signal: .tone))
    }

    func removeBand(_ index: Int) {
        guard draftPattern.bands.indices.contains(index) else { return }
        draftPattern.bands.remove(at: index)
    }

    func playPreview() {
        guard !isPaused else { status = "Resume haptics before playing."; return }
        if outputMode == .trackpad {
            trackpad.playPreview(draftPattern.limited())
            status = "Trackpad preview uses pulse timing only."
            return
        }
        guard selectedDeviceID != 0 else { status = "Select a haptic output first."; return }
        do {
            try audio.play(draftPattern.limited(), on: selectedDeviceID, strength: outputStrength)
            status = "Playing \(draftPattern.name)."
        } catch {
            status = "Playback failed: \(error.localizedDescription)"
        }
    }

    func savePattern() {
        let saved = draftPattern.limited()
        if let index = patterns.firstIndex(where: { $0.id == saved.id }) {
            patterns[index] = saved
        } else {
            patterns.append(saved)
        }
        persistPatterns()
    }

    func saveCopy() {
        var copy = draftPattern.limited()
        copy.id = UUID()
        copy.name += " Copy"
        patterns.append(copy)
        draftPattern = copy
        selectedPatternID = copy.id
        persistPatterns()
    }

    private func persistPatterns() {
        do {
            try store.save(patterns)
            status = "Pattern saved."
        } catch {
            status = "Cannot save pattern: \(error.localizedDescription)"
        }
    }

    func addLayer(sourceIndex: Int) {
        sourceConfigurations[sourceIndex].layers.append(
            AmbientLayer(patternID: selectedPatternID, enabled: false)
        )
    }

    func removeLayer(sourceIndex: Int, layerIndex: Int) {
        sourceConfigurations[sourceIndex].layers.remove(at: layerIndex)
    }

    func addMapping(sourceIndex: Int, layerIndex: Int) {
        let sourceID = sourceConfigurations[sourceIndex].id
        let firstValue = SourceCatalogue.descriptors.first(where: { $0.id == sourceID })?.valueNames.first ?? "level"
        sourceConfigurations[sourceIndex].layers[layerIndex].mappings.append(
            ValueMapping(valueName: firstValue, control: .strength, inputMin: 0, inputMax: 1, outputMin: 0, outputMax: 1)
        )
    }

    func removeMapping(sourceIndex: Int, layerIndex: Int, mappingIndex: Int) {
        sourceConfigurations[sourceIndex].layers[layerIndex].mappings.remove(at: mappingIndex)
    }

    func saveSourceSettings() {
        do {
            try sourceStore.save(sourceConfigurations)
            status = "Source settings saved."
            if ambientPlaybackEnabled { renderAllScenes() }
        } catch {
            status = "Cannot save source settings: \(error.localizedDescription)"
        }
    }

    func playSampleSource() {
        guard !isPaused else { status = "Resume haptics before playing."; return }
        guard let layer = sourceConfigurations.first(where: { $0.id == "sample" })?.layers.first,
              let pattern = patterns.first(where: { $0.id == layer.patternID }) else { return }
        let mapped = PatternMapper.apply(pattern, mappings: layer.mappings, values: ["level": sampleLevel])
        if outputMode == .trackpad {
            trackpad.playPreview(mapped)
            status = "Sample trackpad preview uses pulse timing only."
            return
        }
        guard selectedDeviceID != 0 else { status = "Select a haptic output first."; return }
        do {
            try audio.play(mapped, on: selectedDeviceID, strength: outputStrength * layer.strength)
            status = "Playing sample source."
        } catch {
            status = "Playback failed: \(error.localizedDescription)"
        }
    }

    func updateSampleLevel() {
        updateSource(SourceSnapshot(sourceID: "sample", updatedAt: Date(), values: ["level": sampleLevel]))
    }

    func saveWeatherLocation() {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            weatherStatus = "Enter valid coordinates."
            return
        }
        UserDefaults.standard.set(latitude, forKey: "weather.latitude")
        UserDefaults.standard.set(longitude, forKey: "weather.longitude")
        savedWeatherLocation = (latitude, longitude)
        hasSavedWeatherLocation = true
        weatherStatus = "Location saved."
        if weatherDataEnabled { Task { await refreshWeather() } }
    }

    func setWeatherDataEnabled(_ enabled: Bool) {
        guard !enabled || hasSavedWeatherLocation else {
            weatherStatus = "Save a location first."
            return
        }
        weatherDataEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "weather.openMeteoEnabled")
        weatherTask?.cancel()
        weatherTask = nil
        if enabled {
            weatherStatus = "Fetching weather from Open-Meteo."
            startWeatherUpdates()
        } else {
            weatherSnapshot = nil
            sourceSnapshots.removeValue(forKey: "weather")
            weatherStatus = "Weather access is off."
            if ambientPlaybackEnabled { renderAllScenes() }
        }
    }

    private func startWeatherUpdates() {
        weatherTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshWeather()
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    func connectOutlook() {
        microsoftClientID = microsoftClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(microsoftClientID, forKey: "outlook.clientID")
        outlookAuthTask?.cancel()
        outlookAuthTask = Task {
            do {
                let code = try await outlookSource.beginSignIn(clientID: microsoftClientID)
                outlookUserCode = code.userCode
                outlookVerificationURL = code.verificationURI
                outlookStatus = "Enter the code at the Microsoft sign-in page."
                let token = try await outlookSource.finishSignIn(clientID: microsoftClientID, code: code)
                try saveOutlookToken(token)
                outlookUserCode = ""
                outlookStatus = "Outlook connected."
                startOutlookPolling()
            } catch is CancellationError {
                outlookStatus = "Outlook sign-in stopped."
            } catch {
                outlookStatus = "Outlook sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    func disconnectOutlook() {
        outlookAuthTask?.cancel()
        outlookTask?.cancel()
        outlookAccessToken = ""
        KeychainSecrets.delete("outlook.refreshToken")
        sourceSnapshots.removeValue(forKey: "outlook")
        outlookStatus = "Outlook disconnected."
        if ambientPlaybackEnabled { renderAllScenes() }
    }

    private func saveOutlookToken(_ token: MicrosoftToken) throws {
        outlookAccessToken = token.accessToken
        outlookAccessExpiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn - 60))
        if let refresh = token.refreshToken {
            try KeychainSecrets.save(refresh, for: "outlook.refreshToken")
        }
    }

    private func startOutlookPolling() {
        outlookTask?.cancel()
        outlookTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOutlook()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func pollOutlook() async {
        do {
            if outlookAccessToken.isEmpty || Date() >= outlookAccessExpiresAt {
                guard let refresh = KeychainSecrets.load("outlook.refreshToken") else {
                    outlookStatus = "Connect Outlook to start mail cues."
                    return
                }
                let token = try await outlookSource.refresh(clientID: microsoftClientID, refreshToken: refresh)
                try saveOutlookToken(token)
            }
            let inbox = try await outlookSource.fetchInbox(accessToken: outlookAccessToken)
            guard !Task.isCancelled else { return }
            let now = Date()
            let events = outlookTracker.newEvents(from: inbox, at: now)
            outlookEventTimes.append(contentsOf: events.map(\.occurredAt))
            outlookEventTimes.removeAll { now.timeIntervalSince($0) > 3600 }
            updateSource(SourceSnapshot(
                sourceID: "outlook",
                updatedAt: now,
                values: ["unreadCount": Double(inbox.unreadCount), "messagesPerHour": Double(outlookEventTimes.count)]
            ))
            for event in events { receive(event) }
            outlookStatus = "Outlook checked at \(now.formatted(date: .omitted, time: .shortened))."
        } catch {
            outlookStatus = "Outlook check failed: \(error.localizedDescription)"
        }
    }

    func connectSlack() {
        slackTask?.cancel()
        slackSocket?.cancel(with: .goingAway, reason: nil)
        slackAppToken = slackAppToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slackAppToken.isEmpty else {
            slackStatus = "Enter a Slack app token."
            return
        }
        slackAllowedTeams = slackAllowedTeams.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(slackAllowedTeams, forKey: "slack.allowedTeams")
        do {
            try KeychainSecrets.save(slackAppToken, for: "slack.appToken")
        } catch {
            slackStatus = "Cannot save Slack token: \(error.localizedDescription)"
            return
        }
        slackTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.receiveSlackMessages()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func disconnectSlack() {
        slackTask?.cancel()
        slackSocket?.cancel(with: .goingAway, reason: nil)
        slackSocket = nil
        slackAppToken = ""
        KeychainSecrets.delete("slack.appToken")
        sourceSnapshots.removeValue(forKey: "slack")
        slackStatus = "Slack disconnected."
        if ambientPlaybackEnabled { renderAllScenes() }
    }

    private func receiveSlackMessages() async {
        do {
            let url = try await slackSource.socketURL(appToken: slackAppToken)
            let socket = URLSession.shared.webSocketTask(with: url)
            slackSocket = socket
            socket.resume()
            slackStatus = "Slack connected. Waiting for messages."
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let bytes): data = bytes
                @unknown default: continue
                }
                guard let envelope = try? SlackSocketSource.decode(data) else { continue }
                if let acknowledgement = try SlackSocketSource.acknowledgement(for: envelope) {
                    try await socket.send(.string(acknowledgement))
                }
                if let team = envelope.payload?.teamID { observedSlackTeams.insert(team) }
                let allowed = Set(slackAllowedTeams.split(separator: ",").map {
                    String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                })
                guard let event = envelope.directMessage(allowedTeams: allowed) else { continue }
                guard !Task.isCancelled else { return }
                let now = Date()
                slackEventTimes.append(now)
                slackEventTimes.removeAll { now.timeIntervalSince($0) > 3600 }
                updateSource(SourceSnapshot(
                    sourceID: "slack",
                    updatedAt: now,
                    values: ["messagesPerHour": Double(slackEventTimes.count)]
                ))
                receive(event)
                slackStatus = "Slack message received at \(now.formatted(date: .omitted, time: .shortened))."
            }
        } catch {
            slackStatus = "Slack connection failed: \(error.localizedDescription)"
        }
    }

    func testCue(sourceID: String, kind: String) {
        if outputMode == .trackpad {
            guard !isPaused,
                  let source = sourceConfigurations.first(where: { $0.id == sourceID }),
                  let patternID = source.cuePatternIDs[kind],
                  let pattern = patterns.first(where: { $0.id == patternID }) else { return }
            trackpad.playPreview(pattern)
            status = "Trackpad cue preview uses pulse timing only."
            return
        }
        receive(SourceEvent(id: "test:\(UUID())", sourceID: sourceID, kind: kind, occurredAt: Date()))
    }

    private func receive(_ event: SourceEvent) {
        guard outputMode == .audio,
              !isPaused,
              selectedDeviceID != 0,
              let source = sourceConfigurations.first(where: { $0.id == event.sourceID }),
              source.enabled,
              let patternID = source.cuePatternIDs[event.kind],
              let pattern = patterns.first(where: { $0.id == patternID }),
              eventGate.shouldPlay(event) else { return }
        do {
            try audio.playCue(pattern, on: selectedDeviceID, strength: outputStrength)
            status = "\(event.sourceID.capitalized) cue played."
        } catch {
            status = "Cue failed: \(error.localizedDescription)"
        }
    }

    func refreshWeather() async {
        guard weatherDataEnabled, let location = savedWeatherLocation else { return }
        do {
            let snapshot = try await weatherSource.current(latitude: location.latitude, longitude: location.longitude)
            guard weatherDataEnabled, !Task.isCancelled else { return }
            weatherSnapshot = snapshot
            sourceSnapshots["weather"] = snapshot
            weatherStatus = "Weather updated."
            if ambientPlaybackEnabled { renderAllScenes() }
        } catch {
            guard weatherDataEnabled, !Task.isCancelled else { return }
            weatherStatus = "Weather unavailable: \(error.localizedDescription)"
            if let snapshot = weatherSnapshot, !snapshot.isFresh(for: 1800) {
                weatherSnapshot = nil
                sourceSnapshots.removeValue(forKey: "weather")
                if ambientPlaybackEnabled { renderAllScenes() }
            }
        }
    }

    func toggleAmbientPlayback() {
        guard outputMode == .audio else {
            status = "Automatic scenes need external audio."
            return
        }
        ambientPlaybackEnabled.toggle()
        if ambientPlaybackEnabled {
            isPaused = false
            sourceSnapshots["sample"] = SourceSnapshot(sourceID: "sample", updatedAt: Date(), values: ["level": sampleLevel])
            renderAllScenes()
        } else if selectedDeviceID != 0 {
            try? audio.playScene([], on: selectedDeviceID, strength: outputStrength)
            status = "Ambient scenes stopped."
        }
    }

    func updateSource(_ snapshot: SourceSnapshot) {
        sourceSnapshots[snapshot.sourceID] = snapshot
        if ambientPlaybackEnabled && !isPaused { renderAllScenes() }
    }

    private func expireStaleSources() {
        let staleIDs = sourceSnapshots.compactMap { id, snapshot in
            snapshot.isFresh(for: id == "weather" ? 1800 : 300) ? nil : id
        }
        guard !staleIDs.isEmpty else { return }
        for id in staleIDs { sourceSnapshots.removeValue(forKey: id) }
        if staleIDs.contains("weather") {
            weatherSnapshot = nil
            weatherStatus = "Weather data expired."
        }
        if ambientPlaybackEnabled { renderAllScenes() }
    }

    private func renderAllScenes() {
        guard outputMode == .audio, selectedDeviceID != 0, ambientPlaybackEnabled, !isPaused else { return }
        let inputs: [HapticAudioOutput.SceneInput] = sourceConfigurations.flatMap { config -> [HapticAudioOutput.SceneInput] in
            guard config.enabled,
                  let snapshot = sourceSnapshots[config.id],
                  snapshot.isFresh(for: config.id == "weather" ? 1800 : 300) else { return [] }
            return config.layers.compactMap { layer in
                guard layer.enabled,
                      let pattern = patterns.first(where: { $0.id == layer.patternID }) else { return nil }
                let mapped = PatternMapper.apply(pattern, mappings: layer.mappings, values: snapshot.values)
                return HapticAudioOutput.SceneInput(pattern: mapped, strength: layer.strength)
            }
        }
        do {
            try audio.playScene(inputs, on: selectedDeviceID, strength: outputStrength)
            status = inputs.isEmpty ? "Waiting for current source data." : "Ambient scene playing."
        } catch {
            status = "Ambient playback failed: \(error.localizedDescription)"
        }
    }
}
