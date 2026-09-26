import Foundation
import SwiftData

extension SchemaV1 {
    /// Normalized merchant used for consistent category suggestions (spec §7.4).
    @Model
    public final class Merchant {
        @Attribute(.unique) public var id: UUID
        public var displayName: String
        /// Not `.unique`: SwiftData treats a unique clash as an upsert that silently replaces the existing row.
        public var normalizedName: String
        public var defaultCategoryID: UUID?
        public var createdAt: Date
        public var updatedAt: Date

        public init(id: UUID = UUID(), displayName: String, now: Date) {
            self.id = id
            self.displayName = displayName
            self.normalizedName = Merchant.normalize(displayName)
            self.createdAt = now
            self.updatedAt = now
        }

        /// Case-, diacritic- and whitespace-insensitive key: "  Café  Luna " → "cafe luna".
        public static func normalize(_ name: String) -> String {
            name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
        }
    }
}

public typealias Merchant = SchemaV1.Merchant
