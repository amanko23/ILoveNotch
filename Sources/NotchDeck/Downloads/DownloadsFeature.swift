// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import NotchCore
import Observation
import SwiftUI

/// Downloads: files browsers are still downloading into ~/Downloads (Chrome's `.crdownload`,
/// Safari's `.download` bundles, Firefox's `.part`), with their progress and speed, and the last
/// few that finished. It watches the folder for changes; while something downloads it samples
/// sizes once a second.
@MainActor
@Observable
public final class DownloadsFeature: NotchFeature {
    public struct Download: Identifiable, Hashable, Sendable {
        /// The in-progress file's path.
        public var id: String
        /// The name it will have once done.
        public var name: String
        public var bytes: Int64
        /// The full size when the browser says, else nil.
        public var total: Int64?
        /// Bytes per second, from the last sample.
        public var speed: Double

        public var progress: Double? {
            guard let total, total > 0 else { return nil }
            return min(1, Double(bytes) / Double(total))
        }
    }

    public struct Finished: Identifiable, Hashable, Sendable {
        public var id: String { url.path }
        public var url: URL
        public var date: Date
    }

    public let id = FeatureID.downloads
    public var phase: FeaturePhase = .stopped {
        didSet { if phase != oldValue { update() } }
    }
    public private(set) var active: [Download] = []
    public private(set) var finished: [Finished] = []
    /// Called with the closed notch's ongoing activity while something downloads, nil once done.
    @ObservationIgnored public var onActivity: ((Activity?) -> Void)?
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var sampler: Task<Void, Never>?
    @ObservationIgnored private let folder: URL

    public init(folder: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")) {
        self.folder = folder
    }

    public var view: some View { DownloadsView(downloads: self) }

    /// All downloads' combined progress, when every one knows its size.
    public var overallProgress: Double? {
        Self.overall(active)
    }

    nonisolated static func overall(_ active: [Download]) -> Double? {
        guard !active.isEmpty else { return nil }
        var done: Int64 = 0
        var total: Int64 = 0
        for download in active {
            guard let size = download.total, size > 0 else { return nil }
            done += download.bytes
            total += size
        }
        return min(1, Double(done) / Double(total))
    }

    public func reveal(_ item: Finished) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func update() {
        if phase == .stopped {
            watcher?.cancel()
            watcher = nil
            stopSampling()
            if !active.isEmpty {
                active = []
                onActivity?(nil)
            }
        } else {
            startWatching()
            scan()
        }
    }

    private func startWatching() {
        guard watcher == nil else { return }
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func startSampling() {
        guard sampler == nil else { return }
        sampler = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.scan()
            }
        }
    }

    private func stopSampling() {
        sampler?.cancel()
        sampler = nil
    }

    /// Re-reads the folder: updates sizes and speeds, and moves vanished downloads to Finished.
    private func scan() {
        let previous = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        let urls =
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var now: [Download] = []
        for url in urls {
            guard var download = Self.inProgress(url) else { continue }
            if let before = previous[download.id] {
                download.speed = max(0, Double(download.bytes - before.bytes))
            }
            now.append(download)
        }
        now.sort { $0.name < $1.name }
        let current = Set(now.map(\.id))
        for gone in previous.values where !current.contains(gone.id) {
            let done = folder.appending(path: gone.name)
            if FileManager.default.fileExists(atPath: done.path) {
                finished.insert(Finished(url: done, date: .now), at: 0)
            }
        }
        if finished.count > 5 { finished = Array(finished.prefix(5)) }
        if now != active { active = now }
        if now.isEmpty { stopSampling() } else { startSampling() }
        onActivity?(Self.activity(for: now))
    }

    /// The closed notch's pill: how many are downloading, with a ring for their progress.
    nonisolated static func activity(for active: [Download]) -> Activity? {
        guard let first = active.first else { return nil }
        let title = active.count == 1 ? first.name : "\(active.count) downloading"
        let progress = overall(active)
        let label = progress.map { "Downloading, \(Int($0 * 100)) percent" } ?? "Downloading"
        return Activity(
            feature: .downloads, symbol: "arrow.down.circle", title: title, duration: .zero,
            accessory: Activity.Accessory(symbol: "arrow.down", progress: progress, tint: 0x9DB2CB, label: label))
    }

    /// A browser's in-progress download, or nil for any other file.
    nonisolated static func inProgress(_ url: URL) -> Download? {
        let manager = FileManager.default
        func size(_ path: String) -> Int64 {
            (try? manager.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
        }
        switch url.pathExtension {
        case "crdownload", "part":
            let name = url.deletingPathExtension().lastPathComponent
            return Download(id: url.path, name: name, bytes: size(url.path), total: nil, speed: 0)
        case "download":
            // Safari: a bundle holding the partial file and an Info.plist with the expected size.
            let name = url.deletingPathExtension().lastPathComponent
            let contents = (try? manager.contentsOfDirectory(atPath: url.path)) ?? []
            let bytes = contents.filter { $0 != "Info.plist" }.map { size(url.appending(path: $0).path) }.max() ?? 0
            let info = NSDictionary(contentsOf: url.appending(path: "Info.plist"))
            let total = (info?["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
            return Download(id: url.path, name: name, bytes: bytes, total: total, speed: 0)
        default:
            return nil
        }
    }

    nonisolated static func describe(_ download: Download) -> String {
        let style = ByteCountFormatter.CountStyle.file
        var text = ByteCountFormatter.string(fromByteCount: download.bytes, countStyle: style)
        if let total = download.total {
            text += " of " + ByteCountFormatter.string(fromByteCount: total, countStyle: style)
        }
        if download.speed > 0 {
            text += " · " + ByteCountFormatter.string(fromByteCount: Int64(download.speed), countStyle: style) + "/s"
        }
        return text
    }
}

struct DownloadsView: View {
    let downloads: DownloadsFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DOWNLOADING").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Viorim.ink2)
            if downloads.active.isEmpty {
                Detail("Nothing downloading.")
            } else {
                ForEach(downloads.active.prefix(3)) { download in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(download.name).font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Viorim.ink).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(DownloadsFeature.describe(download)).font(.system(size: 10))
                                .monospacedDigit().foregroundStyle(Viorim.ink2).lineLimit(1)
                        }
                        if let progress = download.progress {
                            ProgressView(value: progress).progressViewStyle(.linear).tint(Viorim.accent)
                        } else {
                            ProgressView().progressViewStyle(.linear).tint(Viorim.accent)
                        }
                    }
                }
            }
            if !downloads.finished.isEmpty {
                Text("FINISHED").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Viorim.ink2)
                    .padding(.top, 2)
                ForEach(downloads.finished) { item in
                    Button {
                        downloads.reveal(item)
                    } label: {
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                .resizable().frame(width: 14, height: 14)
                            Text(item.url.lastPathComponent).font(Viorim.footnote).foregroundStyle(Viorim.ink)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                }
            }
            Spacer(minLength: 0)
        }
    }
}
