# Sir Fish — Shop UI v2 Specification

**Document type:** bonus build prompt for an implementing model
**Project:** `C:\Projects\Godot\Sir Fish` (Godot 4.7-stable, Forward+)
**Relationship to v3 / v3.5:** **bonus scope.** This is not part of M7.6 and not part of M8. It amends v3 §15 (and §17.9) only if and when it is scheduled. `Sir Fish - Demo v3 Implementation Spec.md` and `Sir Fish - Demo v3.5 Implementation Spec.md` are unaffected until then.
**Source:** an owner-supplied render of a shop UI, read against the shipped `shop_modal.tscn` / `shop_buy_card.tscn` / `shop_sell_row.tscn`.
**Milestone:** **M9** — after M8e. See §9 for why it cannot go earlier.

---

## 0. Read this first — the render conflicts with the art direction

The render is a dark, desaturated, ornate, painted fantasy UI: brown and purple metal, stone dungeon backdrop, gem rivets, filigree corners, and photoreal item illustrations on a nebula wash.

v3 §1.1's fourth design pillar reads, in full:

> **Bold, flat, primary colour.** Positive references: *Breath of the Wild*, *CrossCode*, *Monster Train*. Negative references: *DOOM*, *Halls of Torment*, *Voin*. If it reads as gritty, desaturated, or brown, it is wrong.

and v3 §6.1 closes with **"Do not desaturate. If a colour needs to recede, shift it toward the sky blue, not toward grey."**

The render is the negative reference. Two further collisions:

- **v3 §0.1.2 / §23.1** — *"Do not download, import, or reference any third-party asset. Every mesh, texture, icon, material and glyph in this game is generated."* The painted bow, the painted sword, the stone backdrop and the nebula wash cannot be produced by `_draw()` calls, and `coin_glyph.gd`'s own docstring says **"Drawn, never an image file."**
- **Adjacency.** The shop opens over a `#7EC8E3` sky and `#8FBF4F` grass. Taken wholesale, the render makes the shop look like a different game from the one behind it.

**This document does not resolve that.** It is split so the decision stays yours:

- **§3 — Tier A, structural.** Composition, hierarchy, geometry and interaction changes drawn from the render that are **palette-neutral**. Every one of them is an improvement on the shipped shop under *either* art direction, and every one is procedurally drawable with the vocabulary the project already has. This is most of the render's value.
- **§4 — Tier B, surface.** Palette, item artwork, backdrop and ornament. **These need §2's decision before a line is written.**

Implement Tier A on its own if the answer to §2 is "keep the art direction." It stands up alone.

---

## 1. What the render actually changes

Inventory of every difference from the shipped modal, before any judgement about which to take.

| # | Render | As built | Tier |
|---|---|---|---|
| 1 | Two large iconned tabs, **above** the panel, ~72% of panel width, active tab glowing | `TabContainer` with small text tabs `Buy`/`Sell`, inside the panel, top-left | A |
| 2 | No `SHOP` title at all — the tabs are the title | `SHOP` title, `DisplayLabel` 56, left of the header | A |
| 3 | Gold readout **centred** in an angled cartouche | right-aligned plain text in the header | A |
| 4 | Close X **twice** — top-right corner and bottom-centre | one X, top-right, 72 × 72 | A |
| 5 | Cards carry **item artwork** | no artwork anywhere | B |
| 6 | Rarity drives the **whole card treatment** — frame, glow, background | rarity is a 12 px left edge `ColorRect` | A (structure) / B (surface) |
| 7 | Higher-rarity card renders as a **full panel**: art left, name + subtitle + modifiers + large price right | all three cards identical, always show everything | A |
| 8 | Lower-rarity card is **compact**: name, art, price tag only | — | A |
| 9 | Price in a small angled **tag plaque**, bottom-right | plain right-aligned label, flush to the card edge | A |
| 10 | Compact card shows modifiers as an **icon row** (glyph + value) | text lines only | A |
| 11 | Cards are chunky — ~1.9:1 | 880 × 260, ~3.4:1 | A |
| 12 | Ornate metal frame, corner brackets, gem rivets | flat `StyleBoxFlat` | A (brackets) / B (ornament) |
| 13 | Dark stone backdrop with statues behind the panel | `#0F0E14` scrim at 65% | B |
| 14 | Dark desaturated purple/brown palette | v3 §6.1 palette | B |
| 15 | `$` currency symbol; a second bolt-like glyph on prices | one drawn coin glyph | **neither — see §5** |
| 16 | Third card shows base stats: damage 45, armour +13, bolt 33 | items have no base stats | **neither — see §5** |

