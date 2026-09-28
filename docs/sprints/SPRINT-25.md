# Sprint 25 — v1.1: Siri (planned, after Sprint 24)

Owner request 2026-09-28: tell Siri to add an expense, add something to the wishlist, and similar; explore what
Apple Intelligence ("Siri AI") allows for a third-party app.

## Today (baseline)
`HouseholdHubApp/App/AppIntents.swift`: "Log a transaction in Household Hub" (Siri asks for the entry in Quick Add
grammar, confirms, saves; Face ID when the lock is on) and "Quick Add in Household Hub" (opens the sheet). No
wishlist or task intents, no one-sentence phrases with parameters, no Apple Intelligence integration.

## Plan
1. Research first (household-research-apple-api, Apple docs only; record in docs/research/apple-api-decisions.md):
   App Intents + App Shortcuts parameters in phrases, App Entities (categories, accounts, wishlist items, columns),
   Apple Intelligence / assistant schemas and personal context in iOS 26 — what a third-party app can adopt, which
   entitlements it needs, and whether a free Personal Team (no paid program, CLAUDE.md §2) can use it.
2. Build what works under the free account: intents for Add to wishlist, Add a task, Log expense / income with
   parameters ("Add headphones for 149 to my wishlist in Household Hub"), with confirmation for money, the app lock
   honoured, localized phrases (English, Spanish).
3. Apple Intelligence: adopt only what step 1 shows is available and free; otherwise record why not.
4. Tests: intent logic unit-tested through the services; phrases and dialogs checked by hand on the phone (Siri
   can't run in CI) — WALK-QUEUE items.

Owner questions will be sent in one message with defaults when the sprint starts.

## Research result (2026-09-28)
Full findings with doc URLs: `docs/research/apple-api-decisions.md` ("App Intents / Siri / Apple Intelligence on
iOS 26 — Sprint 25 research").

**What to build**
- `AddToWishlistIntent` and `AddTaskIntent`, `.background`, mirroring `LogTransactionIntent`'s shape: a fixed
  trigger phrase with **no embedded parameter** ("Add to my wishlist in Household Hub" / "Add a task in Household
  Hub"), one `@Parameter var text: String` with `requestValueDialog`, and a small new grammar (reusing the Quick
  Add money parser where it fits) that turns a dictated "headphones for 149" / "call the plumber" into a draft.
  `requestConfirmation` before every write, same as money today; the app lock still applies.
- `AppEntity` + `EntityQuery` for `CategoryRecord`, the account/wallet concept, wishlist items and Kanban columns,
  used as selection/disambiguation parameters in later, more specific intents (e.g. "Move task to Done in
  Household Hub"), not as a way to carry free text.
- Add the new phrases (English + Spanish) to the existing `HouseholdHubApp/Resources/AppShortcuts.xcstrings` —
  ordinary String Catalog editing, no new file needed.
- Optionally, inside a wishlist/task intent's `perform()`, let the on-device Foundation Models framework help turn
  the dictated sentence into the draft, still shown back via `requestConfirmation` before anything is saved (§6:
  AI never writes to SwiftData).

**What is not possible, and why**
- **A single Siri utterance cannot carry the item name and amount as declared phrase parameters.** App Shortcuts
  phrase parameters must be `AppEntity`/`AppEnum` (a fixed, enumerable set of values) — never free text or a
  number typed at speech time. "Add headphones for 149 to my wishlist" only works as one breath because the
  *whole trailing phrase* is delivered as a single `String` parameter's value (exactly like `LogTransactionIntent`
  today) for the app's own parser to split — not because Siri understood "headphones" as a name and "149" as an
  amount. This must be verified once on-device (see owner questions).
- **No Apple assistant-schema domain fits this app.** The fixed `AssistantSchemas` list is Books, Browser, Camera,
  Files, Journal, Mail, Photos, Presentation, Reader, Spreadsheet, System, VisualIntelligence, Whiteboard,
  WordProcessor — no finance, list, task, or reminders domain exists, so every intent stays a plain custom
  `AppIntent`/`AppShortcut`, never an `@AssistantIntent(schema:)` conformance.
- **No documented free-form NLU splits a sentence into named parameters for a non-schema app.** "I spent 40 on
  groceries at Safeway yesterday" cannot arrive at `perform()` pre-split into amount/merchant/date; it can only
  arrive as one dictated string for the app's own deterministic grammar (or Foundation Models) to parse, same as
  today.
- **Siri's on-screen awareness / View Annotations API is still evolving past iOS 26.0** (WWDC26 shipped its own
  follow-up sessions on it) and its exact minimum OS could not be confirmed from Apple's docs endpoint. Not
  adopted this sprint; tracked as an open question rather than guessed at.

**Owner questions, with recommended defaults**
1. Wishlist/task add grammar: "<name> for <amount>" reusing the Quick Add money parser vs. a separate simpler
   grammar with no amount (task titles rarely need one). *Recommended default:* wishlist keeps "<name> for
   <amount>" (amount optional, defaults to no price if absent); tasks take the whole dictated text as the title,
   no amount parsing.
2. Whether `AddTaskIntent` should let Siri pick a column (`AppEntity`) in the same phrase, or always add to the
   default/first column and let the person move it later. *Recommended default:* always the default column this
   sprint; add the `AppEntity` column picker as an explicit follow-up sprint item once `AppEntity`/`EntityQuery`
   exist for columns.
3. Whether to spend this sprint's budget on the Foundation Models refinement step (2d) or ship the deterministic
   grammar alone first and add Foundation Models later. *Recommended default:* ship the deterministic grammar
   first (it is what CI can actually test); add Foundation Models as a later, optional refinement once the plain
   intents are green and hand-checked.
4. Confirm on the owner's phone, before this sprint's tests are written: does saying the whole trigger phrase +
   free text in one breath ("Add to my wishlist in Household Hub, headphones for 149") actually deliver as a
   single dictated `String`, the way `LogTransactionIntent` assumes today? This is the load-bearing assumption
   behind "one sentence" in the sprint's plan.

## Owner answers (2026-09-28)
1. Wishlist: "<name> for <amount>", the amount optional. Tasks: the whole dictated text is the title.
2. Tasks added by Siri go to the first column. A column picker is a later item.
3. **Foundation Models refinement this sprint** (owner chose it over the default). A free-form sentence ("I spent
   40 on groceries at Safeway yesterday") goes to the on-device model first where Apple Intelligence is available.
   The deterministic grammar is the fallback everywhere else and is what CI tests. The model's output is a draft
   shown in `requestConfirmation`, and it never writes (§6).
4. Question 4 (one-breath dictation) is checked on the phone as the sprint's first walk item.
