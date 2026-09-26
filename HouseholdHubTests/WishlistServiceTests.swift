import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers

@testable import HouseholdHubCore

struct WishlistServiceTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private struct Fixture {
        let container: ModelContainer
        let service: TransactionService
        let categories: CategoryService

        func context() -> ModelContext { ModelContext(container) }

        func item(_ id: UUID) throws -> WishlistItem {
            let items = try context().fetch(FetchDescriptor<WishlistItem>(predicate: #Predicate { $0.id == id }))
            return try #require(items.first)
        }

        func transactions() throws -> [TransactionRecord] {
            try context().fetch(FetchDescriptor<TransactionRecord>())
        }
    }

    private func makeFixture() async throws -> Fixture {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let fixture = Fixture(
            container: container, service: .make(container: container), categories: .make(container: container))
        try await fixture.service.ensureSettings(currencyCode: "CAD", now: now)
        try await fixture.categories.seedSystemCategoriesIfNeeded(now: now)
        return fixture
    }

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func addItem(_ name: String, _ minorUnits: Int64, to fixture: Fixture) async throws -> UUID {
        let draft = WishlistDraft(name: name, estimatedPrice: cad(minorUnits))
        return try await fixture.service.createWishlistItem(draft, now: now)
    }

    @discardableResult
    private func buy(_ id: UUID, _ minorUnits: Int64, category: UUID? = nil, in fixture: Fixture) async throws -> UUID {
        try await fixture.service.purchaseWishlistItem(
            id, actualPrice: cad(minorUnits), occurredAt: now.addingTimeInterval(-60), categoryID: category, now: now)
    }

    private func categoryID(named name: String, in fixture: Fixture) throws -> UUID {
        let all = try fixture.context().fetch(FetchDescriptor<CategoryRecord>())
        return try #require(all.first { $0.name == name }).id
    }

    // MARK: Create and update

    @Test func draftsAreValidatedBeforeAnythingIsStored() async throws {
        let fixture = try await makeFixture()
        let service = fixture.service
        let blank = WishlistDraft(name: "  ", estimatedPrice: cad(100))
        await #expect(throws: WishlistError.emptyName) { try await service.createWishlistItem(blank, now: now) }
        let negative = WishlistDraft(name: "Lamp", estimatedPrice: cad(-1))
        await #expect(throws: WishlistError.negativeEstimate) {
            try await service.createWishlistItem(negative, now: now)
        }
        let purchased = WishlistDraft(name: "Lamp", estimatedPrice: cad(100), status: .purchased)
        await #expect(throws: WishlistError.statusRequiresDedicatedPath(.purchased)) {
            try await service.createWishlistItem(purchased, now: now)
        }
        let usd = WishlistDraft(name: "Lamp", estimatedPrice: Money(minorUnits: 100, currencyCode: "USD"))
        await #expect(throws: LedgerError.currencyMismatch(expected: "CAD", actual: "USD")) {
            try await service.createWishlistItem(usd, now: now)
        }
        let salary = try categoryID(named: "Salary", in: fixture)
        let income = WishlistDraft(name: "Lamp", estimatedPrice: cad(100), categoryID: salary)
        await #expect(throws: LedgerError.categoryKindMismatch(.income, .expense)) {
            try await service.createWishlistItem(income, now: now)
        }
        #expect(try fixture.context().fetchCount(FetchDescriptor<WishlistItem>()) == 0)
    }

    @Test func createStoresTrimmedFieldsAndZeroMeansUnknownPrice() async throws {
        let fixture = try await makeFixture()
        let draft = WishlistDraft(
            name: "  Standing desk ", estimatedPrice: cad(0), priority: .high, notes: "  ", targetDate: now)
        let id = try await fixture.service.createWishlistItem(draft, now: now)
        let item = try fixture.item(id)
        #expect(item.name == "Standing desk")
        #expect(item.estimatedPrice == cad(0))
        #expect(item.priority == .high)
        #expect(item.status == .wanted)
        #expect(item.notes == nil)
        #expect(item.targetDate == now)
    }

    @Test func updateCannotForcePurchasedStatus() async throws {
        let fixture = try await makeFixture()
        let service = fixture.service
        let id = try await addItem("Lamp", 4_000, to: fixture)
        var draft = WishlistDraft(name: "Floor lamp", estimatedPrice: cad(5_000), status: .pending)
        try await service.updateWishlistItem(id, with: draft, now: now)
        #expect(try fixture.item(id).status == .pending)
        #expect(try fixture.item(id).name == "Floor lamp")
        draft.status = .purchased
        await #expect(throws: WishlistError.statusRequiresDedicatedPath(.purchased)) {
            try await service.updateWishlistItem(id, with: draft, now: now)
        }
        #expect(try fixture.transactions().isEmpty)
    }

    // MARK: Purchase (§8.1)

    @Test func purchaseCreatesExactlyOneLinkedExpenseAtomically() async throws {
        let fixture = try await makeFixture()
        let shopping = try categoryID(named: "Shopping", in: fixture)
        let id = try await addItem("Lamp", 4_000, to: fixture)
        let transactionID = try await buy(id, 3_799, category: shopping, in: fixture)

        let records = try fixture.transactions()
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.id == transactionID)
        #expect(record.amount == cad(3_799))
        #expect(record.type == .expense)
        #expect(record.status == .posted)
        #expect(record.source == .wishlistPurchase)
        #expect(record.categoryID == shopping)
        #expect(record.wishlistItemID == id)
        let item = try fixture.item(id)
        #expect(item.status == .purchased)
        #expect(item.purchasedTransactionID == transactionID)
        #expect(item.actualPrice == cad(3_799))

        await #expect(throws: WishlistError.alreadyPurchased) {
            try await buy(id, 3_799, in: fixture)
        }
        #expect(try fixture.transactions().count == 1)
    }

    @Test func refusedPurchaseLeavesNoTrace() async throws {
        let fixture = try await makeFixture()
        let service = fixture.service
        let salary = try categoryID(named: "Salary", in: fixture)
        let id = try await addItem("Lamp", 4_000, to: fixture)
        await #expect(throws: LedgerError.nonPositiveAmount) {
            try await buy(id, 0, in: fixture)
        }
        await #expect(throws: LedgerError.categoryKindMismatch(.income, .expense)) {
            try await buy(id, 10, category: salary, in: fixture)
        }
        try await service.setWishlistItemArchived(true, item: id, now: now)
        await #expect(throws: WishlistError.archived) {
            try await buy(id, 10, in: fixture)
        }
        await #expect(throws: WishlistError.unknownItem) {
            try await buy(UUID(), 10, in: fixture)
        }
        #expect(try fixture.transactions().isEmpty)
        #expect(try fixture.item(id).purchasedTransactionID == nil)
        #expect(try fixture.item(id).actualPriceMinorUnits == nil)
    }

    @Test func editingThePurchaseKeepsTheItemPriceInStep() async throws {
        let fixture = try await makeFixture()
        let service = fixture.service
        let id = try await addItem("Lamp", 4_000, to: fixture)
        let transactionID = try await buy(id, 3_799, in: fixture)
        let edit = TransactionDraft(amount: cad(3_500), type: .expense, occurredAt: now)
        try await service.update(transactionID, with: edit, now: now)
        #expect(try fixture.item(id).actualPrice == cad(3_500))
        #expect(try fixture.transactions().first?.source == .wishlistPurchase)
    }

    @Test func aPurchaseStaysOneLiveExpense() async throws {
        let fixture = try await makeFixture()
        let service = fixture.service
        let id = try await addItem("Lamp", 4_000, to: fixture)
        let transactionID = try await buy(id, 3_799, in: fixture)
        let asIncome = TransactionDraft(amount: cad(3_799), type: .income, occurredAt: now)
        await #expect(throws: LedgerError.purchaseMustStayExpense) {
            try await service.update(transactionID, with: asIncome, now: now)
        }
        let cancelled = TransactionDraft(amount: cad(3_799), type: .expense, occurredAt: now, status: .cancelled)
        await #expect(throws: LedgerError.purchaseCannotBeCancelled) {
            try await service.update(transactionID, with: cancelled, now: now)
        }
        await #expect(throws: LedgerError.purchaseCannotBeCancelled) {
            try await service.setStatus(.cancelled, forTransaction: transactionID, now: now)
        }
        let record = try #require(fixture.transactions().first)
        #expect(record.type == .expense)
        #expect(record.status == .posted)
        #expect(record.amount == cad(3_799))
        // Pending is still allowed: the purchase remains an expense in the pending impact.
        try await service.setStatus(.pending, forTransaction: transactionID, now: now)
        #expect(try fixture.transactions().first?.status == .pending)
        #expect(try fixture.item(id).status == .purchased)
    }

    @Test func editingAPurchasedOrArchivedItemKeepsItsStatusAndLink() async throws {
        let fixture = try await makeFixture()
        let service = fixture.service
        let bought = try await addItem("Lamp", 4_000, to: fixture)
        let transactionID = try await buy(bought, 3_799, in: fixture)
        let archived = try await addItem("Rug", 100, to: fixture)
        try await service.setWishlistItemArchived(true, item: archived, now: now)
        for id in [bought, archived] {
            let draft = WishlistDraft(name: "Renamed", estimatedPrice: cad(1), priority: .high, status: .pending)
            try await service.updateWishlistItem(id, with: draft, now: now)
        }
        #expect(try fixture.item(bought).status == .purchased)
        #expect(try fixture.item(bought).purchasedTransactionID == transactionID)
        #expect(try fixture.item(bought).name == "Renamed")
        #expect(try fixture.item(archived).status == .archived)
    }

    @Test func itemAmountsMustBeInTheItemsCurrency() async throws {
        let fixture = try await makeFixture()
        let service = fixture.service
        let id = try await addItem("Lamp", 4_000, to: fixture)
        let usd = Money(minorUnits: 100, currencyCode: "USD")
        await #expect(throws: LedgerError.currencyMismatch(expected: "CAD", actual: "USD")) {
            try await service.purchaseWishlistItem(id, actualPrice: usd, occurredAt: now, categoryID: nil, now: now)
        }
        await #expect(throws: LedgerError.currencyMismatch(expected: "CAD", actual: "USD")) {
            try await service.updateWishlistItem(id, with: WishlistDraft(name: "Lamp", estimatedPrice: usd), now: now)
        }
        #expect(try fixture.transactions().isEmpty)
    }

    @Test func wishlistItemsLockTheCurrency() async throws {
        let fixture = try await makeFixture()
        _ = try await addItem("Lamp", 4_000, to: fixture)
        await #expect(throws: LedgerError.currencyLockedByExistingRecords) {
            try await fixture.service.completeOnboarding(
                currencyCode: "USD", startingBalance: Money(minorUnits: 0, currencyCode: "USD"), asOf: now, now: now)
        }
    }

    @Test func mediaReferencesAreValidatedAndHandedBack() async throws {
        let fixture = try await makeFixture()
        let service = fixture.service
        let id = try await addItem("Lamp", 4_000, to: fixture)
        await #expect(throws: WishlistError.invalidMediaReference) {
            try await service.setWishlistMedia("../escape.jpg", item: id, now: now)
        }
        let photoA = "Wishlist/00000000-0000-0000-0000-00000000000A.jpg"
        let photoB = "Wishlist/00000000-0000-0000-0000-00000000000B.jpg"
        let first = try await service.setWishlistMedia(photoA, item: id, now: now)
        #expect(first == nil)
        let replaced = try await service.setWishlistMedia(photoB, item: id, now: now)
        #expect(replaced == photoA)
        let deleted = try await service.deleteWishlistItem(id, now: now)
        #expect(deleted == photoB)
    }

    @Test func deletingThePurchaseOfAnArchivedItemKeepsItArchived() async throws {
        let fixture = try await makeFixture()
        let service = fixture.service
        let id = try await addItem("Lamp", 4_000, to: fixture)
        let transactionID = try await buy(id, 3_799, in: fixture)
        try await service.setWishlistItemArchived(true, item: id, now: now)
        try await service.deleteTransaction(transactionID, alsoDisableSeries: false, now: now)
        let item = try fixture.item(id)
        #expect(item.status == .archived)
        #expect(item.purchasedTransactionID == nil)
        try await service.setWishlistItemArchived(false, item: id, now: now)
        #expect(try fixture.item(id).status == .wanted)
    }

    @Test func purchaseMovesTheBalance() async throws {
        let fixture = try await makeFixture()
        let service = fixture.service
        let calendar = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Vancouver")!)
        try await service.setStartingBalance(cad(10_000), asOf: now.addingTimeInterval(-86_400), now: now)
        let id = try await addItem("Lamp", 4_000, to: fixture)
        try await buy(id, 3_799, in: fixture)
        let snapshot = try await service.balanceSnapshot(
            now: now, calendar: calendar, includePendingInProjection: false)
        #expect(snapshot.current == cad(6_201))
    }

    // MARK: Deletion (§8.2)

    @Test func deletingAPurchasedItemKeepsItsTransaction() async throws {
        let fixture = try await makeFixture()
        let service = fixture.service
        let id = try await addItem("Lamp", 4_000, to: fixture)
        try await buy(id, 3_799, in: fixture)
        try await service.deleteWishlistItem(id, now: now)
        #expect(try fixture.context().fetchCount(FetchDescriptor<WishlistItem>()) == 0)
        let records = try fixture.transactions()
        #expect(records.count == 1)
        #expect(records.first?.amount == cad(3_799))
        #expect(records.first?.wishlistItemID == nil)
    }

    @Test func archiveAndRestoreKeepThePurchase() async throws {
        let fixture = try await makeFixture()
        let service = fixture.service
        let wanted = try await addItem("Rug", 100, to: fixture)
        let bought = try await addItem("Lamp", 100, to: fixture)
        try await buy(bought, 90, in: fixture)
        for id in [wanted, bought] {
            try await service.setWishlistItemArchived(true, item: id, now: now)
            #expect(try fixture.item(id).status == .archived)
            try await service.setWishlistItemArchived(false, item: id, now: now)
        }
        #expect(try fixture.item(wanted).status == .wanted)
        #expect(try fixture.item(bought).status == .purchased)
        #expect(try fixture.transactions().count == 1)
    }

    @Test func deletingThePurchaseTransactionRevertsTheItem() async throws {
        let fixture = try await makeFixture()
        let service = fixture.service
        let id = try await addItem("Lamp", 4_000, to: fixture)
        let transactionID = try await buy(id, 3_799, in: fixture)
        try await service.deleteTransaction(transactionID, alsoDisableSeries: false, now: now)
        let item = try fixture.item(id)
        #expect(item.status == .wanted)
        #expect(item.purchasedTransactionID == nil)
        #expect(item.actualPriceMinorUnits == nil)
        #expect(try fixture.transactions().isEmpty)
        // It can be purchased again, still exactly once.
        try await buy(id, 3_700, in: fixture)
        #expect(try fixture.transactions().count == 1)
    }

    @Test func categoriesReferencedByWishlistItemsAreProtected() async throws {
        let fixture = try await makeFixture()
        let custom = try await fixture.categories.create(
            name: "Gadgets", icon: "desktopcomputer", color: .black, kind: .expense, now: now)
        let draft = WishlistDraft(name: "Lamp", estimatedPrice: cad(100), categoryID: custom)
        let id = try await fixture.service.createWishlistItem(draft, now: now)
        await #expect(throws: LedgerError.categoryInUse(referenceCount: 1)) {
            try await fixture.categories.delete(category: custom)
        }
        await #expect(throws: LedgerError.categoryKindMismatch(.income, .expense)) {
            try await fixture.categories.update(
                category: custom, name: "Gadgets", icon: "desktopcomputer", color: .black, kind: .income, now: now)
        }
        let salary = try categoryID(named: "Salary", in: fixture)
        await #expect(throws: LedgerError.categoryKindMismatch(.income, .expense)) {
            try await fixture.categories.reassign(from: custom, to: salary, now: now)
        }
        #expect(try fixture.item(id).categoryID == custom)
        let shopping = try categoryID(named: "Shopping", in: fixture)
        _ = try await fixture.categories.reassign(from: custom, to: shopping, now: now)
        #expect(try fixture.item(id).categoryID == shopping)
        try await fixture.categories.delete(category: custom)
    }
}

