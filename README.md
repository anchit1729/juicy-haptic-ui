# Ambient Haptics

A macOS menu bar app with optional trackpad feel enhancements.
The current trackpad mode adds spaced taps while you scroll, drag, or click.
The earlier audio mode remains in the project for ambient weather and message patterns.

AppKit provides brief preset taps. It does not offer custom trackpad waveforms or intensity.
The app uses tap spacing to suggest a sandy texture.

## Build and open

1. Install Xcode and XcodeGen.
2. In this folder, run `xcodegen generate`.
3. Open `AmbientHaptics.xcodeproj` in Xcode.
4. Choose the **AmbientHaptics** scheme and run the app.
5. Select **Open Editor** from the new menu bar item.

The project targets macOS 15 or later. It builds with the installed macOS 27 SDK.
XcodeGen reads `project.yml`; do not edit the generated project for lasting changes.

For a command-line check, run:

```sh
xcodebuild -project AmbientHaptics.xcodeproj -scheme AmbientHaptics \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build \
  test CODE_SIGNING_ALLOWED=NO
```

## Trackpad mode

1. Run the app and select **Open Editor** from its menu bar item.
2. Choose **Trackpad preview** under **Output**.
3. Select **Resume**.
4. Turn on **Sandy scrolling**, **Drag ticks**, or **Splash clicks**.
5. Scroll or drag in another app while you touch the Force Touch trackpad.
6. Adjust **Grain spacing** to change the distance between scroll taps.
7. Select **Pause All** from the menu bar to stop the effects.

The app starts paused. Both motion effects start off on a fresh install.
It remembers your effect choices between launches.
It observes only precise scroll movement, pointer drags, and click counts.
It ignores inertial scrolling and requests at most ten texture taps per second.
Splash clicks add two taps after a single click and three after a double click.
The app cancels a single-click tail when it sees the second click.
Drag movements do not start a click splash.
It does not read keyboard input, screen content, or text from other apps.
The **Tap requests** counter shows whether the app receives motion events.
It cannot confirm that you felt a tap.

The public event monitor can observe pointer movement from another input device too.
AppKit does not identify a built-in trackpad through these motion events.
Trackpad feel also depends on the current input device and system haptic settings.

## External audio mode

### Manual trackpad preview

1. Choose **Trackpad preview** under **Output**.
2. Select **Resume**, then select **Test**.
3. Keep a finger on the Force Touch trackpad to check the tap.
4. Select a pattern and press **Play** to compare its tap rhythm.

Trackpad playback depends on the current input device and system haptic settings.
The app cannot set its vibration frequency or intensity through AppKit.
It does not send automatic weather or message feedback to the trackpad.

### Drake output

1. Connect the Drake LFi to the N22 and connect the N22 to a Mac audio output.
2. Set the N22 volume low.
3. Choose **External audio** under **Output**.
4. In the editor, select that output under **Haptic audio output**.
5. Select **Resume**, then select **Test**.
6. Increase the N22 volume slowly until the short pulse feels clear.
7. Check that normal Mac sound still uses your usual output.

The app sends mono haptic audio to the left channel of its selected output.
It caps its digital signal at three per cent of full scale before the strength control.
The N22 volume knob still controls the physical output level.

## Shape a pattern

1. Select a pattern or save a copy.
2. Drag each band's two handles to choose a frequency range.
3. Add up to four bands. Set each band to tone or noise.
4. Adjust gain, pulse rate, variation, pulse length, and strength.
5. Select **Play**, then **Stop**, while you tune the pattern.
6. Select **Save Pattern** to keep it.

The output meter shows the rendered level relative to the software limit.
The **Source scenes** section assigns patterns to a source.
Each ambient layer has its own strength, switch, and value mappings.
Select **Sample source** to test a mapping without a network connection.

## Connect sources for external audio

### Weather

1. Enter your latitude and longitude. The first values shown are a Toronto example.
2. Select **Save Location**.
3. Turn on **Use Open-Meteo weather**.
4. Select **Refresh** to check the first update.
5. Select **Start Ambience** after you choose the haptic output.

The app sends the saved coordinates to Open-Meteo only while weather access is on.
It checks every ten minutes and drops weather data after 30 minutes.
The app uses [Open-Meteo](https://open-meteo.com/) for this draft.
WeatherKit needs an Apple entitlement during app setup.

### Outlook

1. Create a Microsoft public client app that allows device code sign-in.
2. Grant delegated `Mail.ReadBasic`, `User.Read`, and `offline_access` access.
3. Paste its client ID into the Outlook field and select **Connect**.
4. Enter the displayed code on the Microsoft sign-in page.

The app checks one signed-in inbox every minute.
The first check sets a baseline. Later checks cue only newly seen mail.
It stores the refresh token in macOS Keychain.
See [Microsoft device code sign-in](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code).

### Slack

1. Create a Slack app with Socket Mode and the `message.im` event.
2. Grant the scopes needed for direct-message events and Socket Mode.
3. Install that app in each workspace you want to follow.
4. Paste its `xapp-` app token into the Slack field and select **Connect**.
5. Enter workspace IDs to limit cues to chosen workspaces.

The app listens for direct-message events from the Slack app you create.
The installed desktop Slack app does not give another app direct access to its workspaces.
The app stores the Slack token in macOS Keychain.
See [Slack Socket Mode](https://docs.slack.dev/apis/events-api/using-socket-mode/).

## Add a source

1. Add a small adapter under `Sources/Sources`.
2. Give it a source ID and named values in `SourceCatalogue`.
3. Send lasting values through `SourceSnapshot`.
4. Send brief events through `SourceEvent`.
5. Add a default `SourceConfiguration` with patterns and mappings.
6. Connect the adapter to `AppModel` and test it with saved data.

The editor and audio renderer use the same mapping types for every source.
This draft uses in-process adapters. It does not load third-party code at runtime.

## Test status and limits

- Xcode builds the app and runs the unit tests on macOS.
- Tests cover device listing, synthesis bounds, saved patterns, source mappings, weather conversion, message decoding, cue grouping, and saved source settings.
- Tests also check trackpad tap count and timing limits.
- The app starts as a menu bar process.
- The physical Drake output, live weather request, Outlook account, and Slack workspace still need checks on your setup.
- The first draft supports one Outlook account and Slack direct messages. It does not store message text.
- F1 support is outside this draft.