---

## 2. The decision

Three coherent answers. Pick one; do not blend 1 and 3.

**Option 1 — Structure only (recommended).** Take all of Tier A. Keep v3 §6.1's palette exactly, keep everything procedural, keep the game visually one piece. Item "artwork" becomes a flat procedural weapon silhouette in the rarity colour with a `#0F0E14` outline, drawn in the same idiom as `slot_symbol.gd` and `status_icon.gd` (§4.2, Route A). **Cost: one session. Zero new assets. Zero conflict with any existing rule.**

**Option 2 — Structure now, surface later.** Take Tier A now; park Tier B behind a playtest. Costs nothing extra, because Tier A is written to be palette-neutral — every colour it uses is a `Tuning.C_*` reference, so a later palette decision is a `tuning.gd` edit and not a re-layout.

**Option 3 — Take the render.** Adopt Tier A **and** Tier B. This reverses design pillar 4 for the whole game, not just the shop: the battlefield, the console, the slot cabinet and Sir Fish all have to follow, or the shop reads as a bolted-on asset. It also needs five weapon models (§4.2, Route B) and a rewrite of v3 §6.1. **This is a project-level art direction change and should be decided as one, not smuggled in through the shop.**

Recommendation: **Option 1.** The render's real contribution is its *hierarchy* — it makes the rare item obviously the rare item, puts the gold where the eye lands first, and makes the tabs a real target instead of a 60 px text label. None of that is load-bearing on the palette, and all of it is cheap.

Record the answer in `QUESTIONS-shop-ui-v2.md` before writing code.

---

## 3. Tier A — structural, palette-neutral

All coordinates are logical viewport pixels (v3 §2). Every colour is a `Tuning.C_*` constant — **no file may write a hex literal** (v3 §6.1).

### 3.0 Assembly geometry *(supersedes v3 §15.1's panel position)*

Adding a tab bar above the panel changes the vertical assembly. Total height is `128 + 16 + 1200 = 1344`, centred in 1920:

| Element | Rect |
|---|---|
| `TabBar` | x **140 – 940** (800 wide), y **288 – 416** (128 tall) |
| `Panel` | x **60 – 1020** (960 wide), y **432 – 1632** (1200 tall) |

The panel keeps v3's 960 × 1200 size and its 40 px side padding, so the content column stays **880 wide at x 100 – 980** and the existing card width is unchanged. Panel entry animation (scale 0.85 → 1.0, alpha 0 → 1, 0.25 s, `TRANS_BACK/EASE_OUT`) is unchanged; the tab bar enters with it as one unit.

Panel interior, top to bottom:

| Element | Rect |
|---|---|
| `GoldPlate` | x **337 – 743** (406 wide), y **464 – 546** (82 tall) — centred |
| `CloseTop` | x **912 – 1008**, y **452 – 548** (96 × 96) |
| Card 1 | x 100 – 980, y **578 – 866** (880 × 288) |
| Card 2 | x 100 – 980, y **890 – 1178** |
| Card 3 | x 100 – 980, y **1202 – 1490** |
| `CloseBottom` | x **492 – 588**, y **1514 – 1610** (96 × 96) — centred |

Gaps are 24 px throughout; the bottom close button clears the panel edge by 22 px.

### 3.1 S1 — The tab bar *(supersedes v3 §15.1's `TabContainer` bullet)*

