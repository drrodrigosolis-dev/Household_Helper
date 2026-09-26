---
name: household-build
description: Build the Household Hub app for the iOS Simulator and interpret build failures. Use when a change affects compilation, project.yml, targets, or build settings.
---

# household-build

1. Target/setting changes go in `project.yml` (XcodeGen). Never hand-edit or commit `HouseholdHub.xcodeproj`.
   New source folders must be under an existing target's `sources:` path or added there.
2. On macOS: `Scripts/generate.sh && Scripts/build.sh` (build-for-testing, simulator chosen automatically:
   newest iOS ≥ 26 runtime, preferring iPhone 16 Pro Max). Off macOS: push and use `household-verify`.
3. Build settings that must hold: Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY=complete`, warnings as
   errors, iOS 26.0 deployment target, iPhone-only. Do not relax these to make a build pass.
4. Reading failures: the log's deduplicated `error:` lines point to file:line; fix the first real error first
   (later ones are often cascades). Concurrency errors mean an isolation design problem, not a place for
   `@unchecked Sendable` or `nonisolated(unsafe)` without a written justification.
5. Report: the exact command/CI run, result, and any warnings introduced.
