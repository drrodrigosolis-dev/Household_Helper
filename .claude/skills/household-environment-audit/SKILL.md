---
name: household-environment-audit
description: First-run and on-demand environment reconnaissance (spec §16.3). Reports what this session and the CI runner can do, classified AVAILABLE / AVAILABLE WITH LIMITATION / REQUIRES PAID MEMBERSHIP / NOT INSTALLED / NOT AVAILABLE HERE (verified via CI) / UNKNOWN. Use at session start when the environment is unknown, or when a tool unexpectedly fails.
---

# household-environment-audit

1. Run `Scripts/doctor.sh` (read-only). On non-macOS hosts it reports Xcode/Simulator as NOT AVAILABLE HERE.
2. Also check: `git --version`, `git remote -v`, current branch, `claude --version`, configured MCP servers
   (`claude mcp list` or the session's tool list), `gh` presence, outbound network to github.com / api.github.com.
3. For Xcode, Swift, simulator runtimes and devices, swift-format: read the "Select Xcode … and report environment"
   step of the latest `verify.yml` run (it runs `Scripts/doctor.sh` on the runner). That is the authoritative
   answer for this project.
4. Classify every item using the categories above; mark App Groups, CloudKit, TestFlight, push as
   REQUIRES PAID MEMBERSHIP. Confirm the core path needs none of them.
5. Never install anything during the audit. Report missing tools with install hints only.
