# Household Hub v1 — progress

Gate: a phase is **CI green** only when `.github/workflows/verify.yml` concluded `success` on the `build/v1` commit
that completes it (CLAUDE.md, "Autonomous CI-driven operation"; spec §28). Mirrored in the `build/v1 → main` PR description.

| Phase (§21) | Status | Note |
|---|---|---|
| 0 — Environment | in progress | Setup deliverables (CLAUDE.md, settings, hooks, skills, agents, Scripts/, verify.yml) committed; closes when the first verify run is green. CI is the gate by owner override of §14. |
| 1 — Skeleton | not started | Judgment call: a minimal HouseholdHub app + unit/UI test targets already exist so the CI pipeline could be proven end-to-end; Phase 1 still owes the core module, SwiftData container, feature folders. |
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
