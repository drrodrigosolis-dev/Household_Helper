# Sprint 24 — v1.1: Siri (planned, starts after Sprint 23 closes)

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
