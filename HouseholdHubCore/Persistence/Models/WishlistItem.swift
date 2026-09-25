import Foundation
import SwiftData

extension SchemaV1 {
    /// Something the household wants to buy (spec §7.7). A purchase links it both ways to exactly one expense (§8.1).
    @Model
    public final class WishlistItem {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var estimatedPriceMinorUnits: Int64
        public var actualPriceMinorUnits: Int64?
        public var currencyCode: String
        public var priorityRawValue: String
        public var statusRawValue: String
        public var categoryID: UUID?
        public var notes: String?
        /// Relative path under Application Support/Media/Wishlist (spec §5.5); never the image bytes.
        public var mediaReference: String?
        public var linkedTaskID: UUID?
        public var purchasedTransactionID: UUID?
        public var targetDate: Date?
        public var createdAt: Date
        public var updatedAt: Date

        public init(id: UUID = UUID(), name: String, estimatedPrice: Money, priority: Priority, now: Date) {
            self.id = id
            self.name = name
            self.estimatedPriceMinorUnits = estimatedPrice.minorUnits
            self.currencyCode = estimatedPrice.currencyCode
            self.priorityRawValue = priority.rawValue
            self.statusRawValue = WishlistStatus.wanted.rawValue
            self.createdAt = now
            self.updatedAt = now
        }

        public var estimatedPrice: Money {
            Money(minorUnits: estimatedPriceMinorUnits, currencyCode: currencyCode)
        }

        public var actualPrice: Money? {
            actualPriceMinorUnits.map { Money(minorUnits: $0, currencyCode: currencyCode) }
        }

        public var priority: Priority {
            get { Priority(rawValue: priorityRawValue) ?? .medium }
            set { priorityRawValue = newValue.rawValue }
        }

        public var status: WishlistStatus {
            get { WishlistStatus(rawValue: statusRawValue) ?? .wanted }
            set { statusRawValue = newValue.rawValue }
        }
    }
}

public typealias WishlistItem = SchemaV1.WishlistItem
