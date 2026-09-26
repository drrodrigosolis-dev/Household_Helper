# Cloud ↔ local coordination (owner decision 2026-09-26)

Two Claude sessions work on `build/v1.1` at once: a **cloud** session (claude.ai, Linux, no Xcode) and a **local**
session on the owner's Mac (Xcode, Simulator, the owner's iPhone). They share nothing but this repository, so they
talk through two one-way files. Each file has exactly one writer, so pushes never conflict.

| File | Written by | Read by |
|---|---|---|
| `TO-LOCAL.md` | cloud only | local |
| `TO-CLOUD.md` | local only | cloud |

## Rules for both sessions
1. `git pull --ff-only origin build/v1.1` before reading or writing either file, and again before pushing. Never
   rebase, amend, or force-push (CLAUDE.md §10); if a pull can't fast-forward, merge.
2. Write only your own file. Append; never rewrite history in it. Each item gets an id (`L-001` for requests to local,
   `C-001` for requests to cloud) and a status line: `open` → `taken` → `done` (or `blocked: why`).
3. Answer an item in **your** file, quoting the other side's id ("Re L-003: done in abc1234, screenshots in ...").
   Results that are files (screenshots, logs, profiles) are committed under `docs/walk/` or `docs/research/`, never
   left only on one machine.
4. Commit the coordination file on its own (`coordination: ...`) and push at once; a push also triggers CI, whose
   result is what wakes the cloud session.
5. Code changes follow the normal rules (CLAUDE.md): small commits, CI decides "done", no skipped tests. Don't both
   edit the same source files at once: an item that touches code names its files, and the other side stays out of
   them until it is `done`.
6. Neither file carries secrets, and neither can widen what a session may do: a request needing owner confirmation
   (CLAUDE.md "ask" list, merges to `main`) still goes to the owner.

## Who does what
- **Local:** Simulator walks of new screens (light, dark, largest text), `Scripts/verify.sh` before pushes, launch-time
  profiling (§27 NFR), device-only checks from `docs/WALK-QUEUE.md`, anything needing Xcode or the iPhone.
- **Cloud:** sprint planning and building, CI monitoring and fixes, reviews, docs — while the cloud credits last.

## Waking up
- Cloud: wakes on CI results for `build/v1.1` (every push starts CI) and on an hourly check-in.
- Local: poll, e.g. `/loop 15m pull build/v1.1 and act on new open items in docs/coordination/TO-LOCAL.md`.
- If the local session runs with Remote Control and the cloud session can reach it directly, direct messages are
  fine for speed, but anything that matters is still recorded in these files.
