# Walk queue

Only items no automation can reach from the current environment. Each entry: sprint, numbered steps, expected
result, and why it could not be walked automatically. Emptied at the next walk on the owner's Mac.

## Pending
- **Sprint 0/1 (Phases 0–1) — visual pass of the tab shell.** On the Simulator: launch, visit each of the five tabs
  and More → Analytics / Settings in light mode, dark mode, and the largest accessibility text size. Expected:
  titles and empty-state text fully visible, no clipping, tab icons labelled for VoiceOver. Why queued: shipped
  before the screenshot walk existed; covered by navigation UI tests only.
