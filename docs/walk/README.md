# Walk screenshots

Every sprint walk's screenshots, downscaled (360 px JPEG), one folder per CI run. `sheet-<Screen>.jpg` puts light,
dark, and largest-accessibility-text side by side. Produced by `Scripts/walk-screens.py` from the run's artifact.

## Sprint 2 (Phase 3)
| Run | Folder | What it shows | Findings |
|---|---|---|---|
| 36197720269 (`9135c4f`, chunk A) | [run-36197720269-chunkA](sprint-2/run-36197720269-chunkA) | Onboarding + tab shell before Budget/Dashboard existed | Dark column is actually light (walk bug, fixed in `0199d26`); onboarding currency truncated at largest text (fixed in `0199d26`) |
