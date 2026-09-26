---
name: household-accessibility-audit
description: Accessibility audit for Household Hub views — VoiceOver, Switch Control alternatives, Dynamic Type, Reduce Motion, contrast, chart accessibility. Use for every UI phase gate and Phase 10.
---

# household-accessibility-audit

Check each changed view:

1. Every icon-only control (tab icons, floating Quick Add, toolbar buttons) has an `accessibilityLabel` (§24.5).
2. Drag interactions (Kanban) have a non-drag alternative: context menu or "Move to…" sheet (§24.5).
3. Swipe actions have equivalent context-menu actions (§24.5).
4. Charts expose data via `AXChartDescriptor` or an accessible table (§24.5).
5. Money reads naturally ("47 dollars and 50 cents", not "4750"); values combine with labels via
   `accessibilityElement(children: .combine)` where a row is one concept.
6. Dynamic Type: no fixed heights clipping text at AX5; layouts switch to vertical where needed.
7. Reduce Motion: animations conditional on `accessibilityReduceMotion`.
8. Contrast: category `ColorToken`s meet WCAG AA against both appearances (§7.3).
9. UI tests query by `accessibilityIdentifier`; add an XCUI test for any new critical flow's accessible path.
Report file:line, the failure, and the fix.