Two `Button`s, 396 × 128, 8 px apart, at the rect in §3.0.

- **Keep the `TabContainer`.** Set `tabs_visible = false` and drive `current_tab` from the two buttons. This preserves v3 §15.2's "Buy selected on open" and every existing child path — do not restructure the tab contents.
- Each tab holds a glyph and a label in an `HBoxContainer`, 16 px apart, centred: **BUY** takes a coin-stack glyph, **SELL** takes a pouch glyph. Both are `_draw()` calls in the `coin_glyph.gd` idiom — the coin stack is three offset `coin_glyph` circles; the pouch is a rounded polygon with a `C_GOLD` tie band. **No image files.**
- Label: `DisplayLabel` font 48. Active `C_TEXT`; inactive `C_TEXT_DIM`.
- Active tab: `C_PANEL` fill, 4 px `C_GOLD` border, and a 6 px outer glow in `C_GOLD` at 0.5 alpha. Inactive: `C_CONSOLE_BG` fill, 3 px `C_PANEL_BORDER` border, no glow, contents at 0.65 alpha.
- The active tab's bottom edge is flush with the panel top so it reads as attached; the inactive tab sits 6 px higher.
- Switching tabs crossfades the tab body over 0.12 s. **The tab bar is outside the panel, so it must be a sibling under the same modal root** — not a child of `Panel`, or the panel's stylebox will clip it.

**Drop the `SHOP` title** (v3 §15.1). The tabs name the screen.

### 3.2 S2 — The gold cartouche *(supersedes v3 §15.1's gold readout bullet)*

An angled plaque, centred, 406 × 82, holding a `coin_glyph` (radius 20) and `str(GameState.gold)` in `DisplayLabel` font 52, `C_GOLD`, 14 px apart, centred as a group.

