# Walk queue

Only items no automation can reach from the current environment. Each entry: sprint, numbered steps, expected
result, and why it could not be walked automatically. Emptied at the next walk on the owner's Mac.

## Pending
- **Sprint 7 (Phase 8) — on-device AI on a device with Apple Intelligence.** Settings › Intelligence: turn on all
  three switches. Quick Add: type "twelve dollars lunch" (amount and Dining should be suggested and labelled), then
  "47.50 coffee" (nothing from the model may override the parsed amount). Analytics › Summary › Write summary: the
  text must only quote figures shown on the screen. Also run the unit tests there with
  `TEST_RUNNER_HH_LIVE_AI=1 Scripts/test.sh`: the live AI fixtures are opt-in and need the model ready. Why
  queued: the CI simulator's model is unreliable (usually absent; once reported available and then failed every
  request, run 36211058160).
- **Launch baseline (Phase 10).** `LaunchPerformanceUITests.testLaunchPerformance` records cold-launch time in
  CI without a threshold. CI run 36216543703 measured an average of **3.197 s** (2.81–3.57 s over 5 launches) on
  the shared runner's simulator; spec §9 NFR is **under 2 s** to an interactive Dashboard on the reference device.
  On the Mac, run it in Xcode on the iPhone 17 Pro Max simulator: if it is under 2 s, set that as the baseline and
  commit it so regressions fail; if not, profile with Instruments (App Launch) — the store is opened synchronously
  in `HouseholdHubApp.init` before the first frame. Why queued: CI's shared simulator is too slow and noisy to
  judge a 2 s target.


- **Before any on-device walk: delete the app first.** SchemaV1 stays editable until the first release (recorded
  decision) and has gained fields since early sprints (AI switches, widget and Face ID settings). A store written by
  an older build may not open with the new model ("store unavailable" screen). CI always starts fresh.
- **Face ID gate (Phase 10).** Settings › Privacy › Require Face ID: turning it on asks for Face ID first; leave
  the app and come back — it must lock, the app switcher must show only the lock, and the passcode must work as a
  fallback. With the lock on, run the Log Transaction shortcut: it must ask for Face ID first (whether a background
  shortcut can show that prompt is the open question; if it can't, it refuses with "Household Hub is locked").
  Remove the device passcode: the app opens with an alert and the switch stays on. Why queued: the CI simulator has
  no passcode, so the switch is unavailable there.

- **Sprint 18 — board drag feel (owner's finger, Simulator or phone).** 1. In Tasks, drag a To Do card and rest it on
  the right-edge peek: after ~0.6 s In Progress slides in, outlined, and stays (no second jump). 2. Release: the card
  lands in In Progress. 3. Drag a Done card: it should lift (L-018 saw long-press open the menu instead on the Mac's
  synthetic gestures). 4. Rest it on the 16 pt left edge: the previous column slides back; release lands there. Why
  queued: drag feel and lift-vs-menu need a real finger.

- **Sprint 25 — Siri (owner's phone; Siri can't run in CI).** Install a fresh build, open the app once and finish
  setup so Siri reads the shortcuts. Lock off unless a step says otherwise.
  1. **One-breath dictation (owner question 4, first).** Say "Add to my wishlist in Household Hub, headphones for
     149" in one breath. Expected: no follow-up question; the confirmation reads "Add headphones, $149.00?". If Siri
     asks "What would you like to add?" instead, the one-breath assumption is false: record it here and in
     `docs/sprints/SPRINT-25.md`, then answer "headphones for 149" and continue.
  2. **Each phrase, English.** "Add to my wishlist in Household Hub", "Add to my Household Hub wishlist", "Add a wish
     in Household Hub": Siri asks for the item; answer "rain boots for 45" → "Add rain boots, $45.00?" → Yes →
     "Added rain boots to your wishlist."; the item is in Wishlist. Answer "gift for mom" → "Add gift for mom with no
     price?". Say No once: nothing is added.
  3. "Add a task in Household Hub", "Add a Household Hub task", "New task in Household Hub": answer "call the
     plumber" → "Add the task “call the plumber”?" → Yes → the task is at the bottom of the board's first column.
  4. **Log Transaction without Apple Intelligence** (Settings › Intelligence › Quick Add understanding off, or a
     phone without it): "Log a transaction in Household Hub", "47.50 coffee" → "Record $47.50 expense at coffee on
     <today>?". Nothing is saved on No.
  5. **Foundation Models path** (a device with Apple Intelligence on; Quick Add understanding and Category suggestions
     on): "Log a transaction in Household Hub", then "I spent 40 on groceries at Safeway yesterday". Expected:
     "Record $40.00 expense at Safeway on <yesterday>, in Groceries?". Then "2 coffees for 9.50" → $9.50, not $2.00.
     Wishlist: "I'd love the Sony headphones, they cost 149" → "Add Sony headphones, $149.00?". Note how long the
     model takes; after 6 s the grammar's draft is used (the confirmation then shows the plain-grammar wording).
  6. **Lock on** (Settings › Privacy › Require Face ID): each of the three intents asks for Face ID before its
     question or confirmation; failing it ends with "Household Hub is locked…". Lock off again: no prompt.
  7. **Spanish** (iPhone language Español, Siri language Español): "Añade a mi lista de deseos en Household Hub",
     "audífonos por 149" → the confirmation names audífonos and $149.00; "Añade una tarea en Household Hub",
     "llamar al fontanero"; "Registrar un movimiento en Household Hub", "40 supermercado ayer". Check the Spanish
     dialogs read naturally once the Localizable strings are translated.
  Why queued: Siri, dictation, Face ID and the on-device model exist only on the phone.

## Done
- **Sprint 6 (Phase 7) — backup and restore through the Files app** (local Simulator, L-012, 2026-09-27). The first
  try found "Back up now" did nothing: two `fileExporter`s on one view, only the last presented; fixed in `9b100f5`.
  Rerun on `774d0c4`: backup saved to Files, app reinstalled, restore replaced everything; balances, both
  transactions and the wishlist photo matched. Screenshots `docs/walk/sprint-6/local/rerun-*`.
- ~~Cold-launch 22 s blank screen (run 36209505191).~~ Not reproduced: the launch metric in run 36216543703 measured 2.8–3.6 s; the slow UI-test starts were simulator warm-up and automation setup. The 2 s target itself is tracked under Launch baseline.
- ~~Owner decision — Google Sheets export.~~ Dropped from v1 (owner, 2026-09-26); CSV covers it.
- ~~Sprint 0/1 (Phases 0–1) — visual pass of the tab shell.~~ Covered by the automated screenshot walks from Sprint 2
  on (every tab and More › Analytics / Settings in light, dark, and largest text; `docs/walk/`).
