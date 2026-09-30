# Sprint 10 walk — local session (L-003, 2026-09-26)

iPhone 17 Pro Max Simulator, iOS 26.5, Debug build d097637, `-uiTesting -uiTestingSkipOnboarding` (in-memory store).
Appearance and text size switched live with `xcrun simctl ui` (light/dark, large / accessibility-XXXL).

Flow: Settings › Accounts › + Savings ($2,500) and + Visa credit card (owed $420.50) → Budget › New transfer
(Main → Visa $100; Main → Main was blocked with "Choose two different accounts.") → account filter (Savings, Visa)
→ Dashboard Accounts card.

Checks that passed: household total $2,079.50 before and after the transfer (transfer is neutral); Main −$100,
Visa owed $320.50; the credit-card editor relabels Balance as "Owed"; the account filter shows the transfer under
Visa and not under Savings; the filter icon fills while a filter is active; dark mode is legible everywhere.

Findings (see TO-CLOUD.md "Re L-003"):
1. Dashboard › Current balance, largest text: the "+ Add" button breaks mid-word ("Ad" / "d").
   `sprint10-dashboard-dark-largeText.png`
2. Dashboard › Accounts card, largest text: rows lose their leading alignment (icon indented, the name wraps under
   itself, the amount starts at the card edge), and the floating + button covers the amounts.
   `sprint10-dashboard-accounts-card-*-largeText.png`
3. Budget with an account filter that matches nothing: the empty state says "No transactions — Use Quick Add…"
   instead of saying that the filter hides everything (Clear filters exists only inside the menu).
   `sprint10-account-filter-savings-light.png`
4. Settings › Accounts, largest text: the subtitle "Bank account · Default" wraps with the "·" at the start of the
   second line. `sprint10-accounts-three-light-largeText.png`
5. Possible: New transfer, largest text: the Amount field sits half under the keyboard. The text size was changed
   while the keyboard was up, so this may not reproduce from a fresh open.
   `sprint10-transfer-editor-filled-dark-largeText.png`
Not a defect: the account editor's balance field uses `.numbersAndPunctuation` so a minus sign can be typed.
