# Sprint 21 — v1.1: themes, redone after the owner's mockup

Owner feedback 2026-09-28 (decision 30): Sprint 19's themes "fell completely short". The owner's Toy Box (dark)
Dashboard mockup is the target: a chalkboard page, hand-drawn chalk illustrations (sun, cloud, bear, kite, puzzle,
rocket, car, blocks, stars, hearts, crayon squiggles), chalk-sketch card outlines, a handwritten font for titles and
labels, doodles inside the cards, a red crayon add button. "Following that same idea, dress up the other themes and
screens." Owner answers: art from free external generation tools; amounts in clear rounded digits.

## Where the art comes from (decision 1)
No image generator is reachable from the cloud session (the Adobe connector exposes only PDF/font tools here; Canva
is disconnected), and the project bundles no downloaded art. So the art is the owner's, made with a free generator
(the one that made the mockup): one **art board** per theme (a sheet of separate drawings on a flat background).
`Scripts/cut-theme-art.py` (Pillow, local) cuts a board into transparent PNGs in the asset catalog, keyed off the
flat background, so one art set serves light and dark. **Boards are never committed** (the mockup shows the owner's
balances and a notification photo; the repo is public): only the cut drawings are.
- Toy Box: cut from the mockup now.
- Airplanes, Dinosaurs, Love Mom, Winter Special: until their boards arrive they use the new chalk layout with
  code-drawn doodles only (stars, hearts, squiggles, snowflakes, clouds), no illustrations.

## Look (decisions 2–6)
2. **Page:** a chalkboard (dark) or paper (light) background with a faint procedural texture, drawn in code.
3. **Cards:** chalk-sketch outlines (a slightly irregular double stroke drawn in code), no system material.
4. **Type:** the theme's handwriting font for titles, card titles, labels and tab names; amounts in bold SF Rounded
   (owner answer). Body text in lists stays legible (rounded system font).
5. **Illustrations:** a header strip of the theme's drawings under the title (gently bobbing; still with Reduce
   Motion), one drawing tucked in a card corner per screen, empty states show a drawing.
6. **Add button:** the theme's crayon color with a chalk ring. Screens: Dashboard, Budget, Wishlist, Tasks, More,
   Settings, sheets; the same components everywhere (`ThemedCard`, `ChalkBorder`, `ThemeArt`).

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | `Scripts/cut-theme-art.py` + Toy Box art in the catalog (`5597235`; filled heart dropped: a border runs through it) | ☐ | ☐ |
| 2 | Chalk components: background texture, chalk border card, doodles, crayon button (`ThemeArt.swift`) | ☐ | ☐ |
| 3 | Dashboard to the mockup (Toy Box dark), then light | ☐ | ☐ |
| 4 | Budget, Wishlist, Tasks, More/Settings, sheets | ☐ | ☐ |
| 5 | Other themes: art from the owner's two sheets (2026-09-28), cut into `lovemom`, `airplanes`, `winter`, `dinosaurs`; pieces renamed to roles (`header1`, `cornerTopLeading`, ...); `fill` keeps white bodies solid on dark, `isolate` drops neighbours | ☐ | ☐ |
| 6 | Screenshots per theme × light/dark; contrast and Reduce Motion audit | ☐ | ☐ |

## Owner action
Done 2026-09-28: the owner sent two sheets covering all four themes. Was: one art board per remaining theme (prompt in the chat message of 2026-09-28 and in `docs/walk/sprint-21/PROMPTS.md`).
