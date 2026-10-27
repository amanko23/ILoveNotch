// SPDX-License-Identifier: MIT
import AppKit
import Observation

/// Viorim OS from the notch: what's waiting for you there, and a way in. It reads
/// `GET <address>/api/notch` once a minute while Home is on screen, a small JSON object Viorim OS
/// can serve: `{"waiting": 7, "reviews": 3, "approvals": 2, "quotes": 2}` (every field optional).
/// Without it, the tile still opens Viorim OS.
@MainActor
@Observable
public final class ViorimOS {
    public struct Status: Decodable, Equatable, Sendable {
        public var waiting: Int?
        public var reviews: Int?
        public var approvals: Int?
        public var quotes: Int?

        /// Everything waiting: the total Viorim OS gave, or the sum of its parts.
        public var total: Int? {
            waiting ?? [reviews, approvals, quotes].compactMap { $0 }.reduce(nil) { ($0 ?? 0) + $1 }
        }

        /// "3 reviews · 2 approvals · 2 quotes".
        public var breakdown: String? {
            let parts = [(reviews, "review"), (approvals, "approval"), (quotes, "quote")].compactMap { count, noun in
                count.map { "\($0) \(noun)\($0 == 1 ? "" : "s")" }
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    public private(set) var status: Status?
    /// Whether the last read reached Viorim OS.
    public private(set) var reachable: Bool?
    /// Where Viorim OS runs: the app's web address.
    public var address: String {
        didSet { defaults.set(address, forKey: Key.address) }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var poller: Task<Void, Never>?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        address = defaults.string(forKey: Key.address) ?? "http://localhost:3000"
    }

    public var url: URL? { URL(string: address.trimmingCharacters(in: .whitespaces)) }

    public func open() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    public func start() {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard let endpoint = self?.url?.appending(path: "api/notch") else { return }
                let status = await Self.fetch(endpoint)
                guard let self, !Task.isCancelled else { return }
                self.reachable = status != nil
                self.status = status
                do { try await Task.sleep(for: .seconds(60), tolerance: .seconds(5)) } catch { return }
            }
        }
    }

    public func stop() {
        poller?.cancel()
        poller = nil
    }

    nonisolated static func fetch(_ endpoint: URL) async -> Status? {
        var request = URLRequest(url: endpoint, timeoutInterval: 5)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(Status.self, from: data)
    }

    private enum Key {
        static let address = "viorimOS.address"
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
