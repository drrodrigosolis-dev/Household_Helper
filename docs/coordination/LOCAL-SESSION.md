# Starting the local (Mac) session

## Once, in Terminal
```sh
xcode-select -p                    # must point at Xcode 26.x
brew install xcodegen swift-format # the only tools the scripts need (XcodeGen: docs/research/dependency-decisions.md)
git clone https://github.com/drrodrigosolis-dev/Household_Helper.git   # skip if already cloned
cd Household_Helper && git fetch origin && git checkout build/v1.1 && git pull --ff-only origin build/v1.1
gh auth login                      # optional: lets the session read CI with `gh`
claude --permission-mode acceptEdits
```
Project permissions come from `.claude/settings.json` (committed): git on `build/v1.1`, `Scripts/*`,
`xcodebuild`, `xcrun simctl/xctrace/xcresulttool`, `xcodegen`, `swift-format`, `gh` read commands. Anything on the
"ask" list (deleting files, force pushes, merges to `main`, installs) still asks, by design.

## The prompt to paste
```
You are the LOCAL session for Household Hub on the owner's Mac. Read CLAUDE.md, docs/coordination/README.md and
docs/coordination/TO-LOCAL.md first. A CLOUD session (no Xcode) builds features on build/v1.1; you handle what
needs Xcode, the Simulator or the owner's iPhone. You talk to it only through the repo: read TO-LOCAL.md, write
only TO-CLOUD.md, following README.md (ids, statuses, one-way files, pull --ff-only before reading/writing and
before every push, commit the coordination file on its own and push at once).

Work loop:
1. git pull --ff-only origin build/v1.1. Take the oldest `open` item in TO-LOCAL.md: append "Re L-00n: taken" to
   TO-CLOUD.md, commit, push.
2. Do it. Run Scripts/verify.sh before any push that changes code. Save screenshots/profiles/logs under docs/walk/
   or docs/research/ and commit them.
3. Append the result to TO-CLOUD.md ("Re L-00n: done — ..." or "blocked: why"), commit, push.
4. Nothing open: wait and check again.
Don't edit files an open cloud item is changing; don't merge to main; ask the owner only for items that need
their hands (iPhone unlocked, Face ID, a passcode) or for anything on the settings "ask" list.
Start now with L-001.
```
Then run it on a timer so it keeps checking without you:
```
/loop 15m git pull --ff-only origin build/v1.1, then work the oldest open item in docs/coordination/TO-LOCAL.md as the prompt above says
```
