# Moving elements out of code and into the editor

Branch: `move-elements-to-editor`.

Goal: anything with a **position, a size, a colour or a mesh** should be a node you
can select in the Godot editor, not a line in a `_ready()`. This file records what
moved, what deliberately did not, and what is left to decide.

---

## 1. Moved into the editor

Each of these had a fixed set of children built in code. They are authored nodes now;
the scripts that remain only supply data and behaviour.

| Scene | What is now authored | Script left holding |
|---|---|---|
| `scenes/console/upgrade_tray.tscn` | The three upgrade cards, at their own x / top / width | Pairing each card with `Upgrades.ORDER`, re-heighting on console resize |
| `scenes/console/upgrade_button.tscn` | Four parchment `StyleBoxFlat` button faces, the medallion box (`Icon`), the pip row (`Pips`), the coin (`Coin`, now a plain `TextureRect`), the blurb's ink | Two `_draw()` callbacks - the per-upgrade medallion and the per-level pips - and the buy/afford state |
| `scenes/console/party_bars.tscn` | Three hero bars in a `VBoxContainer`; gap = `separation`, centring = `alignment` | Binding each bar to a live hero, hiding spares |
| `scenes/console/slot_reel.tscn` | The five visible symbol cells | Their y positions (the reel scrolls - not authorable) |
| `scenes/console/sir_fish_tank.tscn` | The whole bowl: `WaterBackdrop`, `Glass`, `Base`, `Gravel`, `Plaque`, `PlaqueText`, plus the `Bubbles` burst | Nothing - `sir_fish_tank.gd` is a doc comment now |
| `scenes/modals/run_summary.tscn` | Sir Fish at the top, and one named row per statistic with its caption and a dummy value | Writing real numbers into rows **by node name** |
| `scenes/modals/shop_modal.tscn` | `BonusStrip` (under the header) and `CompareFlyout` (last child) | Opening / closing, stocking the tabs |
| `scenes/battle/props/shop_building.tscn` | `Walls`, `Roof`, `Door`, `Sign`, `WindowGlow` | Pop-in / fade-out tweens |
| `scenes/battle/props/treasure_chest.tscn` | `Body`, four corner straps, hinged `Lid`, `InteriorGlow` | Opening, the coin shower, the flash |
| `scenes/battle/projectiles/arrow.tscn` | `Shaft`, `Fletch`, `Tip`, and the 1.8 view scale on the root | Flight arc and aiming |
| `scenes/battle/projectiles/bomb_arrow.tscn` | **Inherits `arrow.tscn`** and adds `Bag`, `Fuse`, `FuseSpark`, `BombTrail`, `FuseLight` | as above |

### Dummy data, as agreed

Where a thing needs real data to say anything, the scene carries a stand-in that the
game overwrites - the same trick `GoldLabel`'s authored `1275` already used:

- **Upgrade cards** carry `Overcharge` / `Lightning pays +25%.` / `50`; `setup()`
  replaces the title, `refresh()` replaces the blurb and price.
- **Party bars** carry mage / ranger / warrior in the concept board's own
  green / blue / gold, at its own `102 / 120`, `80 / 80`, `70 / 70`; `party_bars.gd`
  overwrites colour, glyph and text the moment a party exists.
- **Run summary** rows carry every caption for real and a plausible number
  (`Gold earned  1480`); only the `Value` labels are overwritten.
- **Reel cells** carry one of each symbol so the reel reads in the editor; the first
  frame of `_layout()` replaces all five from `Tuning.SLOT_STRIP`.

### Two behaviours that got better on the way

- `upgrade_button.gd` now measures its medallion off `Icon.size` and its pip row off
  `Pips.size`, instead of `ICON_SIZE` / `PIP` / `PIP_GAP` constants. Dragging those
  boxes in the editor actually changes the drawing.
- `upgrade_tray.gd` only imposes a **height** on its cards. x, width and top margin
  are whatever the editor says.

### One tradeoff worth knowing

Colours that moved into a scene (the props' and projectiles' cel materials, the
parchment styleboxes) are now literal values in the `.tscn` rather than reads of
`Tuning.C_WOOD`, `Tuning.C_PARCHMENT` and friends. That is the point - they are
editable in the inspector - but it does mean **editing the `Tuning` constant no longer
moves them**. The values were transcribed exactly; if the palette is ever re-based,
these are the places to re-sync.

---

## 2. Left in code because the LAYOUT depends on the data - for review

These are the ones flagged rather than forced.

### 2.1 Shop lists - `shop_modal.gd`

`_build_buy()` makes one card per item in stock, `_build_sell()` one row per
inventory item. The card and row **designs are already fully authored**
(`shop_buy_card.tscn`, `shop_sell_row.tscn`), so only the count is code.

