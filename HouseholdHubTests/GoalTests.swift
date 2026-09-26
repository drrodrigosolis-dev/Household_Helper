import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 12: savings goals (owner decision 19). Progress is one account's current balance; the monthly amount is
/// what is left over the whole months to the target date, rounded up; goals travel in backups and hold their account
/// and wishlist item against deletion.
struct GoalTests {
    private let zone = TimeZone(identifier: "America/Vancouver")!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: zone) }
    private var weekAgo: Date { now.addingTimeInterval(-7 * 86_400) }

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private func rule(target: Int64, date: Date? = nil) -> GoalRule {
        GoalRule(
            id: UUID(), name: "Trip", target: cad(target), accountID: UUID(), targetDate: date, wishlistItemID: nil,
            isArchived: false)
    }

    // MARK: Math

    @Test(arguments: [
        // ((remaining, months), expected)
        ((Int64(100_000), 4), Int64(25_000)),
        ((Int64(100_001), 4), Int64(25_001)),
        ((Int64(1), 12), Int64(1)),
        ((Int64(0), 3), Int64(0)),
        ((Int64(99_999), 1), Int64(99_999)),
        ((Int64.max, 1), Int64.max),
        ((Int64.max, 2), Int64.max / 2 + 1),
        ((Int64.max - 1, 2), Int64.max / 2),
    ])
    func theMonthlyAmountRoundsUpToTheMinorUnit(split: (Int64, Int), expected: Int64) throws {
        #expect(try cad(split.0).dividedRoundingUp(by: split.1) == cad(expected))
    }

    @Test func divisionRefusesNegativeAmountsAndNonPositiveParts() {
        #expect(throws: MoneyError.invalidDivision) { try cad(-1).dividedRoundingUp(by: 2) }
        #expect(throws: MoneyError.invalidDivision) { try cad(100).dividedRoundingUp(by: 0) }
    }

    @Test func aMonthEndDateUnderAMonthAwayStillNeedsOneMonth() throws {
        let status = try GoalCalculator().status(
            of: rule(target: 90_000, date: day(2027, 2, 28, hour: 0)), saved: cad(0), now: day(2027, 1, 31),
            calendar: calendar)
        #expect(status.monthsLeft == 1)
        #expect(status.neededPerMonth == cad(90_000))
    }

    @Test(arguments: [
        // (target day, whole months left)
        ((2027, 3, 26), 6),
        ((2027, 3, 25), 5),
        ((2026, 10, 26), 1),
        ((2026, 10, 1), 1),  // under a month still needs one month's saving
        ((2026, 9, 26), 1),  // today
    ])
    func monthsLeftCountWholeCalendarMonthsFromToday(target: (Int, Int, Int), months: Int) throws {
        let today = day(2026, 9, 26, hour: 20)
        let date = day(target.0, target.1, target.2, hour: 0)
        let status = try GoalCalculator().status(
            of: rule(target: 120_000, date: date), saved: cad(0), now: today, calendar: calendar)
        #expect(status.monthsLeft == months)
        #expect(status.neededPerMonth == (try cad(120_000).dividedRoundingUp(by: months)))
        #expect(!status.isOverdue)
    }

    @Test func withoutADateOnlyTheAmountLeftShows() throws {
        let status = try GoalCalculator().status(
            of: rule(target: 50_000), saved: cad(20_000), now: now, calendar: calendar)
        #expect(status.remaining == cad(30_000))
        #expect(status.monthsLeft == nil)
        #expect(status.neededPerMonth == nil)
        #expect(!status.isReached && !status.isOverdue)
        #expect(status.progressFraction == 0.4)
    }

    @Test func reachedOverdueAndNegativeBalances() throws {
        let calculator = GoalCalculator()
        let reached = try calculator.status(
            of: rule(target: 50_000, date: day(2026, 1, 1)), saved: cad(60_000), now: now, calendar: calendar)
        #expect(reached.isReached && reached.remaining == cad(0) && reached.progressFraction == 1)
        #expect(!reached.isOverdue, "A reached goal is never overdue")

        let overdue = try calculator.status(
            of: rule(target: 50_000, date: day(2026, 1, 1)), saved: cad(10_000), now: now, calendar: calendar)
        #expect(overdue.isOverdue)
        #expect(overdue.monthsLeft == nil)
        #expect(overdue.neededPerMonth == cad(40_000), "Past the date, all of what is left is needed now")

        let behind = try calculator.status(of: rule(target: 50_000), saved: cad(-5_000), now: now, calendar: calendar)
        #expect(behind.remaining == cad(55_000))
        #expect(behind.progressFraction == 0)
    }

    // MARK: Service

    private struct Fixture {
        let container: ModelContainer
        let ledger: TransactionService
        let main: UUID

        func context() -> ModelContext { ModelContext(container) }
    }

    private func makeFixture() async throws -> Fixture {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        try await ledger.setStartingBalance(cad(100_000), asOf: weekAgo, now: now)
        let main = try #require(try await ledger.settingsSnapshot()?.defaultAccountID)
        return Fixture(container: container, ledger: ledger, main: main)
    }

    private func addAccount(_ kind: AccountKind, _ balance: Int64, to fixture: Fixture) async throws -> UUID {
        let draft = AccountDraft(
            name: "\(kind)", kind: kind, startingBalance: cad(balance), startingBalanceDate: weekAgo)
        return try await fixture.ledger.createAccount(draft, now: now)
    }

    private func addWish(_ fixture: Fixture, price: Int64 = 80_000) async throws -> UUID {
        try await fixture.ledger.createWishlistItem(
            WishlistDraft(name: "Bike", estimatedPrice: cad(price)), now: now)
    }

    @Test func progressIsTheAccountsCurrentBalanceAndGoalsShareIt() async throws {
        let fixture = try await makeFixture()
        let savings = try await addAccount(.savings, 40_000, to: fixture)
        let ledger = fixture.ledger
        let trip = try await ledger.createGoal(
            GoalDraft(name: " Trip ", target: cad(100_000), accountID: savings), now: now)
        let fund = try await ledger.createGoal(
            GoalDraft(name: "Fund", target: cad(20_000), accountID: savings), now: now)
        try await ledger.create(
            TransactionDraft(
                amount: cad(10_000), type: .transfer, occurredAt: now.addingTimeInterval(-60), accountID: fixture.main,
                transferAccountID: savings), now: now)

        let report = try await ledger.goalReport(now: now, calendar: calendar)
        #expect(report.map(\.id) == [trip, fund])
        #expect(report.map(\.saved) == [cad(50_000), cad(50_000)], "Two goals on one account show the same balance")
        #expect(report.first?.rule.name == "Trip")
        #expect(report.last?.isReached == true)

        try await ledger.setGoalArchived(true, goal: trip, now: now)
        let reordered = try await ledger.goalReport(now: now, calendar: calendar)
        #expect(reordered.map(\.id) == [fund, trip], "Archived goals come last")
    }

    @Test func goalsNeedANameAPositiveTargetAndAnAccountThatHoldsMoney() async throws {
        let fixture = try await makeFixture()
        let card = try await addAccount(.creditCard, 0, to: fixture)
        let ledger = fixture.ledger
        await #expect(throws: GoalError.emptyName) {
            try await ledger.createGoal(GoalDraft(name: "  ", target: cad(1_000), accountID: fixture.main), now: now)
        }
        await #expect(throws: LedgerError.nonPositiveAmount) {
            try await ledger.createGoal(GoalDraft(name: "A", target: cad(0), accountID: fixture.main), now: now)
        }
        await #expect(throws: LedgerError.currencyMismatch(expected: "CAD", actual: "USD")) {
            try await ledger.createGoal(
                GoalDraft(name: "A", target: Money(minorUnits: 1_000, currencyCode: "USD"), accountID: fixture.main),
                now: now)
        }
        await #expect(throws: GoalError.liabilityAccount) {
            try await ledger.createGoal(GoalDraft(name: "A", target: cad(1_000), accountID: card), now: now)
        }
        await #expect(throws: LedgerError.unknownAccount) {
            try await ledger.createGoal(GoalDraft(name: "A", target: cad(1_000), accountID: UUID()), now: now)
        }
        await #expect(throws: LedgerError.amountTooLarge) {
            try await ledger.createGoal(
                GoalDraft(name: "A", target: cad(Money.maxPlanMinorUnits + 1), accountID: fixture.main), now: now)
        }
        #expect(try fixture.context().fetchCount(FetchDescriptor<SavingsGoal>()) == 0)
        try await ledger.createGoal(
            GoalDraft(name: "A", target: cad(Money.maxPlanMinorUnits), accountID: fixture.main), now: now)
    }

    @Test func archivedAccountsAndBoughtItemsTakeNoNewGoalButKeepTheirs() async throws {
        let fixture = try await makeFixture()
        let ledger = fixture.ledger
        let savings = try await addAccount(.savings, 0, to: fixture)
        let wish = try await addWish(fixture)
        let draft = GoalDraft(name: "Bike", target: cad(80_000), accountID: savings, wishlistItemID: wish)
        let goal = try await ledger.createGoal(draft, now: now)
        try await ledger.setAccountArchived(true, account: savings, now: now)
        try await ledger.purchaseWishlistItem(
            wish, actualPrice: cad(75_000), occurredAt: now, categoryID: nil, now: now)

        var edited = draft
        edited.name = "Bike fund"
        try await ledger.updateGoal(goal, with: edited, now: now)

        await #expect(throws: LedgerError.archivedAccount) {
            try await ledger.createGoal(GoalDraft(name: "B", target: cad(1_000), accountID: savings), now: now)
        }
        try await ledger.deleteGoal(goal)
        await #expect(throws: GoalError.wishlistItemNotWanted) {
            try await ledger.createGoal(
                GoalDraft(name: "B", target: cad(1_000), accountID: fixture.main, wishlistItemID: wish), now: now)
        }
    }

    @Test func aWishlistItemHasAtMostOneGoal() async throws {
        let fixture = try await makeFixture()
        let ledger = fixture.ledger
        let wish = try await addWish(fixture)
        let draft = GoalDraft(name: "Bike", target: cad(80_000), accountID: fixture.main, wishlistItemID: wish)
        let goal = try await ledger.createGoal(draft, now: now)
        await #expect(throws: GoalError.wishlistItemHasGoal) { try await ledger.createGoal(draft, now: now) }
        var edited = draft
        edited.target = cad(90_000)
        try await ledger.updateGoal(goal, with: edited, now: now)
        let stored = try #require(try fixture.context().fetch(FetchDescriptor<SavingsGoal>()).first)
        #expect(stored.target == cad(90_000), "Editing keeps its own link")
    }

    @Test func aGoalHoldsItsAccountAndWishlistItemAgainstDeletion() async throws {
        let fixture = try await makeFixture()
        let ledger = fixture.ledger
        let savings = try await addAccount(.savings, 0, to: fixture)
        let wish = try await addWish(fixture)
        let goal = try await ledger.createGoal(
            GoalDraft(name: "Bike", target: cad(80_000), accountID: savings, wishlistItemID: wish), now: now)

        await #expect(throws: GoalError.usedByGoals(count: 1)) { try await ledger.deleteAccount(savings) }
        await #expect(throws: GoalError.usedByGoals(count: 1)) {
            _ = try await ledger.deleteWishlistItem(wish, now: now)
        }
        let card = AccountDraft(name: "Card", kind: .creditCard, startingBalance: cad(0), startingBalanceDate: weekAgo)
        await #expect(throws: GoalError.usedByGoals(count: 1)) {
            try await ledger.updateAccount(savings, with: card, now: now)
        }
        try await ledger.setGoalArchived(true, goal: goal, now: now)
        await #expect(throws: GoalError.usedByGoals(count: 1)) { try await ledger.deleteAccount(savings) }

        try await ledger.deleteGoal(goal)
        _ = try await ledger.deleteWishlistItem(wish, now: now)
        try await ledger.deleteAccount(savings)
        let context = fixture.context()
        #expect(try context.fetchCount(FetchDescriptor<SavingsGoal>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<WishlistItem>()) == 0)
    }

    @Test func aGoalLocksTheCurrency() async throws {
        let fixture = try await makeFixture()
        #expect(try await fixture.ledger.isCurrencyLocked() == false)
        try await fixture.ledger.createGoal(GoalDraft(name: "A", target: cad(1_000), accountID: fixture.main), now: now)
        #expect(try await fixture.ledger.isCurrencyLocked())
    }

    // MARK: Backup

    @Test func goalsTravelInBackupsAndOlderFilesHaveNone() async throws {
        let fixture = try await makeFixture()
        let wish = try await addWish(fixture)
        let date = day(2027, 6, 1)
        try await fixture.ledger.createGoal(
            GoalDraft(
                name: "Bike", target: cad(80_000), accountID: fixture.main, targetDate: date, wishlistItemID: wish),
            now: now)
        let service = BackupService.make(container: fixture.container)
        let backup = try await service.snapshot(now: now, appVersion: "1") { _ in nil }
        #expect(backup.goals?.count == 1)
        try BackupValidator.validate(backup)

        let target = try await makeFixture()
        _ = try await BackupService.make(container: target.container).restore(backup, availableMedia: [], now: now)
        let restored = try #require(try target.context().fetch(FetchDescriptor<SavingsGoal>()).first)
        #expect(restored.target == cad(80_000))
        #expect(restored.targetDate == date)
        #expect(restored.wishlistItemID == wish)
        #expect(restored.accountID == fixture.main)

        var older = backup
        older.goals = nil
        _ = try await BackupService.make(container: target.container).restore(older, availableMedia: [], now: now)
        #expect(try target.context().fetchCount(FetchDescriptor<SavingsGoal>()) == 0, "A file without goals has none")
    }

    @Test func restoringUpdatesExistingGoalsInPlaceAndRemovesOthers() async throws {
        let fixture = try await makeFixture()
        let ledger = fixture.ledger
        let draft = GoalDraft(name: "Trip", target: cad(80_000), accountID: fixture.main)
        let kept = try await ledger.createGoal(draft, now: now)
        let service = BackupService.make(container: fixture.container)
        let backup = try await service.snapshot(now: now, appVersion: "1") { _ in nil }

        var changed = draft
        changed.target = cad(50_000)
        try await ledger.updateGoal(kept, with: changed, now: now)
        try await ledger.createGoal(GoalDraft(name: "Extra", target: cad(1_000), accountID: fixture.main), now: now)
        _ = try await service.restore(backup, availableMedia: [], now: now)

        let restored = try fixture.context().fetch(FetchDescriptor<SavingsGoal>())
        #expect(restored.map(\.id) == [kept])
        #expect(restored.first?.target == cad(80_000))
    }

    @Test func exportDropsAGoalLinkToAMissingWishlistItem() async throws {
        let fixture = try await makeFixture()
        let wish = try await addWish(fixture)
        try await fixture.ledger.createGoal(
            GoalDraft(name: "Bike", target: cad(80_000), accountID: fixture.main, wishlistItemID: wish), now: now)
        let service = BackupService.make(container: fixture.container)
        var backup = try await service.snapshot(now: now, appVersion: "1") { _ in nil }
        backup.goals?[0].wishlistItemID = UUID()
        #expect(backup.droppingDanglingLinks() == 1)
        #expect(backup.goals?.first?.wishlistItemID == nil)
        try BackupValidator.validate(backup)
    }

    @Test func theValidatorChecksGoals() async throws {
        let fixture = try await makeFixture()
        let card = try await addAccount(.creditCard, 0, to: fixture)
        let wish = try await addWish(fixture)
        try await fixture.ledger.createGoal(
            GoalDraft(name: "Bike", target: cad(80_000), accountID: fixture.main, wishlistItemID: wish), now: now)
        let service = BackupService.make(container: fixture.container)
        let good = try await service.snapshot(now: now, appVersion: "1") { _ in nil }
        func variant(_ change: (inout BackupDTO.GoalDTO) -> Void) -> BackupDTO {
            var copy = good
            if var first = copy.goals?.first {
                change(&first)
                copy.goals = [first]
            }
            return copy
        }
        var twice = good
        if var copy = good.goals?.first {
            copy.id = UUID()
            twice.goals?.append(copy)
        }
        let tooBig = BackupValidator.maxBudgetMinorUnits + 1
        let cases: [(BackupDTO, BackupError)] = [
            (variant { $0.name = " " }, .invalidValue(entity: "goals", field: "name", value: " ")),
            (
                variant { $0.targetMinorUnits = 0 },
                .invalidValue(entity: "goals", field: "targetMinorUnits", value: "0")
            ),
            (
                variant { $0.targetMinorUnits = tooBig },
                .invalidValue(entity: "goals", field: "targetMinorUnits", value: "\(tooBig)")
            ),
            (variant { $0.currencyCode = "USD" }, .currencyMismatch(entity: "goals")),
            (variant { $0.accountID = UUID() }, .missingReference(entity: "goals", field: "accountID")),
            (variant { $0.accountID = card }, .inconsistentLink(entity: "goals", field: "accountID")),
            (variant { $0.wishlistItemID = UUID() }, .missingReference(entity: "goals", field: "wishlistItemID")),
            (twice, .duplicateID(entity: "goals.wishlistItemID")),
        ]
        for (backup, expected) in cases {
            #expect(throws: expected) { try BackupValidator.validate(backup) }
        }
    }
}
