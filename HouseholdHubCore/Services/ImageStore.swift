import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Keeps media files outside the database (spec §5.5): `Application Support/Media/<folder>/<id>.jpg` plus a small
/// `<id>-thumb.jpg`. Records store only the relative reference, e.g. `Wishlist/<id>.jpg`.
public struct ImageStore: Sendable {
    public enum Folder: String, Sendable {
        case wishlist = "Wishlist"
        case receipts = "Receipts"
    }

    public enum ImageStoreError: Error, Equatable {
        case unreadableImage
        case writeFailed
        case invalidReference
    }

    public let root: URL
    public var maxPixelSize = 2048
    public var thumbnailPixelSize = 360

    public init(root: URL) {
        self.root = root
    }

    /// The app's store: `Application Support/Media`.
    public static func standard() throws -> ImageStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return ImageStore(root: support.appending(path: "Media", directoryHint: .isDirectory))
    }

    /// Re-encodes the image (bounded size, metadata such as location dropped) and writes it with its thumbnail.
    public func save(_ data: Data, in folder: Folder) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageStoreError.unreadableImage
        }
        let full = try downscaled(source, to: maxPixelSize)
        let thumbnail = try downscaled(source, to: thumbnailPixelSize)
        let directory = root.appending(path: folder.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let reference = "\(folder.rawValue)/\(id).jpg"
        let fullURL = try url(for: reference)
        let thumbURL = try thumbnailURL(for: reference)
        try write(full, to: fullURL)
        do {
            try write(thumbnail, to: thumbURL)
        } catch {
            try? FileManager.default.removeItem(at: fullURL)
            throw error
        }
        return reference
    }

    /// Exactly "<folder>/<UUID>.jpg", so a reference cannot escape root or collide with a thumbnail.
    public static func isValidReference(_ reference: String) -> Bool {
        let parts = reference.split(separator: "/", omittingEmptySubsequences: false)
        let folders = [Folder.wishlist.rawValue, Folder.receipts.rawValue]
        // The file is "<UUID>.jpg", as `save` names it: nothing else (a hidden file, "..", or another item's
        // "-thumb.jpg") can be addressed through a reference.
        guard parts.count == 2, folders.contains(String(parts[0])), parts[1].hasSuffix(".jpg") else { return false }
        return UUID(uuidString: String(parts[1].dropLast(4))) != nil
    }

    public func url(for reference: String) throws -> URL {
        guard Self.isValidReference(reference) else { throw ImageStoreError.invalidReference }
        return root.appending(path: reference, directoryHint: .notDirectory)
    }

    public func thumbnailURL(for reference: String) throws -> URL {
        guard Self.isValidReference(reference) else { throw ImageStoreError.invalidReference }
        return root.appending(path: thumbnailReference(for: reference), directoryHint: .notDirectory)
    }

    /// Size in bytes of a stored image, or nil when its file is missing (backup manifest, spec §26).
    public func fileSize(of reference: String) -> Int? {
        guard let fileURL = try? url(for: reference),
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        else { return nil }
        return values.fileSize
    }

    public func data(for reference: String) throws -> Data {
        try Data(contentsOf: try url(for: reference))
    }

    /// Writes an image under the reference it had in a backup and rebuilds its thumbnail (restore, spec §26.1). The
    /// image is re-encoded like a new photo, so metadata or an odd payload in someone else's backup isn't kept.
    public func restore(_ data: Data, as reference: String) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageStoreError.unreadableImage
        }
        let full = try downscaled(source, to: maxPixelSize)
        let thumbnail = try downscaled(source, to: thumbnailPixelSize)
        let fullURL = try url(for: reference)
        let thumbURL = try thumbnailURL(for: reference)
        try FileManager.default.createDirectory(
            at: fullURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(full, to: fullURL)
        try write(thumbnail, to: thumbURL)
    }

    /// Every full-size image reference in a folder (thumbnails excluded), for removing files nothing refers to.
    public func references(in folder: Folder) -> [String] {
        let directory = root.appending(path: folder.rawValue, directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return names.filter { !$0.hasSuffix("-thumb.jpg") && !$0.hasPrefix(".") }.map { "\(folder.rawValue)/\($0)" }
            .sorted()
    }

    /// Removes the image and its thumbnail; a missing file is not an error.
    public func delete(_ reference: String) throws {
        let files = [try url(for: reference), try thumbnailURL(for: reference)]
        for file in files where FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func thumbnailReference(for reference: String) -> String {
        let base = reference.hasSuffix(".jpg") ? String(reference.dropLast(4)) : reference
        return base + "-thumb.jpg"
    }

    private func downscaled(_ source: CGImageSource, to pixels: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageStoreError.unreadableImage
        }
        return image
    }

    /// Encodes to JPEG in memory, then writes atomically with complete file protection: photos are readable only
    /// while the device is unlocked (nothing reads them in the background).
    private func write(_ image: CGImage, to url: URL) throws {
        let type = UTType.jpeg.identifier as CFString
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded as CFMutableData, type, 1, nil) else {
            throw ImageStoreError.writeFailed
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageStoreError.writeFailed }
        do {
            try (encoded as Data).write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            throw ImageStoreError.writeFailed
        }
    }
}
