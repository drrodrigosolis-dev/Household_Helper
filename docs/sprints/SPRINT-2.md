# Sprint 2 — Phase 3: Core UX

Planned 2026-09-25 (cloud session); owner answered "run" (all defaults). Starts only once Phase 2 is CI green
(§28). Process: `.claude/skills/household-sprint`. Binding UX: `docs/spec/07-ux-and-screens.md`, grammar
`docs/spec/08-parsing-and-backup.md` §25.

## Owner answers (defaults taken)
1. First-launch onboarding sheet (currency from locale, CAD fallback; starting balance; as-of date = now), with a
   §24.2 spec edit adding it.
2. Quick Add types: Expense and Income now; Wishlist/Task segments appear in Phases 4/5. §25 parser ships now.
3. Budget's Recurring segment (list, create, post an occurrence) is in this sprint.
4. "Include pending in projection": toggle on the Dashboard projected card, persisted in AppSettings, default off.
5. No lanes (fixed cloud budget; lanes cannot compile, so their errors would only surface after merge).
6. Walk: XCUITests attach screenshots (light, dark, largest accessibility text) reviewed before ☑ walked.

## Ground rules
- Views read with `@Query`/fetch descriptors (bounded, §5.4); every write goes through `TransactionService` /
  `CategoryService`. No money math in views; formatting via `Money.formatted`.
- Every icon-only control has an accessibility label; swipe actions have context-menu equivalents (§24.5).
- Strings are localizable literals (String Catalog). Dark Mode and Dynamic Type checked on the walk.

## Items
| # | Item | Spec | Built (CI green) | Walked |
|---|---|---|---|---|
| 1 | Onboarding sheet + `AppSettings` bootstrap; §24.2 table updated | §7.11, §24.2 | ☐ | ☐ |
| 2 | Deterministic Quick Add parser (core, parameterized tests) | §25 | ☐ | tests |
| 3 | Quick Add sheet + floating button on every tab | §24.3, §24.5 | ☐ | ☐ |
| 4 | Budget › Transactions: grouped by day, filters (period, category, status), swipe + context-menu edit/delete, §8.3 delete options, paginated | §24.2, §5.4, §8.3 | ☐ | ☐ |
| 5 | Transaction detail/edit (service `update`) | §7.2 | ☐ | ☐ |
| 6 | Budget › Recurring: list, create series, post an occurrence | §7.5, §9.4 | ☐ | ☐ |
| 7 | Dashboard: current / pending / projected (+ pending toggle), this week, upcoming 7 days, recent 5; cards deep-link | §9.2, §24.2 | ☐ | ☐ |
| 8 | Category management: list, add, edit, archive, reassign | §7.3, §8.4 | ☐ | ☐ |

## Doubts found while planning (default taken, owner may overrule)
- **Where category management lives:** §21 puts it in Phase 3 but §24.2 has no screen for it. Default: More ›
  Settings › Categories (§24.2 Settings row gains "Categories").

## Close-out
☐ CI green on final head · ☐ walk screenshots reviewed · ☐ data-safety review (delete flows) · ☐ PROGRESS + PR ·
☐ WALK-QUEUE updated
