# Sprint 9 — v1 scope gaps (inside Phase 10)

Found 2026-09-26 during the Phase 10 reviews while the owner was away with full authorization: items in the §2.1 v1
scope and the §24.2 Settings row that earlier sprints did not build. Defaults taken and listed for review.

## Defaults taken (owner may overrule)
1. **Face ID gate** (§2.1, §7.11, §24.2): off by default; turning it on authenticates first; passcode is the
   fallback (`.deviceOwnerAuthentication`), so the owner can't be locked out; while locked nothing of the app is
   in the view hierarchy and the app switcher shows a plain cover. Device configuration: never in a backup (§26.1),
   and a restore keeps this device's value. The Log Transaction shortcut requires an unlocked device and, while the lock
   is on, the same Face ID/passcode check. With no device passcode the app opens for the session with an alert; the
   setting never switches itself off.
2. **Task ↔ transaction link** (§2.1 "links between tasks, wishlist items, and transactions", §7.8
   `linkedTransactionID`): the task editor gets a transaction picker (the 50 most recent, newest first); the task
   detail shows the linked transaction. A link to a transaction that no longer exists is dropped on save, and
   deleting a transaction clears links to it.
3. **Appearance** (§7.11 `selectedTheme`, `accentColor`): Theme is System / Light / Dark (default System);
   accent is "Default" (the app's accent color) or one of the category palette colors. Stored as raw strings
   (`selectedThemeRawValue`, `accentColorHex`, empty = default) so an unknown value reads as the default.
   Backed up as optional fields.
4. **Default Quick Add type** (§7.11 `defaultQuickAddType`): Expense / Income / Wishlist / Task, default Expense;
   the Quick Add sheet opens on it. Backed up as an optional field.
5. **About** (§24.2): app name, version and build, "Data stays on this device", and the spec's privacy stance. No
   links to web pages (no network).

## Items
| # | Item | Spec | Built (CI green) | Walked |
|---|---|---|---|---|
| 1 | Face ID gate + app-switcher cover | §2.1, §7.11 | ☑ | device (WALK-QUEUE) |
| 2 | Task ↔ transaction link (editor picker, detail row, service validation) | §2.1, §7.8 | ☑ | UI test (added in `d9dd076`, after this run) |
| 3 | Appearance: theme + accent | §7.11, §24.2 | ☑ | ☑ |
| 4 | Default Quick Add type | §7.11 | ☑ | ☑ |
| 5 | About section | §24.2 | ☑ | ☑ |

## Close-out
☑ CI green: run 36216543703 on `a41b742` · ☑ walk screenshots in `docs/walk/sprint-9/run-36214979821` (Sprints 5–9 walked together) · ☑ data-safety reviews (link validation, backup fields, lock across restores) · ☑ migration audit (new settings fields; SchemaV1 not frozen yet) · ☑ PROGRESS + PR