**Worth deciding:** `Tuning.SHOP_ITEMS_FOR_SALE` is a constant, so the Buy tab is
*always* exactly that many cards. Those could be authored placeholders that `setup()`
fills, the same way the upgrade tray now works. The Sell tab genuinely cannot - the
inventory is any length.

### 2.2 Item modifier lines - `shop_buy_card.gd`, `compare_flyout.gd`

One `Label` per modifier an item rolled, so the count is per-item. The font sizes
(28 on a buy card, 26 in the compare panel) and colours live in code.

**Worth deciding:** a one-Label `mod_line.tscn` would move the styling into the
editor even though the count stays dynamic. Not done because the two call sites want
different sizes and `compare_flyout`'s colours are semantic (green = better,
red = worse), so a shared scene would only carry about half the design. A theme type
variation in `assets/theme.tres` may be the better answer.

### 2.3 The bonus strip - `bonus_strip.gd`

The entire strip is one `_draw()`. It shows only the bonuses that are non-zero, and
it *measures* the visible run of glyph+text pairs so it can centre the whole thing -
so both the number of entries and their positions are functions of the data. Six
possible entries in a fixed order, though, so a version with six authored
glyph+label pairs that hide themselves is possible.

### 2.4 Enemy bars and floating numbers - `battle_overlay.gd`

One `CombatantBars` per enemy spawned, plus damage numbers, health chunks and status
icons that exist for under a second. All four scenes are authored already
(`combatant_bars.tscn`, `damage_number.tscn`, `floating_health_chunk.tscn`,
`status_icon.tscn`); only the spawning is code. Nothing to move.

### 2.5 The console's three bands - `console.gd` / `slot_machine.gd` / `upgrade_tray.gd`

`apply_height()` positions the status strip, the cabinet and the tray from the
runtime battle/console split (`main_layout.gd`). This is the biggest remaining
"layout in code" in the project.

**Worth deciding:** these three could be children of a `VBoxContainer` with size flags
and `custom_minimum_size`, which would put the band proportions in the inspector. It
is a real change to how the split behaves under a short viewport (today the cabinet is
squeezed first and the tray second, deliberately), so it needs a decision first.

---

## 3. Left in code on purpose - generated or drawn, not placed

Not candidates: converting these would lose something real.

- **Custom-drawn controls** - `ornate_frame.gd`, `coin_glyph.gd`, `payline.gd`,
  `reel_grid.gd`, `class_icon_glyph.gd`, `buff_chip.gd`, `status_icon.gd`,
  `slot_symbol.gd`. These *are* editor objects already: you place them, resize them,
  and they expose `@export` knobs (`border`, `corner_radius`, `vines`, `line_width`,
  `glow_color`, `box_fraction`). Only their pixels come from `_draw()`, which is what
  keeps them resolution-independent.
- **`storm_rain.gd`** - three rain bands plus a splash layer whose sideways drift is
  derived from one `WIND_ANGLE_DEG`. The file argues its own case: hand-entering the
  same derived number in four places is how bands end up disagreeing about wind.
  (Note: `scenes/battle/storm_rain.tscn` is not instanced by `battle_world.tscn` any
  more - see section 4.)
- **`parallax_background.gd`** - layers baked with `SurfaceTool` so they are seamless
  by construction.
- **`overworld_field.gd`** - ~330 props as `MultiMesh` instances explicitly to avoid
  ~500 `Node3D`s moving every frame.
- **`battle_vfx.gd`, `lightning.gd`** - transient effects, spawned and freed.
- **`treasure_chest.gd`'s coin shower and radial flash** - same.
- **`cel_materials.gd`** - still the factory for combatant materials, and it must stay
  per-instance so two orcs do not flash and fade as one.
- **`combatant_rig.gd`** - despite the name it builds no geometry any more; it is a
  per-character *materials* pass for the cases a `.glb` cannot carry (the two orcs
  share one asset and are coloured apart at runtime, the shadow monster needs its
  smoke material, the KayKit heroes ship every prop variant switched on).
  **Possible follow-up:** the orc recolour could become a material override in
  `orc_barbarian.tscn` / `orc_warlord.tscn` instead.

---

## 4. Things noticed in passing (not touched)

- **`hero_bars.gd` `HERO_FILL_WIDTH` disagrees with its own scene.** The constant is
  `352.0` and the doc comment describes a 362 / 356 / 352 nest, but `hero_bars.tscn`
  authors `HealthBorder` 307 wide, `HealthBg` 296 and `HealthFill` 296. Since
  `set_health_fraction()` writes `352 * fraction`, a full bar overflows its own track
  by about 56 px. Pre-existing; left alone because fixing it changes how every party
  bar reads.
- **`status_panel.gd`** still has the depth-plate wiring commented out
  (`_update_depth`, the `encounter_started` connection).
- **`scenes/battle/storm_rain.tscn`** is not referenced by any scene or script.
