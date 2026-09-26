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
}
