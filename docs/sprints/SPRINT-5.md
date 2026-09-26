# Sprint 5 — Phase 6: Analytics

Planned 2026-09-26 while the owner was away with full authorization; recommended defaults taken and listed below
for review. Binding: §2 (deterministic analytics layer first), §24.2 Analytics row, §24.5 (chart accessibility),
§7.11 (`defaultAnalyticsPeriod`), §9.4, NFR "recompute under 1 s for 5 years of history".

## Defaults taken (owner may overrule)
1. Periods: This month (default), Last month, Last 3 months, This year, Last 12 months — all whole calendar months in
   the household calendar. The selector remembers the last choice as `AppSettings.defaultAnalyticsPeriod`.
2. Analytics count **posted** transactions only: pending, cancelled, and transfers are excluded, and no projected
   recurring occurrences are included (analytics describe what happened; the Dashboard shows the projection).
3. Spending by category: expense totals per category, largest first, with an "Uncategorized" bucket; shown as a donut
   chart plus a table with amounts and shares. Income vs expense trend: grouped bars per week for single-month
   periods, per month otherwise. Top merchants: the five largest by expense, by merchant (name as last entered).
4. Charts use Apple's Swift Charts (system framework, no dependency). Each chart has an `AXChartDescriptor` and the
   same numbers in a visible table, so nothing is available only as an image (§24.5).
5. Tapping a category (slice or table row) opens Budget filtered to that category (§24.2); the period filter is
   "This month" when the analytics period is This month, otherwise "All time" (Budget has no matching ranges).
6. Added after the data-safety review: only transactions that have happened count (dated up to now), matching the
   balance and the Dashboard; a posted item dated in the future is projection, not history. Posted items dated
   before the starting-balance date do count (analytics is history, not balance). Tapping a category opens Budget
   filtered to posted items only.
7. The AI narrative summary waits for Phase 8 (spec: narratives only after deterministic analytics are stable); no
   placeholder is shown.

## Items
| # | Item | Spec | Built (CI green) | Walked |
|---|---|---|---|---|
| 1 | `AnalyticsPeriod` + `AppSettings.defaultAnalyticsPeriod` | §7.11 | ☑ | tests |
| 2 | `AnalyticsEngine` (pure): totals, by category, trend buckets, top merchants | §2, §9.4 | ☑ | tests |
| 3 | `AnalyticsService` (off the main actor) + performance test | §4.4, NFR | ☑ | tests |
| 4 | Analytics screen: period selector, category donut + table, trend bars + table, top merchants | §24.2 | ☑ | ☑ |
| 5 | Chart accessibility: `AXChartDescriptor`s and tables | §24.5 | ☑ | ☑ |
| 6 | Category → Budget filtered | §24.2 | ☑ | ☑ (UI test) |

## Close-out
☑ CI green: run 36216543703 on `a41b742` · ☑ walk screenshots in `docs/walk/sprint-9/run-36214979821` (Sprints 5–9 walked together) and reviewed (large-text category names fixed after) · ☑ data-safety review (totals match the ledger) · ☑ PROGRESS + PR · ☑ WALK-QUEUE (nothing queued)
