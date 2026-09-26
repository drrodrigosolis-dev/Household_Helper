# Moving development from claude.ai cloud sessions to the Mac

Everything lives in git on `build/v1`; nothing needs copying out of a cloud container.

## Before the cloud credits run out (last cloud session)
1. `git status` clean and `git log origin/build/v1..HEAD` empty: every commit pushed.
2. `docs/PROGRESS.md` and the current `docs/sprints/` plan reflect reality, and the PR description matches.
3. Note in `docs/PROGRESS.md` anything in flight (a red run, a half-done item) so the Mac session picks it up.

## On the Mac (once)
1. Install Xcode 26 from the Mac App Store, open it once, and install an iOS 26 simulator runtime
   (Xcode > Settings > Components).
2. `brew install xcodegen gh`, then `gh auth login`.
3. `git clone https://github.com/drrodrigosolis-dev/Household_Helper && cd Household_Helper && git checkout build/v1`
4. `Scripts/bootstrap.sh` (checks tools, installs nothing), then `Scripts/verify.sh` should pass like CI does.
5. Start Claude Code in the repo (`claude`), signed in with the Claude subscription. Do not set `ANTHROPIC_API_KEY`.
   Project settings, hooks, skills, and subagents load from `.claude/`; personal overrides go in
   `.claude/settings.local.json` (git-ignored).

## What changes on the Mac
- `Scripts/verify.sh` runs locally before each push; CI (`verify.yml`) still decides "green".
- Auto-fix is a cloud feature: turn it off on the PR in claude.ai if it should stop using cloud usage. With it off,
  the local session fixes red CI itself (CLAUDE.md, "Division of labor").
- The swift-format PostToolUse hook becomes active (it is a no-op without Xcode).
- Reading CI uses `gh` (`gh pr checks`, `gh run watch`, `gh run view --log-failed`) instead of the GitHub MCP tools.
- The sprint walk can run on the Simulator with control of the Mac (see the sprint skill), instead of CI screenshots.

## Checks only a Mac or device can do (also listed in `docs/WALK-QUEUE.md`)
- **Delete any earlier install first.** SchemaV1 is still editable before the first release, so a store written by
  an older build may not open ("store unavailable").
- **Live on-device AI fixtures:** `TEST_RUNNER_HH_LIVE_AI=1 Scripts/test.sh` on a Mac or device with Apple
  Intelligence ready. CI never runs them (its simulator's model is unreliable).
- **Launch baseline:** run `LaunchPerformanceUITests.testLaunchPerformance` in Xcode and set a baseline so launch
  regressions fail.
- **Face ID gate:** needs a device (or a simulator with a passcode and enrolled Face ID).
- **Widget and Shortcuts:** add the widget to the Home Screen and try "Log a transaction in Household Hub".
  Under the free Personal Team the widget shows sample figures; live figures need an App Group, which needs a
  paid team: set `HH_APP_GROUP` in `project.yml` to the group id, add the App Groups capability to the app and the
  widget, and regenerate (`xcodegen`). Nothing else changes.

## Backlog for the Mac (owner decision 2026-09-26)
- **Receipt extraction** (spec §12, "preferred"): photograph a receipt and prefill amount, merchant, and date with
  on-device Vision text recognition plus the Foundation Models validator, as a reviewed draft like Quick Add.
  Needs a real camera and device testing.
- **Smart search** (spec §12, "preferred"): natural-language search over transactions ("coffee last month") with a
  deterministic fallback (plain text and filters).

