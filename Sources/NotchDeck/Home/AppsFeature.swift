// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import Observation
import SwiftUI
import WebKit

/// Apps: Viorim OS and the agents' dashboards, a page each with their key takeaways and to-dos.
/// Each site serves them as JSON at `<address>/api/notch`; NotchDeck asks with the sign-in its
/// windows keep, only while this tab is on screen.
@MainActor
@Observable
public final class AppsFeature: NotchFeature {
    /// What a site says at /api/notch.
    public struct Summary: Decodable, Equatable, Sendable {
        public struct Todo: Decodable, Equatable, Sendable {
            public var title: String
            public var done: Bool

            public init(from decoder: Decoder) throws {
                if let title = try? decoder.singleValueContainer().decode(String.self) {
                    self.title = title
                    done = false
                    return
                }
                let container = try decoder.container(keyedBy: Keys.self)
                title = try container.decode(String.self, forKey: .title)
                done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
            }

            private enum Keys: String, CodingKey { case title, done }
        }

        public var takeaways: [String]
        public var todos: [Todo]

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            takeaways = try container.decodeIfPresent([String].self, forKey: .takeaways) ?? []
            todos = try container.decodeIfPresent([Todo].self, forKey: .todos) ?? []
        }

        private enum Keys: String, CodingKey { case takeaways, todos }
    }

    public enum Load: Equatable, Sendable {
        case loading
        case loaded(Summary)
        case unavailable
    }

    public let id = FeatureID.apps
    public var phase: FeaturePhase = .stopped {
        didSet { if phase == .foreground, oldValue != .foreground { refresh() } }
    }
    public let web: WebApps
    public var selected = "viorim"
    public private(set) var loads: [String: Load] = [:]
    @ObservationIgnored private var fetched: [String: Date] = [:]

    public init(web: WebApps) {
        self.web = web
    }

    public var view: some View { AppsView(feature: self) }

    /// Fetches the shown app's summary, at most once a minute unless `force`.
    public func refresh(force: Bool = false) {
        guard let app = web.apps.first(where: { $0.id == selected }) else { return }
        if !force, let last = fetched[app.id], Date.now.timeIntervalSince(last) < 60 { return }
        fetched[app.id] = .now
        if loads[app.id] == nil { loads[app.id] = .loading }
        Task { loads[app.id] = await Self.summary(for: app) }
    }

    /// Fetches every app's summary, for Home's takeaways tile.
    public func refreshAll() {
        let shown = selected
        for app in web.apps {
            selected = app.id
            refresh()
        }
        selected = shown
    }

    /// Every loaded app's takeaways and open to-dos, app by app.
    public var highlights: [(app: WebApps.App, summary: Summary)] {
        web.apps.compactMap { app in
            if case .loaded(let summary) = loads[app.id] { (app, summary) } else { nil }
        }
    }

    public func select(_ id: String) {
        selected = id
        refresh()
    }

    /// The summary URL beside an app's address.
    nonisolated static func summaryURL(_ address: String) -> URL? {
        URL(string: address.trimmingCharacters(in: .whitespaces))?.appending(path: "api/notch")
    }

    private static func summary(for app: WebApps.App) async -> Load {
        guard let url = summaryURL(app.address), let host = url.host() else { return .unavailable }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The sign-in lives in WebKit's store, which the windows share; send its cookies along.
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
            .filter { host == $0.domain || host.hasSuffix("." + $0.domain.trimmingCharacters(in: ["."])) }
        for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let summary = try? JSONDecoder().decode(Summary.self, from: data)
        else { return .unavailable }
        return .loaded(summary)
    }
}

struct AppsView: View {
    let feature: AppsFeature

    var body: some View {
        let web = feature.web
        let app = web.apps.first { $0.id == feature.selected } ?? web.apps[0]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(web.apps) { item in
                    PillButton(item.name, prominent: item.id == app.id) { feature.select(item.id) }
                }
                Spacer(minLength: 0)
                PillButton("Open") { web.open(app) }
            }
            page(app)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(Viorim.smooth, value: feature.selected)
    }

    @ViewBuilder private func page(_ app: WebApps.App) -> some View {
        switch feature.loads[app.id] ?? .loading {
        case .loading:
            Detail("Loading \(app.name)…")
        case .unavailable:
            VStack(alignment: .leading, spacing: 6) {
                Text("No summary from \(app.name) yet.")
                    .font(Viorim.footnote).foregroundStyle(Viorim.ink)
                Text("Sign in with Open once. Takeaways and to-dos show here when the site serves /api/notch.")
                    .font(Viorim.footnote).foregroundStyle(Viorim.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                PillButton("Try again") { feature.refresh(force: true) }
            }
        case .loaded(let summary):
            ScrollView {
                HStack(alignment: .top, spacing: 12) {
                    column("Key takeaways") {
                        ForEach(Array(summary.takeaways.enumerated()), id: \.offset) { _, line in
                            row(symbol: "sparkle", text: line, done: false)
                        }
                        if summary.takeaways.isEmpty { Detail("Nothing new") }
                    }
                    column("To-dos") {
                        ForEach(Array(summary.todos.enumerated()), id: \.offset) { _, todo in
                            let symbol = todo.done ? "checkmark.circle.fill" : "circle"
                            row(symbol: symbol, text: todo.title, done: todo.done)
                        }
                        if summary.todos.isEmpty { Detail("All clear") }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private func column(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Viorim.ink2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(symbol: String, text: String, done: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9)).foregroundStyle(Viorim.accent)
            Text(text)
                .font(Viorim.footnote)
                .foregroundStyle(done ? Viorim.ink2 : Viorim.ink)
                .strikethrough(done)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
