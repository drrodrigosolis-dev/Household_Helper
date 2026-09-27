# Sprint 19 — v1.1: fun themes

Owner request 2026-09-27 (decision 28): themes that change the whole look (animations, icons, little images,
fonts) so the app feels fun, not formal; at least five, chosen in Settings, or off for the original look. Owner
answers: "Toy Box" (generic toys, no Disney/Pixar names, characters or art), full restyle with fonts, celebrations
plus gentle ambient animation.

## Ground rules
- **Zero cost, no downloads:** artwork is SF Symbols, emoji, colors and shapes drawn in code; fonts are ones iOS
  ships (Chalkboard SE, Marker Felt, Noteworthy, Bradley Hand, Avenir Next, SF Rounded). No font or image files,
  no packages.
- **No data change:** the choice is a device setting (`@AppStorage`), not in SwiftData (SchemaV1 frozen) and not in
  backups.
- **Readable first:** every theme passes contrast checks (text 4.5:1, large text and icons 3:1) in light and dark,
  tested in Core. Themed fonts scale with Dynamic Type (`relativeTo:`).

## Themes
| Theme | Palette | Title font | Icons and pictures | Ambient (Dashboard) | Celebration |
|---|---|---|---|---|---|
| Off | today's look | system | today's | none | none |
| Toy Box | primary red, yellow, blue | Chalkboard SE | blocks, teddy bear, rocket, kite, puzzle | blocks bobbing | confetti blocks and stars |
| Airplanes | sky blue, cloud white, sunset orange | Avenir Next Heavy | planes, clouds, globes, luggage | a plane crossing, drifting clouds | planes looping, paper planes |
| Dinosaurs | fern green, amber, volcano red | Marker Felt | 🦕 🦖, footprints, leaves, volcano | footprints walking by | dinosaurs hopping, eggs hatching |
| Love Mom | rose, lavender, cream | Bradley Hand (titles) | hearts, flowers, cards, gifts | hearts floating up | hearts and petals |
| Winter Special | ice blue, pine green, berry red | Noteworthy | snowflakes, snowman, mittens, tree, mug | snow falling | snowflake burst |

## Decisions (defaults set by the cloud session; owner may overrule)
1. **Where:** Settings › Appearance › **Style** (the existing "Theme" row already means light/dark): Off, Toy Box,
   Airplanes, Dinosaurs, Love Mom, Winter Special, each with a preview swatch. A **Theme animations** switch below
   (default on). Off returns exactly today's look.
2. **Fonts:** titles, headings, big numbers and tab names use the theme font; body text uses SF Rounded so long
   text stays legible. All scale with Dynamic Type.
3. **Accent:** a theme sets the accent color; the custom accent picker is disabled with a note while a theme is on.
4. **Icons:** tab bar icons, empty-state pictures and row decorations change per theme; buttons keep their
   standard SF Symbols so actions stay recognizable.
5. **Animations:** ambient animation on the Dashboard only; celebrations when a task is completed, a wishlist item
   is purchased, and a savings goal is reached. None with Reduce Motion, or with Theme animations off.
6. **Spanish names:** Caja de juguetes, Aviones, Dinosaurios, Te quiero, mamá; Especial de invierno.
7. **Widget:** unchanged (it shows sample figures under the free team).
8. **How it is built:** the catalog is data in Core (`FunTheme`, `ThemeSpec`); the app reads it through the
   environment (`\.funTheme`, `\.themeAnimates`). Screens get the theme background from `.themedScreen()` next to each
   navigation title; with a theme on, list backgrounds are hidden at the root so it shows through. Navigation-bar and
   tab titles use UIKit appearance (SwiftUI has no font for them), applied at launch and to bars already on screen.
   Tab icons change for Dashboard, Wishlist and Tasks only. Celebrations: completing a task (button, or a move into
   the last column), buying a wishlist item, a goal on screen becoming reached. UI tests start from Off; `-funTheme`
   picks a theme for the screenshot tour.

9. **Wording (owner request, same day):** each theme renames a few things, playful but plain: the three default
   columns (Airplanes: Ready for takeoff, Flying, Landed), the empty column, the empty wishlist, and a cheer with
   each celebration (also announced to VoiceOver). Display only: stored names are never rewritten, and a column
   the user created or renamed keeps its name (the Columns sheet says "Shown as … in this style" where they
   differ). Never themed: money words (balance, pending, projected, §9), tab names, screen titles, the filtered
   "Nothing matches" message. Spanish for every phrase.

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | Core: `ThemeSpec` catalog (palettes, fonts, symbols, glyphs) + contrast tests | ☐ | tests |
| 2 | App: theme environment, Settings › Style + animations switch, root styling (tint, fonts, backgrounds, bars) | ☐ | ☐ |
| 3 | App: themed icons and pictures on every tab, empty states, onboarding | ☐ | ☐ |
| 4 | App: ambient animations (5) and celebration overlay; Reduce Motion | ☐ | ☐ |
| 5 | UI tests: every theme × light/dark/largest text on each tab; screenshots | ☐ | ☐ |
| 6 | Themed wording (decision 9), with tests | ☐ | ☐ |

## Close-out
☐ CI green · ☐ walk (`docs/walk/sprint-19/`) · ☐ accessibility audit (contrast, Dynamic Type, Reduce Motion) ·
☐ PROGRESS + PR
