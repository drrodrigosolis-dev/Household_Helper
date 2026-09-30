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
        /// Whether the projected balance adds pending transactions (spec §9.3). Off by default.
        public var includePendingInProjection: Bool = false
        /// The Analytics period last chosen (spec §7.11 `defaultAnalyticsPeriod`), stored as its raw value.
        public var defaultAnalyticsPeriodRawValue: String = AnalyticsPeriod.thisMonth.rawValue
        /// Whether Analytics also counts pending transactions (owner decision 2026-09-26). Off by default.
        public var analyticsIncludesPending: Bool = false
        /// On-device AI switches (spec §7.11, §12). On by default (owner decision 2026-09-26); they only take effect
        /// where Apple Intelligence is available, and each can be turned off.
        public var aiCategorizationEnabled: Bool = true
        public var naturalLanguageEnabled: Bool = true
        public var aiInsightsEnabled: Bool = true
        /// Whether the Home Screen widget shows amounts (spec §7.11). On by default (Sprint 8 default 4).
        public var widgetShowsBalance: Bool = true
        /// Optional Face ID / passcode gate (spec §2.1, §7.11). Device configuration: never written to a backup
        /// (§26.1), and a restore leaves this device's value as it is.
        public var faceIDEnabled: Bool = false
        /// Appearance and Quick Add preferences (spec §7.11), stored as raw values; an unknown value reads as the
        /// default. `accentColorHex` empty means the app's own accent color.
        public var selectedThemeRawValue: String = ThemePreference.system.rawValue
        public var accentColorHex: String = ""
        public var defaultQuickAddTypeRawValue: String = QuickAddType.expense.rawValue
        /// The account new entries go to unless another is picked (Sprint 10 decision 8); onboarding creates it.
        public var defaultAccountID: UUID?
        public var createdAt: Date
        public var updatedAt: Date

        public var selectedTheme: ThemePreference { ThemePreference(rawValue: selectedThemeRawValue) ?? .system }
        public var accentColor: ColorToken? { accentColorHex.isEmpty ? nil : ColorToken(hex: accentColorHex) }
        public var defaultQuickAddType: QuickAddType { QuickAddType(rawValue: defaultQuickAddTypeRawValue) ?? .expense }

        public init(id: UUID = UUID(), currencyCode: String, now: Date) {
            self.id = id
            self.currencyCode = currencyCode
            self.onboardingCompleted = false
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
