import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 10: multiple accounts and transfers (owner decisions 13 and 16). Each account has its own baseline and the
/// three §9 figures; the household's are their sums; a transfer moves money between accounts and changes no total.
struct AccountsTests {
    private let zone = TimeZone(identifier: "America/Vancouver")!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: zone) }
    private var weekAgo: Date { now.addingTimeInterval(-7 * 86_400) }
    private var hourAgo: Date { now.addingTimeInterval(-3_600) }

    private struct Fixture {
        let container: ModelContainer
        let ledger: TransactionService
        let main: UUID

        func context() -> ModelContext { ModelContext(container) }
    }

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func makeFixture(mainBalance: Int64 = 100_000) async throws -> Fixture {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        try await ledger.setStartingBalance(cad(mainBalance), asOf: weekAgo, now: now)
        let main = try #require(try await ledger.settingsSnapshot()?.defaultAccountID)
        return Fixture(container: container, ledger: ledger, main: main)
    }

    private func addAccount(
        _ name: String, _ kind: AccountKind, _ balance: Int64, to fixture: Fixture
    ) async throws -> UUID {
        let draft = AccountDraft(name: name, kind: kind, startingBalance: cad(balance), startingBalanceDate: weekAgo)
        return try await fixture.ledger.createAccount(draft, now: now)
    }

    private func balances(_ fixture: Fixture, includePending: Bool = false) async throws -> HouseholdBalances {
        try await fixture.ledger.balances(now: now, calendar: calendar, includePendingInProjection: includePending)
    }

    // MARK: Setup

    @Test func settingUpCreatesAMainAccountThatIsTheDefault() async throws {
        let fixture = try await makeFixture()
        let accounts = try fixture.context().fetch(FetchDescriptor<Account>())
        #expect(accounts.map(\.id) == [fixture.main])
        #expect(accounts.first?.name == TransactionService.mainAccountName)
        #expect(accounts.first?.startingBalance == cad(100_000))
        let snapshot = try #require(try await fixture.ledger.settingsSnapshot())
        #expect(snapshot.startingBalance == cad(100_000), "The settings snapshot reads the default account")
    }

    // MARK: Balances

    @Test func eachAccountHasItsOwnFiguresAndTheHouseholdIsTheirSum() async throws {
        let fixture = try await makeFixture()
        let savings = try await addAccount("Savings", .savings, 50_000, to: fixture)
        let ledger = fixture.ledger
        try await ledger.create(TransactionDraft(amount: cad(4_750), type: .expense, occurredAt: hourAgo), now: now)
        try await ledger.create(
            TransactionDraft(amount: cad(1_000), type: .income, occurredAt: hourAgo, accountID: savings), now: now)
        try await ledger.create(
            TransactionDraft(
                amount: cad(20_000), type: .transfer, occurredAt: hourAgo, accountID: fixture.main,
                transferAccountID: savings), now: now)

        let result = try await balances(fixture)
        #expect(result.balance(of: fixture.main)?.current == cad(100_000 - 4_750 - 20_000))
        #expect(result.balance(of: savings)?.current == cad(50_000 + 1_000 + 20_000))
        #expect(result.household.current == cad(150_000 - 4_750 + 1_000), "The transfer changes no total")
        let household = try await ledger.balanceSnapshot(
            now: now, calendar: calendar, includePendingInProjection: false)
        #expect(household == result.household)
    }

    @Test func aCreditCardOwesAndTheHouseholdTotalSubtractsIt() async throws {
        let fixture = try await makeFixture()
        let card = try await addAccount("Visa", .creditCard, -30_000, to: fixture)
        try await fixture.ledger.create(
            TransactionDraft(amount: cad(2_500), type: .expense, occurredAt: hourAgo, accountID: card), now: now)
        let result = try await balances(fixture)
        #expect(result.balance(of: card)?.current == cad(-32_500))
        #expect(result.household.current == cad(100_000 - 32_500))
        // Paying the card is a transfer: the card owes less, the bank holds less, the household is unchanged.
        try await fixture.ledger.create(
            TransactionDraft(
                amount: cad(32_500), type: .transfer, occurredAt: hourAgo, accountID: fixture.main,
                transferAccountID: card), now: now)
        let paid = try await balances(fixture)
        #expect(paid.balance(of: card)?.current == cad(0))
        #expect(paid.household.current == result.household.current)
    }

    @Test func pendingAndFutureItemsStayInTheirAccountsFigures() async throws {
        let fixture = try await makeFixture()
        let savings = try await addAccount("Savings", .savings, 0, to: fixture)
        try await fixture.ledger.create(
            TransactionDraft(
                amount: cad(3_000), type: .expense, occurredAt: hourAgo, status: .pending, accountID: savings),
            now: now)
        try await fixture.ledger.create(
            TransactionDraft(
                amount: cad(9_000), type: .transfer, occurredAt: now.addingTimeInterval(3 * 86_400),
                transferAccountID: savings), now: now)
        let result = try await balances(fixture, includePending: true)
        let savingsFigures = try #require(result.balance(of: savings))
        #expect(savingsFigures.current == cad(0))
        #expect(savingsFigures.pendingImpact == cad(-3_000))
        #expect(savingsFigures.projected == cad(9_000 - 3_000))
        #expect(result.balance(of: fixture.main)?.projected == cad(100_000 - 9_000))
        #expect(result.household.projected == cad(100_000 - 3_000))
    }

    @Test func aRecurringTransferMovesTheProjectionBetweenAccountsOnly() async throws {
        let fixture = try await makeFixture()
        let savings = try await addAccount("Savings", .savings, 0, to: fixture)
        let tomorrow = now.addingTimeInterval(86_400)
        let series = try await fixture.ledger.createSeries(
            templateAmount: cad(10_000), type: .transfer, rule: .monthlyOnDay(day: 15), timeZone: zone,
            startDate: tomorrow, transferAccountID: savings, now: now)
        let result = try await balances(fixture)
        let occurrences = RecurrenceEngine().occurrences(
            of: RecurringSeries(
                templateAmount: cad(10_000), type: .transfer, rule: .monthlyOnDay(day: 15), timeZone: zone,
                startDate: tomorrow),
            in: result.household.projectionWindow)
        let moved = Int64(occurrences.count) * 10_000
        #expect(result.balance(of: savings)?.projected == cad(moved))
        #expect(result.balance(of: fixture.main)?.projected == cad(100_000 - moved))
        #expect(result.household.projected == cad(100_000))

        if let first = occurrences.first {
            let record = try await fixture.ledger.materialize(seriesID: series, occurrence: first, now: now)
            let stored = try #require(
                try fixture.context().fetch(FetchDescriptor<TransactionRecord>()).first { $0.id == record })
            #expect(stored.accountID == fixture.main)
            #expect(stored.transferAccountID == savings)
        }
    }

    // MARK: Transfer rules

    @Test func transfersNeedTwoDifferentUsableAccountsAndNoCategory() async throws {
        let fixture = try await makeFixture()
        let savings = try await addAccount("Savings", .savings, 0, to: fixture)
        let old = try await addAccount("Old", .bank, 0, to: fixture)
        try await fixture.ledger.setAccountArchived(true, account: old, now: now)
        let ledger = fixture.ledger
        func transfer(from: UUID?, to: UUID?) -> TransactionDraft {
            TransactionDraft(
                amount: cad(100), type: .transfer, occurredAt: hourAgo, accountID: from, transferAccountID: to)
        }
        await #expect(throws: LedgerError.transferNeedsTwoAccounts) {
            try await ledger.create(transfer(from: savings, to: savings), now: now)
        }
        await #expect(throws: LedgerError.transferNeedsTwoAccounts) {
            try await ledger.create(transfer(from: nil, to: fixture.main), now: now)
        }
        await #expect(throws: LedgerError.archivedAccount) {
            try await ledger.create(transfer(from: nil, to: old), now: now)
        }
        await #expect(throws: LedgerError.unknownAccount) {
            try await ledger.create(transfer(from: nil, to: UUID()), now: now)
        }
        var categorized = transfer(from: nil, to: savings)
        categorized.categoryID = UUID()
        await #expect(throws: LedgerError.transferHasNoCategory) { try await ledger.create(categorized, now: now) }
        let income = TransactionDraft(amount: cad(100), type: .income, occurredAt: hourAgo, transferAccountID: savings)
        await #expect(throws: LedgerError.transferNeedsTwoAccounts) { try await ledger.create(income, now: now) }
        #expect(try fixture.context().fetchCount(FetchDescriptor<TransactionRecord>()) == 0)
    }

    @Test func aRecordKeepsAnAccountArchivedSinceButCantMoveToOne() async throws {
        let fixture = try await makeFixture()
        let cash = try await addAccount("Cash", .cash, 0, to: fixture)
        let old = try await addAccount("Old", .bank, 0, to: fixture)
        let ledger = fixture.ledger
        let draft = TransactionDraft(amount: cad(500), type: .expense, occurredAt: hourAgo, accountID: cash)
        let id = try await ledger.create(draft, now: now)
        try await ledger.setAccountArchived(true, account: cash, now: now)
        try await ledger.setAccountArchived(true, account: old, now: now)
        var edited = draft
        edited.amount = cad(600)
        try await ledger.update(id, with: edited, now: now)
        edited.accountID = old
        await #expect(throws: LedgerError.archivedAccount) { try await ledger.update(id, with: edited, now: now) }
    }

    // MARK: Account lifecycle

    @Test func accountsWithHistoryAreArchivedNotDeletedAndTheDefaultStays() async throws {
        let fixture = try await makeFixture()
        let ledger = fixture.ledger
        let unused = try await addAccount("Unused", .cash, 0, to: fixture)
        let used = try await addAccount("Used", .savings, 0, to: fixture)
        try await ledger.create(
            TransactionDraft(amount: cad(100), type: .income, occurredAt: hourAgo, accountID: used), now: now)
        try await ledger.deleteAccount(unused)
        await #expect(throws: LedgerError.accountInUse(referenceCount: 1)) { try await ledger.deleteAccount(used) }
        await #expect(throws: LedgerError.defaultAccountRequired) { try await ledger.deleteAccount(fixture.main) }
        await #expect(throws: LedgerError.defaultAccountRequired) {
            try await ledger.setAccountArchived(true, account: fixture.main, now: now)
        }
        try await ledger.setAccountArchived(true, account: used, now: now)
        await #expect(throws: LedgerError.archivedAccount) { try await ledger.setDefaultAccount(used, now: now) }
        let names = try fixture.context().fetch(FetchDescriptor<Account>()).map(\.name).sorted()
        #expect(names == [TransactionService.mainAccountName, "Used"])
        let result = try await balances(fixture)
        #expect(result.household.current == cad(100_100), "An archived account's money still counts")
    }

    @Test func aNewDefaultTakesNewEntries() async throws {
        let fixture = try await makeFixture()
        let cash = try await addAccount("Cash", .cash, 0, to: fixture)
        try await fixture.ledger.setDefaultAccount(cash, now: now)
        let id = try await fixture.ledger.create(
            TransactionDraft(amount: cad(100), type: .expense, occurredAt: hourAgo), now: now)
        let records = try fixture.context().fetch(FetchDescriptor<TransactionRecord>())
        #expect(records.first { $0.id == id }?.accountID == cash)
        #expect(try await fixture.ledger.settingsSnapshot()?.defaultAccountID == cash)
    }

    @Test func accountDraftsAreValidated() async throws {
        let fixture = try await makeFixture()
        let ledger = fixture.ledger
        await #expect(throws: LedgerError.emptyAccountName) {
            try await ledger.createAccount(
                AccountDraft(name: "  ", kind: .bank, startingBalance: cad(0), startingBalanceDate: now), now: now)
        }
        await #expect(throws: LedgerError.currencyMismatch(expected: "CAD", actual: "USD")) {
            try await ledger.createAccount(
                AccountDraft(
                    name: "US", kind: .bank, startingBalance: Money(minorUnits: 0, currencyCode: "USD"),
                    startingBalanceDate: now), now: now)
        }
        await #expect(throws: LedgerError.startingBalanceInFuture) {
            try await ledger.createAccount(
                AccountDraft(
                    name: "Later", kind: .bank, startingBalance: cad(0),
                    startingBalanceDate: now.addingTimeInterval(60)), now: now)
        }
    }

    // MARK: Wishlist

    @Test func aPurchaseIsPaidFromTheChosenAccount() async throws {
        let fixture = try await makeFixture()
        let card = try await addAccount("Visa", .creditCard, 0, to: fixture)
        let item = try await fixture.ledger.createWishlistItem(
            WishlistDraft(name: "Lamp", estimatedPrice: cad(4_000)), now: now)
        let id = try await fixture.ledger.purchaseWishlistItem(
            item, actualPrice: cad(3_900), occurredAt: hourAgo, categoryID: nil, accountID: card, now: now)
        let records = try fixture.context().fetch(FetchDescriptor<TransactionRecord>())
        #expect(records.first { $0.id == id }?.accountID == card)
        #expect(try await balances(fixture).balance(of: card)?.current == cad(-3_900))
    }

    // MARK: Backups

    @Test func backupsCarryAccountsAndTransfersAndRestoreThem() async throws {
        let fixture = try await makeFixture()
        let savings = try await addAccount("Savings", .savings, 50_000, to: fixture)
        try await fixture.ledger.create(
            TransactionDraft(amount: cad(7_000), type: .transfer, occurredAt: hourAgo, transferAccountID: savings),
            now: now)
        let backupService = BackupService.make(container: fixture.container)
        let backup = try await backupService.snapshot(now: now, appVersion: "1") { _ in nil }
        #expect(backup.schemaVersion == 2)
        #expect(backup.accounts?.count == 2)
        #expect(backup.settings.defaultAccountID == fixture.main)
        try BackupValidator.validate(backup)

        let target = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let targetLedger = TransactionService.make(container: target)
        try await targetLedger.ensureSettings(currencyCode: "CAD", now: now)
        _ = try await BackupService.make(container: target).restore(backup, availableMedia: [], now: now)
        let restored = try await targetLedger.balances(now: now, calendar: calendar, includePendingInProjection: false)
        #expect(restored.balance(of: savings)?.current == cad(57_000))
        #expect(restored.balance(of: fixture.main)?.current == cad(93_000))
        #expect(try ModelContext(target).fetch(FetchDescriptor<Account>()).count == 2)
    }

    @Test func theValidatorRefusesBrokenAccountData() async throws {
        let fixture = try await makeFixture()
        let savings = try await addAccount("Savings", .savings, 0, to: fixture)
        try await fixture.ledger.create(
            TransactionDraft(amount: cad(100), type: .transfer, occurredAt: hourAgo, transferAccountID: savings),
            now: now)
        let backupService = BackupService.make(container: fixture.container)
        let good = try await backupService.snapshot(now: now, appVersion: "1") { _ in nil }
        var sameAccount = good
        sameAccount.transactions[0].transferAccountID = sameAccount.transactions[0].accountID
        var noAccount = good
        noAccount.transactions[0].accountID = nil
        var strayTarget = good
        strayTarget.transactions[0].type = TransactionType.expense.rawValue
        var noDefault = good
        noDefault.settings.defaultAccountID = UUID()
        var badKind = good
        badKind.accounts?[0].kind = "brokerage"
        let cases: [(BackupDTO, BackupError)] = [
            (sameAccount, .inconsistentLink(entity: "transactions", field: "transferAccountID")),
            (noAccount, .missingReference(entity: "transactions", field: "accountID")),
            (strayTarget, .inconsistentLink(entity: "transactions", field: "transferAccountID")),
            (noDefault, .missingReference(entity: "settings", field: "defaultAccountID")),
            (badKind, .invalidValue(entity: "accounts", field: "kind", value: "brokerage")),
        ]
        for (backup, expected) in cases {
            #expect(throws: expected) { try BackupValidator.validate(backup) }
        }
    }

    // MARK: Display rule

    @Test func aCardIsEnteredAsOwedAndStoredNegative() throws {
        #expect(try AccountKind.creditCard.stored(fromEntered: cad(500)) == cad(-500))
        #expect(try AccountKind.creditCard.entered(fromStored: cad(-500)) == cad(500))
        #expect(try AccountKind.savings.stored(fromEntered: cad(500)) == cad(500))
    }

    // MARK: Review follow-ups (Sprint 10 data-safety review)

    @Test func aSeriesMovedAfterPostingIsNotProjectedTwice() throws {
        let checking = UUID()
        let savings = UUID()
        let start = now.addingTimeInterval(-30 * 86_400)
        let accounts = [
            AccountBaseline(id: checking, kind: .bank, startingBalance: cad(0), startingBalanceDate: start),
            AccountBaseline(id: savings, kind: .savings, startingBalance: cad(0), startingBalanceDate: start),
        ]
        let seriesID = UUID()
        // Posted to checking, then the series was moved to savings: the posted occurrence is handled either way.
        let moved = RecurringSeries(
            id: seriesID, templateAmount: cad(1_000), type: .expense, rule: .weekly(interval: 1, weekday: 2),
            timeZone: zone, startDate: start, accountID: savings)
        let window = DateInterval(start: now, end: now.addingTimeInterval(30 * 86_400))
        let first = try #require(RecurrenceEngine().occurrences(of: moved, in: window).first)
        let posted = LedgerLine(
            amount: cad(1_000), type: .expense, status: .posted, occurredAt: first, recurringSeriesID: seriesID,
            scheduledOccurrence: first, accountID: checking)
        let result = try BalanceCalculator().balances(
            accounts: accounts, lines: [posted], series: [moved], now: now, calendar: calendar,
            includePendingInProjection: false, currencyCode: "CAD")
        let count = Int64(RecurrenceEngine().occurrences(of: moved, in: result.household.projectionWindow).count)
        #expect(result.balance(of: checking)?.projected == cad(-1_000), "The posted occurrence stays in checking")
        #expect(result.balance(of: savings)?.projected == cad(-1_000 * (count - 1)), "Only the rest are projected")
    }

    @Test func aLineWithoutAKnownAccountIsRefusedNotDropped() throws {
        let account = AccountBaseline(id: UUID(), kind: .bank, startingBalance: cad(0), startingBalanceDate: weekAgo)
        let stray = LedgerLine(amount: cad(100), type: .income, status: .posted, occurredAt: hourAgo)
        #expect(throws: LedgerError.unreadableRecord(field: "accountID", value: "none")) {
            try BalanceCalculator().balances(
                accounts: [account], lines: [stray], series: [], now: now, calendar: calendar,
                includePendingInProjection: false, currencyCode: "CAD")
        }
    }

    @Test func aVersionOneBackupRestoresIntoOneMainAccount() async throws {
        let fixture = try await makeFixture(mainBalance: 25_000)
        let expense = TransactionDraft(amount: cad(500), type: .expense, occurredAt: hourAgo)
        try await fixture.ledger.create(expense, now: now)
        try await fixture.ledger.createSeries(
            templateAmount: cad(9_000), type: .expense, rule: .monthlyOnDay(day: 1), timeZone: zone,
            startDate: now.addingTimeInterval(86_400), now: now)
        let service = BackupService.make(container: fixture.container)
        var v1 = try await service.snapshot(now: now, appVersion: "1") { _ in nil }
        // The same data as a v1 file: one baseline in settings, no accounts, no account on any record.
        v1.schemaVersion = 1
        v1.accounts = nil
        v1.settings.defaultAccountID = nil
        v1.settings.startingBalanceMinorUnits = 25_000
        v1.settings.startingBalanceDate = weekAgo
        for index in v1.transactions.indices {
            v1.transactions[index].accountID = nil
        }
        for index in v1.recurringTransactions.indices {
            v1.recurringTransactions[index].accountID = nil
        }
        try BackupValidator.validate(v1)

        let target = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let targetLedger = TransactionService.make(container: target)
        try await targetLedger.ensureSettings(currencyCode: "CAD", now: now)
        _ = try await BackupService.make(container: target).restore(v1, availableMedia: [], now: now)
        let accounts = try ModelContext(target).fetch(FetchDescriptor<Account>())
        #expect(accounts.map(\.id) == [v1.settings.id], "The target's own Main account is replaced")
        let series = try ModelContext(target).fetch(FetchDescriptor<RecurringTransaction>())
        #expect(series.allSatisfy { $0.accountID == v1.settings.id })
        let restored = try await targetLedger.balances(now: now, calendar: calendar, includePendingInProjection: false)
        #expect(restored.household.current == cad(24_500))

        var missing = v1
        missing.settings.startingBalanceMinorUnits = nil
        #expect(throws: BackupError.missingReference(entity: "settings", field: "startingBalance")) {
            try BackupValidator.validate(missing)
        }
    }

    @Test func transfersCanBeEditedAndDeleted() async throws {
        let fixture = try await makeFixture()
        let savings = try await addAccount("Savings", .savings, 0, to: fixture)
        let cash = try await addAccount("Cash", .cash, 0, to: fixture)
        let ledger = fixture.ledger
        var draft = TransactionDraft(
            amount: cad(2_000), type: .transfer, occurredAt: hourAgo, transferAccountID: savings)
        let id = try await ledger.create(draft, now: now)
        draft.amount = cad(3_000)
        draft.transferAccountID = cash
        try await ledger.update(id, with: draft, now: now)
        var result = try await balances(fixture)
        #expect(result.balance(of: cash)?.current == cad(3_000))
        #expect(result.balance(of: savings)?.current == cad(0))
        #expect(result.household.current == cad(100_000))
        try await ledger.deleteTransaction(id, alsoDisableSeries: false, now: now)
        result = try await balances(fixture)
        #expect(result.balance(of: fixture.main)?.current == cad(100_000))
        #expect(result.balance(of: cash)?.current == cad(0))
    }

    @Test func aRecurringTransferCanBeRetargeted() async throws {
        let fixture = try await makeFixture()
        let savings = try await addAccount("Savings", .savings, 0, to: fixture)
        let cash = try await addAccount("Cash", .cash, 0, to: fixture)
        let ledger = fixture.ledger
        let start = now.addingTimeInterval(86_400)
        let id = try await ledger.createSeries(
            templateAmount: cad(5_000), type: .transfer, rule: .monthlyOnDay(day: 20), timeZone: zone,
            startDate: start, transferAccountID: savings, now: now)
        try await ledger.updateSeries(
            id, templateAmount: cad(5_000), type: .transfer, rule: .monthlyOnDay(day: 20), startDate: start,
            categoryID: nil, notes: nil, accountID: fixture.main, transferAccountID: cash, now: now)
        let stored = try #require(try fixture.context().fetch(FetchDescriptor<RecurringTransaction>()).first)
        #expect(stored.transferAccountID == cash)
        await #expect(throws: LedgerError.transferNeedsTwoAccounts) {
            try await ledger.updateSeries(
                id, templateAmount: cad(5_000), type: .transfer, rule: .monthlyOnDay(day: 20), startDate: start,
                categoryID: nil, notes: nil, accountID: cash, transferAccountID: cash, now: now)
        }
    }

    @Test func anOccurrenceIsNotPostedIntoAnArchivedAccount() async throws {
        let fixture = try await makeFixture()
        let old = try await addAccount("Old", .bank, 0, to: fixture)
        let start = now.addingTimeInterval(86_400)
        let id = try await fixture.ledger.createSeries(
            templateAmount: cad(1_000), type: .expense, rule: .monthlyOnDay(day: 20), timeZone: zone,
            startDate: start, accountID: old, now: now)
        try await fixture.ledger.setAccountArchived(true, account: old, now: now)
        let stored = try fixture.context().fetch(FetchDescriptor<RecurringTransaction>())
        let next = try #require(stored.first?.nextOccurrence)
        await #expect(throws: LedgerError.archivedAccount) {
            try await fixture.ledger.materialize(seriesID: id, occurrence: next, now: now)
        }
    }

    @Test func aSecondAccountLocksTheCurrency() async throws {
        let fixture = try await makeFixture()
        let before = try await fixture.ledger.isCurrencyLocked()
        #expect(!before)
        _ = try await addAccount("Savings", .savings, 50_000, to: fixture)
        let after = try await fixture.ledger.isCurrencyLocked()
        #expect(after)
        let yen = Money(minorUnits: 1_000, currencyCode: "JPY")
        await #expect(throws: LedgerError.currencyLockedByExistingRecords) {
            try await fixture.ledger.updateHousehold(currencyCode: "JPY", startingBalance: yen, asOf: now, now: now)
        }
    }

    @Test func transfersAreNotWeeklySpendingAndTheWidgetSaysTransfer() async throws {
        let fixture = try await makeFixture()
        let savings = try await addAccount("Savings", .savings, 0, to: fixture)
        try await fixture.ledger.create(
            TransactionDraft(amount: cad(4_000), type: .transfer, occurredAt: hourAgo, transferAccountID: savings),
            now: now)
        try await fixture.ledger.createSeries(
            templateAmount: cad(2_500), type: .transfer, rule: .weekly(interval: 1, weekday: 2), timeZone: zone,
            startDate: now.addingTimeInterval(3_600), transferAccountID: savings, now: now)
        let summary = try await fixture.ledger.dashboardSummary(now: now, calendar: calendar)
        #expect(summary.spentThisWeek == cad(0))
        let widget = WidgetSnapshot.make(from: summary, showAmounts: true, now: now, calendar: calendar)
        let item = try #require(widget.upcoming(from: now, calendar: calendar).first)
        #expect(item.isTransfer == true)
        #expect(try item.displayAmount(currencyCode: "CAD") == cad(2_500), "A transfer is shown unsigned")
    }

    @Test func aCSVTransferRowNamesBothAccounts() {
        let row = TransactionCSV.Row(
            occurredAt: Date(timeIntervalSince1970: 0), type: .transfer, status: .posted, amount: cad(10_000),
            category: nil, merchant: nil, notes: nil, account: "Main account", toAccount: "Savings")
        let lines = TransactionCSV.text([row], calendar: HouseholdCalendar(timeZone: TimeZone(identifier: "UTC")!))
            .components(separatedBy: "\r\n")
        #expect(lines[1] == "1970-01-01 00:00,transfer,posted,100.00,CAD,,,,Main account,Savings")
    }
}
