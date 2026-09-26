# Claude Code decisions

## CI is the authoritative gate (owner override of §0 / §11.2 / §14) — 2026-09-25
The repo is public, so GitHub-hosted macOS runners cost nothing. No session (cloud Linux or the owner's) is assumed
to have Xcode. `.github/workflows/verify.yml` runs the same `Scripts/*.sh` a Mac would, so local and CI checks
cannot drift. Scripts fail fast with a pointer to CI when run off macOS.

## No hard-coded Xcode or simulator — 2026-09-25
The first scaffold's CI run failed because it hard-coded `Xcode_16.app` and `iPhone 16`, and the runner lacked that
simulator runtime. `Scripts/lib/common.sh` now picks the newest Xcode with an iOS ≥ 26 simulator SDK and the best
available iPhone on an iOS ≥ 26 runtime (preferring iPhone 16 Pro Max, the §27 reference device), creates a
device if a runtime has none, and tries `xcodebuild -downloadPlatform iOS` once in CI before failing.

## Reading CI without `gh` — 2026-09-25
Cloud sessions have no `gh` CLI. They use the GitHub MCP tools (`actions_list`, `actions_get`, `get_job_logs`,
`pull_request_read`); `household-verify` documents both paths.

## Guard hook design — 2026-09-25
`.claude/hooks/guard.py` (PreToolUse) returns "ask" for the require-confirmation list. For workflow files it compares
the `on:` and `permissions:` blocks before and after the edit, so routine CI fixes (runner image, timeouts, steps)
stay autonomous while trigger/permission scope changes need the owner. Edits to the guard itself or
`.claude/settings.json` also ask, so the enforcer cannot be silently weakened. The spec's ConfigChange hook
(§15.7) was not added; the owner asked only for PreToolUse/PostToolUse.

## Formatting hook validates, never rewrites — 2026-09-25
Per §15.7, the PostToolUse hook runs `swift-format lint --strict` on the edited file and feeds findings back
(exit 2). It is a no-op off macOS; the CI lint step is the enforcing gate.
