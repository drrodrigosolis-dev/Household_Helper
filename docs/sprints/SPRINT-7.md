# Sprint 7 — Phase 8: Intelligence

Planned 2026-09-26 while the owner was away with full authorization; recommended defaults taken and listed below
for review. Binding: §12 (on-device Foundation Models only, optional, deterministic fallback for every feature, AI
never touches SwiftData, no cloud fallback ever), §12.4 (regression fixtures), §25 (deterministic Quick Add),
§7.11 (`aiCategorizationEnabled`, `naturalLanguageEnabled`, `aiInsightsEnabled`), §24.2 Analytics (narrative
collapsed, never auto-generated when AI is off).

## Defaults taken (owner may overrule)
1. **All AI switches start off**; Settings › Intelligence turns each on, and says when Apple Intelligence is not
   available on the device (then the switches are disabled and the deterministic paths are used).
2. **Category suggestion** has a deterministic first layer that works with AI off: the category most often used
   with the same merchant (ties → most recent). AI is only asked when there is no history, and may only pick one
   of the household's active categories of the right kind; anything else is discarded.
3. **Natural-language Quick Add**: the §25 parser always runs first and wins for every field it recognised. With the
   switch on, the model may fill only fields the parser left empty (amount, type, category, a past date within 31
   days); every value is validated and shown in the editable fields before Save, never saved directly. It never
   writes the description (the note's own words are the description), never moves a day the text named ("today"
   included), and never replaces a value the user typed or picked meanwhile. A category the model picked and the
   user kept is saved with `isAIClassified` (§12.3).
4. **Analytics narrative**: a collapsed "Summary" section with a Generate button, built only from the report's
   already-computed numbers (the model never sees individual transactions). Hidden when the switch is off. The
   model sees figures only as placeholders (`{income}`, `{category1}` …) and the app fills in the formatted values;
   text containing any digit of its own is rejected, so a figure can't be invented, truncated, re-signed or
   re-currencied. Residual risk: the model can still attach a placeholder to the wrong words (e.g. "earned
   {expenses}"); the section says the figures come from the report shown above it.
5. Receipt extraction and smart search are **not in this sprint** (spec lists them as preferred, not required);
   they need camera/photo text work that is better done after the Mac move, with real devices.
6. Regression fixtures (`HouseholdHubTests/AIFixtures`) run the validators always, and the live model only when it
   is available (skipped in CI, where the simulator has no Apple Intelligence model); results note the OS build.

## Items
| # | Item | Spec | Built (CI green) | Walked |
|---|---|---|---|---|
| 1 | AI switches in `AppSettings` + Settings › Intelligence with availability | §7.11, §12.1 | ☐ | ☐ |
| 2 | Deterministic category suggestion from merchant history | §12.3, §25 | ☐ | tests |
| 3 | AI suggestion layer: typed drafts + validators (no persistence access) | §12.2 | ☐ | tests |
| 4 | Foundation Models provider behind availability, with fallback | §12.1, §12.5 | ☐ | tests |
| 5 | Quick Add: suggestions fill only empty fields, marked as suggested | §12.3, §25.4 | ☐ | ☐ |
| 6 | Analytics narrative (collapsed, on demand) | §24.2 | ☐ | ☐ |
| 7 | AI regression fixtures | §12.4 | ☐ | tests |

## Close-out
☐ CI green on final head · ☐ walk screenshots saved to `docs/walk/sprint-7/` and reviewed · ☑ data-safety review
(AI never writes; validation) — first pass blocked on a date overwrite and a substring figure check; both fixed with
the should-fixes (strict amounts, no model description, segment-checked categories, stale-result cancellation,
`isAIClassified`, merge rules as a pure Core function with tests) · ☐ PROGRESS + PR · ☐ WALK-QUEUE (on-device AI checks on a real device)
