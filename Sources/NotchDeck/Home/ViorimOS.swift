// SPDX-License-Identifier: MIT
import AppKit
import Observation
import WebKit

/// The web apps used every day, Viorim OS and the agents' dashboards, each in a NotchDeck window
/// of its own. They share WebKit's persistent store, so a sign-in is remembered across launches.
@MainActor
@Observable
public final class WebApps {
    public struct App: Identifiable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var symbol: String
        public var address: String
    }

    /// Viorim OS's address, changeable in Settings › Home.
    public var viorimAddress: String {
        didSet { defaults.set(viorimAddress, forKey: Key.viorim) }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var windows: [String: NSWindow] = [:]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        viorimAddress = defaults.string(forKey: Key.viorim) ?? "https://app.viorim.com/"
    }

    public var apps: [App] {
        [
            App(id: "viorim", name: "Viorim OS", symbol: "square.grid.2x2", address: viorimAddress),
            App(id: "agents", name: "Agents", symbol: "person.3", address: "https://agents-umber-gamma.vercel.app/"),
            App(id: "holdings", name: "Holdings", symbol: "chart.pie", address: "https://holdings-agent.vercel.app/"),
        ]
    }

    /// Brings the app's window forward, opening it the first time; it stays signed in.
    public func open(_ app: App) {
        if let window = windows[app.id] {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let url = URL(string: app.address.trimmingCharacters(in: .whitespaces)) else { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()  // persistent: cookies and sign-ins survive relaunches
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = app.name
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("NotchDeck.web.\(app.id)")
        if !window.setFrameUsingName("NotchDeck.web.\(app.id)") { window.center() }
        windows[app.id] = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private enum Key {
        static let viorim = "webApps.viorimAddress"
    }
}

/// India Standard Time and Indian formatting, as the Viorim kit writes dates and times: 27 Oct 2026,
/// 24-hour times in IST.
enum IST {
    static let zone = TimeZone(identifier: "Asia/Kolkata") ?? .current
    static let locale = Locale(identifier: "en_IN")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter
    }

    /// "14:05".
    static func time(_ date: Date) -> String { formatter("HH:mm").string(from: date) }
    /// "Tue 27".
    static func day(_ date: Date) -> String { formatter("EEE d").string(from: date) }
    /// "27 Oct 2026".
    static func date(_ date: Date) -> String { formatter("d MMM yyyy").string(from: date) }
    /// "Tue".
    static func weekday(_ date: Date) -> String { formatter("EEE").string(from: date) }
    /// "October 2026".
    static func month(_ date: Date) -> String { formatter("MMMM yyyy").string(from: date) }

    /// A calendar in IST, for "today" and month grids.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = locale
        return calendar
    }
}
