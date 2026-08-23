# Sir Fish — Presentation Redesign Spec

Target: rebuild the game's presentation to match the **bioluminescent night-forest
concept** — a deep teal-and-gold ornate console under a dark glowing overworld —
as closely as the engine and the existing asset pipeline allow.

Written against the `overworld-prototype` branch. §-references in the form §2.1
point at *Sir Fish — Demo v5 Implementation Spec*; bare §4.3 points at this
document.

**This is a presentation spec. It changes no gameplay, no odds, no balance.**

---

## 0. Before you start

### 0.0 Prerequisites the implementing model cannot do for itself

1. **Save the concept image** to `design documents/reference/console_concept.png`.
   Every "compare against the concept" instruction below assumes it is on disk
   and readable. Without it, work from the colour and geometry tables in this
   document, which are transcribed from it.
2. **Fonts** (§3). Cinzel and EB Garamond are SIL OFL and free, but must be
   downloaded and dropped into `assets/fonts/`. If they are absent when you
   start, implement §3.4's fallback and flag it — do not stall.

### 0.1 Turn the UI back on first

`scripts/run/main_layout.gd` currently ships:

```gdscript
@export var hide_console: bool = true
@export var hide_overlay: bool = true
```

The console is **not on screen** on this branch — it was hidden to frame the
overworld camera. Set both to `false` in `scenes/main.tscn` before doing
anything else, or you will be editing a UI you cannot see. Whether they stay
`false` is §11.3's call.

### 0.2 Non-goals — do not drift into these

- No changes to `Tuning.SLOT_STRIP`, the win rule, payouts, `UPGRADE_*` steps,
  hero stats, or any number that affects balance. §16.2's 50.038% win rate and
  the tests that assert it must be untouched.
- No new gameplay systems. Every widget in the concept maps to something that
  already exists (§1.2).
- No changes to the run flow, encounter types, or `RunController`.
- No audio (§22 still stands).

### 0.3 Where the concept and the code disagree — resolved here, once

The concept was rendered from the design docs and is faithful in most details
(the upgrade names, blurbs and prices are all correct). Where it is not, **the
code wins and the art is adapted**, because these are data, not style:

| Concept shows | Code says | Resolution |
|---|---|---|
| 5 upgrade pips, 3 filled | `UPGRADE_MAX_LEVEL := 3` | Draw `UPGRADE_MAX_LEVEL` pips. Never hardcode 5. |
| 3 filled pips *and* base prices (60/70/50) | 3 levels bought means maxed, cost `-1` | Pips reflect real level; the price plate shows `MAX` when `is_maxed()`. |
| Heart icon on the 120 HP bar, shield on the 70 | `class_icon_glyph.gd`: cross=priest, bow=ranger, shield=warrior | Keep the existing glyph→class mapping. Take only the *visual treatment* (medallion tile, colour) from the concept. |
| Bars ordered 120 / 80 / 70 (warrior, ranger, priest) | `PARTY_ORDER` = priest, ranger, warrior | Keep `PARTY_ORDER`. §7.1 fixes party order left-to-right and the status panel's rows are index-addressed. |
| No Sir Fish anywhere | `SirFishTank` is in the status panel's `ResourceRow` | **Keep the fish.** The game is named after him. §4.2 budgets him a home. |
| No party damage button | Not currently in `console.tscn` either | Nothing to do. |

Any *other* disagreement you find: the code wins, and you note it in the
handoff.

---

## 1. Reading the concept

### 1.1 The five changes that carry the whole look

Ranked by how much of the redesign each one delivers. If you run out of time,
this is the order that degrades most gracefully.

