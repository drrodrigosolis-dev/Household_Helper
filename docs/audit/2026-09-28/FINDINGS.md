# Full audit — 2026-09-28

- **Audited commit:** `338a877` (build/v1.1; contains the L-020 fixes `d8a2dad` and `909dec3`)
- **Date:** 2026-09-27/28 (America/Vancouver)
- **Device:** iPhone 17 Pro Max Simulator, iOS 26.5 (23F77), Xcode 27.0 (27A266a); Release configuration
- **What was run:**
  - Release builds for device and Simulator (both succeeded).
  - Hand walk of every tab on a fresh install: onboarding ($3,000 start), CSV import of **1,500 synthetic transactions**
    over 12 months (`sample-1500.csv`: grocery, coffee, gas, pizza, pharmacy, hardware, books, streaming, utility,
    salary), search, categorise, long-press menu, Analytics (checked against my own sums), budget create, recurring
    bill create, wishlist add → Mark Purchased → Refund, Dashboard numbers, cold launch, scroll/CPU sampling.
  - Last complete test runs on nearby heads: unit 387/1 and UI 58/61 on `8a9ec36` (reported under L-020).
- **Not audited:** `Scripts/verify.sh` on `338a877` itself (running now under L-021); tasks spring-load by hand
  (L-021); Goals, Themes, Spanish, Face ID, reminders, widget, Shortcuts, backup/restore (walked in L-006/L-009/L-010/
  L-012/L-019, not repeated); the owner's iPhone (device checks); VoiceOver.
- **Data:** Simulator and synthetic sample data only. Screenshots in this folder.
- **Tooling caveat:** my Simulator tap tool sends near-zero-length taps, which some iOS 26 controls ignore (see
  L-011). Findings that may be the tool are marked in Confidence.

## Summary

| ID | Severity | Area | Title | Status |
|---|---|---|---|---|
| A-001 | blocker | Recurring | A bill whose first date is earlier today is silently skipped | open |
| A-002 | medium | Dashboard | A wishlist purchase appears twice in Recent activity | open |
| A-003 | medium | Budget | CSV import stores the Description in Notes, not Merchant | open |
| A-004 | medium | Budget | Number pads can't be dismissed; fields below stay hidden | open |
| A-005 | medium | Budget | Search typing lags ~1 s with 1,500 transactions | open |
| A-006 | medium | Budget | After an import everything is Uncategorized and there is no fast way to sort it | open |
| A-007 | medium | Budget | No bulk actions on transactions | open |
| A-008 | medium | Refunds | "Refund…" on a wishlist-purchase expense did not open (unconfirmed) | open |
| A-009 | medium | Budget | Empty-state "Add budget" did not respond (unconfirmed) | open |
| A-010 | low | Wishlist | Mark Purchased has no Account picker | open |
| A-011 | low | Budget | Re-tapping the Budget tab leaves the title and search collapsed | open |
| A-012 | low | Settings | Re-tapping More doesn't pop to the More root | open |
| A-013 | low | Budget | Two identical "+" buttons with different meanings | open |
| A-014 | low | Budget | Floating + covers row amounts and search results | open |
| A-015 | low | Budget | Transaction editor Save is enabled with no changes | open |
| A-016 | low | Wishlist | "Recorded in Budget as an expense" is not a link | open |
| A-017 | low | Budget | Budgets have no month navigation / history | open |
| A-018 | low | Dashboard | Analytics charts are not interactive; no month-over-month | open |
| A-019 | low | Wishlist | Empty states are inconsistent (some have no Add action) | open |
| A-020 | low | Recurring | Editor shows no upcoming dates and no warning for a past/today start | open |
| A-021 | low | Settings | Row "Backup and export" opens a screen titled "Data" | open |
| A-022 | low | Settings | Account delete confirms first, then refuses (goal uses it) | open |
| A-023 | low | Tasks | Long-press on a Done card opens the menu instead of lifting it | open |

Totals: 23 findings — 1 blocker, 0 high, 8 medium, 14 low. Feature ideas (not findings) are in the appendix.

---

