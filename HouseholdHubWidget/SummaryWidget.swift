import HouseholdHubCore
import SwiftUI
import WidgetKit

/// The Home Screen widget (spec §24.4): small and medium only, reading the snapshot the app writes. It has no
/// buttons that act on data; its only action opens Quick Add in the app.
struct SummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: SummaryProvider()) { entry in
            SummaryWidgetView(snapshot: entry.snapshot)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Household Hub")
        .description("Your current balance, what's pending, and what's coming up.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SummaryEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// The app reloads the timeline after writing a snapshot, so a single entry that never expires is enough.
struct SummaryProvider: TimelineProvider {
    private var source: any WidgetDataProvider {
        let identifier = Bundle.main.object(forInfoDictionaryKey: WidgetSnapshot.appGroupInfoKey) as? String
        return WidgetDataSource.provider(groupIdentifier: identifier)
    }

    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: .now, snapshot: .sample(now: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SummaryEntry) -> Void) {
        let now = Date.now
        let snapshot: WidgetSnapshot = context.isPreview ? .sample(now: now) : source.snapshot(now: now)
        completion(SummaryEntry(date: now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SummaryEntry>) -> Void) {
        let now = Date.now
        completion(Timeline(entries: [SummaryEntry(date: now, snapshot: source.snapshot(now: now))], policy: .never))
    }
}

struct SummaryWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    // §9: "Current", "Pending", and "In 30 days" are labelled separately, never all "balance".
    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Current").font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Current balance")
                Spacer()
                Image(systemName: "plus.circle.fill").foregroundStyle(.tint).accessibilityHidden(true)
            }
            amount(snapshot.current)
                .font(.title2.weight(.semibold))
                .privacySensitive()
            Spacer(minLength: 0)
            Text(pendingLine).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                .privacySensitive()
        }
        .widgetURL(WidgetSnapshot.quickAddURL)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Quick Add")
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                figure("Current", snapshot.current)
                figure("In \(snapshot.projectionDays) days", snapshot.projected)
                Spacer(minLength: 0)
                Link(destination: WidgetSnapshot.quickAddURL) {
                    Label("Quick Add", systemImage: "plus.circle.fill").font(.caption.weight(.semibold))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Upcoming").font(.caption).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
                if snapshot.upcoming.isEmpty {
                    Text("Nothing due soon").font(.caption)
                }
                ForEach(Array(snapshot.upcoming.enumerated()), id: \.offset) { _, item in
                    upcomingRow(item)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }

    private func figure(_ title: LocalizedStringKey, _ money: Money?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            amount(money).font(.headline).privacySensitive()
        }
        .accessibilityElement(children: .combine)
    }

    private func upcomingRow(_ item: WidgetSnapshot.Upcoming) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title ?? (item.isIncome ? String(localized: "Income") : String(localized: "Expense")))
                .font(.caption.weight(.medium)).lineLimit(1)
            HStack(spacing: 4) {
                Text(item.date, format: .dateTime.month(.abbreviated).day())
                if let minor = item.amountMinorUnits {
                    Text(signed(minor, isIncome: item.isIncome))
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .privacySensitive()
        .accessibilityElement(children: .combine)
    }

    private func amount(_ money: Money?) -> some View {
        Text(money?.formatted() ?? String(localized: "Hidden"))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }

    private var pendingLine: String {
        guard let pending = snapshot.pendingImpact else { return String(localized: "Pending hidden") }
        if pending.isZero { return String(localized: "Nothing pending") }
        return String(localized: "Pending \(pending.formatted())")
    }

    private func signed(_ minor: Int64, isIncome: Bool) -> String {
        let money = Money(minorUnits: isIncome ? minor : -minor, currencyCode: snapshot.currencyCode)
        return (isIncome ? "+" : "") + money.formatted()
    }
}

#Preview(as: .systemSmall) {
    SummaryWidget()
} timeline: {
    SummaryEntry(date: .now, snapshot: .sample(now: .now))
}

#Preview(as: .systemMedium) {
    SummaryWidget()
} timeline: {
    SummaryEntry(date: .now, snapshot: .sample(now: .now))
}