1. **Palette inversion — day to bioluminescent night.** The current world is a
   bright noon meadow (`C_SKY` #7EC8E3, `C_GROUND` #8FBF4F). The concept is a
   dark forest at night lit by purple crystals and a cyan portal. This one
   change does more than everything else combined.
2. **Console chrome — flat panels to framed stone-and-gold.** Current console
   is flat `#231F2E` rectangles with 4px borders. The concept is beveled dark
   green-teal stone with gold trim, diamond joint accents, and vine overgrowth.
3. **Typography — rounded to engraved.** Baloo 2 ExtraBold (soft, rounded) →
   Cinzel (Roman engraved caps). Every heading in the concept is small-caps
   serif.
4. **Screen budget — the world gets bigger.** Battle view goes from 33% of the
   screen to ~42%, and the resource row roughly doubles.
5. **Emissive accents everywhere.** Glow on the payline, on crystals, on the
   portal, on rune marks, on bar fills. The Environment already has
   `glow_enabled` — it is currently doing almost nothing.

### 1.2 Widget inventory — everything in the concept already exists

| Concept element | Existing owner |
|---|---|
| Coin + "1275" + "GOLD" | `status_panel.gd` `GoldLabel` + `CoinGlyph` |
| "DEPTH / 12" plate | `status_panel.gd` `DepthLabel` |
| Three icon + bar rows | `party_bars.gd` → `hero_bars.gd`, `class_icon_glyph.gd` |
| Three reels, bolt/star/plus | `slot_machine.tscn`, `slot_symbol.gd` (`BOLT`/`STAR`/`PLUS` already) |
| Glowing payline with end nodes | `Payline` + `PaylineArrowLeft/Right` `ColorRect`s |
| Three upgrade cards | `upgrade_button.gd` (title, blurb, pips, coin, cost — all present) |
| Party of three from behind | The existing chase camera |

**No new widgets are needed.** This is a reskin of a complete UI, which is why
it is worth doing as one pass.

---

## 2. Palette — `scripts/autoload/tuning.gd`

The colour block at lines 225-258 is the single source of truth (§5) and every
surface reads from it. Rewriting it *is* most of the UI redesign.

### 2.1 Rules

- **Replace values in place. Do not rename constants and do not add a parallel
  set.** `C_SKY` keeps its name even though the sky is now a night canopy —
  every call site already refers to it, and a second palette is the thing §5
  exists to prevent.
- The storm transform (`storm_tint()`, lines 260-277) pulls hues toward
  `STORM_SLATE`. It still works on a night palette but the *contrast* collapses,
  because the base is already dark. Re-check the storm after §2.2 lands and
  raise `STORM_SKY_FLASH` if the lightning stops reading. Do not delete the
  storm.
- Keep every constant's comment. Add the new ones with the same density.

### 2.2 The new values

Transcribed from the concept. Hex is authoritative; the names in the right
column are for your own orientation while working.

```gdscript
# --- world: bioluminescent night forest --------------------------------------
const C_SKY := Color("0E2A33")            # canopy gap, teal-black
const C_FAR_HILLS := Color("143A38")      # deepest treeline
const C_MID_TREES := Color("1B4B3A")      # mid canopy
const C_NEAR_TREES := Color("14231F")     # near trunks, nearly black
const C_GROUND := Color("3E6B3A")         # lit moss down the path centre
const C_BRUSH := Color("0F2B22")          # undergrowth
const C_ROCK := Color("2A3A44")           # faceted boulders, blue-slate
const C_HORIZON_HAZE := Color("1A4A4A")   # what the backdrop ring fades into

# --- arcane accents (new) -----------------------------------------------------
## The purple that every crystal, rune and bolt shares. One hue, so the world
## and the UI read as the same magic - the concept's crystals and its slot
## bolts are the same colour on purpose.
const C_ARCANE := Color("8B5CF6")
const C_ARCANE_BRIGHT := Color("C4B5FD")  # emissive core / glow peak
const C_ARCANE_DEEP := Color("4C1D95")    # shadowed crystal faces
## The portal at the end of the path, and any "destination" light.
const C_PORTAL := Color("7FE3D8")

# --- console chrome -----------------------------------------------------------
const C_CONSOLE_BG := Color("0B1A18")     # behind everything, near-black teal
const C_CONSOLE_PANEL := Color("123A32")  # panel fill
const C_CONSOLE_STONE := Color("1E4038")  # raised frame face
const C_CONSOLE_INSET := Color("081412")  # recessed wells (reel windows)
const C_GOLD := Color("C9A227")           # trim, was F2C230 - aged, not bright
const C_GOLD_BRIGHT := Color("E8C55A")    # top bevel highlight
const C_GOLD_DARK := Color("8A6E1C")      # bottom bevel shadow
const C_PANEL_BORDER := Color("2E5A4E")   # inner border, one step off the fill
const C_VINE := Color("2F6B3E")           # overgrowth
const C_FLOWER := Color("A78BFA")         # the small purple blooms

# --- parchment (upgrade card faces) -------------------------------------------
const C_PARCHMENT := Color("C3BDA8")
const C_PARCHMENT_SHADE := Color("A49E8A") # lower half of the card gradient
const C_INK := Color("241E14")             # text ON parchment

# --- text ---------------------------------------------------------------------
const C_TEXT := Color("F2E9D0")           # cream, on dark
const C_TEXT_DIM := Color("9CAFA4")       # muted sage, on dark
const C_TEXT_GOLD := Color("E8C55A")      # headings and numerals

# --- gameplay signal colours (unchanged meaning, retuned for the dark ground) --
const C_DANGER := Color("E4484F")
const C_HEAL := Color("7CC142")           # green, matches the PLUS symbol
const C_LIGHTNING := Color("A855F7")      # was blue - now the arcane purple
const C_DEFEND := Color("D9A825")         # was blue - now the shield gold
const C_FIRE := Color("FF7A1A")           # unchanged
const C_ICE := Color("5BC8F5")            # unchanged
```

### 2.3 Character colours

The heroes are lit by a dark scene now. Raise their body values so they do not
sink into the ground, and pull the accents toward the arcane/gold scheme:

```gdscript
const C_WARRIOR_ARMOR := Color("5878A8")    # was 4A6FA5 - lifted
const C_WARRIOR_ACCENT := Color("C0333F")
const C_RANGER_LEATHER := Color("478A5C")   # was 3E7A4E - lifted
const C_RANGER_ACCENT := Color("9C6B33")
const C_PRIEST_CLOTH := Color("6E5AA8")     # was F5F0E6 cream - now the
                                            # concept's violet robe
const C_PRIEST_ACCENT := Color("C4B5FD")
```

`body_color` / `accent_color` are **also authored per-character on the `.tres`
files** (`resources/stats/*.tres`, and see `warrior.tres:15-16`). Update both,
or the constants will be silently overridden. Check `combatant_rig.gd` and
`cel_materials.gd` for which of the two actually reaches the mesh before you
assume.

### 2.4 Verification

After §2 alone, `play_scene` + `get_game_screenshot`. The world should already
read as night. It will look flat and unlit — that is §9's job. Do not start
tuning lights yet.

---

## 3. Typography

### 3.1 The problem

`assets/display_font.tres` is Baloo 2 at weight 800 — a soft, rounded,
high-x-height face. Every heading in the concept is an **engraved Roman
capital** with sharp serifs and wide letterspacing. No amount of theme tweaking
gets Baloo there.

### 3.2 The two faces

| Role | Face | Weights | Used for |
|---|---|---|---|
| Display | **Cinzel** | 400, 700, 900 | `DisplayLabel`, all headings, "DEPTH", "GOLD", upgrade titles, numerals |
| Body | **EB Garamond** | 400, 600 | Upgrade blurbs, item subtitles, shop rows, anything below 26px |

Both are SIL OFL from Google Fonts. Place the `.ttf` files in `assets/fonts/`
next to Baloo, with their OFL text alongside, matching the existing
`Baloo2-OFL.txt` convention.

### 3.3 Resources to create

- `assets/display_font.tres` — **repoint** `base_font` at Cinzel, set
  `variation_opentype = {"wght": 900.0}`, and raise `spacing_glyph` from 2 to
  **6**. The concept's headings are widely tracked; Cinzel at default tracking
  looks cramped in small caps.
- `assets/body_font.tres` — new `FontVariation` over EB Garamond at
  `"wght": 400.0`, `spacing_glyph = 1`.

### 3.4 Theme changes — `assets/theme.tres`

- `default_font` → the new body font. `default_font_size` stays 34.
- `DisplayLabel/fonts/font` → the new display font.
- `DisplayLabel/constants/outline_size`: **6 → 4**. Cinzel has finer strokes
  than Baloo; a 6px outline closes its counters at small sizes.
- `DisplayLabel/colors/font_outline_color` → `C_CONSOLE_BG`.
- Add a `PlateLabel` variation for text on parchment: display font,
  `font_color` = `C_INK`, `outline_size = 0`.

**Fallback if the fonts are not on disk:** keep Baloo 2, raise `spacing_glyph`
to 8, and set every heading string through `String.to_upper()`. This
approximates the engraved-caps rhythm and is visibly worse. Flag it in the
handoff; do not silently ship it as the intended design.

### 3.5 Small caps

Cinzel has no lowercase — its "lowercase" glyphs *are* small caps. So
`"Quick Reels"` renders as `QUICK REELS` with the Q and R larger, which is
exactly the concept. **Do not `to_upper()` strings when using Cinzel** — you
would lose the two-tier cap effect that makes the concept's headings read as
engraved rather than shouted.

---

## 4. Screen budget

### 4.1 The change

§2.1's budget is stale — `console.tscn` already disagrees with it (status panel
is ~130 tall in the scene, not 300; the fish/damage-button row does not exist;
`SirFishTank` lives inside the status panel's `ResourceRow`). Replace §2.1 with
the table below and update `Tuning`'s constants at lines 435-444 to match.

The concept's proportions, measured off the image and scaled to 1080×1920:

| Region | Y range | Height | Owner | Was |
|---|---|---|---|---|
| Battle viewport | 0 – 810 | **810** | `BattleView` | 640 |
| Status / resource row | 810 – 1070 | **260** | `StatusPanel` | ~130 |
| Slot machine | 1070 – 1550 | **480** | `SlotMachine` | 880 |
| Fish + slot counter strip | 1550 – 1660 | **110** | `SirFishTank` | in status |
| Upgrade tray | 1660 – 1920 | **260** | `UpgradeTray` | 262 |

810 + 260 + 480 + 110 + 260 = **1920**. Verify this arithmetic every time you
touch it — the budget summing exactly is what §2.1 exists to guarantee.

### 4.2 Notes on the reallocation

- **The divider is gone.** The concept has no 8px gold bar; the console's own
  top frame edge (§5) is the separator. Delete `ConsoleDivider` from
  `main.tscn` and `DIVIDER_H` from `Tuning`, and drop the `divider.visible`
  line from `main_layout.apply_split()`.
- **The slot machine loses 400px.** This is the biggest single loss and it is
  correct — in the concept the cabinet is a wide, short letterbox, not the
  dominant element. `slot_machine.tscn`'s `custom_minimum_size` is
  `Vector2(1080, 880)`; the reel windows, payline and banner are all positioned
  against that and must be re-laid-out, not just scaled. §7.
- **Sir Fish moves out of the resource row** into his own 110px strip below the
  cabinet. The concept has no fish, so this is an invention — but §0.3 keeps
  him, and a low strip under the cabinet is where he fits without competing
  with the three bars for the row the concept gives them.
- `main_layout.gd`'s `battle_height` export default changes 640 → 810, and the
  `clampf(h, 320.0, SCREEN.y - 600.0)` upper bound still admits it.
- `Console.custom_minimum_size` goes from `Vector2(1080, 1272)` to
  `Vector2(1080, 1110)`.

### 4.3 Camera consequence

The battle viewport goes from 1080×640 (aspect 1.69) to 1080×810 (aspect 1.33).
`BattleCamera.keep_aspect = 0` (`KEEP_WIDTH`) is set in `battle_world.tscn` and
re-enforced by `main_layout.gd`, so a taller viewport **shows more vertical
world at the same horizontal framing**. That is what the concept wants — more
canopy above the party. Re-frame after §9 and §10, not now.

---

## 5. Console chrome — the frame system

This is the second-biggest lift and the one that most needs a shared solution
rather than per-panel hacks.

### 5.1 Two tiers

**Pass A — procedural, no new files.** A `StyleBoxFlat` base plus a `_draw()`
overlay for bevels and corner diamonds. This is the codebase's established
approach (`coin_glyph.gd`, `class_icon_glyph.gd`, `slot_symbol.gd` are all
`_draw()`-based, and §16.7 says no image files for the slot). It gets the
beveled stone-and-gold frame, the diamond joints, and the recessed wells —
roughly 75% of the concept's chrome.

**Pass B — authored, needs art.** The vine overgrowth and purple flowers
tangling the frame corners cannot be drawn procedurally at acceptable quality.
They need a 9-patch PNG per frame size, or four corner sprites.

**Do Pass A completely before starting Pass B.** Pass A ships on its own.

### 5.2 New file — `scripts/console/ornate_frame.gd`

One reusable `Control` that every panel puts behind its content. It draws, from
back to front:

1. Filled rounded rect, `C_CONSOLE_STONE`, corner radius 18.
2. Inner filled rounded rect inset by `border` px, `C_CONSOLE_PANEL`, radius 12.
3. Top-and-left bevel: 3px arc/line in `C_GOLD_BRIGHT` along the outer edge.
4. Bottom-and-right bevel: 3px in `C_GOLD_DARK`.
5. A 2px `C_GOLD` line tracing the full outer rounded rect.
6. A diamond at each corner and at the midpoint of each edge: a 4-point
   `draw_colored_polygon` in `C_ARCANE`, ringed in `C_GOLD`, `diamond_size`
   across. This is the concept's most distinctive repeated motif — it appears
   at every panel joint and between the reels.

Exports so every panel configures the same object rather than subclassing it:

```gdscript
@export var border: float = 14.0
@export var corner_radius: float = 18.0
@export var diamond_size: float = 22.0
@export var edge_diamonds: bool = true      # midpoint diamonds, not just corners
@export var inset_well: bool = false        # invert the bevel for recessed areas
@export var fill: Color = Tuning.C_CONSOLE_PANEL
```

`inset_well = true` swaps steps 3 and 4 (dark on top, bright on bottom) and
fills with `C_CONSOLE_INSET`. That single flag is what makes the reel windows
read as carved *into* the cabinet, which is most of why the concept's slot area
has depth.

`mouse_filter = MOUSE_FILTER_IGNORE` on every instance — the frame is decoration
and must never eat a click meant for an upgrade button.

### 5.3 Where it goes

| Panel | `border` | `inset_well` | `edge_diamonds` |
|---|---|---|---|
| Console background (full-bleed outer frame) | 20 | false | true |
| Gold plate | 12 | false | false |
| Depth plate | 12 | false | false |
| Party bar group | 12 | true | false |
| Slot cabinet | 16 | false | true |
| Each reel window (×3) | 8 | true | false |
| Each upgrade card | 10 | false | false |
| Price plate on each card | 6 | true | false |

### 5.4 Pass B — the overgrowth

Four corner PNGs (`vine_tl`, `vine_tr`, `vine_bl`, `vine_br`), ~180×180,
transparent, drawn in `C_VINE` with `C_FLOWER` blooms, placed as `TextureRect`s
over the console background frame's corners at `MOUSE_FILTER_IGNORE`. Additional
sprigs along the left and right outer edges at the concept's positions.

Author them in the existing Blender file and render orthographically, or draw
them directly — either is fine, but they must sit in `assets/ui/` and be
committed with the rest.

---

## 6. Status / resource row

Region 810–1070, 260 tall. Three groups left to right, matching the concept's
proportions: gold plate ~38% width, depth plate ~22%, party bars ~40%.

### 6.1 Gold plate

- `OrnateFrame`, then inside it: `CoinGlyph` at 96×96 on the left, then a
  right-aligned column with `GoldLabel` over a small `"GOLD"` caption.
- `GoldLabel`: display font, **size 76** (up from 52), `C_TEXT`, outline 4.
- New `"GOLD"` caption `Label` beneath it: display font, size 26, `C_TEXT_GOLD`,
  centred under the numeral. This is a new node in `status_panel.tscn`; add it,
  do not synthesise it in script.
- `CoinGlyph` (`scripts/console/coin_glyph.gd`) needs the concept's treatment:
  a `C_GOLD` disc, a `C_GOLD_DARK` inner ring, and the `SlotSymbol.STAR`
  polygon in `C_GOLD_BRIGHT` at the centre. Reuse `SlotSymbol.STAR` — it is
  already a `static var` and the concept's coin and its star reel symbol are
  visibly the same mark.
- Keep the existing punch tween and floating delta in `_on_gold_changed()`
  unchanged. They already do what the concept implies.

### 6.2 Depth plate

- Narrower `OrnateFrame`. `"DEPTH"` caption (display, 30, `C_TEXT_GOLD`) above
  the number (display, 84, `C_TEXT`).
- `_update_depth()` currently sets `text = "DEPTH %d"` on one label. **Split it
  into two labels** so the caption and numeral can carry different sizes, and
  keep the `depth_label.visible = GameState.endless_mode` guard on the group,
  not on one child.

### 6.3 Party bars

Three rows, each: a square medallion tile (icon) then a long bar with
`current / max` text centred on it.

- **Medallion**: `OrnateFrame`-style disc — `C_GOLD` ring, fill tinted per hero,
  `ClassIconGlyph` centred. Per §0.3 keep cross/bow/shield.
- **Tile fill and bar fill share one colour per hero**, taken from the
  concept's three: priest `C_HEAL` green, ranger `C_ARCANE` purple, warrior
  `C_GOLD` — assigned in `PARTY_ORDER` order.
- **Bar**: `inset_well` frame, fill drawn as a rounded rect with a lighter 2px
  top edge (the concept's bars have a specular line along their top).
- **Text**: `"%d / %d"` centred, display font 30, `C_TEXT`, outline 3. The
  concept puts the numbers *on* the bar, not beside it — this is a change from
  the current `hero_bars.gd` layout.
- Keep everything in `hero_bars.gd` that is behaviour: the damage-chunk
  animation (§5.9), the death state, the index-addressed rows. Only the drawing
  changes.

---

## 7. Slot machine

Region 1070–1550, 480 tall — down from 880. Re-layout, do not scale.

### 7.1 Cabinet

- `Cabinet` `Panel` → `OrnateFrame` with `edge_diamonds`, `border = 16`.
- Behind the reels and in front of the cabinet fill, add a **faint arcane
  circle**: a `Control` drawing concentric `draw_arc` rings plus 12 radial ticks
  in `C_ARCANE` at alpha 0.10, centred on the cabinet. The concept has this and
  it is what stops the dark cabinet interior reading as an empty hole. Cheap,
  procedural, no asset.

### 7.2 Reel windows

- Three `OrnateFrame`s with `inset_well = true`, `border = 8`, evenly spaced
  with the cabinet's own frame as the outer margin.
- Fill `C_CONSOLE_INSET`. Each window shows **three cells** (the concept shows
  the symbol above and below the payline one) — confirm `slot_reel.tscn`
  already renders neighbours; if it only renders one, that is a real change and
  should be scoped separately, not improvised here.
- A diamond sits between adjacent reel windows — that is `edge_diamonds` on the
  cabinet doing its job, positioned to fall on the gaps.

### 7.3 Payline

Currently three `ColorRect`s in red (`0.878, 0.192, 0.192`). The concept's
payline is **gold, thin, glowing, with a diamond node at each end and between
each pair of reels**.

- `Payline` → 3px tall, `C_GOLD_BRIGHT`, spanning the full cabinet interior.
- `PaylineArrowLeft` / `PaylineArrowRight` → replace with diamond glyphs
  (`C_GOLD_BRIGHT` fill, `C_ARCANE` core) at the line's ends.
- Give the line a soft glow: set its colour above 1.0 in one channel (e.g.
  `Color(1.4, 1.2, 0.5)`) so the Environment's `glow_hdr_threshold` of 1.05
  catches it. This is why §9.4 raises glow rather than adding a shader.

### 7.4 Symbols

`slot_symbol.gd`'s `BOLT`, `STAR` and `PLUS` polygons already match the concept
exactly. Only recolour:

- `BOLT` → `C_ARCANE`, with `C_ARCANE_BRIGHT` core
- `PLUS` → `C_HEAL`, with a lighter core
- `STAR` → on a `C_GOLD` disc with `C_GOLD_DARK` ring, star in `C_GOLD_BRIGHT`
  — i.e. identical to `CoinGlyph` (§6.1). Draw it once and share.

Keep the black outline (`OUTLINE_WIDTH_FRACTION`) — it is what keeps the glyphs
readable and the concept's symbols have it too.

---

## 8. Upgrade tray

Region 1660–1920, 260 tall. Three cards.

`upgrade_button.gd` already builds title / blurb / pips / coin / cost. The
structure is right; every colour and font is wrong.

### 8.1 Card

- `custom_minimum_size` 340×212 → **340×236** for the taller region.
- Background: `OrnateFrame` is the *wrong* tool here — the concept's cards are
  **parchment**, not stone. Add a `parchment: bool` export to `OrnateFrame`, or
  give the button a `StyleBoxFlat` with a `C_PARCHMENT` → `C_PARCHMENT_SHADE`
  vertical gradient, 3px `C_GOLD_DARK` border, radius 10. Prefer the
  StyleBoxFlat — it goes in the theme and gets hover/pressed/disabled states for
  free, which the button needs and `OrnateFrame` does not provide.
- Theme states: `normal` parchment; `hover` +8% value; `pressed` −10% and 2px
  down-shift; `disabled` desaturated with `C_TEXT_DIM` text (this is the
  can't-afford state and must stay visually distinct — it already is, keep it).

### 8.2 Card contents

| Element | Change |
|---|---|
| `_title` | display font, size 32, `C_INK`, **no outline** (`outline_size = 0` via the `PlateLabel` variation). Dark text on parchment needs no outline and an outline makes it muddy. |
| `_blurb` | body font, size 24, `C_INK` at alpha 0.75. Note the concept ends blurbs with a full stop; `Upgrades.DEFS` blurbs do not. Append it in `upgrade_button.gd`'s formatting, not in `DEFS` — `DEFS` is data. |
| icon medallion | **New.** The concept puts a circular icon left of the title: a purple disc with a glyph. Add a `_icon: Control` drawing a `C_ARCANE` disc, `C_GOLD` ring, and a per-upgrade glyph — reuse `SlotSymbol.BOLT` for `overcharge`, `SlotSymbol.STAR` for `fat_purse`, and three small circles for `quick_reels`. Title and blurb shift right by the medallion's width. |
| `_pips` | `UPGRADE_MAX_LEVEL` diamonds (not circles), `PIP` 18 → 20. Filled: `C_ARCANE` with `C_GOLD` ring. Empty: `C_INK` at alpha 0.2 with a thin `C_INK` ring. |
| price plate | **New frame.** `inset_well` `OrnateFrame` across the card's bottom, `C_CONSOLE_INSET` fill, holding `_coin` and `_cost` centred. Currently they float on the card face. |
| `_cost` | display font, size 34, `C_TEXT_GOLD`. Show `"MAX"` when `Upgrades.is_maxed(id)` — `cost()` returns `-1` there and the current label would print it. **Check whether this is already handled before "fixing" it.** |

---

## 9. The 3D world — light, atmosphere, colour

§2's palette makes the world dark. This makes it *lit*.

### 9.1 Lights — `scenes/battle/battle_world.tscn`

Current: a warm white `KeyLight` at energy 1.15 with shadows, and a cool
`FillLight` at 0.32. That is a noon sun. Replace with a moonlit-plus-magic rig:

| Node | Change |
|---|---|
| `KeyLight` | `light_color` → `C_PORTAL`-ish cool cyan `Color("9FD8D0")`, `light_energy` **1.15 → 0.45**. Keep shadows on and keep the transform — the shadow direction still works. |
| `FillLight` | `light_color` → `C_ARCANE` `Color("8B5CF6")`, `light_energy` **0.32 → 0.55**. This is the purple bounce from the crystals and it does most of the mood work. |
| `RimLight` (**new** `DirectionalLight3D`) | Aimed from behind the party toward the camera, `light_color` `C_PORTAL`, energy 0.9, `shadow_enabled = false`. This is the portal backlight that separates the three silhouettes from the ground in the concept. Without it the party disappears into the forest. |

### 9.2 Environment

```gdscript
ambient_light_source = 3        # unchanged (sky)
ambient_light_energy = 0.85 -> 0.35
tonemap_mode = 2                # unchanged (filmic)
tonemap_white = 2.0 -> 1.4
adjustment_saturation = 1.08 -> 1.22
```

Sky (`ProceduralSkyMaterial`):

```gdscript
sky_top_color = C_SKY                     # 0E2A33
sky_horizon_color = C_HORIZON_HAZE        # 1A4A4A
ground_bottom_color = C_CONSOLE_BG        # 0B1A18
ground_horizon_color = C_HORIZON_HAZE
```

### 9.3 Fog

`battle_world.gd::_ready()` enforces `FOG_DEPTH_BEGIN`/`END` from `Tuning` over
the scene's authored values — **set them in `Tuning`, not the `.tscn`**, or your
change will be overwritten at runtime and you will chase it for an hour.

```gdscript
const FOG_DEPTH_BEGIN := 16.0 -> 11.0     # pull the murk in closer
const FOG_DEPTH_END := 55.0 -> 42.0
```

In the `.tscn`: `fog_light_color` → `C_HORIZON_HAZE`, `fog_depth_curve` 1.35 →
1.6 (a harder falloff, so the near ground stays clear and the treeline goes
soft fast). Also enable `volumetric_fog` at low density (0.02) with
`volumetric_fog_emission` = `C_ARCANE` at 0.05 if the frame budget allows —
this is what gives the concept its visible light shafts. **Measure the frame
time before and after; drop it if it costs more than ~1.5ms.**

### 9.4 Glow

Already enabled and doing almost nothing. The concept is built on emission.

```gdscript
glow_intensity = 0.55 -> 1.10
glow_bloom = 0.2 -> 0.35
glow_hdr_threshold = 1.05 -> 0.85
glow_blend_mode = 1              # ADDITIVE (new)
```

Lowering the threshold to 0.85 means **anything painted above ~0.85 luminance
blooms**, which is how the crystals, the payline, the portal and the rune marks
all glow without a single custom shader.

### 9.5 Vignette

The concept's edges are markedly darker. There is no built-in vignette in
`Environment`. Add a full-viewport `ColorRect` at the bottom of `BattleOverlay`
with a small radial-gradient shader, `C_CONSOLE_BG` at the corners fading to
transparent by ~55% radius, `MOUSE_FILTER_IGNORE`.

Do **not** put it inside the SubViewport — `battle_overlay` is already sized and
positioned 1:1 with the battle view (`main_layout.gd` guarantees this for
`unproject_position()`), so an overlay child lands exactly right and costs one
quad.

---

## 10. The 3D world — new props

Pass B territory: this needs authored meshes in `blender/Sir Fish.blend`,
exported to `assets/meshes/` through the §23 pipeline.

Ordered by value per hour:

### 10.1 Arcane crystals (highest value, lowest cost)

Clusters of faceted purple spikes, scattered like the existing rocks and
bushes. **These carry the entire "bioluminescent" read.**

- Model: 3–5 spike variants in one `env_crystal.glb`, meshes named
  `Env_Crystal*` so `OverworldField._palette()` picks them up with no code
  change (it collects by node-name prefix).
- Material: `C_ARCANE_DEEP` albedo, `emission_enabled`, emission `C_ARCANE` at
  energy ~1.6 — above §9.4's glow threshold, so they bloom.
- Wire in: one line in `_build_scatter()`, plus `FIELD_CRYSTALS` in `Tuning`
  (start at ~90, between `FIELD_ROCKS` and `FIELD_BUSHES`).

### 10.2 Ambient motes

Fireflies drifting through the frame. `GPUParticles3D` parented to
`BattleWorld`, not to the scrolling field — they should feel like they are in
the air the camera moves through, not glued to the ground.

Small billboarded quads, `C_ARCANE_BRIGHT` emissive, ~120 particles, slow
upward drift with turbulence, lifetime 6–10s, size 0.02–0.05, alpha-fade at
both ends. Use `create_particles` / `set_particle_material`.

### 10.3 The path

A cobbled strip running up `RUN_DIR` through the party's lane. The lane is
already computed — `OverworldField._lane` is exactly the corridor the scatter
keeps clear, so the path goes in the same place by construction.

Cheapest version: a second `PlaneMesh` in `_build_ground()`, narrow, oriented
along `RUN_DIR`, lifted 0.005 above the ground plane, with a lighter
`C_GROUND` material. Better version: a tiling cobble mesh laid end to end like
the field copies. Do the cheap one first and look at it.

**Read `_build_ground()`'s comment before touching it.** The ground is a plain
opaque `StandardMaterial3D` on purpose — using `CelMaterials.cel()` puts it in
the transparent pass and it paints over the shadow monster. The path plane has
exactly the same constraint.

### 10.4 The archway

The lit stone arch at the end of the path. This is the concept's focal point
and its hardest asset.

- A `Node3D` prop parked far up `RUN_DIR` (~55–70 units), **not** scrolled with
  the field — it is the destination and should never appear to be passed.
- Stone arch mesh + an emissive `C_PORTAL` plane in the opening + an
  `OmniLight3D` at `C_PORTAL`, energy ~4, range ~25, to cast the backlight
  §9.1's `RimLight` fakes.
- If time-boxed: **ship the light and the emissive plane without the arch
  mesh.** A glowing gap at the end of the path reads correctly at this fog
  density and costs an afternoon instead of a week.

### 10.5 Rune marks on trunks

Lowest value, highest fiddliness. Emissive `C_ARCANE` glyph quads on a fraction
of the tree trunks. Only attempt after everything above is done.

---

## 11. Order of work, and how to check it

### 11.1 Sequence

Each step is independently viewable. Take a `get_game_screenshot` at the end of
every one and compare against the concept before moving on.

1. §0.1 — turn the console back on. Screenshot the baseline. **Keep this
   screenshot**; it is your before.
2. §2 — palette. Big visible jump, no layout risk.
3. §9 — lights, environment, fog, glow, vignette. The world should now be
   ~80% of the concept's read.
4. §3 — fonts and theme.
5. §4 — screen budget. Expect everything in the console to be misplaced after
   this; that is what 6–8 fix.
6. §5 — `ornate_frame.gd` plus its use in the console background.
7. §6 — status row.
8. §7 — slot machine.
9. §8 — upgrade tray.
10. §10.1 and §10.2 — crystals and motes. Highest-value 3D props.
11. §4.3 — re-frame the camera now that the world and the viewport are final.
12. §10.3–10.5 and §5.4 — path, archway, runes, vine overgrowth, as time allows.

### 11.2 Checking

- `play_scene` → `get_game_screenshot` at each step. `compare_screenshots`
  against the previous step catches accidental regressions in regions you were
  not editing.
- The console is only visible with `hide_console = false` (§0.1).
- Check the **shop modal and run summary** after §2 and §3. They are not in the
  concept but they read the same theme and palette, and a night palette with
  the old cream-on-purple modal will look broken. They are in scope.
- Check the **storm** (§2.1) and a **lightning strike** (`Debug` verb
  `lightning`) after §9. Both were tuned against a bright sky.
- Check a **damage number** and a **health chunk** over the dark ground —
  `C_DANGER` and `C_HEAL` moved.

### 11.3 The `hide_console` question

`hide_console` / `hide_overlay` were set true to frame the overworld camera.
This redesign is largely *about* the console, so it must end `false`. Flip the
export defaults in `main_layout.gd`, not just the scene, so a fresh
`main.tscn` instance shows the game rather than the framing aid.

---

## 12. What this breaks

Expect these and handle them; do not treat them as surprises.

1. **`test_parallax_seam.gd`** loads `parallax_background.tscn`, which nothing
   instances any more. It does not touch the palette so it should survive, but
   run it.
2. **Every hardcoded colour outside `Tuning`.** Before starting, run a sweep for
   `Color(` and `Color("` across `scripts/` and route any survivor through a
   `Tuning` constant. The palette is only a single source of truth to the extent
   this is true, and §2 is the moment to enforce it.
3. **`status_panel_preview.gd`** builds a mock director to preview the party
   bars. §6.3 changes their layout; the preview must be updated in step or it
   becomes a lying reference.
4. **`C_PRIEST_CLOTH` changes from cream to violet.** Check the priest actually
   reads at distance against the dark ground before accepting it.
5. **The §2.1 budget table in the v5 spec becomes wrong.** Update it there too
   (§4.1), or the next person reads a stale table — it is *already* stale, which
   is how this section got written.

---

## 13. Deferred

- Animated vine growth or flower bloom on the console frame.
- A parallax star layer visible through the canopy gap.
- Per-biome palette swap (this spec hardcodes one night forest; the cave/biome
  work would generalise `OverworldField`'s mesh and colour set — see the
  separate biome discussion).
- Reactive console lighting — the frame brightening on a slot win.
- Sir Fish redesigned to match the new palette beyond a straight recolour.
