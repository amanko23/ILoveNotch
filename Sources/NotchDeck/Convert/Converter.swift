// SPDX-License-Identifier: MIT
import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// One way to reformat a file: what it's called, the extension it writes, and how.
public struct ConvertTarget: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// An image written as `format` (a UTType identifier), its longest side at most `maxSide` pixels.
        case image(format: String, maxSide: Int?)
        /// An image placed on a PDF page.
        case imageToPDF
        /// A PDF's pages as images in `format`.
        case pdfPages(format: String)
        /// A movie or sound re-exported with an AVFoundation preset into a file type.
        case media(preset: String, fileType: String)
    }

    public var title: String
    public var ext: String
    public var kind: Kind
    public var id: String { title }
}

/// The conversions: pure helpers to pick targets and name outputs, and the work itself, which runs
/// off the main actor. Files are written beside the original; nothing leaves the Mac.
enum Converter {
    /// The 2000 px resize's longest side.
    nonisolated static let resizedSide = 2000

    nonisolated static func targets(for type: UTType) -> [ConvertTarget] {
        if type.conforms(to: .pdf) {
            return [
                ConvertTarget(title: "PNG", ext: "png", kind: .pdfPages(format: UTType.png.identifier)),
                ConvertTarget(title: "JPEG", ext: "jpg", kind: .pdfPages(format: UTType.jpeg.identifier)),
            ]
        }
        if type.conforms(to: .image) {
            return [
                ConvertTarget(title: "JPEG", ext: "jpg", kind: .image(format: UTType.jpeg.identifier, maxSide: nil)),
                ConvertTarget(title: "PNG", ext: "png", kind: .image(format: UTType.png.identifier, maxSide: nil)),
                ConvertTarget(
                    title: "JPEG, \(resizedSide) px", ext: "jpg",
                    kind: .image(format: UTType.jpeg.identifier, maxSide: resizedSide)),
                ConvertTarget(title: "HEIC", ext: "heic", kind: .image(format: UTType.heic.identifier, maxSide: nil)),
                ConvertTarget(title: "TIFF", ext: "tiff", kind: .image(format: UTType.tiff.identifier, maxSide: nil)),
                ConvertTarget(title: "PDF", ext: "pdf", kind: .imageToPDF),
            ]
        }
        if type.conforms(to: .movie) {
            return [
                ConvertTarget(
                    title: "MP4", ext: "mp4",
                    kind: .media(preset: AVAssetExportPresetHighestQuality, fileType: AVFileType.mp4.rawValue)),
                ConvertTarget(
                    title: "MOV", ext: "mov",
                    kind: .media(preset: AVAssetExportPresetHighestQuality, fileType: AVFileType.mov.rawValue)),
                ConvertTarget(
                    title: "M4A audio", ext: "m4a",
                    kind: .media(preset: AVAssetExportPresetAppleM4A, fileType: AVFileType.m4a.rawValue)),
            ]
        }
        if type.conforms(to: .audio) {
            return [
                ConvertTarget(
                    title: "M4A", ext: "m4a",
                    kind: .media(preset: AVAssetExportPresetAppleM4A, fileType: AVFileType.m4a.rawValue))
            ]
        }
        return []
    }

    /// The file's type from its extension, or nil.
    nonisolated static func type(of url: URL) -> UTType? { UTType(filenameExtension: url.pathExtension) }

    /// "<name>.<ext>" beside `source`, or "<name> 2.<ext>", "<name> 3.<ext>"… when taken. The
    /// original itself always counts as taken.
    nonisolated static func outputURL(for source: URL, ext: String, existing: (URL) -> Bool) -> URL {
        let folder = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent
        var number = 1
        while true {
            let name = number == 1 ? "\(stem).\(ext)" : "\(stem) \(number).\(ext)"
            let candidate = folder.appending(path: name)
            if candidate.standardizedFileURL != source.standardizedFileURL, !existing(candidate) { return candidate }
            number += 1
        }
    }

