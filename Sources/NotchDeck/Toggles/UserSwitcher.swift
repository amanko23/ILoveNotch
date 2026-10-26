// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices
import NotchFeatures

/// Switch User: locks the Mac and brings up the login window, where any user can sign in while
/// this one's apps keep running. macOS has no public call for the user menu itself, so this
/// presses Control-Command-Q, the system's Lock Screen shortcut, when NotchDeck has Accessibility
/// access; otherwise it puts the display to sleep, which locks the Mac when it asks for the
/// password right away (the default). NotchDeck never sees or stores a password.
@MainActor
public enum UserSwitcher {
    /// Whether the lock can go straight to the login window.
    public static var locksDirectly: Bool { AXIsProcessTrusted() }

    public static func lockAndSwitch() {
        if locksDirectly {
            pressLockScreenShortcut()
        } else {
            Task { _ = await Subprocess.run("/usr/bin/pmset", ["displaysleepnow"]) }
        }
    }

    /// Opens Privacy & Security › Accessibility, where NotchDeck can be allowed to lock directly.
    public static func openAccessibilitySettings() {
        NSWorkspace.shared.open(.privacySettings("Privacy_Accessibility"))
    }

    private static func pressLockScreenShortcut() {
        let q: CGKeyCode = 12  // kVK_ANSI_Q
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: q, keyDown: keyDown)
            event?.flags = [.maskCommand, .maskControl]
            event?.post(tap: .cghidEventTap)
        }
    }
}
