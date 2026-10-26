// SPDX-License-Identifier: MIT
import AppKit

// LSUIElement (project.yml) makes this an accessory app: no Dock icon, no menu bar,
// and the notch panel never steals focus. First efficiency lever.
// NotchDeck opens in the Viorim OS look until the user picks another in Settings › Appearance.
UserDefaults.standard.register(defaults: ["theme": "viorim", "animationStyle": "measured"])
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
