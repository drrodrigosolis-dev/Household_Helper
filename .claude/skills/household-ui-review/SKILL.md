---
name: household-ui-review
description: Review SwiftUI screens against the Household Hub UX spec (§24) — navigation, composition, states, Quick Add, and HIG conformance. Use after any user-facing change.
---

# household-ui-review

Read `docs/spec/07-ux-and-screens.md` first. Check the change against it:

1. **Navigation (§24.1):** 5-tab `TabView` (Dashboard, Budget, Wishlist, Tasks, More→Analytics/Settings); each tab
   owns a `NavigationStack`; Quick Add is a floating button + sheet, never a tab. No new screens or levels
   unless §24.2's table is updated first.
2. **Composition (§24.2):** content order per screen matches the table; balance terminology keeps current,
   pending impact, and projected distinct (§9.2).
3. **Quick Add (§24.3, §25):** autofocused field, type segmented control, progressive disclosure, Save disabled
   until a valid draft; no-amount parse leaves fields empty rather than erroring.
4. **States:** loading, empty, error, and populated states each exist and are reachable in previews.
5. **Destructive actions:** confirmation dialogs state consequences (§8); swipe actions mirrored in context menus.
6. **Presentation:** Dark Mode, Dynamic Type up to accessibility sizes without truncating money, Reduce Motion,
   no hard-coded device dimensions, localization-ready strings (String Catalog), currency via formatters.
7. Hand off to `household-accessibility-audit` for the accessibility pass.
Report findings as file:line with the spec section each violates.
