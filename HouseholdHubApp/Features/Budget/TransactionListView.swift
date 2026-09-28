import HouseholdHubCore
import SwiftData
import SwiftUI

/// Transactions grouped by local day, newest first, loaded in pages (spec §5.4) and filtered in the store.
struct TransactionListView: View {
    private static let pageSize = 200

    let filter: TransactionFilter
    /// Sprint 14: words in the notes, merchant, category or account, or an exact amount.
    var search = ""
    /// Sprint 23 (A-007): Select mode, turned on and off from the Budget toolbar.
    @Binding var isSelecting: Bool
    @State private var limit = TransactionListView.pageSize

    var body: some View {
        FilteredTransactions(filter: filter, search: SearchQuery(search), limit: limit, isSelecting: $isSelecting) {
            limit += TransactionListView.pageSize
        }
        .id(filter)
    }
}

/// Sprint 23 (A-007): the rules the Select mode's bulk actions follow. Each change still goes through the transaction
/// service one record at a time, so every rule of a single edit or delete applies to each.
enum BulkEdit {
    /// Transfers never have a category, and a refund takes its purchase's, so neither is recategorized.
    static func canSetCategory(_ type: TransactionType) -> Bool {
        type == .expense || type == .income
    }

    /// Active categories that allow every recategorizable type among the selected transactions.
    static func categories(_ all: [CategoryRecord], for types: Set<TransactionType>) -> [CategoryRecord] {
        all.filter { category in !category.isArchived && types.allSatisfy { category.kind.allows($0) } }
    }

    /// The edit that changes only the category; the service validates it like any other edit and learns the
    /// merchant's category from it.
    static func draft(_ record: TransactionRecord, categoryID: UUID) -> TransactionDraft {
        TransactionDraft(
            amount: record.amount, type: record.type, occurredAt: record.occurredAt, status: record.status,
            categoryID: categoryID, merchantName: record.merchantNameSnapshot, notes: record.notes,
            accountID: record.accountID)
    }

    /// Refunds go first, so a purchase whose refunds are also selected can be deleted after them.
    static func deletionOrder(_ records: [TransactionRecord]) -> [TransactionRecord] {
        records.filter { $0.type == .refund } + records.filter { $0.type != .refund }
    }
}

/// One day's transactions in the list.
private struct TransactionDay {
    let day: Date
    let records: [TransactionRecord]
}

private struct FilteredTransactions: View {
    @Environment(\.services) private var services
    @Environment(AppRouter.self) private var router
    @Query private var records: [TransactionRecord]
    @Query private var categories: [CategoryRecord]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    let limit: Int
    let loadMore: () -> Void
    let search: SearchQuery
    /// Whether a filter narrows the list, so the empty state can offer to clear it.
    let isFiltered: Bool
    @Binding var isSelecting: Bool

    @State private var pendingDelete: TransactionRecord?
    @State private var editing: TransactionRecord?
    @State private var errorMessage: String?
    @State private var selection: Set<UUID> = []
    @State private var isPickingCategory = false
    @State private var isConfirmingBulkDelete = false
    @State private var isWorking = false
    private let calendar = HouseholdCalendar(timeZone: .current)

    init(
        filter: TransactionFilter, search: SearchQuery, limit: Int, isSelecting: Binding<Bool>,
        loadMore: @escaping () -> Void
    ) {
        var descriptor = filter.fetchDescriptor(now: .now, calendar: HouseholdCalendar(timeZone: .current))
        // A search looks through everything the filter allows; the household's history is small.
        if search.isEmpty {
            descriptor.fetchLimit = limit
        }
        _records = Query(descriptor)
        _isSelecting = isSelecting
        self.search = search
        self.limit = limit
        self.loadMore = loadMore
        self.isFiltered = filter.isActive
    }