### A-001: A bill whose first date is earlier today is silently skipped
- Severity: blocker (wrong money: a due bill never reaches the balance, projection or Upcoming)
- Area: Recurring
- Where: `HouseholdHubApp/Features/Budget/RecurringEditorView.swift:45` (`startDate = Date.now`); occurrence
  calculation for a start earlier than now (`RecurringTransaction.nextOccurrence`)
- Steps:
  1. Launch, Budget › Recurring › toolbar +.
  2. Bill, Name "Netflix", Expense 17.99, Monthly on a day (day 27 = today), Starts left at today 8:45 PM.
  3. Wait a minute, Save (8:47 PM).
- Expected: today's occurrence is due now (posted or pending per the bill's rule, or listed as due today).
- Actual: row reads "Monthly on day 27 · Next Oct 27, 2026"; no transaction, balance unchanged, Upcoming "Nothing due".
- Evidence: `21-dashboard-after.png` (Upcoming: Nothing due; balance only reflects the $149 purchase),
  `18-recurring-editor.png`.
- Confidence: seen once (reproduce with any start time a minute in the past).
- Suggestion: default Starts to start of today; treat an occurrence on the start day as due regardless of the time.

### A-002: A wishlist purchase appears twice in Recent activity
- Severity: medium
- Area: Dashboard
- Where: `HouseholdHubApp/Features/Dashboard/DashboardView.swift:14–37` (`recent`, `recentWishes` merged)
- Steps: 1. Wishlist › + "Headphones" 149. 2. Open it › Mark Purchased › Record. 3. Dashboard.
- Expected: one row for the purchase.
- Actual: "Headphones · Medium priority · Purchased" (wishlist row) and the $149.00 expense row.
- Evidence: `21-dashboard-after.png`
- Confidence: reproduced every time (2 of 2, also seen in L-012).
- Suggestion: drop purchased items from `recentWishes`, or show only the expense with a wishlist badge.

### A-003: CSV import stores the Description in Notes, not Merchant
- Severity: medium
- Area: Budget
- Where: `HouseholdHubCore/Services/TransactionService+Import.swift:37` and `:51` (`notes: row.description`)
- Steps: 1. More › Settings › Backup and export › Import transactions from CSV… › `sample-1500.csv` › Import.
  2. Budget › open "Pizza Place".
- Expected: Merchant "Pizza Place".
- Actual: Merchant empty ("Optional"), Notes "Pizza Place".
- Evidence: `11-transaction-edit` (in `docs/walk/walk-338a877/`), `13-after-categorize.png`
- Confidence: reproduced every time.
- Suggestion: map Description → merchant (find-or-create `Merchant`), keep Notes empty; data-safety review applies.

### A-004: Number pads can't be dismissed; fields below stay hidden
- Severity: medium
- Area: Budget (all amount fields: 9 `.keyboardType(.decimalPad)` sites)
- Where: every editor with `.decimalPad`; no `.scrollDismissesKeyboard` or keyboard toolbar anywhere in the app (0 hits)
- Steps: 1. Budget › Recurring › + › Amount, type 17.99. 2. Try to reach "Day" and "Starts".
- Expected: a Done key or swipe-down dismisses the keyboard.
- Actual: the pad has no Done; swiping the form down does nothing; the only way out is tapping a text field and Return.
- Evidence: `18-recurring-editor.png` (keyboard over Day/Starts)
- Confidence: reproduced every time.
- Suggestion: `ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focus = nil } }` in a shared
  modifier, plus `.scrollDismissesKeyboard(.interactively)` on forms.

### A-005: Search typing lags ~1 s with 1,500 transactions
- Severity: medium
- Area: Budget
- Where: `HouseholdHubApp/Features/Budget/BudgetView.swift:31` (`.searchable`), filtering on each keystroke
- Steps: 1. With the 1,500-row import, Budget › pull down › Search › type "pizza".
- Expected: characters appear as typed.
- Actual: the field kept its placeholder ~1 s after typing, then updated with results.
- Evidence: `10-search-pizza.png` (final state)
- Confidence: intermittent (2 of 3 attempts).
- Suggestion: debounce ~150 ms and filter off the main actor; measure with Instruments on the device.

