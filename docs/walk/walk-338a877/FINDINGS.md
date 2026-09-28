# Full click-through — findings for the next cloud sprint

Build: Release, `338a877` (includes the L-020 fixes `d8a2dad`), iPhone 17 Pro Max Simulator, iOS 26.5, Xcode 27.0.
Data: fresh install, $3,000 starting balance, **1,500 imported sample transactions over 12 months** (synthetic CSV:
grocery, coffee, gas, pizza, pharmacy, hardware, books, streaming, utility, salary), plus a budget, a recurring bill, a
wishlist purchase. Screenshots: `docs/walk/walk-338a877/`. Earlier walks' open items are folded in (marked *carried*).

Priority: **P1** wrong or blocked behaviour · **P2** friction a tester will hit · **P3** polish · **F** feature idea.
"Unconfirmed" means my Simulator tap tool may be the cause; check by hand before fixing.

## 1. Bugs

| # | Pri | Where | What happens | Expected |
|---|---|---|---|---|
| B1 | P1 | Recurring › new bill | Bill created with start **today** at a time a minute earlier (8:45 PM, saved 8:47) shows "Next Oct 27". Today's occurrence is neither posted nor pending — silently skipped; balance unchanged. | A first occurrence due today (or earlier today) is due now: posted/pending per the bill's rule, or at least listed as due today. Default start time should not be "now" (use start of day). |
| B2 | P1 | Dashboard › Recent activity | A wishlist purchase shows **twice**: the wishlist item ("Headphones · Medium priority · Purchased") and its expense transaction. | One row (the expense, with a wishlist badge), or the item row only while it's unbought. |
| B3 | P2 | CSV import | The CSV "Description" column is stored in **Notes**, not **Merchant**. Imported rows have no merchant, so merchant memory, grouping and per-merchant views can't use them; the Merchant field reads "Optional". | Map Description → Merchant (keep Notes empty), or offer both in the column mapping. |
| B4 | P2 | Budget tab › tap tab again | Scrolls the list to the top, but the large "Budget" title and the search field stay collapsed; you must pull down to get search back. | Tab re-tap: scroll to top **and** restore the large title/search. |
| B5 | P2 | More tab | Re-tapping More while deep in Settings › Data doesn't pop to the More root (other tabs pop). | Re-tap pops to root (standard iOS). |
| B6 | P2 | Recurring editor (number pad) | The decimal pad has no Done/Return and swipe-down doesn't dismiss it; controls under it (Day stepper, Starts) are hidden. The only way out is tapping a text field and pressing Return. Same on every amount field. | Keyboard toolbar with **Done**, and `.scrollDismissesKeyboard(.interactively)` on forms. |
| B7 | P2 | Budget › search | With 1,500 rows, the first keystrokes appear ~1 s late (field kept its placeholder while filtering). | Debounce (~150 ms) and filter off the main actor; keep typing responsive. |
| B8 | P2 | Budgets › empty state | "Add budget" link in the empty state didn't respond (normal and 120 ms presses); toolbar **+** works. *Unconfirmed* (UI test `budgets.addEmpty` passes). | Check by hand on the phone. |
| B9 | P2 | Transaction editor › Refund… | On a wishlist-purchase expense, "Refund…" (enabled, blue) didn't open the sheet with several presses. *Unconfirmed* (RefundUITests reach the sheet). | Check by hand on the phone right after a purchase. |
| B10 | P3 | Transaction editor | **Save** is enabled with no changes. | Disabled until something changes. |
| B11 | P3 | Wishlist › Mark Purchased | No **Account** picker, although other expenses can choose an account. | Account picker (default account preselected). |
| B12 | P1 | Tasks board *carried* | Resting a card on the right-edge peek skipped two columns (L-018/L-020). Fixed in `d8a2dad` per the cloud; **not re-verified by hand yet**. | One column per drag; drop lands there. |

## 2. Performance (1,500 transactions)

| # | Result | Note |
|---|---|---|
| P1 | CSV import of 1,500 rows: **~3 s** from Import to "Imported 1,500 transactions." | Fine. A progress indicator would help for 5,000-row files (parser limit). |
| P2 | Cold launch to a populated Dashboard: **~0.6–0.9 s** (Simulator, Release). | Well under the 2 s NFR. Re-measure on the iPhone. |
| P3 | Scrolling the transaction list: app CPU peaks ~40–48 % during fast flicks, back to ~10 % within 2 s; no visible stutter. | Fine. |
| P4 | Search typing lag ~1 s at 1,500 rows (see B7). | Main action item. |
| P5 | Analytics with 12 months: totals exact (Sept income $33,600.00, expenses $5,270.29 match my own sum). | Fine. |
| P6 | Memory ~350 MB RSS in the Simulator. | Simulator numbers overstate; profile Allocations on the phone before worrying. |

