# Dependency decisions

Policy: zero third-party Swift packages (§3.2.1). Every package or build tool is recorded here before adoption.

## XcodeGen (build tooling only; not linked into the app) — adopted 2026-09-25
- **Need:** no session has Xcode, so the `.xcodeproj` cannot be created or edited through Xcode. Hand-writing
  `project.pbxproj` is error-prone and unreviewable; `project.yml` is small and diffable. §14.1 already expects a
  "project generation/configuration" step.
- **Cost/privacy:** free, offline, no account, no telemetry. Ships nothing into the app binary.
- **License:** MIT. **Health:** actively maintained (2.46.0 observed on the CI runner via Homebrew).
- **Footprint:** installed on the CI runner with `brew install xcodegen`; locally a developer installs it the same
  way (bootstrap.sh only checks, never installs).
- **Exit strategy:** run `xcodegen generate` once and commit the resulting `.xcodeproj`, then drop `project.yml`.

## swift-format — adopted 2026-09-25
Bundled with the Xcode toolchain (`xcrun swift-format`), so not a third-party install. Config: `.swift-format`.
