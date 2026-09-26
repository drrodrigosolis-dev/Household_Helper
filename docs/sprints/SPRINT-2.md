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
| 1 | Onboarding sheet + `AppSettings` bootstrap; §24.2 table updated | §7.11, §24.2 | ☑ | ☑ |
| 2 | Deterministic Quick Add parser (core, parameterized tests) | §25 | ☑ | tests |
| 3 | Quick Add sheet + floating button on every tab | §24.3, §24.5 | ☑ | ☑ |
| 4 | Budget › Transactions: grouped by day, filters (period, category, status), swipe + context-menu edit/delete, §8.3 delete options, paginated | §24.2, §5.4, §8.3 | ☑ | ☑ |
| 5 | Transaction detail/edit (service `update`) | §7.2 | ☑ | ☑ |
| 6 | Budget › Recurring: list, create series, post an occurrence | §7.5, §9.4 | ☑ | ☑ |
| 7 | Dashboard: current / pending / projected (+ pending toggle), this week, upcoming 7 days, recent 5; cards deep-link | §9.2, §24.2 | ☑ | ☑ |
| 8 | Category management: list, add, edit, archive, reassign | §7.3, §8.4 | ☑ | ☑ |

## Doubts found while planning (default taken, owner may overrule)
- **Where category management lives:** §21 puts it in Phase 3 but §24.2 has no screen for it. Default: More ›
  Settings › Categories (§24.2 Settings row gains "Categories").

## Decisions made while building
- §25 parser: a weekday word means its most recent occurrence **including today**; keywords are English only in v1;
  an unmatched `#tag` is dropped (no category), and a tag never selects a category of the wrong kind.
- Onboarding changes currency only while no transactions or series exist (§6.3 → `currencyLockedByExistingRecords`).
- Walk screenshots: UI tests attach named screenshots; `Scripts/ui-test.sh` exports them to `build/screenshots/`,
  uploaded with the run's artifact.

## Data-safety review (subagent) — gate BLOCKED, then fixed
| Finding | Fix |
|---|---|
| Onboarding `Decimal(string:)` parsed a prefix ("1,250.50" → 1) | Strict locale-aware `LedgerFormat.parseDecimal`, used by every amount field |
| Quick Add Save had no in-flight guard (double tap → two records) | `isSaving` guard on every save (Quick Add, editor, recurring, category, onboarding) |
| Quick Add kept income/amount/category after the text stopped supplying them | Text-owned fields revert when the parse no longer yields them |
| Unused category deleted without confirmation | Confirmation dialog; move-then-delete reports which step failed |
| Editor: archived category blocked edits; wrong-kind category silently cleared | Service allows the record's own archived category; editor shows an error instead |

Logged, not fixed: `update` clears a series-set `merchantID` without a snapshot name — unreachable today (no UI sets
a series merchant); revisit when one does. Not covered by a UI test: the double-tap race itself (guarded in code).

## Walk findings (screenshots from run 36197720269)
- Dark captures were identical to light: `XCUIDevice.shared.appearance` does not take effect during a run. Walk now
  launches with `-uiTestingDarkMode`, which makes the root view prefer dark (`nil`, i.e. system, otherwise).
- Onboarding at the largest text size truncated the currency to "US D…(USD)": picker is now navigation-link style.
- Artifacts download needs `*.blob.core.windows.net` in the environment's allowed domains (owner added it).

## Close-out
☑ CI green on final head · ☑ walk screenshots reviewed · ☑ data-safety review (delete flows) · ☑ PROGRESS + PR ·
☑ WALK-QUEUE updated

Closed 2026-09-26: CI green on run 36205435799 on `9635f01` (all unit tests, 25 UI tests including the full light/dark/large-text
walks). Walks saved under `docs/walk/`. Data-safety review findings fixed before green.