    var body: some View {
        // Narrowed once per update, not once per section (A-005).
        let shown = matchingRecords()
        Group {
            if shown.isEmpty, isFiltered || !search.isEmpty {
                // Found in the local Sprint 10 walk: an empty filtered list must say the filter hides everything.
                ContentUnavailableView {
                    Label("No matching transactions", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Nothing matches these filters.")
                } actions: {
                    if isFiltered {
                        Button("Clear Filters") { router.budgetFilter = TransactionFilter() }
                            .accessibilityIdentifier("budget.clearFilters")
                    }
                }
            } else if shown.isEmpty {
                ContentUnavailableView {
                    EmptyStateLabel(Text("No transactions"), systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Use Quick Add to record an expense or income.")
                }
            } else {
                list(shown)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                bulkBar(shown.filter { selection.contains($0.id) })
            }
        }
        .onChange(of: isSelecting) {
            if !isSelecting {
                selection = []
            }
        }
        .navigationDestination(item: $editing) { record in
            if record.type == .transfer {
                TransferEditorView(record: record)
            } else {
                TransactionEditorView(record: record)
            }
        }
        .confirmationDialog(
            "Delete this transaction?", isPresented: deleteDialogShown, titleVisibility: .visible,
            presenting: pendingDelete
        ) { record in
            deleteActions(for: record)
        } message: { record in
            Text(deleteMessage(for: record))
        }
    }

    private func list(_ shown: [TransactionRecord]) -> some View {
        List(selection: selectionBinding) {
            if let errorMessage {
                ErrorText(errorMessage)
            }
            ForEach(Self.days(shown, calendar: calendar), id: \.day) { section in
                Section {
                    ForEach(section.records) { record in
                        row(record).themedRow()
                    }
                } header: {
                    Text(dayLabel(section.day))
                }
            }
            if search.isEmpty, records.count >= limit {
                Button("Show more", action: loadMore)
                    .accessibilityIdentifier("budget.showMore")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, Binding.constant(isSelecting ? EditMode.active : EditMode.inactive))
    }

    /// Rows are selectable only in Select mode; otherwise a tap opens the editor.
    private var selectionBinding: Binding<Set<UUID>>? {
        isSelecting ? $selection : nil
    }

    @ViewBuilder
    private func row(_ record: TransactionRecord) -> some View {
        let category = categories.first { $0.id == record.categoryID }
        if isSelecting {
            TransactionRow(record: record, category: category, accounts: accounts)
                .tag(record.id)
        } else {
            TransactionRow(record: record, category: category, accounts: accounts)
                .contentShape(Rectangle())
                .onTapGesture { editing = record }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the editor")
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) { pendingDelete = record }
                    Button("Edit") { editing = record }
                        .tint(.blue)
                }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { editing = record }
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = record }
                }
                .accessibilityAction(named: "Edit") { editing = record }
                .accessibilityAction(named: "Delete") { pendingDelete = record }
        }
    }

    @ViewBuilder
    private func deleteActions(for record: TransactionRecord) -> some View {
        if record.recurringSeriesID != nil {
            Button("Delete this occurrence", role: .destructive) { delete(record, disableSeries: false) }
            Button("Delete this occurrence and disable the series", role: .destructive) {
                delete(record, disableSeries: true)
            }
        } else {
            Button("Delete transaction", role: .destructive) { delete(record, disableSeries: false) }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func deleteMessage(for record: TransactionRecord) -> String {
        if record.recurringSeriesID != nil {
            return String(
                localized: "This occurrence will be marked as skipped. The series keeps running unless you disable it.")
        }
        if record.wishlistItemID != nil {
            return String(
                localized: "It will be removed from history and balances; its wishlist item is no longer purchased.")
        }
        return String(localized: "It will be removed from your history and balances.")
    }

    private var deleteDialogShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func delete(_ record: TransactionRecord, disableSeries: Bool) {
        let id = record.id
        pendingDelete = nil
        Task {
            do {
                try await services?.transactions.deleteTransaction(id, alsoDisableSeries: disableSeries, now: .now)
                errorMessage = nil
            } catch LedgerError.purchaseHasRefunds {
                errorMessage = String(localized: "This purchase has refunds. Delete its refunds first.")
            } catch {
                errorMessage = String(localized: "That transaction couldn't be deleted. Nothing was changed.")
            }
        }
    }

    // MARK: Select mode (Sprint 23, A-007)

    /// Set category… and Delete for the selected rows, under the list.
    private func bulkBar(_ selected: [TransactionRecord]) -> some View {
        let categorizable = selected.filter { BulkEdit.canSetCategory($0.type) }
        return HStack {
            Button("Set category…", systemImage: "folder") { isPickingCategory = true }
                .disabled(categorizable.isEmpty || isWorking)
                .accessibilityIdentifier("transactions.bulkCategory")
            Spacer(minLength: 8)
            Text("\(selected.count) selected")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("transactions.selectedCount")
            Spacer(minLength: 8)
            Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingBulkDelete = true }
                .disabled(selected.isEmpty || isWorking)
                .accessibilityIdentifier("transactions.bulkDelete")
                .confirmationDialog(
                    Text("Delete \(selected.count) transactions?"), isPresented: $isConfirmingBulkDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete \(selected.count) transactions", role: .destructive) { bulkDelete(selected) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(bulkDeleteMessage(selected))
                }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
        .sheet(isPresented: $isPickingCategory) {
            NavigationStack {
                bulkCategoryPicker(categorizable, skipped: selected.count - categorizable.count)
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// Active categories valid for every selected type; transfers and refunds are left as they are.
    private func bulkCategoryPicker(_ categorizable: [TransactionRecord], skipped: Int) -> some View {
        let options = BulkEdit.categories(categories, for: Set(categorizable.map(\.type)))
            .sorted { $0.sortOrder < $1.sortOrder }
        return List {
            Section {
                ForEach(options) { category in
                    Button {
                        setCategory(category.id, on: categorizable)
                    } label: {
                        Label {
                            Text(category.name)
                        } icon: {
                            CategoryBadge(icon: category.icon, color: category.color)
                        }
                    }
                    .accessibilityIdentifier("transactions.bulkCategoryOption")
                }
            } footer: {
                if skipped > 0 {
                    Text("Transfers and refunds keep their own category, so \(skipped) selected will be skipped.")
                }
            }
        }
        .navigationTitle("Set category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { isPickingCategory = false }
            }
        }
    }

    private func bulkDeleteMessage(_ selected: [TransactionRecord]) -> String {
        var parts = [String(localized: "They will be removed from your history and balances.")]
        if selected.contains(where: { $0.recurringSeriesID != nil }) {
            parts.append(String(localized: "Recurring occurrences are marked as skipped; their series keep running."))
        }
        if selected.contains(where: { $0.wishlistItemID != nil }) {
            parts.append(String(localized: "Wishlist items they bought are no longer purchased."))
        }
        if selected.contains(where: { $0.type == .expense }) {
            parts.append(String(localized: "A purchase that still has refunds is kept."))
        }
        return parts.joined(separator: " ")
    }

    /// Changes each record through the service's update, so validation and merchant memory apply. Records that fail
    /// stay selected and are counted in the message.
    private func setCategory(_ categoryID: UUID, on categorizable: [TransactionRecord]) {
        let drafts = categorizable.map { ($0.id, BulkEdit.draft($0, categoryID: categoryID)) }
        isPickingCategory = false
        guard let services, !drafts.isEmpty else { return }
        isWorking = true
        Task {
            var failed: Set<UUID> = []
            for (id, draft) in drafts {
                do {
                    try await services.transactions.update(id, with: draft, now: .now)
                } catch {
                    failed.insert(id)
                }
            }
            isWorking = false
            finishBulk(failed: failed)
            if !failed.isEmpty {
                errorMessage = String(
                    localized: "\(failed.count) of \(drafts.count) couldn't be changed. They are still selected.")
            }
        }
    }

    /// Deletes each record through the service, as a single delete would: an occurrence is marked skipped, a purchase
    /// with refunds is refused, a wishlist purchase reverts its item. Records that fail stay selected.
    private func bulkDelete(_ selected: [TransactionRecord]) {
        let ids = BulkEdit.deletionOrder(selected).map(\.id)
        guard let services, !ids.isEmpty else { return }
        isWorking = true
        Task {
            var failed: Set<UUID> = []
            var hasRefunds = 0
            for id in ids {
                do {
                    try await services.transactions.deleteTransaction(id, alsoDisableSeries: false, now: .now)
                } catch LedgerError.purchaseHasRefunds {
                    failed.insert(id)
                    hasRefunds += 1
                } catch {
                    failed.insert(id)
                }
            }
            isWorking = false
            finishBulk(failed: failed)
            if hasRefunds > 0 {
                errorMessage = String(
                    localized: "\(hasRefunds) purchases have refunds and were kept. Delete their refunds first.")
            } else if !failed.isEmpty {
                errorMessage = String(
                    localized: "\(failed.count) of \(ids.count) couldn't be deleted. They are still selected.")
            }
        }
    }

    /// Leaves Select mode after a full success; otherwise keeps only the failed rows selected.
    private func finishBulk(failed: Set<UUID>) {
        if failed.isEmpty {
            errorMessage = nil
            isSelecting = false
        } else {
            selection = failed
        }
    }

    /// The fetched records narrowed by the search, if any. Names are looked up by id once per pass (A-005).
    private func matchingRecords() -> [TransactionRecord] {
        guard !search.isEmpty else { return records }
        let categoryNames = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let accountNames = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return records.filter { record in
            let fields = [
                record.notes, record.merchantNameSnapshot, record.categoryID.flatMap { categoryNames[$0] },
                record.accountID.flatMap { accountNames[$0] }, record.transferAccountID.flatMap { accountNames[$0] },
            ]
            return search.matches(fields, amount: record.amount)
        }
    }

    /// Records grouped by local day, newest day first.
    private static func days(_ records: [TransactionRecord], calendar: HouseholdCalendar) -> [TransactionDay] {
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.occurredAt) }
        return grouped.keys.sorted(by: >).map { TransactionDay(day: $0, records: grouped[$0] ?? []) }
    }

    private func dayLabel(_ day: Date) -> String {
        switch calendar.relativeDay(for: day, now: .now) {
        case .today: return String(localized: "Today")
        case .yesterday: return String(localized: "Yesterday")
        case .tomorrow: return String(localized: "Tomorrow")
        case .earlierThisWeek, .other: return day.formatted(.dateTime.weekday(.wide).month().day())
        }
    }
}

/// One transaction: category badge, title, category/status line, signed amount (VoiceOver reads it as one element).
struct TransactionRow: View {
    let record: TransactionRecord
    let category: CategoryRecord?
    /// Every account, so a row can name its own when there is more than one (Sprint 10 decision 7).
    var accounts: [Account] = []
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Transfers and refunds show what they are; everything else shows its category's icon.
    static func badgeIcon(_ type: TransactionType) -> String? {
        switch type {
        case .transfer: "arrow.left.arrow.right"
        case .refund: "arrow.uturn.backward"
        case .income, .expense: nil
        }
    }

    private func accountName(_ id: UUID?) -> String? {
        accounts.first { $0.id == id }?.name
    }

    private var title: String {
        if record.type == .transfer {
            let destination = accountName(record.transferAccountID) ?? String(localized: "another account")
            return record.notes ?? String(localized: "Transfer to \(destination)")
        }
        return record.merchantNameSnapshot ?? record.notes ?? category?.name ?? String(localized: "Transaction")
    }

    private var subtitle: String {
        var parts: [String] = []
        if record.type == .refund {
            parts.append(String(localized: "Refund"))
        }
        if record.type == .transfer {
            let source = accountName(record.accountID) ?? String(localized: "another account")
            let destination = accountName(record.transferAccountID) ?? String(localized: "another account")
            parts.append(String(localized: "\(source) → \(destination)"))
        } else if accounts.count > 1, let name = accountName(record.accountID) {
            parts.append(name)
        }
        if let category, record.merchantNameSnapshot != nil || record.notes != nil {
            parts.append(category.name)
        }
        if record.status != .posted {
            parts.append(LedgerFormat.statusText(record.status))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(
                icon: Self.badgeIcon(record.type) ?? category?.icon ?? "questionmark",
                color: category?.color)
            rowLayout {
                details
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }
                AmountText(LedgerFormat.signedAmount(record.amount, type: record.type))
                    .strikethrough(record.status == .cancelled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("transaction.row")
    }

    /// Amount moves under the title at accessibility text sizes instead of squeezing both onto one line.
    private var rowLayout: AnyLayout {
        if typeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        }
        return AnyLayout(HStackLayout(spacing: 8))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
