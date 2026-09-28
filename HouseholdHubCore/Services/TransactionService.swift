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

    /// The language the first account is named in when the data is first set up (Sprint 16).
    var seedLanguage = SeedLanguage.english

    public func setSeedLanguage(_ language: SeedLanguage) {
        seedLanguage = language
    }

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
        begin()
        guard try insertSettingsIfMissing(currencyCode: currencyCode, now: now) else { return }
        try commit()
    }

    /// Inserts the settings row if there is none, with the first account ("Main account", Sprint 10 decision 2) as
    /// the default, without saving; returns whether it inserted one.
    private func insertSettingsIfMissing(currencyCode: String, now: Date) throws -> Bool {
        guard try settings() == nil else { return false }
        let currency = try Currency(code: currencyCode)
        let settings = AppSettings(currencyCode: currency.code, now: now)
        modelContext.insert(settings)
        settings.defaultAccountID = try insertMainAccount(currencyCode: currency.code, now: now).id
        return true
    }

    public func settingsSnapshot() throws -> SettingsSnapshot? {
        guard let settings = try settings() else { return nil }
        let main = try defaultAccount(settings)
        return SettingsSnapshot(
            currencyCode: settings.currencyCode, onboardingCompleted: settings.onboardingCompleted,
            startingBalance: main?.startingBalance ?? .zero(settings.currencyCode),
            startingBalanceDate: main?.startingBalanceDate ?? settings.createdAt,
            includePendingInProjection: settings.includePendingInProjection, defaultAccountID: main?.id)
    }

    /// Whether the optional Face ID lock is on; entry points outside the app (Shortcuts) must honor it too.
    public func isLockEnabled() throws -> Bool {
        try settings()?.faceIDEnabled == true
    }

    /// First-launch setup. The currency may change only while no transactions or series exist (spec §6.3).
    public func completeOnboarding(currencyCode: String, startingBalance: Money, asOf date: Date, now: Date) throws {
        begin()
        let currency = try Currency(code: currencyCode)
        guard startingBalance.currencyCode == currency.code else {
            throw LedgerError.currencyMismatch(expected: currency.code, actual: startingBalance.currencyCode)
        }
        guard date <= now else { throw LedgerError.startingBalanceInFuture }
        // Same save as the rest of onboarding: a refused currency change leaves no half-created settings row.
        _ = try insertSettingsIfMissing(currencyCode: currency.code, now: now)
        let settings = try requireSettings()
        try applyHousehold(currency: currency, startingBalance: startingBalance, asOf: date, to: settings, now: now)
        settings.onboardingCompleted = true
        try commit()
    }

    /// Settings › Household: corrects the default account's starting balance and date (§9.1, a baseline, so no
    /// transaction changes),
    /// and the currency only while nothing has been recorded (§6.3: never reinterpret historic values; v1 has one
    /// currency, so with records the answer is a new data set, not a conversion).
    public func updateHousehold(currencyCode: String, startingBalance: Money, asOf date: Date, now: Date) throws {
        begin()
        let currency = try Currency(code: currencyCode)
        guard startingBalance.currencyCode == currency.code else {
            throw LedgerError.currencyMismatch(expected: currency.code, actual: startingBalance.currencyCode)
        }
        guard date <= now else { throw LedgerError.startingBalanceInFuture }
        let settings = try requireSettings()
        try applyHousehold(currency: currency, startingBalance: startingBalance, asOf: date, to: settings, now: now)
        try commit()
    }

    /// True once any transaction, recurring series, or wishlist item exists, or a second account: amounts are then
    /// stored in the household currency, so it can no longer change (§6.3). Settings › Household re-enters only the
    /// default account's baseline, so another account's baseline would be relabelled, not converted.
    public func isCurrencyLocked() throws -> Bool {
        let records = try modelContext.fetchCount(FetchDescriptor<TransactionRecord>())
        let series = try modelContext.fetchCount(FetchDescriptor<RecurringTransaction>())
        let wishes = try modelContext.fetchCount(FetchDescriptor<WishlistItem>())
        let accounts = try modelContext.fetchCount(FetchDescriptor<Account>())
        let budgets = try modelContext.fetchCount(FetchDescriptor<CategoryBudget>())
        let goals = try modelContext.fetchCount(FetchDescriptor<SavingsGoal>())
        return records + series + wishes + budgets + goals > 0 || accounts > 1
    }

    private func applyHousehold(
        currency: Currency, startingBalance: Money, asOf date: Date, to settings: AppSettings, now: Date
    ) throws {
        if settings.currencyCode != currency.code {
            guard try !isCurrencyLocked() else { throw LedgerError.currencyLockedByExistingRecords }
            settings.currencyCode = currency.code
            // Every account uses the household currency (Sprint 10 decision 3); with nothing recorded, their
            // baselines are the only amounts, and they follow.
            for account in try modelContext.fetch(FetchDescriptor<Account>()) {
                account.currencyCode = currency.code
                account.updatedAt = now
            }
        }
        let main = try requireDefaultAccount(settings, now: now)
        main.startingBalanceMinorUnits = startingBalance.minorUnits
        main.startingBalanceDate = date
        main.updatedAt = now
        settings.updatedAt = now
    }

    public func setIncludePendingInProjection(_ include: Bool, now: Date) throws {
        begin()
        let settings = try requireSettings()
        settings.includePendingInProjection = include
        settings.updatedAt = now
        try commit()
    }

    public func setDefaultAnalyticsPeriod(_ period: AnalyticsPeriod, now: Date) throws {
        begin()
        let settings = try requireSettings()
        guard settings.defaultAnalyticsPeriod != period else { return }
        settings.defaultAnalyticsPeriod = period
        settings.updatedAt = now
        try commit()
    }

    /// Appearance (spec §7.11). A nil accent means the app's own accent color.
    public func setAppearance(theme: ThemePreference, accent: ColorToken?, now: Date) throws {
        begin()
        let settings = try requireSettings()
        settings.selectedThemeRawValue = theme.rawValue
        settings.accentColorHex = accent?.hex ?? ""
        settings.updatedAt = now
        try commit()
    }

    public func setAnalyticsIncludesPending(_ include: Bool, now: Date) throws {
        begin()
        let settings = try requireSettings()
        settings.analyticsIncludesPending = include
        settings.updatedAt = now
        try commit()
    }

    public func setDefaultQuickAddType(_ type: QuickAddType, now: Date) throws {
        begin()
        let settings = try requireSettings()
        settings.defaultQuickAddTypeRawValue = type.rawValue
        settings.updatedAt = now
        try commit()
    }

    public func setFaceIDEnabled(_ enabled: Bool, now: Date) throws {
        begin()
        let settings = try requireSettings()
        settings.faceIDEnabled = enabled
        settings.updatedAt = now
        try commit()
    }

    public func setWidgetShowsBalance(_ shows: Bool, now: Date) throws {
        begin()
        let settings = try requireSettings()
        settings.widgetShowsBalance = shows
        settings.updatedAt = now
        try commit()
    }

    public enum AISwitch: Sendable {
        case categorization
        case naturalLanguage
        case insights
    }

    public func setAI(_ feature: AISwitch, enabled: Bool, now: Date) throws {
        begin()
        let settings = try requireSettings()
        switch feature {
        case .categorization: settings.aiCategorizationEnabled = enabled
        case .naturalLanguage: settings.naturalLanguageEnabled = enabled
        case .insights: settings.aiInsightsEnabled = enabled
        }
        settings.updatedAt = now
        try commit()
    }

    /// Deterministic category suggestion (Sprint 7 default 2): the category the user last filed the merchant that
    /// `text` names under (its learned default, Sprint 23), else the one most often used with it, ties broken by the
    /// most recent use; only an active category of the right kind is returned. The learned default is read exactly as
    /// the import preview reads it (`learnedCategories`), so Quick Add and an import offer the same category.
    public func suggestedCategory(forMerchantText text: String, type: TransactionType) throws -> UUID? {
        let key = Merchant.normalize(text)
        guard !key.isEmpty else { return nil }
        let merchants = FetchDescriptor<Merchant>(
            predicate: #Predicate { $0.normalizedName == key }, sortBy: [SortDescriptor(\.createdAt)])
        guard let merchant = try modelContext.fetch(merchants).first else { return nil }
        let usable = Set(
            try modelContext.fetch(FetchDescriptor<CategoryRecord>()).filter { !$0.isArchived && $0.kind.allows(type) }
                .map(\.id))
        if let learned = try learnedCategories(for: [key], usable: usable)[key] {
            return learned
        }
        let merchantID: UUID? = merchant.id
        let typeRaw = type.rawValue
        let history = try modelContext.fetch(
            FetchDescriptor<TransactionRecord>(
                predicate: #Predicate { $0.merchantID == merchantID && $0.typeRawValue == typeRaw }))
        var uses: [UUID: (count: Int, latest: Date)] = [:]
        for record in history {
            guard let categoryID = record.categoryID, usable.contains(categoryID) else { continue }
            let current = uses[categoryID] ?? (0, .distantPast)
            uses[categoryID] = (current.count + 1, max(current.latest, record.occurredAt))
        }
        return uses.max { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            if lhs.value.latest != rhs.value.latest { return lhs.value.latest < rhs.value.latest }
            return lhs.key.uuidString > rhs.key.uuidString
        }?.key
    }

    public func setStartingBalance(_ balance: Money, asOf date: Date, now: Date) throws {
        begin()
        let settings = try requireSettings()
        try requireCurrency(balance, settings)
        guard date <= now else { throw LedgerError.startingBalanceInFuture }
        let main = try requireDefaultAccount(settings, now: now)
        main.startingBalanceMinorUnits = balance.minorUnits
        main.startingBalanceDate = date
        main.updatedAt = now
        try commit()
    }

    // MARK: Transactions

    @discardableResult
    public func create(_ draft: TransactionDraft, now: Date) throws -> UUID {
        begin()
        try draft.validate()
        let settings = try requireSettings()
        try requireCurrency(draft.amount, settings)
        if let categoryID = draft.categoryID {
            try requireUsableCategory(categoryID, for: draft.type)
        }
        let learned = try learnableCategory(draft.categoryID, type: draft.type, isAIClassified: draft.isAIClassified)
        let accounts = try resolveAccounts(draft, settings: settings, current: nil, now: now)
        let record = TransactionRecord(
            amount: draft.amount, type: draft.type, status: draft.status, source: draft.source,
            occurredAt: draft.occurredAt, now: now)
        record.accountID = accounts.source
        record.transferAccountID = accounts.destination
        record.categoryID = draft.categoryID
        record.isAIClassified = draft.categoryID != nil && draft.isAIClassified
        record.notes = draft.notes
        if let name = draft.merchantName, !Merchant.normalize(name).isEmpty {
            let merchant = try findOrCreateMerchant(named: name, now: now)
            record.merchantID = merchant.id
            record.merchantNameSnapshot = name
            learn(learned, for: merchant, now: now)
        }
        modelContext.insert(record)
        try commit()
        return record.id
    }

    /// Replaces the user-editable fields of an existing transaction. Provenance (source, recurring link) is kept.
    public func update(_ id: UUID, with draft: TransactionDraft, now: Date) throws {
        begin()
        let record = try requireTransaction(id)
        // A refund is edited with `updateRefund`, which keeps it tied to its purchase (Sprint 20).
        guard record.type != .refund else { throw LedgerError.refundNeedsPurchase }
        try requirePurchaseInvariant(record, type: draft.type, status: draft.status)
        var checked = draft
        checked.source = .manual
        try checked.validate()
        let settings = try requireSettings()
        try requireCurrency(draft.amount, settings)
        if let categoryID = draft.categoryID {
            // A category archived after this record was filed stays valid for the record; new use is refused.
            try requireUsableCategory(categoryID, for: draft.type, allowArchived: categoryID == record.categoryID)
        }
        let accounts = try resolveAccounts(
            draft, settings: settings, current: (record.accountID, record.transferAccountID), now: now)
        try requireRefundsStillFit(
            record, type: draft.type, status: draft.status, amount: draft.amount, accountID: accounts.source,
            occurredAt: draft.occurredAt)
        // The parts of a split are one payment (Sprint 23): they take this part's status, date, account and merchant.
        let otherParts = try splitSiblings(of: record)
        try requireSplitEdit(
            record, siblings: otherParts, type: draft.type, status: draft.status, accountID: accounts.source,
            occurredAt: draft.occurredAt)
        // Fetched before the first edit (the merchant insert below), so a failed fetch leaves nothing pending.
        let linkedItem = try record.wishlistItemID.flatMap { try wishlistItem($0) }
        let refundRecords = try allRefunds(of: record)
        // Each other part's refunds follow that part's merchant, which this edit may change (Sprint 23 review B1).
        let otherPartRefunds = try otherParts.map { ($0, try allRefunds(of: $0)) }
        let keepsCategory = draft.categoryID == record.categoryID
        let isAIClassified = keepsCategory ? record.isAIClassified : draft.isAIClassified
        let learned = try learnableCategory(draft.categoryID, type: draft.type, isAIClassified: isAIClassified)
        var merchant: Merchant?
        let name = draft.merchantName.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if !Merchant.normalize(name).isEmpty {
            // The same name keeps the record's own merchant: names aren't unique, so looking it up again could pick
            // another one with the same name (Sprint 23 review S1; bulk Set category re-saves many rows).
            let current = try record.merchantID.flatMap { id in
                try modelContext.fetch(FetchDescriptor<Merchant>(predicate: #Predicate { $0.id == id })).first
            }
            if let current, current.normalizedName == Merchant.normalize(name) {
                merchant = current
            } else {
                merchant = try findOrCreateMerchant(named: name, now: now)
            }
        }
        let merchantID = merchant?.id
        // Only a new pairing teaches the merchant: an edit to the amount or date alone doesn't bring an older
        // category back over one learned since.
        if let merchant, !keepsCategory || merchantID != record.merchantID {
            learn(learned, for: merchant, now: now)
        }
        record.amountMinorUnits = draft.amount.minorUnits
        record.currencyCode = draft.amount.currencyCode
        record.type = draft.type
        record.status = draft.status
        record.occurredAt = draft.occurredAt
        record.accountID = accounts.source
        record.transferAccountID = accounts.destination
        if draft.categoryID == nil {
            record.isAIClassified = false
        } else if draft.categoryID != record.categoryID {
            record.isAIClassified = draft.isAIClassified
        }
        record.categoryID = draft.categoryID
        record.notes = draft.notes
        record.merchantID = merchantID
        record.merchantNameSnapshot = merchantID == nil ? nil : name
        record.updatedAt = now
        carryClassification(of: record, to: refundRecords, now: now)
        shareSplit(from: record, to: otherParts, now: now)
        for (part, refunds) in otherPartRefunds {
            carryClassification(of: part, to: refunds, now: now)
        }
        // A purchase's item records the price actually paid; keep it in step with the edited transaction.
        if let item = linkedItem, item.purchasedTransactionID == id {
            item.actualPriceMinorUnits = draft.amount.minorUnits
            item.updatedAt = now
        }
        try commit()
    }

    public func setStatus(_ status: TransactionStatus, forTransaction id: UUID, now: Date) throws {
        begin()
        let record = try requireTransaction(id)
        try requirePurchaseInvariant(record, type: record.type, status: status)
        try requireRefundsStillFit(
            record, type: record.type, status: status, amount: record.amount, accountID: record.accountID,
            occurredAt: record.occurredAt)
        if record.type == .refund, status != .cancelled {
            try requireRefundFits(record, status: status)
        }
        // Every part of a split takes the new status (Sprint 23).
        let otherParts = try splitSiblings(of: record)
        try requireSplitEdit(
            record, siblings: otherParts, type: record.type, status: status, accountID: record.accountID,
            occurredAt: record.occurredAt)
        // Parts stored out of step would take this part's merchant too; their refunds follow it (review B1).
        let otherPartRefunds = try otherParts.map { ($0, try allRefunds(of: $0)) }
        record.status = status
        record.updatedAt = now
        shareSplit(from: record, to: otherParts, now: now)
        for (part, refunds) in otherPartRefunds {
            carryClassification(of: part, to: refunds, now: now)
        }
        try commit()
    }

    /// Deletes one transaction, carrying out the user's choice from spec §8.3. A recurring occurrence is kept as a
    /// cancelled record instead of being erased, so the occurrence stays "handled": it neither reappears in the
    /// projection nor can be posted again. Deleting an occurrence disables its series only when asked.
    public func deleteTransaction(_ id: UUID, alsoDisableSeries: Bool, now: Date) throws {
        begin()
        let record = try requireTransaction(id)
        // Its refunds depend on it (Sprint 20); they are deleted first, one by one, each confirmed.
        guard try !hasAnyRefund(record) else { throw LedgerError.purchaseHasRefunds }
        let series = try record.recurringSeriesID.flatMap { try recurringSeries($0) }
        // Fetched before the first edit. A deleted transaction must not leave a task pointing at it: a dangling id
        // would make every later backup fail validation.
        let target: UUID? = id
        let linkedTasks = try modelContext.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { $0.linkedTransactionID == target }))
        let otherParts = try splitSiblings(of: record)
        if alsoDisableSeries, let series {
            series.isEnabled = false
            series.updatedAt = now
        }
        if record.recurringSeriesID != nil, record.scheduledOccurrence != nil {
            record.status = .cancelled
            record.updatedAt = now
        } else {
            try revertPurchase(linkedTo: record, now: now)
            for task in linkedTasks {
                task.linkedTransactionID = nil
                task.updatedAt = now
            }
            // The last part left of a split is no longer split (Sprint 23).
            leaveSplit(siblings: otherParts, now: now)
            modelContext.delete(record)
        }
        try commit()
    }

    // MARK: Recurring

    /// Creates a validated recurring series (positive template, household currency, usable category of the right
    /// kind, usable accounts; a recurring transfer names two accounts and no store). Series are definitions only; no
    /// transactions are generated (spec §9.4). A purchase (Sprint 22) is an expense, usually at a store
    /// (`merchantName`), which each posted occurrence records as its merchant.
    @discardableResult
    public func createSeries(
        templateAmount: Money, type: TransactionType, rule: RecurrenceRule, timeZone: TimeZone, startDate: Date,
        endDate: Date? = nil, categoryID: UUID? = nil, notes: String? = nil, accountID: UUID? = nil,
        transferAccountID: UUID? = nil, kind: RecurringKind = .bill, merchantName: String? = nil, now: Date
    ) throws -> UUID {
        begin()
        guard kind == .bill || type == .expense else { throw LedgerError.purchaseMustBeExpense }
        let store = Self.storeName(merchantName)
        let template = TransactionDraft(
            amount: templateAmount, type: type, occurredAt: startDate, categoryID: categoryID, merchantName: store,
            accountID: accountID, transferAccountID: transferAccountID)
        try template.validate()
        let settings = try requireSettings()
        try requireCurrency(templateAmount, settings)
        if let categoryID {
            try requireUsableCategory(categoryID, for: type)
        }
        let accounts = try resolveAccounts(template, settings: settings, current: nil, now: now)
        let series = try RecurringTransaction(
            templateAmount: templateAmount, type: type, rule: rule, timeZone: timeZone, startDate: startDate,
            endDate: endDate, now: now)
        series.accountID = accounts.source
        series.transferAccountID = accounts.destination
        series.categoryID = categoryID
        series.notes = notes
        series.kind = kind
        if let store {
            series.merchantID = try findOrCreateMerchant(named: store, now: now).id
        }
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
        begin()
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
        // A series stored before accounts existed posts to the default account. An occurrence is a new entry, so
        // an account archived since is refused (Sprint 10 decision 4): the series is edited to another first.
        let source = try series.accountID ?? requireDefaultAccount(settings, now: now).id
        try requireUsableAccount(source)
        if let destination = series.transferAccountID {
            try requireUsableAccount(destination)
        }
        record.accountID = source
        record.transferAccountID = series.transferAccountID
        record.categoryID = series.categoryID
        record.merchantID = series.merchantID
        // The store's name as it is now, kept on the record like a typed-in merchant (spec §7.4).
        if let merchantID = series.merchantID {
            record.merchantNameSnapshot = try merchant(merchantID)?.displayName
        }
        record.notes = series.notes
        modelContext.insert(record)
        series.nextOccurrence = RecurrenceEngine().nextOccurrence(of: snapshot, after: occurrence)
        series.updatedAt = now
        try commit()
        return record.id
    }

    // MARK: Balances

    /// The household's figures: the sums over every account (Sprint 10), archived ones included since their money
    /// still exists.
    public func balanceSnapshot(
        now: Date, calendar: HouseholdCalendar, includePendingInProjection: Bool, projectionDays: Int = 30
    ) throws -> BalanceSnapshot {
        try balances(
            now: now, calendar: calendar, includePendingInProjection: includePendingInProjection,
            projectionDays: projectionDays
        ).household
    }

    /// Every account's figures and the household's (Sprint 10 decision 1).
    public func balances(
        now: Date, calendar: HouseholdCalendar, includePendingInProjection: Bool, projectionDays: Int = 30
    ) throws -> HouseholdBalances {
        let settings = try requireSettings()
        let accounts = try modelContext.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))
            .map { try $0.baseline() }
        let earliest = accounts.map(\.startingBalanceDate).min() ?? now
        let afterStart = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.occurredAt > earliest })
        var lines = try modelContext.fetch(afterStart).map { try $0.ledgerLine() }
        // Occurrences already handled whose record is dated before every baseline (a date edited back) still count
        // as handled, so they are never projected again. Their dates keep them out of every account's figures.
        let windowStart = calendar.startOfDay(for: now)
        let handledEarly = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate {
                $0.occurredAt <= earliest && $0.recurringSeriesID != nil
                    && ($0.scheduledOccurrence ?? windowStart) > windowStart
            })
        lines += try modelContext.fetch(handledEarly).map { try $0.ledgerLine() }
        let enabled = FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.isEnabled == true })
        let series = try modelContext.fetch(enabled).map { try $0.series() }
        return try BalanceCalculator(projectionDays: projectionDays).balances(
            accounts: accounts, lines: lines, series: series, now: now, calendar: calendar,
            includePendingInProjection: includePendingInProjection, currencyCode: settings.currencyCode)
    }

    /// What the Home Screen widget shows: the Dashboard's figures, without amounts when the user hid them or turned
    /// on the Face ID lock (a locked app must not show its balances on the Home Screen).
    public func widgetSnapshot(now: Date, calendar: HouseholdCalendar) throws -> WidgetSnapshot {
        let settings = try requireSettings()
        let showAmounts = settings.widgetShowsBalance && !settings.faceIDEnabled
        return WidgetSnapshot.make(
            from: try dashboardSummary(now: now, calendar: calendar), showAmounts: showAmounts, now: now,
            calendar: calendar)
    }

    public func dashboardSummary(now: Date, calendar: HouseholdCalendar, days: Int = 7) throws -> DashboardSummary {
        let settings = try requireSettings()
        let all = try balances(
            now: now, calendar: calendar, includePendingInProjection: settings.includePendingInProjection)
        let balance = all.household

        let weekStart = calendar.startOfWeek(for: now)
        let expense = TransactionType.expense.rawValue
        let refund = TransactionType.refund.rawValue
        let posted = TransactionStatus.posted.rawValue
        let thisWeek = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate {
                $0.occurredAt >= weekStart && $0.occurredAt <= now
                    && ($0.typeRawValue == expense || $0.typeRawValue == refund) && $0.statusRawValue == posted
            })
        // Refunds this week count against this week's spending (Sprint 20), never below zero.
        let weekLines = try modelContext.fetch(thisWeek).map { record in
            let line = try record.ledgerLine()
            return line.type == .refund ? try line.amount.negated() : line.amount
        }
        let netSpent = try Money.sum(weekLines, currencyCode: settings.currencyCode)
        let spent = netSpent.minorUnits < 0 ? .zero(settings.currencyCode) : netSpent

        let upcoming = try upcomingOccurrences(now: now, calendar: calendar, days: days)
        return DashboardSummary(balance: balance, spentThisWeek: spent, upcoming: upcoming, accounts: all.accounts)
    }

    /// Recurring occurrences from the start of today through the next `days` days that have not been recorded yet,
    /// soonest first (the Dashboard's Upcoming card; Sprint 14 bill reminders).
    public func upcomingOccurrences(now: Date, calendar: HouseholdCalendar, days: Int) throws -> [UpcomingOccurrence] {
        let dayStart = calendar.startOfDay(for: now)
        let end = calendar.calendar.date(byAdding: .day, value: days, to: dayStart) ?? dayStart
        let window = DateInterval(start: dayStart, end: max(end, dayStart))
        let windowStart = window.start
        let windowEnd = window.end
        let never = Date.distantPast
        let materializedDescriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate {
                $0.recurringSeriesID != nil && ($0.scheduledOccurrence ?? never) >= windowStart
                    && ($0.scheduledOccurrence ?? never) < windowEnd
            })
        var handled = Set<String>()
        for record in try modelContext.fetch(materializedDescriptor) {
            if let seriesID = record.recurringSeriesID, let date = record.scheduledOccurrence {
                handled.insert("\(seriesID.uuidString)-\(date.timeIntervalSinceReferenceDate)")
            }
        }
        let enabled = FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.isEnabled == true })
        let models = try modelContext.fetch(enabled)
        // Store names for purchases (Sprint 22), in one fetch.
        var storeNames: [UUID: String] = [:]
        if models.contains(where: { $0.merchantID != nil }) {
            for merchant in try modelContext.fetch(FetchDescriptor<Merchant>()) {
                storeNames[merchant.id] = merchant.displayName
            }
        }
        var upcoming: [UpcomingOccurrence] = []
        for model in models {
            let series = try model.series()
            let merchantName = series.merchantID.flatMap { storeNames[$0] }
            for date in RecurrenceEngine().occurrences(of: series, in: window) {
                let item = UpcomingOccurrence(
                    seriesID: series.id, date: date, amount: series.templateAmount, type: series.type,
                    title: model.notes, kind: series.kind, merchantName: merchantName)
                if !handled.contains(item.id) {
                    upcoming.append(item)
                }
            }
        }
        upcoming.sort { $0.date < $1.date }
        return upcoming
    }

    public func setSeriesEnabled(_ enabled: Bool, series id: UUID, now: Date) throws {
        begin()
        guard let series = try recurringSeries(id) else { throw LedgerError.unknownSeries }
        series.isEnabled = enabled
        series.updatedAt = now
        try commit()
    }

    /// Changes a series' template and rule (spec §9.4: occurrences are computed, so a rule change only moves the
    /// projection). Transactions already posted from it keep their own amount, date, category and merchant; the next
    /// occurrence is recomputed after the latest one posted, so nothing is offered twice. `kind` and `merchantName`
    /// replace the stored ones, so they have no defaults: a caller that left them out would turn a purchase into a
    /// bill and clear its store (Sprint 22 review S2). No store clears it.
    public func updateSeries(
        _ id: UUID, templateAmount: Money, type: TransactionType, rule: RecurrenceRule, startDate: Date,
        endDate: Date? = nil, categoryID: UUID?, notes: String?, accountID: UUID? = nil,
        transferAccountID: UUID? = nil, kind: RecurringKind, merchantName: String?, now: Date
    ) throws {
        begin()
        guard let series = try recurringSeries(id) else { throw LedgerError.unknownSeries }
        // Before any lookup or edit, so an impossible rule leaves nothing half-changed (review S3).
        try rule.validate()
        guard kind == .bill || type == .expense else { throw LedgerError.purchaseMustBeExpense }
        let store = Self.storeName(merchantName)
        let template = TransactionDraft(
            amount: templateAmount, type: type, occurredAt: startDate, categoryID: categoryID, merchantName: store,
            accountID: accountID, transferAccountID: transferAccountID)
        try template.validate()
        let settings = try requireSettings()
        try requireCurrency(templateAmount, settings)
        if let categoryID {
            // An unchanged category that was archived since may stay; a newly picked one must be active.
            try requireUsableCategory(categoryID, for: type, allowArchived: categoryID == series.categoryID)
        }
        let accounts = try resolveAccounts(
            template, settings: settings, current: (series.accountID, series.transferAccountID), now: now)
        // Looked up before the first edit to the series, so a failed fetch leaves it as it was.
        var merchantID: UUID?
        if let store {
            // The same store name keeps the series' own merchant: names aren't unique, so looking it up again could
            // pick another one with the same name (review S5).
            let current = try series.merchantID.flatMap { id in
                try modelContext.fetch(FetchDescriptor<Merchant>(predicate: #Predicate { $0.id == id })).first
            }
            if let current, current.normalizedName == Merchant.normalize(store) {
                merchantID = current.id
            } else {
                merchantID = try findOrCreateMerchant(named: store, now: now).id
            }
        }
        series.accountID = accounts.source
        series.transferAccountID = accounts.destination
        try series.setRule(rule)
        series.templateAmountMinorUnits = templateAmount.minorUnits
        series.currencyCode = templateAmount.currencyCode
        series.type = type
        series.startDate = startDate
        series.endDate = endDate
        series.categoryID = categoryID
        series.notes = notes
        series.kind = kind
        series.merchantID = merchantID
        series.updatedAt = now
        let target: UUID? = id
        let posted = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.recurringSeriesID == target })
        let latest = try modelContext.fetch(posted).compactMap(\.scheduledOccurrence).max()
        // `nextOccurrence(after:)` is strict, so step back one second to include the start itself.
        let after = max(latest ?? .distantPast, startDate.addingTimeInterval(-1))
        series.nextOccurrence = RecurrenceEngine().nextOccurrence(of: try series.series(), after: after)
        try commit()
    }

    /// Deletes a series nothing was posted from. With posted transactions it is refused, so their provenance stays
    /// intact (CLAUDE.md §5: never silently delete financial history); disabling stops future occurrences instead.
    public func deleteSeries(_ id: UUID) throws {
        begin()
        guard let series = try recurringSeries(id) else { throw LedgerError.unknownSeries }
        let target: UUID? = id
        let posted = try modelContext.fetchCount(
            FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.recurringSeriesID == target }))
        guard posted == 0 else { throw LedgerError.seriesHasHistory(postedCount: posted) }
        modelContext.delete(series)
        try commit()
    }

    // MARK: Persistence

    /// Discards edits left pending by an earlier operation that threw before saving, so this write can't persist
    /// them (the same guard as TaskBoardService).
    func begin() {
        if modelContext.hasChanges {
            modelContext.rollback()
        }
    }

    /// Saves, or discards every pending edit if the save fails, so no later save can persist a failed operation.
    func commit() throws {
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

    func requireSettings() throws -> AppSettings {
        guard let settings = try settings() else { throw LedgerError.settingsMissing }
        return settings
    }

    func requireCurrency(_ money: Money, _ settings: AppSettings) throws {
        guard money.currencyCode == settings.currencyCode else {
            throw LedgerError.currencyMismatch(expected: settings.currencyCode, actual: money.currencyCode)
        }
    }

    func requireTransaction(_ id: UUID) throws -> TransactionRecord {
        let descriptor = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try modelContext.fetch(descriptor).first else { throw LedgerError.unknownTransaction }
        return record
    }

    /// A wishlist purchase must remain one live expense while it is linked (spec §8.1).
    func requirePurchaseInvariant(
        _ record: TransactionRecord, type: TransactionType, status: TransactionStatus
    ) throws {
        guard record.source == .wishlistPurchase || record.wishlistItemID != nil else { return }
        guard type == .expense else { throw LedgerError.purchaseMustStayExpense }
        guard status != .cancelled else { throw LedgerError.purchaseCannotBeCancelled }
    }

    private func recurringSeries(_ id: UUID) throws -> RecurringTransaction? {
        let descriptor = FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    func requireUsableCategory(_ id: UUID, for type: TransactionType, allowArchived: Bool = false) throws {
        let descriptor = FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id })
        guard let category = try modelContext.fetch(descriptor).first else { throw LedgerError.unknownCategory }
        guard allowArchived || !category.isArchived else { throw LedgerError.archivedCategory }
        guard category.kind.allows(type) else { throw LedgerError.categoryKindMismatch(category.kind, type) }
    }

    /// The category a manual choice teaches its merchant (Sprint 23, A-006): an active category of a kind that allows
    /// the type, on an expense or income. A model's pick is not learned (AI output never becomes stored data, spec
    /// §12), nor is a transfer or refund. Fetched before the first edit, so a failed fetch leaves nothing pending.
    func learnableCategory(_ id: UUID?, type: TransactionType, isAIClassified: Bool) throws -> UUID? {
        guard let id, !isAIClassified, type == .expense || type == .income else { return nil }
        let descriptor = FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id })
        guard let category = try modelContext.fetch(descriptor).first, !category.isArchived, category.kind.allows(type)
        else { return nil }
        return category.id
    }

    /// Points the merchant's default category (a suggestion only, spec §7.4) at `categoryID`, without saving.
    func learn(_ categoryID: UUID?, for merchant: Merchant, now: Date) {
        guard let categoryID, merchant.defaultCategoryID != categoryID else { return }
        merchant.defaultCategoryID = categoryID
        merchant.updatedAt = now
    }

    private func merchant(_ id: UUID) throws -> Merchant? {
        let descriptor = FetchDescriptor<Merchant>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    /// A series' store (Sprint 22): the trimmed name, or nil when there is none.
    private static func storeName(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Merchant.normalize(trimmed).isEmpty ? nil : trimmed
    }

    /// The learned category of each normalized merchant name in `keys` that has one in `usable`. Names aren't unique;
    /// the oldest merchant with a usable category speaks for the name. Quick Add (`suggestedCategory`) and the import
    /// preview (`importCategorySuggestions`) both read it here, so the same text gets the same suggestion.
    func learnedCategories(for keys: Set<String>, usable: Set<UUID>) throws -> [String: UUID] {
        guard !keys.isEmpty, !usable.isEmpty else { return [:] }
        var descriptor = FetchDescriptor<Merchant>(sortBy: [SortDescriptor(\.createdAt)])
        if keys.count == 1, let only = keys.first {
            descriptor.predicate = #Predicate<Merchant> { $0.normalizedName == only }
        }
        var learned: [String: UUID] = [:]
        for merchant in try modelContext.fetch(descriptor) where keys.contains(merchant.normalizedName) {
            guard learned[merchant.normalizedName] == nil, let category = merchant.defaultCategoryID,
                usable.contains(category)
            else { continue }
            learned[merchant.normalizedName] = category
        }
        return learned
    }

    /// The oldest merchant with `name`'s normalized name, else a new one. Every path that records a merchant (a new
    /// entry, Quick Add, an edit, an import, a series) comes through here, so a name always lands on the same one.
    func findOrCreateMerchant(named name: String, now: Date) throws -> Merchant {
        let key = Merchant.normalize(name)
        let descriptor = FetchDescriptor<Merchant>(
            predicate: #Predicate { $0.normalizedName == key }, sortBy: [SortDescriptor(\.createdAt)])
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let merchant = Merchant(displayName: name.trimmingCharacters(in: .whitespacesAndNewlines), now: now)
        modelContext.insert(merchant)
        return merchant
    }
}
