---
name: household-verify
description: End-of-feature verification loop for Household Hub. Pushes to build/v1, waits for the real verify.yml CI result on that exact commit, diagnoses failures from logs, fixes, and repeats until green. Use before claiming any feature, DoD item, or phase complete.
---

# household-verify

CI (`.github/workflows/verify.yml`) is the only authoritative gate. No session has Xcode; never report success
without a concluded CI run on the pushed SHA.

## Required behavior

1. **Read the diff.** `git status`, `git diff` (and `git diff origin/build/v1...` for unpushed commits). Confirm
   only intended files changed; no secrets; no `.xcodeproj` committed.
2. **Inspect affected boundaries.** For each changed area, note: core vs app target, persistence/schema impact,
   money/accounting impact, UI/accessibility impact. Invoke `household-data-safety-review` or
   `household-migration-audit` if persistence, money, backup, or deletion paths changed.
3. **Local pre-flight (whatever this host can run).** Always: `python3 Scripts/split-spec.py --check`,
   `bash -n` on changed scripts. On macOS only: `Scripts/verify.sh --keep-going`. Off macOS, do not attempt builds.
4. **Commit and push.** `git push origin build/v1`. Record the pushed SHA: `git rev-parse HEAD`.
5. **Find the run for that SHA.** Never use "the latest run" without matching `head_sha`.
   - With `gh`: `gh run list --branch build/v1 --workflow verify.yml --json databaseId,headSha,status,conclusion`
   - Without `gh` (cloud sessions): `mcp__github__actions_list` method `list_workflow_runs`,
     resource_id `verify.yml`, filter branch `build/v1`; pick the run whose `head_sha` equals the pushed SHA.
   If no run exists yet, wait and re-check (runs appear within ~1 minute). Push and pull_request events can both
   start runs for the same SHA; either concluding is a valid result, but a red one is red.
6. **Wait for an actual conclusion.** `gh run watch <id> --exit-status`, or poll
   `mcp__github__actions_get` method `get_workflow_run` every few minutes (a full run is ~10–25 min). In a
   session subscribed to PR activity, CI completion also arrives as an event; still verify the SHA matches.
   Do not proceed while `status` is `queued`/`in_progress`.
7. **On failure, read evidence.** `gh run view <id> --log-failed`, or `mcp__github__get_job_logs` with
   `run_id` + `failed_only: true` + `return_content: true`. The workflow prints `[FAIL] <step>: <message>`,
   deduplicated compiler errors with file:line, failing test names with messages, and a step outcome table.
   The `verify-<run_id>-<attempt>` artifact holds full logs and `.xcresult` bundles.
8. **Fix only what the evidence supports.** Root-cause it; no speculative edits, no skipped/disabled tests,
   no weakened lint rules. A second identical failure after one re-run is real, not a flake.
9. **Repeat 3–8** until the run for the current head SHA concludes `success`.
10. **Summarize:** what changed, the green run URL + SHA, what was verified (build, unit, UI, lint), and remaining
    risks/uncertainty. Update `docs/PROGRESS.md` if a phase or DoD item changed state.
