import Foundation
import SwiftData

/// The only writer of transaction records (spec §4.4). Runs on its own serial executor off the main actor.
@ModelActor
public actor TransactionService {
    public static func make(container: ModelContainer) -> TransactionService {
        TransactionService(modelContainer: container)
    }

    // MARK: Settings

    /// Creates the singleton settings row on first launch; a no-op afterwards.
    public func ensureSettings(currencyCode: String, now: Date) throws {
        guard try settings() == nil else { return }
        let currency = try Currency(code: currencyCode)
        modelContext.insert(AppSettings(currencyCode: currency.code, now: now))
        try modelContext.save()
    }

    public func setStartingBalance(_ balance: Money, asOf date: Date, now: Date) throws {
        let settings = try requireSettings()
        try requireCurrency(balance, settings)
        settings.startingBalanceMinorUnits = balance.minorUnits
        settings.startingBalanceDate = date
        settings.updatedAt = now
        try modelContext.save()
    }

    // MARK: Transactions

    @discardableResult
    public func create(_ draft: TransactionDraft, now: Date) throws -> UUID {
        try draft.validate()
        let settings = try requireSettings()
        try requireCurrency(draft.amount, settings)
        if let categoryID = draft.categoryID {
            try requireUsableCategory(categoryID, for: draft.type)
        }
        let record = TransactionRecord(
            amount: draft.amount, type: draft.type, status: draft.status, source: draft.source,
            occurredAt: draft.occurredAt, now: now)
        record.categoryID = draft.categoryID
        record.notes = draft.notes
        if let name = draft.merchantName, !Merchant.normalize(name).isEmpty {
            let merchant = try findOrCreateMerchant(named: name, now: now)
            record.merchantID = merchant.id
            record.merchantNameSnapshot = name
        }
        modelContext.insert(record)
        try modelContext.save()
        return record.id
    }

    public func setStatus(_ status: TransactionStatus, forTransaction id: UUID, now: Date) throws {
        let record = try requireTransaction(id)
        record.status = status
        record.updatedAt = now
        try modelContext.save()
    }

    /// Deletes one transaction. For a recurring occurrence the caller passes the user's choice from spec §8.3;
    /// deleting an occurrence never disables its series implicitly.
    public func deleteTransaction(_ id: UUID, alsoDisableSeries: Bool, now: Date) throws {
        let record = try requireTransaction(id)
        if alsoDisableSeries, let seriesID = record.recurringSeriesID, let series = try recurringSeries(seriesID) {
            series.isEnabled = false
            series.updatedAt = now
        }
        modelContext.delete(record)
        try modelContext.save()
    }

    // MARK: Recurring

    /// Posts (or records as pending) one occurrence of a series, exactly once (spec §9.4).
    @discardableResult
    public func materialize(
        seriesID: UUID, occurrence: Date, status: TransactionStatus = .posted, now: Date
    ) throws -> UUID {
        guard let series = try recurringSeries(seriesID) else { throw LedgerError.unknownSeries }
        let snapshot = try series.series()
        let probe = DateInterval(start: occurrence, duration: 1)
        guard RecurrenceEngine().occurrences(of: snapshot, in: probe).first == occurrence else {
            throw LedgerError.notAnOccurrence
        }
        let targetSeries: UUID? = seriesID
        let targetOccurrence: Date? = occurrence
        let existing = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate {
                $0.recurringSeriesID == targetSeries && $0.scheduledOccurrence == targetOccurrence
            })
        guard try modelContext.fetchCount(existing) == 0 else { throw LedgerError.alreadyMaterialized }

        let record = TransactionRecord(
            amount: series.templateAmount, type: series.type, status: status, source: .recurring,
            occurredAt: occurrence, now: now)
        record.recurringSeriesID = seriesID
        record.scheduledOccurrence = occurrence
        record.categoryID = series.categoryID
        record.merchantID = series.merchantID
        record.notes = series.notes
        modelContext.insert(record)
        series.nextOccurrence = RecurrenceEngine().nextOccurrence(of: snapshot, after: occurrence)
        series.updatedAt = now
        try modelContext.save()
        return record.id
    }

    // MARK: Balances

    public func balanceSnapshot(
        now: Date, calendar: HouseholdCalendar, includePendingInProjection: Bool, projectionDays: Int = 30
    ) throws -> BalanceSnapshot {
        let settings = try requireSettings()
        let startDate = settings.startingBalanceDate
        let afterStart = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.occurredAt > startDate })
        let lines = try modelContext.fetch(afterStart).map(\.ledgerLine)
        let enabled = FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.isEnabled == true })
        let series = try modelContext.fetch(enabled).map { try $0.series() }
        let starting = Money(minorUnits: settings.startingBalanceMinorUnits, currencyCode: settings.currencyCode)
        return try BalanceCalculator(projectionDays: projectionDays).snapshot(
            startingBalance: starting, startingBalanceDate: startDate, lines: lines, series: series, now: now,
            calendar: calendar, includePendingInProjection: includePendingInProjection)
    }

    // MARK: Lookups

    private func settings() throws -> AppSettings? {
        try modelContext.fetch(FetchDescriptor<AppSettings>()).first
    }

    private func requireSettings() throws -> AppSettings {
        guard let settings = try settings() else { throw LedgerError.settingsMissing }
        return settings
    }

    private func requireCurrency(_ money: Money, _ settings: AppSettings) throws {
        guard money.currencyCode == settings.currencyCode else {
            throw LedgerError.currencyMismatch(expected: settings.currencyCode, actual: money.currencyCode)
        }
    }

    private func requireTransaction(_ id: UUID) throws -> TransactionRecord {
        let descriptor = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try modelContext.fetch(descriptor).first else { throw LedgerError.unknownTransaction }
        return record
    }

    private func recurringSeries(_ id: UUID) throws -> RecurringTransaction? {
        let descriptor = FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    private func requireUsableCategory(_ id: UUID, for type: TransactionType) throws {
        let descriptor = FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id })
        guard let category = try modelContext.fetch(descriptor).first else { throw LedgerError.unknownCategory }
        guard !category.isArchived else { throw LedgerError.archivedCategory }
        guard category.kind.allows(type) else { throw LedgerError.categoryKindMismatch(category.kind, type) }
    }

    private func findOrCreateMerchant(named name: String, now: Date) throws -> Merchant {
        let key = Merchant.normalize(name)
        let descriptor = FetchDescriptor<Merchant>(predicate: #Predicate { $0.normalizedName == key })
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let merchant = Merchant(displayName: name.trimmingCharacters(in: .whitespacesAndNewlines), now: now)
        modelContext.insert(merchant)
        return merchant
    }
}
