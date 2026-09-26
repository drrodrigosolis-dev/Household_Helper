import Foundation

/// The whole backup and restore sequences, files included, so the app layer only presents them (spec §26.1).
public struct BackupFlow: Sendable {
    public typealias RestoreSummary = BackupService.RestoreSummary

    public let service: BackupService
    public let images: ImageStore?

    /// Largest `backup.json` and image file a restore will read; anything bigger is refused, not loaded.
    public static let maxJSONBytes = 200 * 1_024 * 1_024
    public static let maxImageBytes = 40 * 1_024 * 1_024

    public init(service: BackupService, images: ImageStore?) {
        self.service = service
        self.images = images
    }

    public struct Prepared: Sendable {
        public let backup: BackupDTO
        public let media: [String: Data]
        /// Photos referenced by items whose files could not be read; they are left out of this backup.
        public let unreadablePhotos: Int
    }

    // MARK: Export

    /// A snapshot with the bytes of every readable photo, checked by the same validator a restore uses, so a backup
    /// the app writes is always one it can restore.
    public func prepareBackup(now: Date, appVersion: String) async throws -> Prepared {
        let images = self.images
        let snapshot = try await service.snapshot(now: now, appVersion: appVersion) { reference in
            images?.fileSize(of: reference)
        }
        var media: [String: Data] = [:]
        var manifest: [BackupDTO.MediaEntry] = []
        for entry in snapshot.mediaManifest {
            if let data = try? images?.data(for: entry.reference) {
                media[entry.reference] = data
                manifest.append(BackupDTO.MediaEntry(reference: entry.reference, sizeBytes: data.count))
            }
        }
        var backup = snapshot
        backup.mediaManifest = manifest
        let referenced = snapshot.wishlistItems.compactMap(\.mediaReference).count
        try BackupValidator.validate(backup)
        return Prepared(backup: backup, media: media, unreadablePhotos: referenced - manifest.count)
    }

    // MARK: Restore

    /// Reads a backup folder: `backup.json` first, then only the image files its manifest lists, each within the
    /// size limits and matching its recorded size. Unlisted files in the folder are never read.
    public static func read(folder: URL) throws -> (backup: BackupDTO, media: [String: Data]) {
        let jsonURL = folder.appending(path: BackupPackage.jsonName, directoryHint: .notDirectory)
        guard let jsonSize = fileSize(jsonURL) else { throw BackupError.notABackup }
        guard jsonSize <= maxJSONBytes else { throw BackupError.tooLarge(BackupPackage.jsonName) }
        let backup: BackupDTO
        do {
            backup = try BackupDTO.decoder().decode(BackupDTO.self, from: try Data(contentsOf: jsonURL))
        } catch {
            throw BackupError.notABackup
        }
        var media: [String: Data] = [:]
        for entry in backup.mediaManifest where ImageStore.isValidReference(entry.reference) {
            let url = folder.appending(path: BackupPackage.mediaFolder, directoryHint: .isDirectory)
                .appending(path: entry.reference, directoryHint: .notDirectory)
            guard let size = fileSize(url), size == entry.sizeBytes, size <= maxImageBytes,
                let data = try? Data(contentsOf: url)
            else { continue }
            media[entry.reference] = data
        }
        return (backup, media)
    }

    /// Validates everything, writes the backup's photos, replaces the store in one save, then removes image files
    /// nothing refers to any more. If the store is not replaced, only photos the store did not already use are
    /// removed again, so a failed restore leaves both the data and the photos as they were.
    public func restore(_ backup: BackupDTO, media: [String: Data], now: Date) async throws -> RestoreSummary {
        try BackupValidator.validate(backup)
        let before = try await service.mediaReferences()
        let listed = Set(backup.mediaManifest.map(\.reference))
        var written = Set<String>()
        for (reference, data) in media where listed.contains(reference) {
            if (try? images?.restore(data, as: reference)) != nil {
                written.insert(reference)
            }
        }
        // A photo the backup refers to but whose copy in the folder couldn't be read (an iCloud file not downloaded,
        // a size mismatch) is still usable if this device already has it: references are UUIDs, so it is the same
        // image. Without this, restoring this device's own backup could delete intact photos.
        let referenced = Set(backup.wishlistItems.compactMap(\.mediaReference))
        let onDevice = referenced.subtracting(written).filter { images?.fileSize(of: $0) != nil }
        let available = written.union(onDevice)
        do {
            let summary = try await service.restore(backup, availableMedia: available, now: now)
            let kept = referenced.intersection(available)
            for reference in images?.references(in: .wishlist) ?? [] where !kept.contains(reference) {
                try? images?.delete(reference)
            }
            return summary
        } catch {
            for reference in written where !before.contains(reference) {
                try? images?.delete(reference)
            }
            throw error
        }
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])).flatMap { values in
            values.isRegularFile == true ? values.fileSize : nil
        }
    }
}
