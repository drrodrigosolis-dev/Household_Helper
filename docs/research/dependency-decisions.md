# Dependency decisions

Policy: zero third-party Swift packages (§3.2.1). Every package or build tool is recorded here before adoption.

## XcodeGen (build tooling only; not linked into the app) — adopted 2026-09-25
- **Need:** no session has Xcode, so the `.xcodeproj` cannot be created or edited through Xcode. Hand-writing
  `project.pbxproj` is error-prone and unreviewable; `project.yml` is small and diffable. §14.1 already expects a
  "project generation/configuration" step.
- **Cost/privacy:** free, offline, no account, no telemetry. Ships nothing into the app binary.
- **License:** MIT. **Health:** actively maintained (2.46.0 observed on the CI runner via Homebrew).
- **Footprint:** CI downloads release 2.46.0 from GitHub and checks its SHA-256 before use (pinned 2026-09-26, owner
  decision 22; it was `brew install xcodegen`, which followed whatever Homebrew had). Locally a developer installs it
  with Homebrew (bootstrap.sh only checks, never installs); a local version newer than CI's is fine for generation.
- **Bumping:** change `XCODEGEN_VERSION` and `XCODEGEN_SHA256` together in `.github/workflows/verify.yml` (the zip's
  `shasum -a 256`), and note the version here.
- **Exit strategy:** run `xcodegen generate` once and commit the resulting `.xcodeproj`, then drop `project.yml`.

## swift-format — adopted 2026-09-25
Bundled with the Xcode toolchain (`xcrun swift-format`), so not a third-party install. Config: `.swift-format`.

## GitHub Actions used by CI — pinned 2026-09-26 (owner decision 22)
`actions/checkout` v5.1.0 (`fbc6f39…`) and `actions/upload-artifact` v4.6.2 (`ea165f8…`), referenced by full commit
SHA in `.github/workflows/verify.yml` so a moved tag can't change what runs. Both are GitHub's own actions (MIT).
Bump by resolving the new release tag to its commit (`git ls-remote --tags https://github.com/actions/<name>.git`)
and updating the SHA and its version comment together. Known: upload-artifact v4 runs on Node 20 and GitHub forces it
onto Node 24 with a warning; v5 would clear the warning when there's a reason to bump.