    /// A size scaled down so its longest side is at most `maxSide`; never scaled up.
    nonisolated static func fitted(_ size: CGSize, maxSide: Int) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > CGFloat(maxSide), longest > 0 else { return size }
        let scale = CGFloat(maxSide) / longest
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    enum Failure: LocalizedError {
        case unreadable, unwritable, unsupported
        var errorDescription: String? {
            switch self {
            case .unreadable: "Couldn't read the file."
            case .unwritable: "Couldn't write the new file."
            case .unsupported: "This file can't be converted that way."
            }
        }
    }

    /// Converts `source`, returning the files written.
    @concurrent nonisolated static func convert(_ source: URL, to target: ConvertTarget) async throws -> [URL] {
        let exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        switch target.kind {
        case .image(let format, let maxSide):
            let output = outputURL(for: source, ext: target.ext, existing: exists)
            try writeImage(source, to: output, format: format, maxSide: maxSide)
            return [output]
        case .imageToPDF:
            let output = outputURL(for: source, ext: target.ext, existing: exists)
            guard let image = NSImage(contentsOf: source), let page = PDFPage(image: image) else {
                throw Failure.unreadable
            }
            let document = PDFDocument()
            document.insert(page, at: 0)
            guard document.write(to: output) else { throw Failure.unwritable }
            return [output]
        case .pdfPages(let format):
            return try writePages(source, format: format, ext: target.ext, existing: exists)
        case .media(let preset, let fileType):
            let output = outputURL(for: source, ext: target.ext, existing: exists)
            try await export(source, to: output, preset: preset, fileType: AVFileType(rawValue: fileType))
            return [output]
        }
    }

    nonisolated private static func writeImage(_ source: URL, to output: URL, format: String, maxSide: Int?) throws {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil) else { throw Failure.unreadable }
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, format as CFString, 1, nil) else {
            throw Failure.unsupported
        }
        let quality: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        if let maxSide {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSide,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(input, 0, options as CFDictionary) else {
                throw Failure.unreadable
            }
            CGImageDestinationAddImage(destination, image, quality as CFDictionary)
        } else {
            // Straight from the source, so its metadata and orientation carry over.
            CGImageDestinationAddImageFromSource(destination, input, 0, quality as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw Failure.unwritable }
    }

    /// Each page at twice its point size, as "<name>.<ext>" for one page or "<name> 1.<ext>"… for
    /// more. At most 50 pages.
    nonisolated private static func writePages(
        _ source: URL, format: String, ext: String, existing: (URL) -> Bool
    ) throws -> [URL] {
        guard let document = PDFDocument(url: source), document.pageCount > 0 else { throw Failure.unreadable }
        let count = min(document.pageCount, 50)
        var written: [URL] = []
        for index in 0..<count {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let size = CGSize(width: bounds.width * 2, height: bounds.height * 2)
            let image = page.thumbnail(of: size, for: .mediaBox)
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw Failure.unreadable
            }
            let stem = source.deletingPathExtension().lastPathComponent
            let named =
                count == 1 ? source : source.deletingLastPathComponent().appending(path: "\(stem) \(index + 1).pdf")
            let output = outputURL(for: named, ext: ext, existing: { existing($0) || written.contains($0) })
            guard let destination = CGImageDestinationCreateWithURL(output as CFURL, format as CFString, 1, nil) else {
                throw Failure.unsupported
            }
            let quality: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
            CGImageDestinationAddImage(destination, cgImage, quality as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw Failure.unwritable }
            written.append(output)
        }
        return written
    }

    nonisolated private static func export(_ source: URL, to output: URL, preset: String, fileType: AVFileType)
        async throws
    {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw Failure.unsupported }
        if #available(macOS 15, *) {
            try await session.export(to: output, as: fileType)
        } else {
            session.outputURL = output
            session.outputFileType = fileType
            nonisolated(unsafe) let running = session
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                running.exportAsynchronously { continuation.resume() }
            }
            if running.status != .completed { throw running.error ?? Failure.unwritable }
        }
    }
}