### A-006: After an import everything is Uncategorized and there is no fast way to sort it
- Severity: medium
- Area: Budget
- Where: CSV import (Category column "None") and Analytics › Spending by category
- Steps: 1. Import `sample-1500.csv`. 2. More › Analytics.
- Expected: most rows get a suggested category (the app has on-device classification and merchant memory).
- Actual: 99 % "Uncategorized" ($5,240.95 of $5,270.29 this month); the donut is one grey ring; categorising means
  opening rows one by one.
- Evidence: `04-csv-preview.png` ("Uncategorized" on every row), `15-analytics.png`, `16-analytics-2.png`
- Confidence: reproduced every time.
- Suggestion: category suggestions at import (rules + model, reviewed in the preview), and a triage screen reached from
  a Dashboard/Analytics nudge ("1,500 uncategorized — sort them").

### A-007: No bulk actions on transactions
- Severity: medium
- Area: Budget
- Where: transaction list context menu (Edit, Delete only)
- Steps: 1. Budget › long-press any row.
- Expected: a way to set the category/account of many rows at once.
- Actual: only Edit and Delete; no multi-select; no "apply to all from this merchant".
- Evidence: `14-row-menu.png`
- Confidence: reproduced every time.
- Suggestion: Edit mode with multi-select (Set category / Set account / Delete), and after a manual category change on an
  imported row, offer "Apply to all 'Pizza Place'".

### A-008: "Refund…" on a wishlist-purchase expense did not open (unconfirmed)
- Severity: medium
- Area: Refunds
- Where: `HouseholdHubApp/Features/Budget/TransactionEditorView.swift:241` (`Refund…`, `isRefunding`), sheet at `:145`
- Steps: 1. Wishlist › + "Headphones" 149 › Mark Purchased › Record. 2. Budget › Transactions › "Headphones" ›
  Refund… (4 presses, 0 ms and 120–150 ms).
- Expected: the refund sheet opens.
- Actual: nothing; the button is blue (enabled); other controls on the screen respond.
- Evidence: walk screenshots `docs/walk/walk-338a877/` (editor after presses)
- Confidence: seen once, possibly the tap tool (RefundUITests reach this sheet). Needs a finger.

### A-009: Empty-state "Add budget" did not respond (unconfirmed)
- Severity: medium
- Area: Budget
- Where: `HouseholdHubApp/Features/Budget/BudgetsListView.swift:30`
- Steps: 1. Fresh install › Budget › Budgets (none) › tap "Add budget".
- Expected: New Budget sheet.
- Actual: nothing (0 ms and 120 ms presses); the toolbar + opens the sheet.
- Evidence: `17-budgets.png` (after creating via the toolbar)
- Confidence: seen once, possibly the tap tool (the UI test `budgets.addEmpty` passes). Needs a finger.

### A-010: Mark Purchased has no Account picker
- Severity: low
- Area: Wishlist
- Where: Wishlist item › Mark Purchased sheet
- Steps: 1. With a second account, Wishlist item › Mark Purchased.
- Expected: Account picker like the transaction editor.
- Actual: Price paid, Date, Category only; the expense goes to the default account.
- Evidence: `20-mark-purchased.png`
- Confidence: reproduced every time.

### A-011: Re-tapping the Budget tab leaves the title and search collapsed
- Severity: low
- Area: Budget
- Where: Budget tab re-tap
- Steps: 1. Budget › scroll down › tap the Budget tab.
- Expected: list at top with the large title and search field.
- Actual: list at top, inline title, search hidden until you pull down.
- Evidence: walk screenshots after re-tap (`docs/walk/walk-338a877/`)
- Confidence: reproduced every time.

### A-012: Re-tapping More doesn't pop to the More root
- Severity: low
- Area: Settings
- Steps: 1. More › Settings › Backup and export. 2. Dashboard tab. 3. More tab. 4. More tab again.
- Expected: back to More.
- Actual: stays on Data.
- Evidence: `06-import-done.png`
- Confidence: reproduced every time.

### A-013: Two identical "+" buttons with different meanings
- Severity: low
- Area: Budget
- Where: Budget › Recurring and Budgets (toolbar + = new item; floating + = Quick Add)
- Expected: distinguishable actions. Actual: same glyph twice on screen.
- Evidence: `17-budgets.png`
- Confidence: reproduced every time.
- Suggestion: labelled toolbar button ("New budget"), or hide the floating + on those sub-tabs.

