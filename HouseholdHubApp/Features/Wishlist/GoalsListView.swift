import Combine
import HouseholdHubCore
import SwiftData
import SwiftUI

/// Wishlist › Goals (Sprint 12 decision 5): each goal's progress against its account's current balance, what is left,
/// and what to save each month to reach it by its date. Reached goals stay until archived. Tapping a row edits it.
struct GoalsListView: View {
    @Environment(\.services) private var services
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var goals: [SavingsGoal]
    @State private var statuses: [GoalStatus] = []
    @State private var editing: GoalEditorView.Mode?
    @State private var showsArchived = false
    @State private var loadFailed = false

    private var storeSaves: some Publisher<Notification, Never> {
        NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)
    }

    private var active: [GoalStatus] { statuses.filter { !$0.rule.isArchived } }
    private var archived: [GoalStatus] { statuses.filter(\.rule.isArchived) }

    var body: some View {
        Group {
            if statuses.isEmpty, !loadFailed {
                ContentUnavailableView {
                    Label("No savings goals", systemImage: "target")
                } description: {
                    Text("Set a target on an account to see how far along you are and what to save each month.")
                } actions: {
                    Button("Add goal") { editing = .create(wishlistItem: nil) }
                        .accessibilityIdentifier("goals.addEmpty")
                }
            } else {
                List {
                    Section {
                        ForEach(active) { status in row(status) }
                    } footer: {
                        Text("Progress is the account's current balance. Goals on the same account share it.")
                    }
                    if !archived.isEmpty {
                        Section {
                            DisclosureGroup("Archived (\(archived.count))", isExpanded: $showsArchived) {
                                ForEach(archived) { status in row(status) }
                            }
                            .accessibilityIdentifier("goals.archived")
                        }
                    }
                    if loadFailed {
                        ErrorText(String(localized: "Goals couldn't be calculated. Your data is safe."))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add goal", systemImage: "plus") { editing = .create(wishlistItem: nil) }
                    .accessibilityIdentifier("goals.add")
            }
        }
        .sheet(item: $editing) { mode in
            NavigationStack { GoalEditorView(mode: mode) }
        }
        .task { await refresh() }
        .onReceive(storeSaves) { _ in Task { await refresh() } }
    }

    private func row(_ status: GoalStatus) -> some View {
        GoalRow(status: status, accountName: accounts.first { $0.id == status.rule.accountID }?.name)
            .contentShape(Rectangle())
            .onTapGesture { edit(status) }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Edits this goal")
    }

    private func edit(_ status: GoalStatus) {
        guard let goal = goals.first(where: { $0.id == status.id }) else { return }
        editing = .edit(goal)
    }

    private func refresh() async {
        guard let services else { return }
        do {
            statuses = try await services.transactions.goalReport(
                now: .now, calendar: HouseholdCalendar(timeZone: .current))
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}

/// One goal: name and account, saved of target, a progress bar, what is left (or "Reached"), and the monthly amount
/// needed by the target date. VoiceOver reads it as one element.
struct GoalRow: View {
    let status: GoalStatus
    let accountName: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            rowLayout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.rule.name)
                    Text(GoalFormat.savedLine(status, accountName: accountName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }
                Text(GoalFormat.leftText(status))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(status.isReached ? Color.green : Color.primary)
                    .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            }
            ProgressView(value: status.progressFraction)
                .tint(status.isReached ? .green : .accentColor)
                .accessibilityHidden(true)
            if let plan = GoalFormat.planText(status) {
                Text(plan)
                    .font(.caption)
                    .foregroundStyle(status.isOverdue ? Color.red : Color.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("goal.row")
    }

    /// Side by side normally; stacked at accessibility text sizes so amounts never truncate.
    private var rowLayout: AnyLayout {
        if typeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        }
        return AnyLayout(HStackLayout(spacing: 12))
    }
}

/// Goal wording (Sprint 12 decisions 3 and 4): words and colour, never colour alone.
enum GoalFormat {
    static func savedLine(_ status: GoalStatus, accountName: String?) -> String {
        let saved = String(localized: "\(status.saved.formatted()) of \(status.rule.target.formatted())")
        guard let accountName else { return saved }
        return saved + " · " + accountName
    }

    static func leftText(_ status: GoalStatus) -> String {
        status.isReached ? String(localized: "Reached") : String(localized: "\(status.remaining.formatted()) left")
    }

    /// "Save $120.00 a month until Mar 2027"; "Target date passed"; nil without a date or once reached.
    static func planText(_ status: GoalStatus) -> String? {
        guard !status.isReached, let date = status.rule.targetDate else { return nil }
        if status.isOverdue {
            return String(localized: "Target date passed")
        }
        guard let perMonth = status.neededPerMonth else { return nil }
        let until = date.formatted(.dateTime.month(.abbreviated).day().year())
        return String(localized: "Save \(perMonth.formatted()) a month until \(until)")
    }
}
