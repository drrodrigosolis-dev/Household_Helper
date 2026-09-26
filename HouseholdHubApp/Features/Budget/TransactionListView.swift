import HouseholdHubCore
import SwiftData
import SwiftUI

/// Transactions grouped by local day, newest first, loaded in pages (spec §5.4) and filtered in the store.
struct TransactionListView: View {
    private static let pageSize = 200

    let filter: TransactionFilter
    @State private var limit = TransactionListView.pageSize

    var body: some View {
        FilteredTransactions(filter: filter, limit: limit) { limit += TransactionListView.pageSize }
            .id(filter)
    }
}

private struct FilteredTransactions: View {
    @Environment(\.services) private var services
    @Query private var records: [TransactionRecord]
    @Query private var categories: [CategoryRecord]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    let limit: Int
    let loadMore: () -> Void

    @State private var pendingDelete: TransactionRecord?
    @State private var editing: TransactionRecord?
    @State private var errorMessage: String?
    private let calendar = HouseholdCalendar(timeZone: .current)

    init(filter: TransactionFilter, limit: Int, loadMore: @escaping () -> Void) {
        let calendar = HouseholdCalendar(timeZone: .current)
        let start = filter.startDate(now: .now, calendar: calendar) ?? .distantPast
        let categoryID: UUID? = filter.categoryID
        let anyCategory = filter.categoryID == nil
        let status = filter.status?.rawValue ?? ""
        let anyStatus = filter.status == nil
        let accountID: UUID? = filter.accountID
        let anyAccount = filter.accountID == nil
        var descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate {
                $0.occurredAt >= start && (anyCategory || $0.categoryID == categoryID)
                    && (anyStatus || $0.statusRawValue == status)
                    && (anyAccount || $0.accountID == accountID || $0.transferAccountID == accountID)
            },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
        descriptor.fetchLimit = limit
        _records = Query(descriptor)
        self.limit = limit
        self.loadMore = loadMore
    }

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView(
                    "No transactions", systemImage: "list.bullet.rectangle",
                    description: Text("Use Quick Add to record an expense or income."))
            } else {
                List {
                    if let errorMessage {
                        ErrorText(errorMessage)
                    }
                    ForEach(days, id: \.self) { day in
                        Section {
                            ForEach(recordsByDay[day] ?? []) { record in
                                row(record)
                            }
                        } header: {
                            Text(dayLabel(day))
                        }
                    }
                    if records.count >= limit {
                        Button("Show more", action: loadMore)
                            .accessibilityIdentifier("budget.showMore")
                    }
                }
                .listStyle(.insetGrouped)
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

    private func row(_ record: TransactionRecord) -> some View {
        let category = categories.first { $0.id == record.categoryID }
        return TransactionRow(record: record, category: category, accounts: accounts)
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
            } catch {
                errorMessage = String(localized: "That transaction couldn't be deleted. Nothing was changed.")
            }
        }
    }

    private var recordsByDay: [Date: [TransactionRecord]] {
        Dictionary(grouping: records) { calendar.startOfDay(for: $0.occurredAt) }
    }

    private var days: [Date] {
        recordsByDay.keys.sorted(by: >)
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
                icon: record.type == .transfer ? "arrow.left.arrow.right" : category?.icon ?? "questionmark",
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
