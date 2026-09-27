import HouseholdHubCore
import SwiftData
import SwiftUI

/// Add several (Sprint 17): paste a list, one task or wishlist item per line. Every line is previewed with what it
/// becomes, or why it is skipped, and the valid ones are added with one save.
struct BatchAddView: View {
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]

    @State private var kind: BatchAddKind
    @State private var text = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(kind: BatchAddKind) {
        _kind = State(initialValue: kind)
    }

    private var currencyCode: String { settings.first?.currencyCode ?? "CAD" }

    private var lines: [BatchLine] {
        guard let currency = try? Currency(code: currencyCode) else { return [] }
        let options = categories.filter { !$0.isArchived }.map {
            QuickAddCategoryOption(id: $0.id, name: $0.name, kind: $0.kind)
        }
        let planner = BatchAddPlanner(
            kind: kind, currency: currency, categories: options, calendar: HouseholdCalendar(timeZone: .current))
        return planner.plan(text, now: .now)
    }

    var body: some View {
        let lines = self.lines
        let count = lines.filter { $0.result.skipReason == nil }.count
        Form {
            Section {
                Picker("Add", selection: $kind) {
                    Text("Tasks").tag(BatchAddKind.tasks)
                    Text("Wishlist").tag(BatchAddKind.wishlist)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("batch.kind")
            }
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .accessibilityLabel("List")
                    .accessibilityIdentifier("batch.text")
            } header: {
                Text("One per line")
            } footer: {
                Text(hint)
            }
            if !lines.isEmpty {
                Section {
                    ForEach(lines) { line in
                        BatchLineRow(line: line, categoryNames: categoryNames)
                    }
                } header: {
                    Text("Preview · \(count) to add")
                        .accessibilityIdentifier("batch.count")
                }
            }
            if let errorMessage {
                Section { ErrorText(errorMessage) }
            }
        }
        .navigationTitle("Add several")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { Task { await save(lines) } }
                    .disabled(count == 0 || isSaving)
                    .accessibilityIdentifier("batch.save")
            }
        }
    }

    private var hint: LocalizedStringKey {
        switch kind {
        case .tasks:
            "A day word sets the due date: today, tomorrow, or a weekday. Example: call plumber friday"
        case .wishlist:
            "A number is the price, #tag picks a category. Example: 250 new bike #home"
        }
    }

    private var categoryNames: [UUID: String] {
        Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private func save(_ lines: [BatchLine]) async {
        guard let services else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            switch kind {
            case .tasks:
                try await services.board.createTasks(lines.taskDrafts, now: .now)
            case .wishlist:
                try await services.transactions.createWishlistItems(lines.wishlistDrafts, now: .now)
            }
            dismiss()
        } catch {
            errorMessage = String(localized: "Nothing was added. Check the list and try again.")
        }
    }
}

/// One previewed line: what it becomes, or why it is skipped.
private struct BatchLineRow: View {
    let line: BatchLine
    let categoryNames: [UUID: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch line.result {
            case .task(let draft):
                Text(draft.title)
                if let due = draft.dueDate {
                    Text("Due \(due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .wishlist(let draft):
                Text(draft.name)
                Text(detail(draft))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .skipped(let reason):
                Text(line.text)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                Text(reasonText(reason))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("batch.line")
    }

    private func detail(_ draft: WishlistDraft) -> String {
        let price =
            draft.estimatedPrice.minorUnits > 0
            ? draft.estimatedPrice.formatted() : String(localized: "Price unknown")
        guard let name = draft.categoryID.flatMap({ categoryNames[$0] }) else { return price }
        return price + " · " + name
    }

    private func reasonText(_ reason: BatchSkipReason) -> String {
        switch reason {
        case .noText: String(localized: "Skipped: nothing left to add")
        case .priceTooLarge: String(localized: "Skipped: the price is too large")
        case .overLimit: String(localized: "Skipped: over the \(BatchAddPlanner.maxItems)-item limit")
        }
    }
}
