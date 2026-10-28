// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import NotchCore
import Observation
import SQLite3
import SwiftUI

/// Inbox: the Mac's recent notifications, read from Notification Center's own database. It needs
/// Full Disk Access. Notifications are only read into memory, never stored, and the list empties
/// when the screen locks.
@MainActor
@Observable
public final class InboxFeature: NotchFeature {
    public struct Item: Identifiable, Hashable, Sendable {
        public var id: String
        public var app: String
        public var title: String
        public var body: String
        public var delivered: Date
    }

    public enum Access: Sendable { case unknown, allowed, denied }

    public let id = FeatureID.inbox
    public var phase: FeaturePhase = .stopped {
        didSet { if phase != oldValue { update() } }
    }
    public private(set) var items: [Item] = []
    public private(set) var access: Access = .unknown
    /// Notifications since the tab was last open.
    public private(set) var unread = 0
    /// Items delivered before this are hidden: set on Clear and when the screen locks.
    @ObservationIgnored private var clearedBefore: Date = .distantPast
    @ObservationIgnored private var seenUntil: Date = .now
    @ObservationIgnored private var lastRead: Date = .distantPast
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var lockObserver: NSObjectProtocol?
    @ObservationIgnored private var poll: Task<Void, Never>?

    public init() {}

    public var view: some View { InboxView(inbox: self) }

    public func clear() {
        clearedBefore = .now
        items = []
        unread = 0
    }

    public static func openFullDiskAccess() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        else { return }
        NSWorkspace.shared.open(url)
    }

    private func update() {
        switch phase {
        case .stopped:
            stopWatching()
            poll?.cancel()
            poll = nil
            if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver) }
            lockObserver = nil
        case .background:
            poll?.cancel()
            poll = nil
            startObservingLock()
            startWatching()
        case .foreground:
            startObservingLock()
            startWatching()
            unread = 0
            seenUntil = .now
            poll = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.read()
                    try? await Task.sleep(for: .seconds(10))
                }
            }
        }
    }

    private func startObservingLock() {
        guard lockObserver == nil else { return }
        lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.clear() }
        }
    }

    /// Watches the database's write-ahead log, which changes on every new notification.
    private func startWatching() {
        guard watcher == nil, let path = Self.databasePath else { return }
        let descriptor = open(path + "-wal", O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Re-read at most every 10 s.
                guard Date.now.timeIntervalSince(self.lastRead) > 10 else { return }
                Task { await self.read() }
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    private func read() async {
        lastRead = .now
        guard let path = Self.databasePath else {
            access = .denied
            return
        }
        let result = await Task.detached { Self.load(path: path) }.value
        guard let found = result else {
            access = .denied
            return
        }
        access = .allowed
        items = found.filter { $0.delivered > clearedBefore }
        unread = phase == .foreground ? 0 : items.filter { $0.delivered > seenUntil }.count
        if phase == .foreground { seenUntil = .now }
    }

    /// Notification Center's database: in the per-user Darwin folder on macOS 15, else the group
    /// container. Nil when neither is there.
    nonisolated static var databasePath: String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        var candidates: [String] = []
        if confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count) > 0 {
            let directory = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            candidates.append((directory as NSString).appendingPathComponent("com.apple.notificationcenter/db2/db"))
        }
        candidates.append(
            NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db")
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates.first
    }

    /// The latest 30 notifications, or nil when the database can't be opened (no Full Disk Access).
    nonisolated static func load(path: String) -> [Item]? {
        var db: OpaquePointer?
        let uri = "file:\(path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        let sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date FROM record r
            JOIN app a ON a.app_id = r.app_id ORDER BY r.delivered_date DESC LIMIT 30
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        var items: [Item] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let app = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let count = Int(sqlite3_column_bytes(statement, 2))
            guard let bytes = sqlite3_column_blob(statement, 2), count > 0 else { continue }
            let data = Data(bytes: bytes, count: count)
            let delivered = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3))
            guard let item = parse(data, id: String(id), app: app, delivered: delivered) else { continue }
            items.append(item)
        }
        return items
    }

    /// Reads a record's binary plist: `req` holds the title (`titl`), subtitle (`subt`) and `body`.
    nonisolated static func parse(_ data: Data, id: String, app: String, delivered: Date) -> Item? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let request = plist["req"] as? [String: Any]
        else { return nil }
        let title = request["titl"] as? String ?? ""
        let subtitle = request["subt"] as? String ?? ""
        let body = [subtitle, request["body"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " — ")
        guard !title.isEmpty || !body.isEmpty else { return nil }
        let bundle = plist["app"] as? String ?? app
        return Item(id: id, app: bundle, title: title, body: body, delivered: delivered)
    }
}

struct InboxView: View {
    let inbox: InboxFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("INBOX").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Viorim.ink2)
                Spacer(minLength: 0)
                if !inbox.items.isEmpty { PillButton("Clear") { inbox.clear() } }
            }
            switch inbox.access {
            case .denied:
                Text("NotchDeck needs Full Disk Access to read Notification Center. Nothing is stored.")
                    .font(Viorim.footnote).foregroundStyle(Viorim.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                PillButton("Allow Full Disk Access", prominent: true) { InboxFeature.openFullDiskAccess() }
            case .unknown:
                Detail("Reading notifications…")
            case .allowed where inbox.items.isEmpty:
                Detail("No new notifications. The list clears when your Mac locks.")
            case .allowed:
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(inbox.items) { InboxRow(item: $0) }
                    }
                }
                .scrollIndicators(.never)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct InboxRow: View {
    let item: InboxFeature.Item

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(nsImage: Self.icon(item.app)).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(item.title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Viorim.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.delivered, format: .relative(presentation: .named))
                        .font(.system(size: 10)).foregroundStyle(Viorim.ink2).lineLimit(1)
                }
                if !item.body.isEmpty {
                    Text(item.body).font(Viorim.footnote).foregroundStyle(Viorim.ink2).lineLimit(2)
                }
            }
        }
    }

    static func icon(_ bundle: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "bell", accessibilityDescription: nil) ?? NSImage()
    }
}