## 3. UX improvements

| # | Pri | Where | Suggestion |
|---|---|---|---|
| U1 | P1 | Import → Analytics | After importing, **99 % of spending is "Uncategorized"** and the donut is one grey ring. Add: (a) category suggestions at import from the description (rules + on-device model already in the app), (b) a "1,500 uncategorized — sort them" nudge on Dashboard/Analytics opening a fast triage screen (one tap per row, "apply to all from this merchant"). |
| U2 | P1 | Transactions | **No bulk actions.** Long-press only offers Edit/Delete. Add multi-select (Edit mode) with Set category / Set account / Delete, and "Apply this category to all ‘Pizza Place’" after a manual change. |
| U3 | P2 | Budget screens | Two **+** buttons on the same screen (toolbar = new budget/recurring, floating = Quick Add) look identical in meaning. Label the toolbar one ("New budget") or hide the floating + on sub-tabs other than Transactions. |
| U4 | P2 | Floating + | Covers the amount of the last visible row on Budget/Dashboard lists and sits over results while searching with the keyboard up. Hide it while searching; add bottom content inset on every list. *carried (Dashboard)*. |
| U5 | P2 | Budgets | No month navigation: can't see last month's result or how rollover built up. Add ‹ Month › header and a small history per budget. |
| U6 | P2 | Analytics | Charts aren't interactive. Tap a category slice/row → filtered transaction list; tap a week bar → that week's transactions. Add "vs last month" deltas. |
| U7 | P2 | Wishlist item (purchased) | "Recorded in Budget as an expense" isn't a link. Make it open the transaction (and offer Refund there). |
| U8 | P2 | Empty states | Inconsistent: Budgets has an "Add budget" action, Wishlist and Recurring don't. Give every empty state its primary action. |
| U9 | P2 | Recurring | Show the **next 3 dates** under the rule; warn when the start is in the past or today. |
| U10 | P3 | Settings | Row says "Backup and export", screen title says "Data". Align. *carried* |
| U11 | P3 | Accounts | Account delete asks "This can't be undone…" and only then refuses (goal uses it). Refuse up front. *carried* |
| U12 | P3 | Settings › Style | Choosing a style pops back to Settings root (by design) — consider staying so people can compare styles quickly. *carried* |
| U13 | P3 | Tasks | Long-press on a **Done** card opens the context menu instead of lifting it to drag. *carried, needs a finger* |

## 4. Feature ideas (for owner decision)

| # | Idea | Why |
|---|---|---|
| F1 | **Categorization rules** ("merchant contains X → category Y"), learned from manual edits and applied to imports. | Biggest time saver after importing a bank CSV (U1). |
| F2 | **Recurring detection** from history: "Streaming Co charges ~monthly — make it a recurring bill?" | The imported data has clear monthly patterns; turns history into Upcoming. |
| F3 | **Undo** (toast) for delete and bulk edits. | Safer than confirmations; fits "never silently delete history". |
| F4 | **Duplicate transaction** and **split transaction** (one receipt, two categories). | Common household needs. |
| F5 | **Month-end summary** notification/screen: spent vs budget, top categories, goal progress. | Uses existing Analytics + on-device summary. |
| F6 | Search filters: amount range, date range, account; saved searches. | Search exists; filters make 1,500+ rows usable. |
| F7 | Budget alerts at 80 % / 100 % (local notification, names only). | Reminders infrastructure already exists (Sprint 14). |
| F8 | Import presets per bank (remember column mapping, date format, sign). | Repeat imports become one tap. |

## 5. Beta-tester distribution (important)

The Release builds are on the owner's Desktop (`HouseholdHub-beta-338a877/`). **The iPhone build is signed by the free
Personal Team and will only install on devices registered to that team (the owner's iPhone).** It cannot be sent to
other people's iPhones. Options within the zero-cost rule: (a) testers with a Mac + Xcode run the **Simulator zip**
(`xcrun simctl install booted HouseholdHub.app`); (b) testers build from source with their own Apple ID (free, 7-day);
(c) TestFlight/ad-hoc needs the paid Developer Program (CLAUDE.md §2: owner decision).