### A-014: Floating + covers row amounts and search results
- Severity: low
- Area: Budget
- Where: floating + over lists; also while searching with the keyboard up
- Evidence: `08-budget-list.png`, `09-budget-scrolled.png`, `10-search-pizza.png`
- Confidence: reproduced every time.
- Suggestion: hide it while searching; bottom content inset on every list.

### A-015: Transaction editor Save is enabled with no changes
- Severity: low
- Area: Budget
- Where: `HouseholdHubApp/Features/Budget/TransactionEditorView.swift:139–140` (`disabled(amount == nil || isSaving)`)
- Evidence: editor screenshots in `docs/walk/walk-338a877/`
- Confidence: reproduced every time.

### A-016: "Recorded in Budget as an expense" is not a link
- Severity: low
- Area: Wishlist
- Where: purchased wishlist item detail
- Expected: opens the expense (and its Refund…). Actual: static row; you must find it in Budget.
- Confidence: reproduced every time.

### A-017: Budgets have no month navigation / history
- Severity: low
- Area: Budget
- Where: Budget › Budgets ("September 2026" only)
- Expected: see previous months and how rollover built up. Actual: current month only.
- Evidence: `17-budgets.png`
- Confidence: reproduced every time.

### A-018: Analytics charts are not interactive; no month-over-month
- Severity: low
- Area: Dashboard
- Where: More › Analytics (donut, weekly bars)
- Expected: tap a slice/row/bar → filtered transactions; deltas vs last month. Actual: static.
- Evidence: `15-analytics.png`, `16-analytics-2.png` (totals verified exact against the CSV)
- Confidence: reproduced every time.

### A-019: Empty states are inconsistent
- Severity: low
- Area: Wishlist
- Where: Budgets empty state has "Add budget"; Wishlist ("No wishlist items yet") and Recurring have no action.
- Confidence: reproduced every time.

### A-020: Recurring editor shows no upcoming dates and no warning for a past/today start
- Severity: low
- Area: Recurring
- Where: Recurring editor summary line ("Monthly on day 27")
- Suggestion: list the next three dates; warn when the start is in the past or earlier today (ties to A-001).
- Confidence: reproduced every time.

### A-021: Row "Backup and export" opens a screen titled "Data"
- Severity: low
- Area: Settings
- Evidence: `06-import-done.png`
- Confidence: reproduced every time. (Carried from L-012; logged by cloud as spec naming.)

### A-022: Account delete confirms first, then refuses
- Severity: low
- Area: Settings
- Where: Settings › Accounts › swipe › Delete on an account a savings goal uses
- Expected: refusal up front. Actual: "This can't be undone…" confirmation, then refusal.
- Evidence: `docs/walk/sprint-12/local/delete-account-with-goal-light.png`
- Confidence: reproduced every time. (Carried from L-006.)

### A-023: Long-press on a Done card opens the menu instead of lifting it
- Severity: low
- Area: Tasks
- Where: Tasks › Done column › long-press a card
- Evidence: `docs/walk/sprint-18/local/board-left-longpress-opens-menu.png`
- Confidence: reproduced every time with the tap tool (3 of 3); needs a finger to confirm. (Carried from L-018.)

---

## Performance observations (no action needed unless noted)
- CSV import of 1,500 rows: ~3 s to "Imported 1,500 transactions." (`06-import-done.png`).
- Cold launch to a populated Dashboard (1,500 rows, Release): ~0.6–0.9 s.
- Transaction list fast scrolling: app CPU peaks ~40–48 %, idle within ~2 s; no visible stutter.
- Analytics totals match an independent sum of the CSV exactly (Sept: income $33,600.00, expenses $5,270.29).
- Search lag: see A-005.

## Appendix: feature ideas (owner decision, not findings)
1. Categorisation rules learned from manual edits, applied to imports (pairs with A-006/A-007).
2. Recurring detection from history ("Streaming Co ~monthly — make it a bill?").
3. Undo toast for delete and bulk edits.
4. Duplicate and split transactions.
5. Month-end summary (spent vs budget, top categories, goals).
6. Search filters: amount range, date range, account; saved searches.
7. Budget alerts at 80 % / 100 % (local notifications, names only).
8. Import presets per bank (remember mapping, date format, sign).
