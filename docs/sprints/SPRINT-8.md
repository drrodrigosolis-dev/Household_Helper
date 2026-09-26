# Sprint 8 — Phase 9: Optional system surfaces

Planned 2026-09-26 while CI verified Sprints 5–7 and the owner was away with full authorization; recommended
defaults taken and listed below for review. Implementation starts only once `build/v1` head is green (§28 gate).
Binding: §21 Phase 9, §5.2 (widget/App Group boundary), §24.4 (widget content), §11.2 and §0 (free Personal Team:
no App Group, no paid capability may become a dependency), §9 (current vs pending vs projected are never all
"balance"), §7.11 (`widgetShowsBalance`).

## Defaults taken (owner may overrule)
1. **The widget reads a small snapshot, not the SwiftData store.** The app computes a `WidgetSnapshot` (current
   balance, pending impact, projected 30-day balance, next two upcoming recurring items, generated-at date) with
   the same Core functions the Dashboard uses, and `WidgetSyncService` writes it as JSON after every ledger change
   and on launch. The extension never opens the store, so there is no second container, no cross-process
   migration risk, and nothing in the widget can write financial data. (§5.2 allows either; this is the smaller
   surface. Recorded in `docs/research/apple-api-decisions.md`.)
2. **Providers per §5.2:** `WidgetDataProvider` protocol with `FreeDevelopmentWidgetDataProvider` (fixture
   snapshot for simulator and previews) and `AppGroupWidgetDataProvider` (reads the snapshot from the App Group
   container). The App Group identifier comes from a build setting (`HH_APP_GROUP`, empty by default) exposed in
   Info.plist, never hard-coded; the App Group path is used only when the identifier is set **and**
   `containerURL(forSecurityApplicationGroupIdentifier:)` returns a URL. With the free Personal Team the widget
   shows the fixture data in the same design (§24.4 forbids a visible difference).
3. **Two sizes only (§24.4):** small = current balance + one-line pending impact; medium = current, projected
   30-day, next two recurring items. Labels say "Current", "Pending", "In 30 days" — never three "balances" (§9).
4. **`widgetShowsBalance` defaults to on** and lives in Settings › Widget; off shows "Hidden" in place of amounts
   (the snapshot then carries no amounts at all). Backed up with the other settings as an optional field.
5. **Quick Add from the widget** is a deep link (`householdhub://quickadd`, a URL scheme — no entitlement): `Link`
   on the medium widget, `widgetURL` on the small one. Apple asks that widget buttons "do more than open the app",
   and a widget `Button(intent:)` runs in the extension process, so the widget has no intent button. Shortcuts get
   `OpenQuickAddIntent` (`supportedModes = .foreground(.immediate)`, iOS 26; `openAppWhenRun` is deprecated),
   which asks a main-actor navigator (registered with `AppDependencyManager`) to show the Quick Add sheet.
6. **Shortcuts intent `LogTransactionIntent`** takes one text parameter in the §25 grammar ("47.50 coffee"),
   parses it with `QuickAddParser` (never the model), and asks for confirmation showing the parsed amount, type and
   date (`requestConfirmation(conditions:actionName:dialog:)`) before saving through `TransactionService` with source
   `.widget`. No amount → the intent fails with a
   message and saves nothing. It runs in the app process (no App Group needed).
7. No Lock Screen / Control Center / Live Activity surfaces in v1 (not in §24.4).

## Items
| # | Item | Spec | Built (CI green) | Walked |
|---|---|---|---|---|
| 1 | Verify WidgetKit / App Intents API shapes for iOS 26 (research skill) and record | §19.1 | ☐ | doc |
| 2 | `WidgetSnapshot` + builder in Core, parity with Dashboard figures | §9, §24.4 | ☐ | tests |
| 3 | `WidgetDataProvider` (fixture + App Group) and `WidgetSyncService` (write on change) | §5.2 | ☐ | tests |
| 4 | Widget extension target in `project.yml` (small + medium), fixture previews | §24.4 | ☐ | ☐ |
| 5 | `widgetShowsBalance` setting + Settings › Widget + backup field | §7.11 | ☐ | ☐ |
| 6 | Deep link + `OpenQuickAddIntent` | §24.4 | ☐ | UI test |
| 7 | `LogTransactionIntent` with confirmation, parser only | §25 | ☐ | tests |

## Close-out
☐ CI green on final head · ☐ walk screenshots saved to `docs/walk/sprint-8/` and reviewed · ☐ data-safety review
(intent writes, snapshot contents) · ☐ migration audit (new setting) · ☐ PROGRESS + PR · ☐ WALK-QUEUE (widget on the
Home Screen and Shortcuts on a device; App Group path once a paid team exists)
