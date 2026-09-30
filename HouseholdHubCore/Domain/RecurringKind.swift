import Foundation

/// What a recurring item is (Sprint 22 decision 1). Both kinds project and post the same way; the kind only changes
/// how an item is shown, which merchant its occurrences carry, and whether it gets a "due" reminder.
public enum RecurringKind: String, CaseIterable, Codable, Sendable {
    /// Something owed on a schedule (rent, a phone plan): the behavior before Sprint 22, with a reminder the day
    /// before each occurrence.
    case bill
    /// Something bought on a schedule at a store (groceries every week): always an expense, usually recorded with its
    /// store as the merchant, and no "due" reminder (it's something you do, not something you owe).
    case purchase
}
