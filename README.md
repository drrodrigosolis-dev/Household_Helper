# Household Hub

Local-first iPhone app (iOS 26+) for household budget, wishlist, and tasks. Spec:
[`docs/Household_Hub_iOS_App_Specs_Enhanced_v3.1.md`](docs/Household_Hub_iOS_App_Specs_Enhanced_v3.1.md)
(split for agents in [`docs/spec/`](docs/spec/00-index.md)). Progress: [`docs/PROGRESS.md`](docs/PROGRESS.md).

## Verification
`.github/workflows/verify.yml` on GitHub-hosted macOS runners is the authoritative gate: it generates the project,
lints, builds for the iOS Simulator, and runs unit (Swift Testing) and UI (XCTest) tests.

## On a Mac (optional)
```bash
Scripts/bootstrap.sh     # checks tools, installs nothing
Scripts/generate.sh      # project.yml -> HouseholdHub.xcodeproj (XcodeGen; the .xcodeproj is git-ignored)
Scripts/verify.sh        # same steps as CI
open HouseholdHub.xcodeproj
```

## Layout
```
project.yml            XcodeGen spec (edit this, not the .xcodeproj)
HouseholdHubApp/       app target
HouseholdHubTests/     Swift Testing unit/domain tests
HouseholdHubUITests/   XCTest UI tests
Scripts/               bootstrap, doctor, generate, format, lint, build, test, ui-test, verify
.claude/               Claude Code settings, hooks, skills, subagents
docs/                  spec, split spec, progress, research log
```
