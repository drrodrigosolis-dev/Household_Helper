# Walk screenshots

Every sprint walk's screenshots, downscaled (360 px JPEG), one folder per CI run. `sheet-<Screen>.jpg` puts light,
dark, and largest-accessibility-text side by side. Produced by `Scripts/walk-screens.py` from the run's artifact.

## Sprint 2 (Phase 3)
| Run | Folder | What it shows | Findings |
|---|---|---|---|
| 36197720269 (`9135c4f`, chunk A) | [run-36197720269-chunkA](sprint-2/run-36197720269-chunkA) | Onboarding + tab shell before Budget/Dashboard existed | Dark column is actually light (walk bug, fixed in `0199d26`); onboarding currency truncated at largest text (fixed in `0199d26`) |
| 36198714018 (`87c15f3`, Phase 3 gate) | [run-36198714018](sprint-2/run-36198714018) | Budget list, editors, recurring, categories, dashboard, Quick Add | Quick Add button covers list rows and the pushed editor; at largest text dashboard cards break words, amounts wrap mid-number, category badges clip; editor fields unlabeled; "Repeats" truncates. Balances verified correct (0 + 1,200 − 47.50 = CA$1,152.50). Dark column still light (run predates `0199d26`). Fixes in next commit |

## Sprint 3 (Phase 4)
| Run | Folder | What it shows | Findings |
|---|---|---|---|
| 36202442661 (`b69c8fa`) | [run-36202442661](sprint-3/run-36202442661) | Sprint 2 walk fixes; first real dark mode; Wishlist list, grid, editor, detail, Mark Purchased (light/dark). Walk stopped at the purchased check (a test query bug, fixed in `0748b2a`), so large-text wishlist screens and the purchased state are missing | Dark mode now correct everywhere. Large-text rows and dashboard cards stack, amounts stay on one line, editor fields labelled: Sprint 2 findings fixed. New: ~100 pt gap between wishlist filter chips and content (horizontal ScrollView claiming height; fixed next commit). Minor: uncategorized rows show a "?" badge |

## Sprint 4 (Phase 5)
| Run | Folder | What it shows | Findings |
|---|---|---|---|
| 36205435799 (`9635f01`, all green) | [run-36205435799](sprint-4/run-36205435799) | Full walk, all 25 UI tests passing: every screen of Phases 1–5 in light, dark, largest text, incl. Tasks board/detail/editor/columns, Quick Add Task and Wishlist, purchased wishlist item, Dashboard activity | Balances correct after purchase (1,152.50 − 450.00 = 702.50; week 497.50). Still open: gap under wishlist chips (earlier fix ineffective; chips now a ViewThatFits, no ScrollView); large-text wishlist grid broke names mid-word (one column at accessibility sizes); Columns sheet broke "In Progress" mid-word (name gets priority, count moves under it). Fixes in the next commit |

## Sprints 5–9 (Phases 6–10)
| Run | Folder | What it shows | Findings |
|---|---|---|---|
| 36214979821 (`e43e528`; build, 180 unit and 29 UI tests passed, lint red on one fixed line) | [run-36214979821](sprint-9/run-36214979821) | Full walk incl. Analytics (donut, table, trend), Data, Intelligence, lower Settings (Privacy/Face ID, Appearance, Quick Add, Widget, About), Tasks detail with Move to…, Quick Add segments | Balances consistent (CA$1,152.50 before the purchase walk). At largest text the Analytics category name broke mid-word ("Un-cate-go-rized"): rows now stack at accessibility sizes. About text still said AI is off until turned on (outdated by the owner's AI-on decision): reworded. "Understanding" hyphenates at AX5 on Intelligence (system hyphenation, acceptable). The CI model reported available in this run, so the Intelligence footer reads "on this device only"; UI tests now always run without the model |

## v1.1 Sprints 12–16
| Run | Folder | What it shows | Findings |
|---|---|---|---|
| 36268510203 (`25afbec`, all green) | [sprint-12](sprint-12), [sprint-14](sprint-14), [sprint-15](sprint-15), [sprint-16](sprint-16) | Goals list, editor at largest text, Dashboard Goals card; Settings › Reminders; task search with an accent ("pássport" finds "Renew passport"); Data › Import; every tab, Settings and Quick Add in Spanish (light and largest text) | Goal editor takes input at largest text (`FocusingRow` fix holds). Spanish: default task columns were still "To Do / In Progress / Done" for Spanish users (fixed next commit: seeded as "Por hacer / En curso / Hecho"). "Main account" in the Spanish walk is expected (UI tests seed English data). At largest text "Sin movimientos" truncates to "Sin movimient…" (system `ContentUnavailableView` title; minor, open). Segmented pickers keep small text (system control) |
