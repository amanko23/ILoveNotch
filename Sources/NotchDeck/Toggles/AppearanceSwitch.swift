// SPDX-License-Identifier: MIT
import AppKit
import NotchFeatures
import Observation

/// Switches macOS between light and dark appearance, the way the Appearance setting in System
/// Settings does, through System Events: public AppleScript that macOS asks about once (Privacy &
/// Security › Automation). It listens for the change only while something on screen shows it.
@MainActor
@Observable
public final class AppearanceSwitch {
    public private(set) var isDark: Bool
    public private(set) var isSwitching = false
    /// Why the last switch didn't happen, with the fix.
    public private(set) var failure: String?
    @ObservationIgnored private var observer: NSObjectProtocol?

    public init() {
        isDark = Self.systemIsDark()
    }

    public func startObserving() {
        isDark = Self.systemIsDark()
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isDark = Self.systemIsDark() }
        }
    }

    public func stopObserving() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
    }

    public func toggle() {
        guard !isSwitching else { return }
        let dark = !isDark
        isSwitching = true
        Task { [weak self] in
            let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"
            let result = await Subprocess.run("/usr/bin/osascript", ["-e", script])
            guard let self else { return }
            self.isSwitching = false
            if result.status == 0 {
                self.isDark = dark
                self.failure = nil
            } else {
                self.failure = "Allow NotchDeck to control System Events in Privacy & Security › Automation."
            }
        }
    }

    /// Opens Privacy & Security › Automation, where the switch is allowed.
    public func openAutomationSettings() {
        NSWorkspace.shared.open(.privacySettings("Privacy_Automation"))
    }

    /// The global `AppleInterfaceStyle` preference, read fresh: "Dark", or absent for light.
    static func systemIsDark() -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication)
        return (style as? String) == "Dark"
    }
}
