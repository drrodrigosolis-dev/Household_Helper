# Household Hub v1 — progress

Gate: a phase is **CI green** only when `.github/workflows/verify.yml` concluded `success` on the `build/v1` commit
that completes it (CLAUDE.md, "Autonomous CI-driven operation"; spec §28). Mirrored in the `build/v1 → main` PR description.

| Phase (§21) | Status | Note |
|---|---|---|
| 0 — Environment | CI green | Run 36192377205 on `729351a`: Xcode 26.6 / Swift 6.3.3 / iPhone 17 Pro Max iOS 26.5, lint+build+1 unit+1 UI passed. §27's iPhone 16 Pro Max is absent from the runner (open question for Phase 10). |
| 1 — Skeleton | CI green | Run 36193820270 on `44681ee` (5 unit, 3 UI tests). `HouseholdHubCore` framework (no SwiftUI) with the §5.2 factory, SchemaV1 + migration plan, §24.1 tab shell with placeholder screens, String Catalog. Judgment call: SchemaV1 holds only a minimal `AppSettings` and stays mutable until first release; Phase 2 adds the §7 models to it. Not yet seen visually (Dark Mode, Dynamic Type): pending the sprint walk decision. |
| 2 — Domain foundation | not started | |
| 3 — Core UX | not started | |
| 4 — Wishlist | not started | |
| 5 — Tasks | not started | |
| 6 — Analytics | not started | |
| 7 — Backup/export | not started | |
| 8 — Intelligence | not started | |
| 9 — Optional system surfaces | not started | |
| 10 — Hardening | not started | |

Statuses: not started / in progress / CI green / blocked.