Plaque: `C_CONSOLE_BG` fill, 3 px `C_PANEL_BORDER` border, drawn as a hexagon with 24 px chamfers on the left and right edges (matching the render's cartouche silhouette) via `draw_colored_polygon` — six points, `static var`, per v3 §16.7.

**Still updates live on every buy, sell and slot payout** (v3 §15.1). When it changes, punch it: scale 1.0 → 1.08 → 1.0 over 0.18 s, `TRANS_BACK/EASE_OUT`. Green for a gain, `C_DANGER` for a spend, back to `C_GOLD` over 0.3 s.

### 3.3 S3 — Corner brackets

The render's corner ornaments reduce to a drawable primitive: an L-shaped bracket at each of the four corners of the panel and of every card.

- Panel brackets: 72 × 72 arms, 8 px stroke, `C_GOLD`.
- Card brackets: 56 × 56 arms, 6 px stroke, **rarity colour** (v3 §17.9).
- Drawn with `draw_polyline` in the card's own `_draw()`. Six points per bracket, four brackets, one loop.

This is what carries the render's "framed" feel with no texture. **The gem rivets are Tier B** (§4.4).

### 3.4 S4 — Two close buttons *(amends v3 §15.4)*

The render's second, bottom-centre X is a real ergonomic gain and should be taken regardless of §2: on a 1920-tall portrait screen the top-right corner is out of one-handed thumb reach, and v3 §15.4 makes that corner the *only* way out of the modal.

- `CloseTop`, 96 × 96 (up from 72), at §3.0's rect, inset so it sits **on** the panel's top-right corner rather than inside it.
- `CloseBottom`, 96 × 96, centred at the panel's bottom.
- Both are `C_DANGER` fill, corner radius 20, `C_TEXT` glyph, drawn as a stroked X via `draw_line` — not a font `X`, which is what the shipped button uses and which is why the current glyph sits slightly off-centre.
- **Both call the same `close()`.** v3 §15.4's rule is otherwise unchanged: nothing else closes the modal, scrim clicks do not close it, and `ui_cancel` remains allowed-not-required.

### 3.5 S5 — Rarity drives the card treatment *(supersedes v3 §15.2's card structure)*

The render's own placeholder subtitle reads **"Magical full-panel"** — it is telling us that rarity selects the layout, not just an accent colour. That maps cleanly onto v3 §13.2's four rarities and their 0/1/2/3 modifier counts:

| Rarity | Modifiers | Treatment |
|---|---|---|
| Common | 0 | **Compact** — brackets, name, art, price tag |
| Uncommon | 1 | **Compact + glyph row** (§3.8) |
| Magic | 2 | **Full panel** |
| Rare | 3 | **Full panel** |

**Reject the alternative reading** — that the middle card is *selected* and the others are collapsed — because it implies a two-tap purchase, and v3 §15.2 specifies one tap. Changing the purchase interaction is not a UI-skin decision and is out of scope here.

Both treatments occupy the same 880 × 288 rect, so the three-card column is uniform.

**Compact card** (Common / Uncommon):

| Element | Rect within the card |
|---|---|
| Name, `DisplayLabel` 44, `C_TEXT`, centred | y 20 – 74 |
| Art region (§4.2), 400 × 144, centred | y 82 – 226 |
| Glyph row (Uncommon only, §3.8), left-aligned | x 20 – 500, y 214 – 277 |
| Price tag (§3.7) | x 647 – 860, y 214 – 277 |

**Full panel** (Magic / Rare):

| Element | Rect within the card |
|---|---|
| Art region, 240 × 240 | x 20 – 260, y 24 – 264 |
| Name, `DisplayLabel` 44, `C_TEXT` | x 288, y 30 – 84 |
| `subtitle()`, font 30, rarity colour | x 288, y 88 – 122 |
| Modifier lines, font 28, `C_TEXT_DIM`, one per modifier | x 288, from y 126, 34 px apart |
| Price + coin glyph, `DisplayLabel` 58, `C_GOLD` | x 288, y 200 – 262 |

The full panel additionally gets a 5 px border in the rarity colour, an outer glow in the rarity colour at 0.45 alpha, and a `scale` of **1.03** about its centre so it visibly pops out of the column — 906 × 297 rendered. The 12 px rarity edge bar from v3 §15.2 is **removed**; the brackets, border and glow carry rarity now.

**Trap, carried from v3 §15.2:** the card root is still a `PanelContainer`, which force-resizes every child to fill it. The compact/full swap must happen inside the existing `Row > [Edge, Layout]` structure — replace `Edge`'s role, do not re-parent the root.

### 3.6 S6 — Card geometry *(supersedes v3 §15.2's `880 × 260`)*

Cards go from 880 × 260 to **880 × 288**. The render's cards are ~1.9:1 because they hold artwork; 880 × 288 is 3.06:1, which is as chunky as the panel budget allows once the tab bar, cartouche and bottom close button are paid for. Three cards at 288 with 24 px gaps is 912 px of a 1200 px panel.

`shop_buy_card.tscn`'s `custom_minimum_size` and the two `offset_` values must both move — the shipped scene sets `Vector2(880, 260)` **and** `offset_bottom = 260.0`, and changing only one silently leaves the old height.

### 3.7 S7 — The price tag

A small angled plaque at the compact card's bottom-right, 213 × 63: `C_CONSOLE_BG` fill, 3 px `C_GOLD` border, left edge chamfered 20 px (a five-point `static var` polygon), holding a `coin_glyph` at radius 15 and the price in `DisplayLabel` 46, `C_GOLD`.

This closes v3.5 §2.4's finding about the price sitting flush against the card edge, and it supersedes that fix — do not apply both.

The full-panel card has **no** tag; its price is the inline font-58 line in §3.5.

**Affordability behaviour is unchanged** from v3 §15.2 and must survive the reskin intact: unaffordable → whole card `modulate = Color(0.45, 0.45, 0.5, 1.0)` and untappable; the idle price pulse (1.0 ↔ 1.04, 1.6 s) runs only when affordable; on purchase the price becomes `SOLD!` in `C_DANGER` and the card grays out permanently for that visit; **every card re-evaluates on every `gold_changed`**. v3 §15.2's worked example (200/250/300 against 350 gold) must still hold exactly.

### 3.8 S8 — The compact glyph row

The render's icon-and-number row is directly buildable from glyphs the project already draws: `bonus_strip.gd` has sword, bolt, coin, plus and element chips, all procedural.

For an Uncommon card, render its single modifier as one glyph + value pair, 44 px glyph, value in `DisplayLabel` 38, `C_TEXT`, 10 px apart, left-aligned in the rect from §3.5. Map `modifiers[n]["id"]` onto the same glyph vocabulary `bonus_strip.gd` uses; reuse its lookup rather than writing a second one, so the two can never drift.

If a modifier id has no glyph, fall back to the text label — **never** draw a placeholder box.

---

## 4. Tier B — surface treatment, blocked on §2

Do not write any of this until §2 is answered.

### 4.1 T1 — Palette

If §2 answers Option 3, v3 §6.1 is rewritten as a whole-project change, not a shop-local one, and this document is not the place for it. Raise it as a **BLOCKER** and get a full replacement palette table before touching `tuning.gd`.

Under Options 1 and 2 nothing here changes: every colour named in §3 is already a `C_*` constant.

### 4.2 T2 — Item artwork

The single biggest visual difference, and the one with a hard constraint: v3 §0.1.2 forbids imported assets, so the render's painted illustrations cannot be used. Two legitimate routes.

**Route A — procedural 2D silhouette (recommended, pairs with Option 1).**

One flat polygon per `weapon_type` — v3 §4.2 defines exactly five: `axe`, `sword`, `bow`, `dagger`, `staff`. Drawn filled in the rarity colour with a 4 px `C_INK` outline, scaled to fit the art rect, in the idiom `slot_symbol.gd` and `status_icon.gd` already establish. Each is a `static var PackedVector2Array` (v3 §16.7 — `const` is not a constant expression for these in 4.7). A slow ±3° rocking tween keeps it alive per pillar 2.

Cost: five polygons. No new assets, no `SubViewport`, no Blender time, and it is the only route that is consistent with "bold, flat, primary colour."

**Route B — 3D weapon render (pairs with Option 3).**

`item_render.tscn`: `SubViewportContainer` → `SubViewport` (`own_world_3d = true`) → `WorldEnvironment` + `DirectionalLight3D` + orthographic `Camera3D` + `WeaponRoot`, holding one of five low-poly Blender weapon meshes with the cel + outline treatment, idling at ±12° yaw.

Cost: five modelled and exported weapons — roughly 10% of M8's asset count — plus a new Blender sub-milestone. Schedule it after M8c, never before.

**Trap for Route B.** This puts **three** live `SubViewport`s in the modal on top of `SirFishTank`'s. Every one needs `own_world_3d` **and** its own `WorldEnvironment`, or it renders the battle world, or renders unlit — that is v3 §21.4's `sir_fish_tank.tscn` trap, three more times. Check the frame rate with `get_performance_monitors` while the modal is open, against v3's 60 fps floor.

### 4.3 T3 — Backdrop

The render's stone dungeon with statues is a background image and is forbidden by v3 §0.1.2.

Under Option 3 the nearest legitimate equivalent is a procedural vertical gradient plus a low-alpha repeating polygon motif drawn in `_draw()`. Under Options 1 and 2, **keep v3 §15.1's scrim exactly**: full-screen `C_INK` at 65% alpha, fading in over 0.2 s, and scrim clicks still do not close the modal.

### 4.4 T4 — Ornament

Gem rivets, filigree and metal bevel. All decoration, all Tier B, none of it load-bearing. The corner brackets in §3.3 carry the framed read on their own; if Option 3 is taken, rivets are `draw_circle` pairs at the bracket elbows and cost nothing extra.

---

## 5. What the render implies that the game must not adopt

Three things in the render come from a different game. Do not build them.

- **Base item stats.** The third card shows damage 45 / armour +13 / bolt 33. `Item` (v3 §4.2) has **no** base stats — only `modifiers`, `value` and `rarity`. Inventing a stat block means inventing a combat system to consume it. §3.8 renders the modifiers the item actually has.
- **Equipment comparison.** A stat row implies comparing against an equipped item. Equipping is deferred (v3 §22, and A6: *"No equipping in the demo"*). `Item.equipped` and `sellable_items()` exist and must keep working; no UI.
- **A second currency and the `$` symbol.** The render shows `$` on the gold plate and a different bolt-like glyph on prices. The game has one currency, rendered as one drawn `coin_glyph`. `$` also reads as real-world money, which is the wrong register for a fantasy shop.

---

## 6. Tuning additions

Per v3 §5, no file may hardcode these.

```gdscript
# --- 5.11 Shop UI v2 ------------------------------------------- [shop-ui-v2]
const SHOP_TAB_SIZE := Vector2(396, 128)
const SHOP_TAB_GAP := 8.0
const SHOP_CARD_SIZE := Vector2(880, 288)     # was 880 x 260 (v3 15.2)
const SHOP_CARD_GAP := 24.0
const SHOP_FEATURED_SCALE := 1.03             # Magic/Rare pop-out
const SHOP_FEATURED_GLOW_ALPHA := 0.45
const SHOP_BRACKET_ARM := 56.0                # card corner brackets
const SHOP_BRACKET_ARM_PANEL := 72.0
const SHOP_BRACKET_STROKE := 6.0
const SHOP_CLOSE_SIZE := 96.0                 # was 72 (v3 15.1)
const SHOP_GOLD_PLATE_SIZE := Vector2(406, 82)
const SHOP_GOLD_PUNCH_TIME := 0.18
const SHOP_PRICE_TAG_SIZE := Vector2(213, 63)
```

---

## 7. Amendments to v3, if scheduled

| v3 section | Status |
|---|---|
| §15.1 panel position | **Superseded** by §3.0 — panel moves to y 432 – 1632 to make room for the tab bar |
| §15.1 `SHOP` title | **Removed** by §3.1 |
| §15.1 gold readout | **Superseded** by §3.2 — centred cartouche, not right-aligned text |
| §15.1 close button | **Superseded** by §3.4 — 96 × 96, and there are two |
| §15.1 `TabContainer` | **Amended** by §3.1 — retained with `tabs_visible = false`, driven by external buttons |
| §15.2 card size | **Superseded** by §3.6 — 880 × 288 |
| §15.2 card structure | **Superseded** by §3.5 — rarity selects compact vs full panel |
| §15.2 rarity edge bar | **Removed** by §3.5 — brackets, border and glow carry rarity |
| §15.2 affordability | **Unchanged and must survive the reskin** — §3.7 |
| §15.3 sell row | **Unchanged.** The render shows only the Buy tab; do not guess at Sell. See §10. |
| §15.4 close | **Amended** by §3.4 — two buttons, same `close()`, everything else identical |
| §17.9 rarity colours | **Unchanged** — reused, and now carrying more weight |
| v3.5 §2.4 price padding | **Superseded** by §3.7 — do not apply both |
| §1.1 pillar 4, §6.1 palette | **Untouched under Options 1 and 2.** Option 3 rewrites them project-wide (§4.1) |

---

## 8. Traps

| Where | Trap |
|---|---|
| modal root | The tab bar sits **outside** `Panel`. Parent it to the modal root, or the panel's stylebox clips it. |
| `shop_modal.tscn` | Keep the `TabContainer` with `tabs_visible = false`. Replacing it re-paths every child and breaks v3 §15.2's cached-stock rule. |
| `shop_buy_card.tscn` | The root is a `PanelContainer` and force-resizes every child. Swap layouts **inside** `Row > Layout`, never by re-parenting the root. (v3 §15.2) |
| `shop_buy_card.tscn` | `custom_minimum_size` **and** `offset_bottom` both carry the height. Change one and the card silently keeps the old size. |
| all `_draw()` work | `const X := PackedVector2Array([...])` is not a constant expression in 4.7 — `static var`. The parse failure cascades into the class never registering. (v3 §21.4) |
| `shop_buy_card.gd` | Affordability re-evaluates on **every** `gold_changed`, including slot payouts arriving while the modal is open. The reskin must not drop that connection. |
| Route B only | Three more `SubViewport`s, each needing `own_world_3d` **and** its own `WorldEnvironment`, or they render the battle world or render unlit. (v3 §21.4) |
| everywhere | No hex literals. Every colour is a `Tuning.C_*`. That is what keeps §2's decision a one-file change. |
| v3.5 interaction | If v3.5 §3.1 has landed, the shop pauses the tree, so `ModalLayer` is `PROCESS_MODE_ALWAYS`. Every new tween here — the gold punch, the tab crossfade, the featured glow — inherits that and will run while paused. That is correct; just do not be surprised by it. |

---

## 9. Milestone M9 and its gate

**Why it cannot go earlier.** Tier A is genuinely independent of M8 and could technically run any time. It is scheduled after M8e anyway for two reasons: Route B (if Option 3 wins) needs the Blender pipeline proven through M8c, and M8e's gate is *"three consecutive full hands-off runs with stable node counts"* — a shop reskin lands three new procedural `_draw()` controls per card in the middle of exactly that measurement. Reskinning a screen that M8e is using as a stability baseline is the wrong order.

**Prerequisite:** §2 answered and recorded.

**Gate:**

1. **Layout, measured not eyeballed.** Screenshot the open modal and confirm the eight rects in §3.0 to the pixel.
2. **All four rarities.** Force one of each with `Debug shop` + `additem` and screenshot: Common and Uncommon render compact, Magic and Rare render as full panels at 1.03 scale with a rarity glow.
3. **v3 §15.2's worked example still holds exactly** — items at 200/250/300 against 350 gold, buy the 250, and confirm the other two gray out. Force it with `Debug shop 200 250 300` + `gold 350`. This is the one behaviour most likely to be lost in a reskin.
4. **Live gold.** Trigger a slot gold payout while the modal is open; the cartouche updates and punches, and affordability re-evaluates on all three cards.
5. **Both close buttons** dismiss the modal, and the shop encounter resolves — v3 §15.4's `closed` signal still fires, and `_run_shop()`'s `await` still returns. A shop that never resolves hangs the run forever (v3 §21.4).
6. **Sell tab untouched and still working** — open it, sell an item, confirm the row collapses, the gold plate updates, and the Buy tab's affordability re-evaluates.
7. **Route B only:** `get_performance_monitors` shows ≥ 60 fps with the modal open and three weapon viewports live.
8. **A full hands-off run** with zero errors and zero warnings, closing only the shop.

---

## 10. Open questions

Open `QUESTIONS-shop-ui-v2.md`. Same discipline as always: implement as specified, record every deviation with the file and the reasoning, change nothing silently, raise a **BLOCKER** rather than guessing.

Three are open now and one of them blocks the whole document.

- **BLOCKER — §2.** Option 1, 2 or 3. Nothing in Tier B may be written before this is answered, and Option 3 additionally requires a full replacement for v3 §6.1's palette table before `tuning.gd` is touched.
- **The Sell tab.** The render shows only Buy. `shop_sell_row.tscn` is 880 × 180 with the same edge structure the buy card is losing, so after §3.5 the two tabs will not match. Options: leave Sell alone and accept the mismatch for now, or extend the compact treatment to it. **Not guessed at here** — the render gives no evidence either way.
- **Route A vs Route B for item art (§4.2)** follows from §2 but is separable: Option 1 could still take Route B later, at the cost of five weapon models and three `SubViewport`s. Route A first is reversible; Route B first is not.

---

*End of specification.*
