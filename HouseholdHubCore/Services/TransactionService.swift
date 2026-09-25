import Foundation
import SwiftData
import Synchronization

/// The only writer of transaction records (spec §4.4). Runs on its own serial executor off the main actor.
///
/// Exactly one instance exists per container (`make(container:)`), so every write goes through one serial context:
/// check-then-insert guards such as "not materialized yet" cannot race a second writer in the same process.
@ModelActor
public actor TransactionService {
    // Holds each container for the process lifetime, so ObjectIdentifier keys are never reused.
    private static let instances = Mutex<[ObjectIdentifier: TransactionService]>([:])

    public static func make(container: ModelContainer) -> TransactionService {
        instances.withLock { cache in
            if let existing = cache[ObjectIdentifier(container)] {
                return existing
            }
            let service = TransactionService(modelContainer: container)
            cache[ObjectIdentifier(container)] = service
            return service
        }
    }

    // MARK: Settings

    /// Creates the singleton settings row on first launch; a no-op afterwards.
    public func ensureSettings(currencyCode: String, now: Date) throws {
        guard try settings() == nil else { return }
        let currency = try Currency(code: currencyCode)
        modelContext.insert(AppSettings(currencyCode: currency.code, now: now))
        try commit()
    }

    public func settingsSnapshot() throws -> SettingsSnapshot? {
        guard let settings = try settings() else { return nil }
        let balance = Money(minorUnits: settings.startingBalanceMinorUnits, currencyCode: settings.currencyCode)
        return SettingsSnapshot(
            currencyCode: settings.currencyCode, onboardingCompleted: settings.onboardingCompleted,
            startingBalance: balance, startingBalanceDate: settings.startingBalanceDate,
            includePendingInProjection: settings.includePendingInProjection)
    }

    /// First-launch setup. The currency may change only while no transactions or series exist (spec §6.3).
    public func completeOnboarding(currencyCode: String, startingBalance: Money, asOf date: Date, now: Date) throws {
        let currency = try Currency(code: currencyCode)
        guard startingBalance.currencyCode == currency.code else {
            throw LedgerError.currencyMismatch(expected: currency.code, actual: startingBalance.currencyCode)
        }
        guard date <= now else { throw LedgerError.startingBalanceInFuture }
        try ensureSettings(currencyCode: currency.code, now: now)
        let settings = try requireSettings()
        if settings.currencyCode != currency.code {
            let records = try modelContext.fetchCount(FetchDescriptor<TransactionRecord>())
            let series = try modelContext.fetchCount(FetchDescriptor<RecurringTransaction>())
            guard records + series == 0 else { throw LedgerError.currencyLockedByExistingRecords }
            settings.currencyCode = currency.code
        }
        settings.startingBalanceMinorUnits = startingBalance.minorUnits
        settings.startingBalanceDate = date
        settings.onboardingCompleted = true
        settings.updatedAt = now
        try commit()
    }

    public func setIncludePendingInProjection(_ include: Bool, now: Date) throws {
        let settings = try requireSettings()
        settings.includePendingInProjection = include
        settings.updatedAt = now
        try commit()
    }

    public func setStartingBalance(_ balance: Money, asOf date: Date, now: Date) throws {
        let settings = try requireSettings()
        try requireCurrency(balance, settings)
        guard date <= now else { throw LedgerError.startingBalanceInFuture }
        settings.startingBalanceMinorUnits = balance.minorUnits
        settings.startingBalanceDate = date
        settings.updatedAt = now
        try commit()
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
        try commit()
        return record.id
    }

    /// Replaces the user-editable fields of an existing transaction. Provenance (source, recurring link) is kept.
    public func update(_ id: UUID, with draft: TransactionDraft, now: Date) throws {
        let record = try requireTransaction(id)
        var checked = draft
        checked.source = .manual
        try checked.validate()
        let settings = try requireSettings()
        try requireCurrency(draft.amount, settings)
        if let categoryID = draft.categoryID {
            try requireUsableCategory(categoryID, for: draft.type)
        }
        var merchantID: UUID?
        let name = draft.merchantName.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if !Merchant.normalize(name).isEmpty {
            merchantID = try findOrCreateMerchant(named: name, now: now).id
        }
        record.amountMinorUnits = draft.amount.minorUnits
        record.currencyCode = draft.amount.currencyCode
        record.type = draft.type
        record.status = draft.status
        record.occurredAt = draft.occurredAt
        record.categoryID = draft.categoryID
        record.notes = draft.notes
        record.merchantID = merchantID
        record.merchantNameSnapshot = merchantID == nil ? nil : name
        record.updatedAt = now
        try commit()
    }

    public func setStatus(_ status: TransactionStatus, forTransaction id: UUID, now: Date) throws {
        let record = try requireTransaction(id)
        record.status = status
        record.updatedAt = now
        try commit()
    }

    /// Deletes one transaction, carrying out the user's choice from spec §8.3. A recurring occurrence is kept as a
    /// cancelled record instead of being erased, so the occurrence stays "handled": it neither reappears in the
    /// projection nor can be posted again. Deleting an occurrence disables its series only when asked.
    public func deleteTransaction(_ id: UUID, alsoDisableSeries: Bool, now: Date) throws {
        let record = try requireTransaction(id)
        let series = try record.recurringSeriesID.flatMap { try recurringSeries($0) }
        if alsoDisableSeries, let series {
            series.isEnabled = false
            series.updatedAt = now
        }
        if record.recurringSeriesID != nil, record.scheduledOccurrence != nil {
            record.status = .cancelled
            record.updatedAt = now
        } else {
            modelContext.delete(record)
        }
        try commit()
    }

    // MARK: Recurring

    /// Creates a validated recurring series (positive template, household currency, usable category of the right
    /// kind). Series are definitions only; no transactions are generated (spec §9.4).
    @discardableResult
    public func createSeries(
        templateAmount: Money, type: TransactionType, rule: RecurrenceRule, timeZone: TimeZone, startDate: Date,
        endDate: Date? = nil, categoryID: UUID? = nil, notes: String? = nil, now: Date
    ) throws -> UUID {
        guard templateAmount.minorUnits > 0 else { throw LedgerError.nonPositiveAmount }
        guard type != .transfer else { throw LedgerError.transfersUnavailable }
        let settings = try requireSettings()
        try requireCurrency(templateAmount, settings)
        if let categoryID {
            try requireUsableCategory(categoryID, for: type)
        }
        let series = try RecurringTransaction(
            templateAmount: templateAmount, type: type, rule: rule, timeZone: timeZone, startDate: startDate,
            endDate: endDate, now: now)
        series.categoryID = categoryID
        series.notes = notes
        let snapshot = try series.series()
        // `nextOccurrence(after:)` is strict, so step back one second to include the start itself.
        series.nextOccurrence = RecurrenceEngine().nextOccurrence(of: snapshot, after: startDate.addingTimeInterval(-1))
        modelContext.insert(series)
        try commit()
        return series.id
    }

    /// Posts (or records as pending) one occurrence of a series, exactly once (spec §9.4).
    @discardableResult
    public func materialize(
        seriesID: UUID, occurrence: Date, status: TransactionStatus = .posted, now: Date
    ) throws -> UUID {
        guard let series = try recurringSeries(seriesID) else { throw LedgerError.unknownSeries }
        let snapshot = try series.series()
        guard snapshot.templateAmount.minorUnits > 0 else { throw LedgerError.nonPositiveAmount }
        let settings = try requireSettings()
        try requireCurrency(snapshot.templateAmount, settings)
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
            amount: snapshot.templateAmount, type: snapshot.type, status: status, source: .recurring,
            occurredAt: occurrence, now: now)
        record.recurringSeriesID = seriesID
        record.scheduledOccurrence = occurrence
        record.categoryID = series.categoryID
        record.merchantID = series.merchantID
        record.notes = series.notes
        modelContext.insert(record)
        series.nextOccurrence = RecurrenceEngine().nextOccurrence(of: snapshot, after: occurrence)
        series.updatedAt = now
        try commit()
        return record.id
    }

    // MARK: Balances

    public func balanceSnapshot(
        now: Date, calendar: HouseholdCalendar, includePendingInProjection: Bool, projectionDays: Int = 30
    ) throws -> BalanceSnapshot {
        let settings = try requireSettings()
        let startDate = settings.startingBalanceDate
        let afterStart = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.occurredAt > startDate })
        let lines = try modelContext.fetch(afterStart).map { try $0.ledgerLine() }
        let enabled = FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.isEnabled == true })
        let series = try modelContext.fetch(enabled).map { try $0.series() }
        let starting = Money(minorUnits: settings.startingBalanceMinorUnits, currencyCode: settings.currencyCode)
        return try BalanceCalculator(projectionDays: projectionDays).snapshot(
            startingBalance: starting, startingBalanceDate: startDate, lines: lines, series: series, now: now,
            calendar: calendar, includePendingInProjection: includePendingInProjection)
    }

    // MARK: Persistence

    /// Saves, or discards every pending edit if the save fails, so no later save can persist a failed operation.
    private func commit() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: Lookups

    private func settings() throws -> AppSettings? {
        var descriptor = FetchDescriptor<AppSettings>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
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
