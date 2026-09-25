import HouseholdHubCore
import SwiftData
import SwiftUI

/// Wishlist tab (spec §24.2): priority and status filter chips, a list/grid toggle remembered on this device, and
/// cards with thumbnail, name, priority, and estimated price. Tapping a card opens the detail with Mark Purchased.
struct WishlistView: View {
    enum Layout: String {
        case list
        case grid
    }

    enum StatusFilter: String, CaseIterable, Identifiable {
        case active
        case purchased
        case archived
        case all

        var id: String { rawValue }

        func includes(_ status: WishlistStatus) -> Bool {
            switch self {
            case .active: return status == .wanted || status == .pending
            case .purchased: return status == .purchased
            case .archived: return status == .archived
            case .all: return true
            }
        }

        var title: String {
            switch self {
            case .active: return String(localized: "Active")
            case .purchased: return String(localized: "Purchased")
            case .archived: return String(localized: "Archived")
            case .all: return String(localized: "All")
            }
        }
    }

    @Query(sort: \WishlistItem.createdAt, order: .reverse) private var items: [WishlistItem]
    /// A per-device display preference, deliberately outside the store and backups (spec §7.11).
    @AppStorage("wishlist.layout") private var layout = Layout.list
    @State private var priority: Priority?
    @State private var status = StatusFilter.active
    @State private var isAdding = false

    private var visible: [WishlistItem] {
        // Highest priority first; `items` is newest first and the sort is stable, so ties stay newest first.
        items.filter { status.includes($0.status) && (priority == nil || $0.priority == priority) }
            .sorted { $0.priority > $1.priority }
    }

    var body: some View {
        NavigationStack {
            content
                .safeAreaInset(edge: .top) { chips }
                .quickAddAccess()
                .navigationTitle("Wishlist")
                .navigationDestination(for: UUID.self) { id in
                    WishlistDetailView(itemID: id)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { layoutToggle }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add item", systemImage: "plus") { isAdding = true }
                            .accessibilityIdentifier("wishlist.add")
                    }
                }
                .sheet(isPresented: $isAdding) {
                    NavigationStack { WishlistEditorView(item: nil) }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if visible.isEmpty {
            ContentUnavailableView(
                emptyTitle, systemImage: "heart",
                description: Text("Add things you're saving for. Mark them purchased to record the expense."))
        } else if layout == .grid {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(visible) { item in
                        NavigationLink(value: item.id) { WishlistCard(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        } else {
            List(visible) { item in
                NavigationLink(value: item.id) { WishlistRow(item: item) }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var emptyTitle: String {
        items.isEmpty ? String(localized: "No wishlist items yet") : String(localized: "Nothing matches these filters")
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Priority", selection: $priority) {
                        Text("Any priority").tag(Priority?.none)
                        ForEach(Priority.allCases.reversed(), id: \.self) { value in
                            Text(WishlistFormat.priorityText(value)).tag(Priority?.some(value))
                        }
                    }
                } label: {
                    chipLabel(priorityChipTitle, active: priority != nil)
                }
                .accessibilityIdentifier("wishlist.priorityFilter")
                Menu {
                    Picker("Status", selection: $status) {
                        ForEach(StatusFilter.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                } label: {
                    chipLabel(status.title, active: status != .active)
                }
                .accessibilityIdentifier("wishlist.statusFilter")
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    private var priorityChipTitle: String {
        guard let priority else { return String(localized: "Any priority") }
        return WishlistFormat.priorityText(priority)
    }

    private func chipLabel(_ title: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(active ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12)))
    }

    private var layoutToggle: some View {
        Button {
            layout = layout == .list ? .grid : .list
        } label: {
            Label(layoutToggleTitle, systemImage: layout == .list ? "square.grid.2x2" : "list.bullet")
        }
        .accessibilityIdentifier("wishlist.layout")
    }

    private var layoutToggleTitle: String {
        layout == .list ? String(localized: "Show as grid") : String(localized: "Show as list")
    }
}

/// List presentation: thumbnail, name, priority and status, estimated price. Read by VoiceOver as one element.
struct WishlistRow: View {
    let item: WishlistItem
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            WishlistThumbnail(reference: item.mediaReference)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                Text(WishlistItemSummary.subtitle(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if typeSize.isAccessibilitySize {
                    AmountText(WishlistItemSummary.price(item))
                }
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 8)
                AmountText(WishlistItemSummary.price(item))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wishlist.row")
    }
}

/// Grid presentation of the same information.
struct WishlistCard: View {
    let item: WishlistItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WishlistThumbnail(reference: item.mediaReference, size: nil)
            Text(item.name)
                .font(.headline)
                .lineLimit(2)
            Text(WishlistItemSummary.subtitle(item))
                .font(.caption)
                .foregroundStyle(.secondary)
            AmountText(WishlistItemSummary.price(item), font: .subheadline)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemGroupedBackground)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wishlist.row")
    }
}

enum WishlistItemSummary {
    /// "High priority · Pending": priority is always spelled out, so it never relies on an icon or color alone.
    static func subtitle(_ item: WishlistItem) -> String {
        var parts = [String(localized: "\(WishlistFormat.priorityText(item.priority)) priority")]
        if item.status != .wanted {
            parts.append(WishlistFormat.statusText(item.status))
        }
        return parts.joined(separator: " · ")
    }

    /// The price actually paid once purchased, otherwise the estimate.
    static func price(_ item: WishlistItem) -> String {
        if let actual = item.actualPrice {
            return actual.formatted()
        }
        return WishlistFormat.estimateText(item.estimatedPrice)
    }
}

#Preview {
    WishlistView()
}
