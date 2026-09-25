# Household Hub — project contract

Spec: `docs/Household_Hub_iOS_App_Specs_Enhanced_v3.1.md` (source of truth). Load `docs/spec/00-index.md` plus only the
numbered file(s) the task needs (§29.2); do not load the full spec by default. Progress: `docs/PROGRESS.md`.

## 1. Product purpose
Local-first, private iPhone app (iOS 26+, iPhone 16 Pro Max design target) combining budget/transactions, a wishlist
whose purchases become real transactions, and a Kanban task board. v1 scope is §2.1; non-goals in §2.2 are never
built as hidden assumptions. Screens and navigation are fixed by §24; do not invent screens.

## 2. Zero-cost constraint
No Apple Developer Program, no paid services, no paid APIs, no telemetry SDKs. Core features must work in the
Simulator under a free Personal Team. App Groups, CloudKit, TestFlight, push are DEFERRED/out of scope (§11.2).
Never set or use `ANTHROPIC_API_KEY`; Claude Code runs on the owner's subscription.

## 3. Architecture decisions
- SwiftUI + `@Observable` feature state; feature folders (§3.4); no view model per view by default.
- Shared core module (`HouseholdHubCore`) with no SwiftUI import; used by app and widget.
- Structured concurrency; `ModelActor` for background persistence; UI state `@MainActor`.
- Small single-purpose services (§4.4). No DI, routing, networking, or database frameworks.
- Project file is generated: edit `project.yml`, never a `.xcodeproj` (it is git-ignored).

## 4. Persistence rules
SwiftData, one authoritative container from one factory (§5.2); in-memory config for tests/previews; no CloudKit;
explicit `VersionedSchema` + `SchemaMigrationPlan`, never destructive migration. No raw `ModelContext` across actors.
Images live under Application Support/Media with a relative reference in SwiftData (§5.5). Tokens go in Keychain.

## 5. Money / accounting rules
Money is `Int64` minor units + ISO currency code; `Decimal` only at input boundaries; never `Double`. All arithmetic in
one module, fully tested. Starting balance is a baseline, not a transaction. Current (posted) vs pending impact vs
projected (30 days) are distinct and never all called "balance" (§9). Recurrence is a rule, not pre-generated rows.
A wishlist purchase creates exactly one linked transaction atomically (§8.1). Never silently delete financial history.
All dates go through `HouseholdCalendar` (§10).

## 6. AI safety rules
On-device Foundation Models only, optional, each feature with a deterministic fallback (§12, §25). AI output is a
validated draft reviewed by the user; AI never writes to SwiftData. No cloud LLM fallback, ever.

## 7. Dependency policy
Zero third-party Swift packages. Adding one requires owner confirmation plus a record in
`docs/research/dependency-decisions.md` (reason, license, health, transitive impact, OS/toolchain floor, exit plan).
Build tooling decisions are recorded there too (XcodeGen is the only one so far).

## 8. Testing commands
Swift Testing for unit/domain/service tests (`HouseholdHubTests`); XCTest/XCUIAutomation for UI and performance
(`HouseholdHubUITests`). Never mix both APIs inside one test. Parameterize money, recurrence, dates, parsing.
`Scripts/test.sh` (unit) · `Scripts/ui-test.sh` (UI) · `Scripts/verify.sh` (everything, same order as CI).

## 9. Formatting / linting commands
`Scripts/lint.sh` (non-mutating: spec-split drift, shell syntax, `swift-format lint --strict`) ·
`Scripts/format.sh` (explicit in-place format). Config: `.swift-format` (4-space indent, 120 cols).
After editing `docs/Household_Hub_iOS_App_Specs_Enhanced_v3.1.md`, run `python3 Scripts/split-spec.py`.

## 10. Git rules
Work on `build/v1`; one open PR `build/v1 → main`. Small coherent commits describing the change, not the prompt.
Never force-push, amend pushed commits, rebase, reset --hard, or delete branches. Never push to or merge into
`main` without the owner's explicit go-ahead. Never commit secrets (see §11 of this file).

## 11. Definition of Done
§18 checklist, plus the data-sensitive list for money/persistence/backup work. A DoD item is only checked when the
matching CI run on the current head is green (see "Autonomous CI-driven operation"). Record remaining uncertainty.
Never store secrets in CLAUDE.md, settings, source, `.mcp.json`, workflow files, or fixtures.

## 12. Research / source verification rules
Apple docs first, then Anthropic docs, then package repos; blogs and snippets only for interpretation (§19.1).
Record version-sensitive API decisions in `docs/research/apple-api-decisions.md` (min OS, toolchain, entitlement,
availability, fallback). Use the `household-research-apple-api` skill before coding against an unfamiliar API.

## Autonomous CI-driven operation
**Override of spec §0/§11.2/§14:** the spec says local Xcode is authoritative and GitHub Actions optional. For this
project the owner has inverted that: the repo is public so hosted macOS runners are free, and no session (cloud or
the owner's) is assumed to have Xcode. Do not "correct" this back to the spec.

- Source of truth for "does it work" is `.github/workflows/verify.yml` on the `build/v1` PR, not local execution.
  Scripts refuse to run off-macOS by design; do not try to install Xcode or Swift in a Linux session.
- Loop: commit → push `build/v1` → find the run whose head SHA equals your pushed SHA → wait for a real conclusion
  → on failure read the failed job logs and fix the root cause → repeat. Never assume success.
- Reading CI: with `gh`, `gh pr checks` / `gh run watch` / `gh run view --log-failed`. In cloud sessions without
  `gh`, use the GitHub MCP tools: `actions_list` (list_workflow_runs, branch `build/v1`), `actions_get`
  (get_workflow_run), `get_job_logs` (failed_only), `pull_request_read` (get_check_runs). The `household-verify`
  skill has the exact procedure.
- **Division of labor (owner decision):** claude.ai "Auto-fix" is on for the `build/v1` PR and owns fixing red CI.
  The lead session writes phase work and does not race Auto-fix: if the latest run on `build/v1` is red, wait for
  Auto-fix's fix to go green instead of pushing a competing fix. Always `git pull --ff-only origin build/v1`
  before committing and again before pushing, because Auto-fix pushes to the same branch.
- A DoD item (§18) or a phase (§21) is complete only when CI is green on the commit that contains it. Phase gates
  (§28) use CI, not memory: before starting phase N+1, confirm the latest run on `build/v1` head is green.
- After each phase: update `docs/PROGRESS.md` and mirror its table into the PR description.
- Check in with the owner only for: (a) end of each phase (log in PROGRESS.md; do not wait for a reply unless
  something is ambiguous); (b) any require-confirmation action (`.claude/settings.json` "ask" list or the guard
  hook); (c) a genuinely ambiguous spec call where a wrong guess is costly to unwind; (d) v1 scope (§2.1) complete
  with CI green end-to-end — then wait for explicit go-ahead before merging to `main`.
- Never skip, disable, or weaken a test or lint rule to get green. "Flaky" is not a root cause.
