import Foundation
import HouseholdHubCore
import Testing

@testable import HouseholdHub

/// Sprint 23 F2: the Recurring screen's suggestions. Detection can't be seeded through the UI (Quick Add dates reach
/// back six days at most, and there is no fixture launch argument), so the screen's model is covered here: what is
/// shown, the row text, and dismissals remembered per merchant and type on this device.
@MainActor
struct RecurringSuggestionsModelTests {
    private func suggestion(
        _ name: String, type: TransactionType = .expense, kind: RecurringKind = .bill,
        cadence: RecurringCadence = .monthly
    ) -> RecurringSuggestion {
        RecurringSuggestion(
            id: "\(type.rawValue)|name:\(name.lowercased())", merchantName: name, merchantID: nil, type: type,
            kind: kind, amount: Money(minorUnits: 1_799, currencyCode: "CAD"), cadence: cadence,
            rule: .monthlyOnDay(day: 15), nextDate: .now, occurrenceCount: 3, lastDate: .now, categoryID: nil,
            accountID: nil)
    }

    /// A private defaults suite per test, so nothing touches the app's own settings.
    private func freshDefaults() throws -> UserDefaults {
        let name = "RecurringSuggestionsModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func dismissingHidesASuggestionAndIsRememberedOnThisDevice() throws {
        let defaults = try freshDefaults()
        let model = RecurringSuggestionsModel(defaults: defaults)
        let streaming = suggestion("Streaming Co")
        let gym = suggestion("Gym")
        model.show([streaming, gym])
        #expect(model.visible == [streaming, gym])
        model.dismiss(streaming)
        #expect(model.visible == [gym])
        #expect(defaults.stringArray(forKey: RecurringSuggestionsModel.dismissedKey) == [streaming.id])

        let reopened = RecurringSuggestionsModel(defaults: defaults)
        reopened.show([streaming, gym])
        #expect(reopened.visible == [gym], "A dismissal survives leaving the screen")
    }

    @Test func dismissingAnExpenseKeepsIncomeFromTheSameMerchant() throws {
        let model = RecurringSuggestionsModel(defaults: try freshDefaults())
        let spent = suggestion("Market")
        let earned = suggestion("Market", type: .income)
        model.show([spent, earned])
        model.dismiss(spent)
        #expect(model.visible == [earned])
    }

    @Test func rowTextNamesTheMerchantCadenceAndQuestion() {
        let bill = RecurringSuggestionsModel.text(for: suggestion("Streaming Co"))
        #expect(bill.hasPrefix("Streaming Co · about monthly · "))
        #expect(bill.hasSuffix(" — Make it a bill?"))
        let groceries = RecurringSuggestionsModel.text(
            for: suggestion("FreshMart", kind: .purchase, cadence: .weekly))
        #expect(groceries.hasPrefix("FreshMart · about weekly · "))
        #expect(groceries.hasSuffix("Make it a recurring purchase?"))
        let pay = RecurringSuggestionsModel.text(for: suggestion("Acme", type: .income, cadence: .biweekly))
        #expect(pay.contains("about every two weeks"))
        #expect(pay.hasSuffix("Make it recurring income?"))
    }
}
