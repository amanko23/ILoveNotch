// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import Observation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Convert: drop a file on the notch and pick a format. Images become JPEG, PNG, HEIC, TIFF or PDF
/// (or a 2000 px JPEG), PDFs become images, and movies and sound become MP4, MOV or M4A. The new
/// files land beside the originals. Nothing runs until something is dropped.
@MainActor
@Observable
public final class ConvertFeature: NotchFeature {
    public struct Job: Identifiable, Sendable {
        public enum State: Equatable, Sendable {
            case working, done([URL]), failed(String)
        }

        public let id = UUID()
        public let source: URL
        public let target: ConvertTarget
        public var state: State = .working
    }

    public let id = FeatureID.convert
    public var phase: FeaturePhase = .stopped
    /// The dropped files that can be converted.
    public private(set) var files: [URL] = []
    /// What they can become, from the first file's type.
    public private(set) var targets: [ConvertTarget] = []
    public private(set) var jobs: [Job] = []
    public private(set) var thumbnail: NSImage?

    public init() {}

    public var view: some View { ConvertView(feature: self) }

    /// Takes dropped files, keeping those that can be converted. Files of other kinds than the first
    /// are left out, so one set of formats fits all. False when none can be converted.
    @discardableResult
    public func accept(_ urls: [URL]) -> Bool {
        let convertible = urls.filter { url in
            Converter.type(of: url).map { !Converter.targets(for: $0).isEmpty } ?? false
        }
        guard let first = convertible.first, let type = Converter.type(of: first) else { return false }
        let shown = Converter.targets(for: type)
        files = convertible.filter { Converter.type(of: $0).map(Converter.targets(for:)) == shown }
        targets = shown
        jobs = []
        thumbnail = NSWorkspace.shared.icon(forFile: first.path(percentEncoded: false))
        loadThumbnail(for: first)
        return true
    }

    /// Converts every dropped file to `target`.
    public func convert(to target: ConvertTarget) {
        for file in files {
            let job = Job(source: file, target: target)
            jobs.append(job)
            Task { [weak self] in
                let state: Job.State
                do {
                    state = .done(try await Converter.convert(file, to: target))
                } catch {
                    state = .failed(error.localizedDescription)
                }
                guard let self, let index = self.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                self.jobs[index].state = state
            }
        }
    }

    /// Forgets the dropped files.
    public func clear() {
        files = []
        targets = []
        jobs = []
        thumbnail = nil
    }

    public func reveal(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }

    /// Puts the files on the clipboard, to paste in Finder, Mail or a chat.
    public func copy(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    /// A small preview for an image, read off the main actor; other files keep their Finder icon.
    private func loadThumbnail(for url: URL) {
        guard Converter.type(of: url)?.conforms(to: .image) == true else { return }
        Task { [weak self] in
            guard let image = await Self.preview(of: url) else { return }
            guard let self, self.files.first == url else { return }
            self.thumbnail = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        }
    }

    @concurrent nonisolated private static func preview(of url: URL) async -> sending CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 192,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

struct ConvertView: View {
    let feature: ConvertFeature

    var body: some View {
        if feature.files.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Viorim.accent)
                Text("Drop a file on the notch to convert it.")
                    .font(Viorim.footnote)
                    .foregroundStyle(Viorim.ink2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 8) {
                preview
                VStack(alignment: .leading, spacing: 6) {
                    if feature.jobs.isEmpty {
                        choices
                    } else {
                        progress
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 4) {
            if let thumbnail = feature.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            Text(feature.files.count == 1 ? feature.files[0].lastPathComponent : "\(feature.files.count) files")
                .font(.system(size: 10))
                .foregroundStyle(Viorim.ink2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(8)
        .frame(width: 96)
        .frame(maxHeight: .infinity)
        .background(Viorim.surfaceRaised.opacity(0.62), in: RoundedRectangle(cornerRadius: Viorim.radiusTile))
    }

    /// The three likeliest formats as big tiles, the rest as chips under them.
    private var choices: some View {
        let big = feature.targets.prefix(3)
        let small = feature.targets.dropFirst(3)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(big)) { target in
                    TargetTile(target: target) { feature.convert(to: target) }
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 6) {
                ForEach(Array(small)) { target in
                    PillButton(target.title) { feature.convert(to: target) }
                }
                Spacer(minLength: 0)
                PillButton("Clear") { feature.clear() }
            }
        }
    }

    private var progress: some View {
        let finished = feature.jobs.flatMap { job -> [URL] in
            if case .done(let urls) = job.state { urls } else { [] }
        }
        let working = feature.jobs.contains { $0.state == .working }
        return VStack(alignment: .leading, spacing: 5) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(feature.jobs) { job in JobRow(job: job) }
                }
            }
            .scrollIndicators(.never)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if !finished.isEmpty, !working {
                    PillButton("Reveal in Finder", prominent: true) { feature.reveal(finished) }
                    PillButton("Copy file") { feature.copy(finished) }
                }
                Spacer(minLength: 0)
                PillButton(working ? "Converting…" : "Done") { feature.clear() }
                    .disabled(working)
            }
        }
    }
}

/// A big format tile: a round icon over the format's name, lit on hover.
private struct TargetTile: View {
    let target: ConvertTarget
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Viorim.accent)
                    .frame(width: 34, height: 34)
                    .background(Viorim.highlight.opacity(hovering ? 1 : 0.6), in: Circle())
                Text(target.title)
                    .font(Viorim.footnote)
                    .foregroundStyle(Viorim.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                (hovering ? Viorim.highlight : Viorim.surfaceRaised.opacity(0.62)),
                in: RoundedRectangle(cornerRadius: Viorim.radiusTile, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Viorim.snappy, value: hovering)
    }

    private var symbol: String {
        switch target.kind {
        case .image(_, let maxSide): maxSide == nil ? "photo" : "arrow.down.right.and.arrow.up.left"
        case .imageToPDF: "doc.richtext"
        case .pdfPages: "photo.on.rectangle"
        case .media(_, let fileType): fileType == "com.apple.m4a-audio" ? "waveform" : "film"
        }
    }
}

private struct JobRow: View {
    let job: ConvertFeature.Job

    var body: some View {
        HStack(spacing: 6) {
            switch job.state {
            case .working: ProgressView().controlSize(.mini)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Viorim.success)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Viorim.warning)
            }
            Text("\(job.source.lastPathComponent) → \(job.target.title)")
                .font(Viorim.footnote)
                .foregroundStyle(Viorim.ink)
                .lineLimit(1)
            if case .failed(let reason) = job.state {
                Text(reason).font(.system(size: 10)).foregroundStyle(Viorim.ink2).lineLimit(1)
            }
        }
        .font(.system(size: 11))
    }
}
