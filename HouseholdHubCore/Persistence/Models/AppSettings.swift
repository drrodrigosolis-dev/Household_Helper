import Foundation
import SwiftData

extension SchemaV1 {
    /// Singleton durable configuration included in backups (spec §7.11). Remaining §7.11 fields arrive with the
    /// features that own them.
    @Model
    public final class AppSettings {
        @Attribute(.unique) public var id: UUID
        public var currencyCode: String
        public var onboardingCompleted: Bool
        public var startingBalanceMinorUnits: Int64
        public var startingBalanceDate: Date
        public var createdAt: Date
        public var updatedAt: Date

        public init(id: UUID = UUID(), currencyCode: String, now: Date) {
            self.id = id
            self.currencyCode = currencyCode
            self.onboardingCompleted = false
            self.startingBalanceMinorUnits = 0
            self.startingBalanceDate = now
            self.createdAt = now
            self.updatedAt = now
        }
    }
}

public typealias AppSettings = SchemaV1.AppSettings
