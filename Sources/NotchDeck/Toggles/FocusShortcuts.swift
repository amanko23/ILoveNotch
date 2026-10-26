// SPDX-License-Identifier: MIT
import AppKit
import NotchFeatures
import Observation

/// Focus modes, through the user's own shortcuts: apps can't read or set Focus directly, but a
/// shortcut with the Shortcuts app's "Set Focus" action can. Any shortcut whose name mentions
/// Focus or Do Not Disturb shows up, run with the public `shortcuts` command-line tool.
@MainActor
@Observable
public final class FocusShortcuts {
    public private(set) var names: [String] = []
    public private(set) var running: String?
    public private(set) var hasLoaded = false

    public init() {}

    public func refresh() {
        Task { [weak self] in
            let result = await Subprocess.run("/usr/bin/shortcuts", ["list"])
            guard let self else { return }
            self.names = Self.focusShortcuts(in: result.output)
            self.hasLoaded = true
        }
    }

    public func run(_ name: String) {
        guard running == nil else { return }
        running = name
        Task { [weak self] in
            _ = await Subprocess.run("/usr/bin/shortcuts", ["run", name])
            self?.running = nil
        }
    }

    public func openShortcutsApp() {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") else { return }
        workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The shortcuts in `shortcuts list`'s output that look like they set a Focus.
    nonisolated static func focusShortcuts(in output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { name in
                let lowered = name.lowercased()
                return lowered.contains("focus") || lowered.contains("do not disturb") || lowered.contains("dnd")
            }
    }
}
