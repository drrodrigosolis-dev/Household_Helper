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
        /// Whether the projected balance adds pending transactions (spec §9.3). Off by default.
        public var includePendingInProjection: Bool = false
        /// The Analytics period last chosen (spec §7.11 `defaultAnalyticsPeriod`), stored as its raw value.
        public var defaultAnalyticsPeriodRawValue: String = AnalyticsPeriod.thisMonth.rawValue
        public var createdAt: Date
        public var updatedAt: Date

        public init(id: UUID = UUID(), currencyCode: String, now: Date) {
            self.id = id
            self.currencyCode = currencyCode
            self.onboardingCompleted = false
            self.startingBalanceMinorUnits = 0
            self.startingBalanceDate = now
            self.includePendingInProjection = false
            self.createdAt = now
            self.updatedAt = now
        }

        public var defaultAnalyticsPeriod: AnalyticsPeriod {
            get { AnalyticsPeriod(rawValue: defaultAnalyticsPeriodRawValue) ?? .thisMonth }
            set { defaultAnalyticsPeriodRawValue = newValue.rawValue }
        }
    }
}

public typealias AppSettings = SchemaV1.AppSettings
