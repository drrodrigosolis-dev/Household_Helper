import Foundation

/// The snapshot file shared with the widget extension. Writes are atomic; reads reject anything oversized, of an
/// unknown version, or undecodable, so a damaged file can only make the widget fall back to the fixture.
public struct WidgetSnapshotStore: Sendable {
    public static let fileName = "widget-snapshot.json"
    /// A snapshot is a few hundred bytes; anything far larger is not ours.
    public static let maxBytes = 64 * 1024

    public let url: URL

    public init(directory: URL) {
        url = directory.appending(path: Self.fileName, directoryHint: .notDirectory)
    }

    /// The store in the App Group container, or nil when no identifier is configured or the system gives no container
    /// (on a device, when the entitlement is missing; the Simulator does not enforce it).
    public static func appGroup(_ identifier: String?) -> WidgetSnapshotStore? {
        guard let identifier, !identifier.isEmpty,
            let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else { return nil }
        return WidgetSnapshotStore(directory: container)
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: url, options: [.atomic])
    }

    public func read() -> WidgetSnapshot? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.maxBytes,
            let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
            snapshot.version == WidgetSnapshot.currentVersion
        else { return nil }
        return snapshot
    }
}
