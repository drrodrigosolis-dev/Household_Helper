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
