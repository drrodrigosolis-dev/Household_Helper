# Walk queue

Only items no automation can reach from the current environment. Each entry: sprint, numbered steps, expected
result, and why it could not be walked automatically. Emptied at the next walk on the owner's Mac.

## Pending
- **Sprint 6 (Phase 7) — backup and restore through the Files app.** On the Simulator or a device: add a few
  transactions and a wishlist item with a photo; Settings › Backup and export › Back up now; save the folder in
  Files. Delete the app's data (reinstall), finish onboarding, then Restore from backup… and pick the folder.
  Expected: a confirmation that says everything will be replaced; afterwards balances, wishlist (with photo), and
  tasks match the original. Why queued: the system document picker cannot be driven reliably by UI tests; the
  backup format, validation, and restore are covered by unit tests.
- **Owner decision — Google Sheets export (Phase 7, optional in spec §2.1).** Not built: it needs a Google Cloud
  OAuth client and a network dependency, both on the confirm-first list. Say whether to add it and who owns the
  Google project.

- **Sprint 7 (Phase 8) — on-device AI on a device with Apple Intelligence.** Settings › Intelligence: turn on all
  three switches. Quick Add: type "twelve dollars lunch" (amount and Dining should be suggested and labelled), then
  "47.50 coffee" (nothing from the model may override the parsed amount). Analytics › Summary › Write summary: the
  text must only quote figures shown on the screen. Also run the unit tests there: the live AI fixtures run only
  where the model is available. Why queued: the CI simulator has no Apple Intelligence model.

## Done
- ~~Sprint 0/1 (Phases 0–1) — visual pass of the tab shell.~~ Covered by the automated screenshot walks from Sprint 2
  on (every tab and More › Analytics / Settings in light, dark, and largest text; `docs/walk/`).