struct ImageStoreTests {
    private func makeStore() -> ImageStore {
        let root = FileManager.default.temporaryDirectory.appending(path: "ImageStoreTests-\(UUID().uuidString)")
        return ImageStore(root: root)
    }

    private func pngData(width: Int, height: Int) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let made = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: info)
        let context = try #require(made)
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let png = UTType.png.identifier as CFString
        let destination = try #require(CGImageDestinationCreateWithData(data as CFMutableData, png, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pixelWidth(of url: URL) throws -> Int {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return try #require(properties[kCGImagePropertyPixelWidth] as? Int)
    }

    @Test func savesBoundedImageAndThumbnailThenDeletes() throws {
        let store = makeStore()
        let reference = try store.save(try pngData(width: 3_000, height: 1_000), in: .wishlist)
        #expect(reference.hasPrefix("Wishlist/"))
        let full = try store.url(for: reference)
        let thumbnail = try store.thumbnailURL(for: reference)
        #expect(try pixelWidth(of: full) == 2_048)
        #expect(try pixelWidth(of: thumbnail) == 360)
        try store.delete(reference)
        #expect(!FileManager.default.fileExists(atPath: full.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: thumbnail.path(percentEncoded: false)))
        try store.delete(reference)
    }

    @Test func rejectsUnreadableDataAndEscapingReferences() throws {
        let store = makeStore()
        #expect(throws: ImageStore.ImageStoreError.unreadableImage) {
            try store.save(Data("not an image".utf8), in: .wishlist)
        }
        for bad in ["../secret.jpg", "Wishlist/../../x.jpg", "Other/a.jpg", "Wishlist/.hidden", "a.jpg"] {
            #expect(throws: ImageStore.ImageStoreError.invalidReference) { try store.url(for: bad) }
        }
    }
}
