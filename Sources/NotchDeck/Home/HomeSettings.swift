// SPDX-License-Identifier: MIT
import AppKit
import CoreLocation
import NotchFeatures
import SwiftUI

extension HomeFeature {
    /// Settings › Home: how the notch opens, Pomodoro's lengths, and where the weather is for.
    public var settingsView: some View { HomeSettings(home: self) }
}

private struct HomeSettings: View {
    @Bindable var home: HomeFeature

    var body: some View {
        @Bindable var pomodoro = home.pomodoro
        @Bindable var weather = home.weather
        @Bindable var web = home.webApps
        Group {
            Section {
                Toggle(isOn: $home.opensOnHome) {
                    Text("Always open on Home")
                    Text("Otherwise the notch opens on the tab you used last.")
                }
                Toggle(isOn: $home.hidesWhileWatchingVideo) {
                    Text("Keep the notch quiet while watching video")
                    Text("No titles beside the camera during YouTube, Netflix and the like. Hover to open it.")
                }
                Toggle(isOn: $home.showsClaudeInClosedNotch) {
                    Text("Show Claude's progress in the closed notch")
                    Text("A ring beside what's playing, or Claude on its own, while a session works.")
                }
            }
            Section("Viorim OS and agents") {
                LabeledContent {
                    TextField("Address", text: $web.viorimAddress, prompt: Text("https://app.viorim.com/"))
                        .labelsHidden()
                        .frame(maxWidth: 220)
                } label: {
                    Text("Viorim OS address")
                    Text("Opens in its own window, which stays signed in.")
                }
                LabeledContent {
                    TextField("Agents", text: projects).labelsHidden().frame(maxWidth: 260)
                } label: {
                    Text("Agent projects")
                    Text("Folder names, separated by commas. Each gets a page in the Claude peek.")
                }
            }
            Section("Pomodoro") {
                Picker("Focus", selection: $pomodoro.plan.focusMinutes) {
                    ForEach([15, 20, 25, 30, 45, 50, 60], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Picker("Short break", selection: $pomodoro.plan.shortBreakMinutes) {
                    ForEach([3, 5, 10], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Picker("Long break", selection: $pomodoro.plan.longBreakMinutes) {
                    ForEach([10, 15, 20, 30], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Picker("Long break after", selection: $pomodoro.plan.rounds) {
                    ForEach([2, 3, 4, 5, 6], id: \.self) { Text("\($0) focus sessions").tag($0) }
                }
                Toggle("Start breaks automatically", isOn: $pomodoro.startsBreaksAutomatically)
                Toggle("Start the next focus session automatically", isOn: $pomodoro.startsFocusAutomatically)
                Toggle(isOn: $pomodoro.notifies) {
                    Text("Notify me when a session ends")
                    Text("A notification and a chime at every switch. The notch shows it too.")
                }
            }
            Section("Weather") {
                Picker("Temperature", selection: unit) {
                    Text("Automatic").tag(0)
                    Text("Celsius").tag(1)
                    Text("Fahrenheit").tag(2)
                }
                LabeledContent {
                    TextField("City", text: $weather.city, prompt: Text("Use my location"))
                        .labelsHidden()
                        .frame(maxWidth: 200)
                        .onSubmit { weather.refresh() }
                } label: {
                    Text("City")
                    Text(locationNote)
                }
                LabeledContent {
                    Button("Refresh") { weather.refresh() }
                } label: {
                    Text("Forecast")
                    Text("Free from Open-Meteo.com, no account. Your location is rounded to about 10 km.")
                }
            }
        }
    }

    /// The agent projects as one comma-separated line.
    private var projects: Binding<String> {
        Binding(
            get: { home.agentProjects.joined(separator: ", ") },
            set: { line in
                home.agentProjects = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            })
    }

    /// Automatic (0), Celsius (1), or Fahrenheit (2).
    private var unit: Binding<Int> {
        Binding(
            get: { home.weather.prefersFahrenheit.map { $0 ? 2 : 1 } ?? 0 },
            set: { home.weather.prefersFahrenheit = $0 == 0 ? nil : $0 == 2 })
    }

    private var locationNote: String {
        guard home.weather.usesLocation else { return "The weather is for this city." }
        switch home.weather.locationAccess {
        case .denied, .restricted: return "Location access is off. Type a city, or allow it in Privacy & Security."
        case .notDetermined: return "Leave empty to use your location; macOS asks the first time."
        default: return "Empty: the weather is for where you are."
        }
    }
}
