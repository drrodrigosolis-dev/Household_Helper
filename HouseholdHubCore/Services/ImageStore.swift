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
        try write(thumbnail, to: thumbURL)
        return reference
    }

    public func url(for reference: String) throws -> URL {
        let parts = reference.split(separator: "/")
        let folders = [Folder.wishlist.rawValue, Folder.receipts.rawValue]
        // Exactly "<folder>/<file>" with no hidden or parent-directory component, so a reference cannot escape root.
        guard parts.count == 2, folders.contains(String(parts[0])), !parts[1].hasPrefix(".") else {
            throw ImageStoreError.invalidReference
        }
        return root.appending(path: reference, directoryHint: .notDirectory)
    }

    public func thumbnailURL(for reference: String) throws -> URL {
        try url(for: thumbnailReference(for: reference))
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

    private func write(_ image: CGImage, to url: URL) throws {
        let type = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw ImageStoreError.writeFailed
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageStoreError.writeFailed }
    }
}
