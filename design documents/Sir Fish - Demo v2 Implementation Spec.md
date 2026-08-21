# Sir Fish — Demo v2 Implementation Specification

**Document type:** build prompt for an implementing model
**Project:** `C:\Projects\Godot\Sir Fish` (Godot 4.7-stable, Forward+)
**Supersedes:** `Sir Fish - Demo v1 Implementation Spec.md` — **v1 is dead.** Do not read it, do not cite it, do not resolve a conflict in its favour. This document is the whole specification.
**Answers:** every question in `QUESTIONS.md` (Q0–Q24). See §0.2 for the index.
**Source:** `design documents/initial vision.txt`, plus v1's owner-resolved decisions, plus two scope additions ratified by the owner for v2 (§0.4).

---

## 0. How to use this document

M0–M5 of v1 are **built and verified**. You are not starting from zero. Roughly 100 source files exist and a full run plays hands-off from encounter 0 to the run summary. Your job is three further milestones:

- **M6 — Ratification pass.** Apply this document's answers to the existing code. No new features.
- **M7 — Core-loop slice.** Build the upgrade system, make items affect play, and put Sir Fish in the console.
- **M8 — Blender assets.** Replace every primitive with a model.

Where this document gives a number, use that exact number. Where it gives a name, use that exact name. Where it differs from the code that exists, **the document wins and the code changes** — every such difference is listed explicitly in §21.

### 0.1 Non-negotiable working rules

1. **Use the Godot MCP Pro tools for all Godot work.** Read `CLAUDE.md` at the project root first.
   - Never edit `project.godot` by hand. Use `set_project_setting`.
   - Prefer `update_property` (inspector values) over hardcoding visual values in scripts. Scripts hold *logic*; scenes hold *configuration*.
   - **Exception — resource-valued properties.** No tool in this MCP build can assign an existing `.tres`/`.tscn` to a node property (`add_resource` only *creates* a new inline resource; `update_property` writes `null`). Do **not** hand-edit `.tscn` files to work around this. Instead declare the property as `@export var x: SomeType = preload("res://path.tres")` in the node's script. The exported default is visible and overridable in the inspector, which satisfies the intent of the rule, and it needs no tool support. This is the standing answer to **Q22**.
   - Use explicit type annotations everywhere. `var x := <call on an untyped variable>` is a hard parse error in 4.7; `const X := PackedVector2Array([...])` is not a constant expression — use `static var`. Both bit v1.
2. **Use the Blender MCP tools for all 3D asset work** (M8). Do not download, import, or reference any third-party asset. Every mesh, texture, icon, material and glyph in this game is generated — procedurally in Godot, or modelled in Blender via MCP.
3. **Verify every milestone.** Each milestone in §20 has a gate. Drive it with `play_scene` + the runtime tools + the `Debug` harness (§19) + the headless tests (§19.3), screenshot it, and run `get_editor_errors` / `get_output_log`. The gate is not passed while any error or warning exists.
4. **Check `get_editor_errors` after every script write.** Use `validate_script` before `save_scene`.
5. **All balance numbers live in `res://scripts/autoload/tuning.gd`** (§5). No magic numbers anywhere else.

### 0.2 Where each open question is answered

| Q | Subject | Answer | Section |
|---|---|---|---|
| Q0 | MCP toolset connected | Closed. Verified figures carried into §16.2, §13.3. | — |
| Q1 | `msaa_3d` = 2 or 2× | **4× MSAA (`msaa_3d = 2`).** The literal was right, the annotation was wrong. | §2 |
| Q2 | Limb rotations invisible to the camera | **Ratified.** All limb keys re-authored on `rotation.z`, signs re-derived from physical intent. | §9.0, §9.1–9.5 |
| Q3 | Forward-axis convention for enemies | **Ratified.** One clip set, forward = local +X, enemies carry `rotation.y = PI`. | §9.0 |
| Q4 | `model_scale` collides with squash/stretch | **Ratified.** `model_scale` → `Rig.scale`; `Visual.scale` reserved for animation. | §8.2 |
| Q5 | `run` / `special` not on every combatant | **Changed.** Mandatory set is derived from data (`is_hero`, `special_every_n_actions`) and validated. | §8.3 |
| Q6 | Warlord 1.15× time scale | **Ratified as slower.** Impact drift eliminated by mandating method-call tracks. | §8.7, §10.2 |
| Q7 | `demo_level.tres` vs `build_level()` | **Code is canonical. Delete the `.tres`.** | §12.1 |
| Q8 | Cooldown accounting while attacking | **Behaviour ratified, stat table corrected.** Stop the discarded decrement. | §5.2, §10.2 |
| Q9 | Priest skip rule and `% n` | **Changed.** A `special_pending` flag replaces the `action_count` decrement. | §10.2 |
| Q10 | Simultaneous damage numbers | **Changed.** Global AoE stagger + anti-overlap offsets. | §5.1, §11.4 |
| Q11 | Dead heroes hidden, not freed | **Ratified.** "Removed from the battlefield" = visually removed. | §12.5 |
| Q12 | Files beyond §3.1's tree | **Ratified.** The tree was a floor. §3.1 now lists everything. | §3.1 |
| Q13 | Modifier duplicates on one item | **Ratified.** Drawn without replacement. | §13.2 |
| Q14 | Shop price spread too wide | **Spread kept, stock rule added.** One card is always cheap, one is always a teaser. | §13.6 |
| Q15 | Defend icon outlives the warrior | **Changed.** All status icons and buffs are cancelled on death. | §8.5 |
| Q16 | Outline cannot fade | **Changed.** `outline.gdshader` gains `blend_mix` + an `alpha` uniform. | §6.3 |
| Q17 | Slot dims through most of the demo | **Changed.** Attract mode: reels drift, nothing pays. | §16.6 |
| Q18 | There is no fish | **Resolved by the owner.** Sir Fish is the player — he lives in the console. | §1.2, §17.7 |
| Q19 | Bomb arrow reads like an arrow | **Changed.** Universal special-cast telegraph + a bomb trail. | §9.6 |
| Q20 | Typography at 1080×1920 | **Changed.** `FontVariation` emboldens the built-in font. No files shipped. | §6.5 |
| Q21 | No `execute_*_script` in this MCP build | **Yes to a harness — permanent and flag-gated, not temporary.** | §19 |
| Q22 | Theme severed by `CanvasLayer`; resources unassignable | **Changed.** `ModalLayer` becomes a `Control`. Resources via `@export` + `preload`. | §0.1.1, §3.3 |
| Q23 | Gold on hand is 50–100, not 150–260 | **Supply raised**, prices untouched. | §5.4, §13.6 |
| Q24 | Summary win % reads low on short runs | **Changed.** Raw count on the summary, live counter in the console, % only in the test. | §17.8, §18.2 |

### 0.3 Engine version

`get_project_info` reports **4.7-stable (official)**, `forward_plus`. Do not change the declared feature set. Everything here uses APIs stable in 4.4+. If an API in this document does not exist, use the nearest equivalent and append a note to §21.

### 0.4 What v2 adds beyond ratification

Two scope additions, both owner-ratified:

1. **Sir Fish exists.** The title stops being a lie. Sir Fish is not a hero — **he is the player's avatar**, an armoured fish in a tank bolted to the management console, reacting to everything that happens. He has no gameplay effect. He costs one small model and a set of reaction states, and he gives the console a face. (§1.2, §17.7)
2. **The core loop is real.** The initial vision names *"by buying upgrades and finding items in the world, the slot machines give bigger and better bonuses more often"* as the heart of the game, and v1 deferred all of it — an empty upgrade tray and items with no effect. v2 builds a **vertical slice**: three purchasable slot upgrades (§17.6) and item modifiers that actually feed hero damage and slot payouts (§13.5). Not a full upgrade tree — enough that the loop closes and can be felt. (§13.5, §17.6)

### 0.5 Scope discipline

This is still a **demo**. Build exactly what is specified. Systems marked *Deferred* in §22 must be structurally accommodated and must not be implemented.

---

## 1. What the game is

**Sir Fish** is an autobattler crossed with a slot-machine incremental.

- The **top third** of the screen is an autobattler: a party of three heroes travels left-to-right through a sequence of encounters and fights without any player input.
- The **bottom two thirds** is the **management console**: a slot machine that spins continuously during combat and pays out in damage, gold, and healing; a button that buys the party temporary advantages; and an upgrade tray that makes the slot pay bigger and more often.

The player never controls the heroes. The player's entire agency lives in the console.

### 1.1 Design pillars (use these to break ties)

1. **Legibility over spectacle.** A player must be able to read what happened in combat at a glance. This is why cooldowns start staggered, why every hit detaches a visible chunk of health bar, why area effects stagger, and why targeting is simple.
2. **The console is always doing something.** Even when the player isn't tapping, the slot is moving and the upgrade tray is live. Dead air is a bug.
3. **Juice on every state change.** Chests pop, bars detach and float, lightning cracks, symbols slam into place, the fish reacts. Nothing appears or disappears without a tween.
4. **Bold, flat, primary colour.** Positive references: *Breath of the Wild*, *CrossCode*, *Monster Train*. Negative references: *DOOM*, *Halls of Torment*, *Voin*. If it reads as gritty, desaturated, or brown, it is wrong.

### 1.2 Who Sir Fish is

**Sir Fish is the player.** He is a small armoured fish — a knight's helm, a gold circlet, blue scales — in a glass tank mounted on the left side of the management console, directly beside the button you press. He is the one running the war room. The heroes are his employees.

He is **purely decorative and has zero gameplay effect**, and that is deliberate: he is the emotional read on state the numbers can't give you. He cheers when the slot pays, darts when a hero is hit, sinks to the gravel when one dies, and lies on his side when the run ends. The full state table is §17.7.

This resolves **Q18**. The name is no longer a working title.

---

## 2. Target platform and project settings

**Portrait mobile, 1080 × 1920.** Touch-first, fully playable with a mouse in the editor.

Apply with `set_project_setting`:

| Setting | Value |
|---|---|
| `display/window/size/viewport_width` | `1080` |
| `display/window/size/viewport_height` | `1920` |
| `display/window/size/window_width_override` | `540` |
| `display/window/size/window_height_override` | `960` |
| `display/window/stretch/mode` | `canvas_items` |
| `display/window/stretch/aspect` | `keep` |
| `display/window/handheld/orientation` | `portrait` |
| `rendering/renderer/rendering_method` | `forward_plus` |
| `rendering/anti_aliasing/quality/msaa_3d` | **`2`** — this is the enum value for **4× MSAA** |
| `rendering/environment/defaults/default_clear_color` | `Color(0.494, 0.784, 0.890)` (`#7EC8E3`) |
| `input_devices/pointing/emulate_touch_from_mouse` | `true` |
| `application/run/main_scene` | `res://scenes/main.tscn` |
| `application/config/name` | `Sir Fish` |
| `physics/common/physics_ticks_per_second` | `60` |
| `sir_fish/debug/harness` | `true` — custom setting, see §19 |

**Q1 answered.** The property is an enum (`0 = Disabled, 1 = 2×, 2 = 4×, 3 = 8×`). v1 wrote `2` and annotated it "2× MSAA — outlines need it". The literal and the parenthetical disagreed; the *intent* — "outlines need it" — argues for more antialiasing, not less. Use **`2` = 4×**. The inverted-hull outline is the entire art direction and it is 0.018 world units thin; it aliases visibly at 2×. The scene has under 40 meshes, so the cost is irrelevant on desktop. If a mobile export preset is ever added, override to `1` there and nowhere else.

The window override (540×960) exists so the game window fits a development monitor while the logical viewport stays 1080×1920. **All coordinates in this document are logical viewport pixels.**

### 2.1 Screen budget (exact, sums to 1920)

| Region | Y range | Height | Owner |
|---|---|---|---|
| Battle viewport | 0 – 640 | 640 | `BattleView` (3D SubViewport) |
| Divider | 640 – 648 | 8 | `ConsoleDivider` (gold bar) |
| Status panel | 648 – 948 | 300 | `StatusPanel` |
| Slot machine | 948 – 1548 | 600 | `SlotMachine` |
| Fish tank / damage button / slot counter | 1548 – 1708 | 160 | `SirFishTank`, `PartyDamageButton`, `SlotCounter` |
| Upgrade tray | 1708 – 1920 | 212 | `UpgradeTray` (live in v2) |

640 is exactly one third of 1920.

---

## 3. Architecture

### 3.1 Directory layout

This is the **complete** tree, not a floor — it lists every file that exists plus every file v2 adds. **Q12 answered:** v1's tree was under-specified and the implementer was right to add files; those files are now named here. New in v2 is marked **[new]**; deleted is marked **[delete]**.

```
res://
├── assets/
│   ├── display_font.tres                       [new]  FontVariation, §6.5
│   ├── theme.tres
│   ├── materials/
│   │   ├── cel_shade.tres
│   │   └── outline.tres
│   ├── meshes/                                        .glb exports (M8); empty until then
│   └── shaders/
│       ├── cel_shade.gdshader
│       ├── outline.gdshader                           gains alpha uniform, §6.3
│       ├── smoke.gdshader
│       ├── parallax_layer.gdshader
│       └── water.gdshader                      [new]  fish tank glass, §17.7
├── scenes/
│   ├── main.tscn
│   ├── battle/
│   │   ├── battle_world.tscn
│   │   ├── combatant.tscn
│   │   ├── parallax_background.tscn
│   │   ├── heroes/{warrior,ranger,priest}.tscn
│   │   ├── enemies/{shadow_monster,orc_barbarian,orc_warlord}.tscn
│   │   ├── props/{treasure_chest,shop_building}.tscn
│   │   └── projectiles/{arrow,bomb_arrow}.tscn
│   ├── overlay/
│   │   ├── battle_overlay.tscn
│   │   ├── combatant_bars.tscn
│   │   ├── floating_health_chunk.tscn
│   │   ├── damage_number.tscn
│   │   └── status_icon.tscn
│   ├── console/
│   │   ├── console.tscn
│   │   ├── status_panel.tscn
│   │   ├── hero_status_row.tscn
│   │   ├── inventory_strip.tscn
│   │   ├── slot_machine.tscn
│   │   ├── slot_reel.tscn
│   │   ├── slot_symbol.tscn
│   │   ├── party_damage_button.tscn
│   │   ├── sir_fish_tank.tscn              [new]  §17.7
│   │   ├── slot_counter.tscn               [new]  §17.8
│   │   ├── upgrade_tray.tscn               [new]  §17.6
│   │   ├── upgrade_button.tscn             [new]  §17.6
│   │   └── bonus_strip.tscn                [new]  §17.6
│   └── modals/
│       ├── shop_modal.tscn
│       ├── shop_buy_card.tscn
│       ├── shop_sell_row.tscn
│       ├── item_tooltip.tscn
│       └── run_summary.tscn
├── scripts/
│   ├── autoload/
│   │   ├── tuning.gd            Tuning
│   │   ├── rng.gd               RNG
│   │   ├── event_bus.gd         EventBus
│   │   ├── itemizer.gd          Itemizer
│   │   ├── game_state.gd        GameState
│   │   ├── upgrades.gd          Upgrades   [new]  §17.6
│   │   └── debug.gd             Debug      [new]  §19
│   ├── data/
│   │   ├── combatant_stats.gd
│   │   ├── item.gd
│   │   ├── encounter_def.gd
│   │   └── level_def.gd
│   ├── battle/
│   │   ├── combatant.gd
│   │   ├── combatant_rig.gd
│   │   ├── combatant_animations.gd
│   │   ├── ability.gd
│   │   ├── battle_director.gd
│   │   ├── battle_world.gd
│   │   ├── battle_vfx.gd
│   │   ├── cel_materials.gd
│   │   ├── parallax_background.gd
│   │   ├── projectile.gd
│   │   ├── treasure_chest.gd
│   │   └── shop_building.gd
│   ├── run/
│   │   └── run_controller.gd
│   ├── console/
│   │   ├── console.gd
│   │   ├── status_panel.gd
│   │   ├── hero_status_row.gd
│   │   ├── inventory_strip.gd
│   │   ├── buff_chip.gd
│   │   ├── coin_glyph.gd
│   │   ├── slot_machine.gd
│   │   ├── slot_reel.gd
│   │   ├── slot_symbol.gd
│   │   ├── party_damage_button.gd
│   │   ├── sir_fish_tank.gd                [new]
│   │   ├── sir_fish.gd                     [new]
│   │   ├── slot_counter.gd                 [new]
│   │   ├── upgrade_tray.gd                 [new]
│   │   ├── upgrade_button.gd               [new]
│   │   └── bonus_strip.gd                  [new]
│   ├── overlay/
│   │   ├── battle_overlay.gd
│   │   ├── combatant_bars.gd
│   │   ├── damage_number.gd
│   │   ├── floating_health_chunk.gd
│   │   └── status_icon.gd
│   └── modals/
│       ├── shop_modal.gd
│       ├── shop_buy_card.gd
│       ├── shop_sell_row.gd
│       ├── item_tooltip.gd
│       └── run_summary.gd
├── resources/
│   ├── stats/{warrior,ranger,priest,shadow_monster,orc_barbarian,orc_warlord}.tres
│   └── levels/demo_level.tres               [delete]  §12.1
└── tests/
    ├── test_slot_odds.{gd,tscn}
    ├── test_item_distribution.{gd,tscn}
    ├── test_damage_chunk.{gd,tscn}          [new]  §19.3
    ├── test_retarget.{gd,tscn}              [new]  §19.3
    ├── test_economy.{gd,tscn}               [new]  §19.3
    └── test_upgrades.{gd,tscn}              [new]  §19.3
```

### 3.2 Autoloads

Register in this order. `Tuning` and `RNG` must exist before `GameState`; `Upgrades` before anything that reads a payout.

| Order | Name | Path |
|---|---|---|
| 1 | `Tuning` | `res://scripts/autoload/tuning.gd` |
| 2 | `RNG` | `res://scripts/autoload/rng.gd` |
| 3 | `EventBus` | `res://scripts/autoload/event_bus.gd` |
| 4 | `Itemizer` | `res://scripts/autoload/itemizer.gd` |
| 5 | `Upgrades` | `res://scripts/autoload/upgrades.gd` **[new]** |
| 6 | `GameState` | `res://scripts/autoload/game_state.gd` |
| 7 | `Debug` | `res://scripts/autoload/debug.gd` **[new]** |

The three `MCP*` autoloads already present must be left untouched.

### 3.3 Root scene tree (`res://scenes/main.tscn`)

```
Main (Control, anchors full rect, mouse_filter = IGNORE, theme = res://assets/theme.tres)
├── BattleView (SubViewportContainer)          # pos (0,0)   size 1080×640, stretch = true
│   └── BattleViewport (SubViewport)           # size 1080×640, transparent_bg = false
│       └── BattleWorld (Node3D)               # instance of battle_world.tscn
├── BattleOverlay (Control)                    # pos (0,0)   size 1080×640, mouse_filter = IGNORE
│   ├── BarsLayer (Control)
│   ├── FloatingLayer (Control)                # detached chunks, damage numbers, loot labels
│   └── VfxLayer (Control)                     # status icons
├── ConsoleDivider (ColorRect)                 # pos (0,640)  size 1080×8   colour #F2C230
├── Console (Control)                          # pos (0,648)  size 1080×1272
│   ├── StatusPanel (PanelContainer)           # pos (0,0)    size 1080×300
│   ├── SlotMachine (Control)                  # pos (0,300)  size 1080×600
│   ├── SirFishTank (SubViewportContainer)     # pos (8,898)  size 164×164        [new]
│   ├── PartyDamageButton (Button)             # pos (180,900) size 720×160
│   ├── SlotCounter (Control)                  # pos (900,898) size 172×164       [new]
│   └── UpgradeTray (Control)                  # pos (0,1060) size 1080×212       [live in v2]
├── ModalLayer (Control)                       # full rect, mouse_filter = IGNORE  [CHANGED]
│   ├── ShopModal (hidden by default)
│   └── RunSummary (hidden by default)
└── RunController (Node)                       # run_controller.gd — drives everything
```

**Q22 answered — `ModalLayer` is a `Control`, not a `CanvasLayer`.** v1 put the modals under a `CanvasLayer`; theme inheritance walks the `Control` tree, so the `CanvasLayer` severed it and both modals rendered in Godot's default theme. v1's fix — assigning `theme` on each modal instance — works but needs a `.tscn` hand-edit (no MCP tool can assign an existing resource) and creates three places the theme is named.

Make `ModalLayer` a full-rect `Control` with `mouse_filter = IGNORE`, declared **last** among `Main`'s children. Draw order in a `Control` tree is tree order, so last child = on top, and §6.5's single-assignment rule holds literally: `Main.theme` is the only theme assignment in the project. Remove both per-modal `theme` lines.

**Standing rule:** nothing may be added to `Main` after `ModalLayer`. If something must sit above the modals later, add it as a child of `ModalLayer`.

**Why a SubViewport:** the battlefield is 3D and must be clipped to the top 640px. `BattleView` and `BattleOverlay` are the same size at the same position, so a point from `camera.unproject_position()` maps **1:1** into `BattleOverlay` local coordinates with no extra transform. `ModalLayer` being a plain `Control` in the same space does not disturb this.

### 3.4 EventBus signals

Define exactly these. All cross-system communication goes through them — no direct node-path lookups between the battle and the console. Keep `@warning_ignore_start("unused_signal")` at the top of the file; every signal is emitted from elsewhere.

```gdscript
extends Node
@warning_ignore_start("unused_signal")

# --- Run flow ---
signal run_started()
signal encounter_started(index: int, def: EncounterDef)
signal encounter_resolved(index: int, def: EncounterDef)
signal travel_started()
signal travel_finished()
signal run_completed()
signal game_over()

# --- Combat ---
signal combat_started(heroes: Array, enemies: Array)
signal combat_ended(victory: bool)
signal combatant_spawned(c: Node)
signal combatant_attacked(attacker: Node, target: Node, amount: int)
signal combatant_damaged(target: Node, amount: int, previous_hp: int, new_hp: int)
signal combatant_healed(target: Node, amount: int)
signal combatant_died(c: Node)
signal hero_damage_dealt(amount: int)          # feeds the slot's rolling 3-hit buffer

# --- Economy / items ---
signal gold_changed(new_total: int, delta: int)
signal item_added(item: Item)
signal item_removed(item: Item)
signal party_bonuses_changed(bonuses: Dictionary)   # [new] §13.5

# --- Console ---
signal slot_spin_started()
signal slot_spin_stopped(symbols: Array)       # Array[int] of 3 Sym values
signal slot_payout(kind: String, count: int)   # kind in "lightning"|"gold"|"heal"
signal party_damage_buff_started(duration: float)
signal party_damage_buff_ended()
signal upgrade_purchased(id: StringName, new_level: int)   # [new] §17.6
```

`party_bonuses_changed` fires whenever the inventory changes; `upgrade_purchased` whenever a level is bought. Both are what Sir Fish, the bonus strip and the slot listen to.

---

## 4. Data model

### 4.1 `CombatantStats` (`scripts/data/combatant_stats.gd`)

```gdscript
class_name CombatantStats
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var is_hero: bool = false
@export var max_hp: int = 100
@export var base_damage: int = 10
@export var attack_cooldown: float = 1.5      # RECOVERY after an action ends — see §5.2
@export var special_every_n_actions: int = 0  # 0 = no special
@export var model_scale: float = 1.0
@export var body_color: Color = Color.WHITE
@export var accent_color: Color = Color.WHITE
@export var scene_path: String = ""

## The exact set of animation names this character must expose (§8.3).
## Derived, not authored — there is no second source of truth to drift.
func required_anims() -> Array[StringName]:
    var names: Array[StringName] = [&"idle", &"attack", &"hurt", &"die"]
    if is_hero:
        names.append(&"run")
    if special_every_n_actions > 0:
        names.append(&"special")
    return names
```

One `.tres` per character in `res://resources/stats/`. Values in §5.2.

### 4.2 `Item` (`scripts/data/item.gd`)

```gdscript
class_name Item
extends Resource

enum Rarity { COMMON, UNCOMMON, MAGIC, RARE }
enum Kind { WEAPON, POTION, RELIC }

@export var display_name: String = ""        # generated, e.g. "Fat Knife"
@export var kind: Kind = Kind.WEAPON
@export var rarity: Rarity = Rarity.COMMON
@export var weapon_type: StringName = &""    # axe|sword|bow|dagger|staff ; empty if not a weapon
@export var modifiers: Array[Dictionary] = []# [{ "id": &"dmg_flat", "label": "+4 Damage", "roll": 4, "value_mult": 0.42 }, ...]
@export var value: int = 0                   # computed intrinsic gold value
@export var equipped: bool = false           # always false in the demo (§13.7)

func subtitle() -> String:
    return "%s %s" % [rarity_name(), type_name()]

func rarity_name() -> String:
    return ["Common", "Uncommon", "Magic", "Rare"][rarity]

func type_name() -> String:
    if kind == Kind.WEAPON and weapon_type != &"":
        return String(weapon_type).capitalize()
    return ["Weapon", "Potion", "Relic"][kind]
```

**Note the `"roll"` key.** v1 stored only the formatted `label`, which meant the numeric magnitude was unrecoverable. v2's modifiers have gameplay effects (§13.5), so the raw roll must be stored alongside the label.

### 4.3 `EncounterDef` / `LevelDef`

```gdscript
class_name EncounterDef
extends Resource

enum Type { COMBAT, LOOT, SHOP }

@export var type: Type = Type.COMBAT
@export var is_boss: bool = false
@export var enemy_stat_ids: Array[StringName] = []  # COMBAT only, 1–3 entries
@export var loot_item_count: int = 0                # LOOT only
@export var shop_item_count: int = 3                # SHOP only
@export var travel_duration: float = 2.5            # seconds of scrolling before this encounter
```

```gdscript
class_name LevelDef
extends Resource

@export var display_name: String = "The Whispering Wood"
@export var encounters: Array[EncounterDef] = []
```

### 4.4 `GameState` (autoload)

```gdscript
extends Node

var gold: int = 0
var inventory: Array[Item] = []
var hero_runtime: Array = []       # [{stats_id, current_hp, max_hp, alive}, ...]
var current_encounter_index: int = -1
var level: LevelDef
var run_stats := {
    "encounters_cleared": 0,
    "gold_earned": 0,
    "gold_spent": 0,          # [new] — upgrades + shop, for the summary
    "damage_dealt": 0,
    "damage_taken": 0,
    "slot_spins": 0,
    "slot_wins": 0,
    "items_found": 0,
    "items_sold": 0,
    "upgrades_bought": 0,     # [new]
    "run_time": 0.0,
}

func add_gold(amount: int) -> void       # emits gold_changed, tracks gold_earned
func spend_gold(amount: int) -> bool     # false and no change if insufficient; tracks gold_spent
func add_item(item: Item) -> void        # emits item_added AND party_bonuses_changed
func remove_item(item: Item) -> void     # emits item_removed AND party_bonuses_changed
func sellable_items() -> Array[Item]     # inventory.filter(func(i): return not i.equipped)
func party_bonuses() -> Dictionary       # §13.5 — aggregate of every inventory modifier
func build_level() -> LevelDef           # §12.1 — the ONLY definition of the demo level
func reset_run() -> void                 # full reset: §18.3
```

**Hero HP persists across encounters.** There is no between-encounter heal. Healing comes only from the priest and the slot. This is deliberate — it makes the slot's plus payouts matter.

---

## 5. Tuning — single source of truth

Everything below lives in `res://scripts/autoload/tuning.gd` as `const`. **No other file may hardcode these numbers.** Values that changed from v1 are marked **[v2]**.

### 5.1 Timing

```gdscript
const TRAVEL_SPEED := 4.0                 # world units/sec at full scroll speed
const TRAVEL_ACCEL_TIME := 0.6
const TRAVEL_DECEL_TIME := 0.9
const ENEMY_FADE_IN_TIME := 0.35
const ENEMY_DEATH_HOLD := 1.5
const ENEMY_DEATH_FADE := 2.0
const BARS_POP_IN_TIME := 0.25
const COOLDOWN_START_FRACTION := 0.5      # every combatant starts half-charged
const COOLDOWN_START_JITTER := 0.10       # ±10%, de-syncs identical enemies (§21-D2)
const HURT_ANIM_TIME := 0.30
const DEAD_HERO_EXIT_TIME := 1.6
const ENCOUNTER_RESOLVE_PAUSE := 0.8
const AOE_STAGGER := 0.06                 # [v2] gap between per-target resolutions of any AoE
const DAMAGE_NUMBER_SPREAD := 46.0        # [v2] px offset per concurrent number, §11.4
```

### 5.2 Combatant stats

**Q8 answered — the behaviour is ratified and the table is corrected.**

The initial vision says: *"after their attack finishes, their cooldown bar would fill to 100% and drain as the cooldown completes."* So `attack_cooldown` is **recovery after an action ends**, not the interval between actions. The code implements that correctly. What was wrong was v1's stat table, which presented `attack_cooldown` as if it were the whole cycle — so the priest looked like a 2.0 s attacker when its real cycle is 2.95 s.

Two consequences, both now fixed:

- **The `real cycle` column below is authoritative for balance discussion.** `attack_cooldown` is a component of it, not the whole of it.
- **Stop decrementing `cooldown_remaining` while `state == ATTACKING`.** v1 decremented it and then overwrote it on animation finish, so the decrement was discarded — dead code that made the loop read as if the cooldown ran during the attack. Skip combatants in `ATTACKING` in the tick loop. The bar already reads 0 during an attack (§11.3), which now matches the model exactly.

The numbers are **not** retuned. The observed pacing across a full verified run is good, and changing six cooldowns on paper without playtest data would trade a working fight for a table that looks tidier. Re-tuning is a post-demo task (§22) and now has real numbers to work from.

| id | display_name | hero | max_hp | base_damage | `attack_cooldown` | attack len | **real cycle** | special_every_n | special len | model_scale |
|---|---|---|---|---|---|---|---|---|---|---|
| `warrior` | Warrior | yes | 120 | 12 | 1.6 | 0.70 | **2.30** | 3 | 0.55 | 1.00 |
| `ranger` | Ranger | yes | 80 | 14 | 1.4 | 0.80 | **2.20** | 4 | 0.80 | 0.95 |
| `priest` | Priest | yes | 70 | 10 | 2.0 | 0.95 | **2.95** | 3 | 0.85 | 0.95 |
| `shadow_monster` | Shadow Monster | no | 40 | 8 | 1.8 | 0.60 | **2.40** | 0 | — | 0.90 |
| `orc_barbarian` | Orc Barbarian | no | 70 | 15 | 2.4 | 0.85 | **3.25** | 0 | — | 1.15 |
| `orc_warlord` | Orc Warlord | no | 280 | 22 | 2.0 | 0.98 | **2.98** | 0 | — | 1.70 |

The warlord's attack length is 0.85 ÷ 0.87 = 0.98 s, because it plays at `speed_scale = 0.87` (§8.7).

### 5.3 Ability tuning

```gdscript
const WARRIOR_DEFEND_REDUCTION := 0.50    # incoming damage × (1 - 0.50)
const WARRIOR_DEFEND_DURATION := 4.0
const RANGER_BOMB_AOE_MULT := 0.75
const PRIEST_HEAL_MULT := 1.0
const PRIEST_DARKEN_ENABLED := true
const DAMAGE_VARIANCE := 0.15             # every hit rolls × randf_range(0.85, 1.15)
const SPECIAL_CAST_FLASH_TIME := 0.15     # [v2] §9.6
```

### 5.3b Battlefield geometry

```gdscript
const HERO_SLOT_X := [-4.2, -3.0, -1.8]   # priest, ranger, warrior (left → right)
const ENEMY_X_MIN := 1.6
const ENEMY_X_MAX := 4.8
const MAX_ENEMIES := 3
```

### 5.4 Economy **[v2 — Q23]**

```gdscript
const STARTING_GOLD := 75                 # [v2] was 50
const SHOP_BUY_MARKUP := 1.5              # buy price  = round(value × 1.5)
const SHOP_SELL_RATE := 0.5               # sell price = round(value × 0.5)
const LOOT_ITEMS_PER_CHEST := 2
const SHOP_ITEMS_FOR_SALE := 3
```

**Q23 answered — raise supply, leave prices alone.** Measured over 200 generated items, buy prices run 27 / 62 / 582 (min / median / max), which is a healthy spread. The failure was on the other side: observed gold on hand at the encounter-3 shop was **50–100**, against v1's predicted 150–260, and two of three observed runs bought nothing.

Gold comes only from slot GOLD payouts, so the fix is there:

| Constant | v1 | v2 |
|---|---|---|
| `STARTING_GOLD` | 50 | **75** |
| `SLOT_PAY_2_GOLD` | 25 | **35** |
| `SLOT_PAY_3_GOLD` | 50 | **90** |

Expected gold per spin = `0.14937 × 35 + 0.01743 × 90` = **6.80**. Across the ~14 spins of encounters 0 and 2 that is ~95 gold; plus 75 starting and ~40 from selling the two chest items, the party reaches the shop with roughly **210 gold** — inside v1's predicted band, and enough to buy the median card with change. Across a full six-encounter run the slot pays roughly 300 gold.

The prices are untouched because upgrades (§17.6) now compete for the same gold, and the tension between *buy an item*, *sell an item*, and *buy an upgrade* is the loop. `test_economy.gd` (§19.3) asserts the gold curve.

### 5.5 Slot machine

```gdscript
enum Sym { LIGHTNING, GOLD, PLUS, BLANK }

const SLOT_REEL_STOPS := 27
const SLOT_STRIP: Array[int] = [ ... ]    # see §16.2 — 27 entries, 7/7/7/6. DO NOT CHANGE.
const SLOT_SPIN_DURATION := 1.10          # reel 0 stop time
const SLOT_REEL_STAGGER := 0.28           # reel 1 stops +0.28s, reel 2 stops +0.56s
const SLOT_RESULT_HOLD := 0.85            # pause after reel 2 stops before the next spin
const SLOT_PAY_2_GOLD := 35               # [v2]
const SLOT_PAY_3_GOLD := 90               # [v2]
const SLOT_HEAL_2_FRACTION := 0.25        # lowest-hp hero healed 25% of max
const SLOT_HEAL_3_FRACTION := 0.25        # entire party healed 25% of max
const SLOT_LIGHTNING_2_MULT := 1.0
const SLOT_LIGHTNING_3_MULT := 2.0
const SLOT_LIGHTNING_FALLBACK := 12       # used if no hero strike is recorded yet
const SLOT_ATTRACT_SPEED := 0.15          # [v2] fraction of spin speed in attract mode, §16.6
const SLOT_ATTRACT_DIM := Color(0.78, 0.78, 0.82)   # [v2] was Color(0.55, 0.55, 0.62)
```

### 5.6 Party damage button

```gdscript
const PARTY_DAMAGE_BUFF_MULT := 1.10      # +10%
const PARTY_DAMAGE_BUFF_DURATION := 30.0
```

### 5.7 Upgrades **[v2 — §17.6]**

```gdscript
const UPGRADE_MAX_LEVEL := 3
const UPGRADE_COST_GROWTH := 1.9          # cost(n) = round(base × 1.9^(n-1))

const UPGRADE_QUICK_REELS_BASE := 60
const UPGRADE_QUICK_REELS_STEP := 0.86    # spin-cycle multiplier per level (compounding)

const UPGRADE_OVERCHARGE_BASE := 70
const UPGRADE_OVERCHARGE_STEP := 0.25     # +25% lightning damage per level (additive)

const UPGRADE_FAT_PURSE_BASE := 50
const UPGRADE_FAT_PURSE_STEP := 0.40      # +40% gold per level (additive)
```

---

## 6. Art direction

### 6.1 Palette (use these hex values literally)

| Role | Hex | Notes |
|---|---|---|
| Sky | `#7EC8E3` | also the viewport clear colour |
| Far hills | `#4A9E6F` | parallax layer 1 |
| Mid trees | `#2E8B57` | parallax layer 2 |
| Near trees | `#1E6B45` | parallax layer 3 |
| Ground | `#8FBF4F` | parallax layer 4 |
| Foreground brush | `#14532D` | parallax layer 5, in front of characters |
| Outline / ink | `#0F0E14` | inverted-hull outline colour, everywhere |
| Warrior armour | `#4A6FA5` | steel blue |
| Warrior accent | `#D9333F` | tabard red |
| Ranger leather | `#3E7A4E` | |
| Ranger accent | `#8B5A2B` | |
| Priest cloth | `#F5F0E6` | |
| Priest accent | `#3B6FD4` | |
| Orc skin | `#6FA83E` | |
| Orc iron | `#8C94A3` | |
| Shadow body | `#14121A` | |
| Shadow eyes | `#FF2D2D` | emissive, strength 3.0 |
| Gold / UI trim | `#F2C230` | coins, dividers, slot cabinet trim |
| Danger red | `#E03131` | health bar fill, damage numbers |
| Heal green | `#2FBF4F` | heal plus, heal numbers |
| Lightning blue | `#3B82F6` | bolt symbol, lightning VFX |
| Defend blue | `#3B6FD4` | defend shield icon background |
| Fire orange | `#FF7A1A` | **[v2]** fire-modifier damage numbers |
| Ice cyan | `#5BC8F5` | **[v2]** ice-modifier damage numbers |
| Fish scale | `#4A9BE8` | **[v2]** Sir Fish body |
| Fish fin | `#3B6FD4` | **[v2]** Sir Fish fins |
| Console bg | `#231F2E` | |
| Console panel | `#332C42` | |
| Panel border | `#4A4260` | |
| Text primary | `#FFF6E0` | |
| Text dim | `#9B93AE` | |

**Do not desaturate.** If a colour needs to recede, shift it toward the sky blue, not toward grey.

### 6.2 Cel shader — `res://assets/shaders/cel_shade.gdshader`

Unchanged from v1. Write exactly this:

```glsl
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float band_count : hint_range(2.0, 5.0, 1.0) = 3.0;
uniform vec4 shadow_tint : source_color = vec4(0.45, 0.52, 0.78, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength : hint_range(0.0, 6.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
    ALBEDO = albedo.rgb;
    ALPHA = alpha;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    EMISSION = emission_color.rgb * emission_strength;
}

void light() {
    float ndotl = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
    float steps = max(band_count - 1.0, 1.0);
    float banded = round(ndotl * steps) / steps;
    vec3 shaded = mix(ALBEDO * shadow_tint.rgb, ALBEDO, banded);
    DIFFUSE_LIGHT += shaded * LIGHT_COLOR * ATTENUATION / PI;

    float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    rim = smoothstep(1.0 - rim_amount, 1.0, rim) * banded;
    SPECULAR_LIGHT += rim_color.rgb * rim * 0.5;
}
```

One always-transparent variant is used everywhere (`blend_mix` in the render mode above). The scene has under 40 meshes, so the sorting cost is irrelevant, and a single material path removes the swap-on-fade complexity v1 hedged about.

### 6.3 Outline shader — `res://assets/shaders/outline.gdshader` **[v2 — Q16]**

**Q16 answered — give the outline a real alpha.** v1's outline was `unshaded` with no alpha, so `CelMaterials.set_alpha()` faked a fade by shrinking `outline_width` proportionally. That does not read as a fade; it reads as the model shrinking inside its own ink while a solid silhouette hangs in the air. Enemies fade in at every combat start and out at every death, so this is visible constantly.

```glsl
shader_type spatial;
render_mode cull_front, depth_draw_opaque, unshaded, blend_mix;

uniform vec4 outline_color : source_color = vec4(0.059, 0.055, 0.078, 1.0);
uniform float outline_width : hint_range(0.0, 0.2) = 0.018;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void vertex() {
    VERTEX += normalize(NORMAL) * outline_width;
}

void fragment() {
    ALBEDO = outline_color.rgb;
    ALPHA = outline_color.a * alpha;
}
```

Attach via `material.next_pass = outline_material` on every character and prop material. Because the camera is orthographic, a constant world-space width gives a constant screen-space width — no distance compensation.

`CelMaterials.set_alpha(node, a)` now sets the `alpha` uniform on **both** the cel material and its `next_pass` outline material, and **`outline_width` is never touched at runtime**.

`CelMaterials.flash()` keeps v1's fix: the base colour is remembered once via `set_meta("base_albedo")` on first use, never re-read from the live albedo. Reading the live albedo let two overlapping flashes latch white in permanently.

### 6.4 Lighting and environment

`BattleWorld` contains:

- `WorldEnvironment` with a new `Environment`:
  - `background_mode = BG_COLOR`, `background_color = #7EC8E3`
  - `ambient_light_source = AMBIENT_SOURCE_COLOR`, `ambient_light_color = #A8D8E8`, `ambient_light_energy = 0.55`
  - `tonemap_mode = TONE_MAPPER_LINEAR` — do **not** use filmic/ACES, it desaturates the primaries
  - `glow_enabled = true`, `glow_intensity = 0.5`, `glow_bloom = 0.15`, `glow_hdr_threshold = 1.1`
  - `adjustment_enabled = true`, `adjustment_saturation = 1.15`
- `DirectionalLight3D` `KeyLight`: rotation `(-40°, -35°, 0°)`, energy `1.4`, colour `#FFF3D6`, `shadow_enabled = true`, `directional_shadow_mode = SHADOW_ORTHOGONAL`, `shadow_bias = 0.03`
- `DirectionalLight3D` `FillLight`: rotation `(-20°, 145°, 0°)`, energy `0.35`, colour `#9BC8F5`, `shadow_enabled = false`

### 6.5 Typography **[v2 — Q20]**

**Q20 answered — embolden the built-in font with a `FontVariation`. Ship no files.**

The no-third-party-assets rule (§0.1.2) is about *assets*, and a font file is an asset — the rule holds. But Godot's built-in default font is part of the engine, not a third-party asset, and Godot can synthesise a heavier face from it at runtime with **`FontVariation`**, which ships nothing. That is the answer to "the default font is a small, thin sans that was never designed to carry an 84 px DEFEATED".

Create `res://assets/display_font.tres` — a `FontVariation` with:

- `variation_embolden = 0.35`
- `variation_transform = Transform2D(1.06, 0, 0, 1.0, 0, 0)` — 6% wider, for weight without smearing
- `spacing_glyph = 2`
- `base_font` left **empty**, so it resolves to the theme's default font.

If the editor refuses an empty `base_font`, assign `ThemeDB.fallback_font` in a one-line `_ready()` on `Main` and record it in §21. If `FontVariation` will not resolve at all in this build, fall back to outline-plus-shadow only and record that too — but try the variation first and confirm it in a screenshot.

Project-wide `Theme` at `res://assets/theme.tres`, assigned once to `Main.theme` (§3.3):

- `default_font_size = 34`
- `Label/colors/font_color = #FFF6E0`
- `Button` StyleBoxFlat: `bg_color = #4A6FA5`, `corner_radius_* = 16`, `border_width_* = 4`, `border_color = #F2C230`, content margins 24/24/18/18
- `Button:disabled` StyleBoxFlat: `bg_color = #3A3548`, `border_color = #5C5470`, font colour `#7A7290`
- `PanelContainer` StyleBoxFlat: `bg_color = #332C42`, `corner_radius_* = 20`, `border_width_* = 3`, `border_color = #4A4260`
- **Type variation `DisplayLabel`** (base type `Label`): `font = res://assets/display_font.tres`, `font_outline_size = 6`, `font_outline_color = #0F0E14`

**Every string at font size 40 or above must use `theme_type_variation = &"DisplayLabel"`.** That is: the run-summary title, the slot win banner, damage numbers, the gold readout, shop prices, shop card names, and the upgrade button titles. Body text and stat rows keep the plain default font.

---

## 7. The battlefield

### 7.1 `battle_world.tscn`

```
BattleWorld (Node3D)
├── WorldEnvironment
├── KeyLight (DirectionalLight3D)
├── FillLight (DirectionalLight3D)
├── BattleCamera (Camera3D)
├── ParallaxBackground (Node3D)     # parallax_background.tscn
├── HeroSlots (Node3D)
│   ├── Slot0 (Marker3D)  position (-4.2, 0, 0)   # Priest   (leftmost)
│   ├── Slot1 (Marker3D)  position (-3.0, 0, 0)   # Ranger
│   └── Slot2 (Marker3D)  position (-1.8, 0, 0)   # Warrior  (front line)
├── EnemyRoot (Node3D)
├── PropRoot (Node3D)
└── ProjectileRoot (Node3D)
```

**Hero order is fixed left-to-right: Priest, Ranger, Warrior.** This places the warrior closest to the enemies, which reads correctly as a front line.

### 7.2 `BattleCamera` (Camera3D)

| Property | Value |
|---|---|
| `projection` | `PROJECTION_ORTHOGONAL` |
| `size` | `6.5` (vertical extent in world units) |
| `near` / `far` | `0.05` / `200.0` |
| `position` | `(0.0, 2.2, 12.0)` |
| `rotation` | `(0, 0, 0)` — dead-on side view, no tilt |

Derived and relied on elsewhere: viewport aspect = 1080/640 = **1.6875**, horizontal extent = 6.5 × 1.6875 = **10.97 units**, half-width **±5.48**. Visible vertical range **y ∈ [-1.05, 5.45]**. Ground plane is `y = 0`. A 1.0-scale character is **1.8 units tall**.

**The camera stays dead-on.** Q2 offered an angled camera as an alternative to re-authoring the animation keys; it is rejected. A tilt would break the 1:1 `unproject_position` → `BattleOverlay` mapping that the bars depend on (§11.1), and it would put the parallax layers into perspective disagreement with their fake-parallax scroll speeds. The animations move to the Z axis instead (§9.0).

No camera shake except where §9 and §11.4 specify it.

### 7.3 Enemy slot placement

```gdscript
func enemy_slot_x(index: int, total: int) -> float:
    if total <= 1:
        return (Tuning.ENEMY_X_MIN + Tuning.ENEMY_X_MAX) * 0.5     # 3.2
    return Tuning.ENEMY_X_MIN \
        + (Tuning.ENEMY_X_MAX - Tuning.ENEMY_X_MIN) * (float(index) / float(total - 1))
```

Verified against §7.2: the rightmost enemy at `x = 4.8` plus a ~0.4 half-width sits at 5.2, inside ±5.48; the leftmost hero at `x = -4.2` sits at -4.6, also inside. The 1.70× warlord has a ~0.7 half-width, so at the `total == 2` right-hand position of 4.8 it would reach 5.5 and clip — **list `orc_warlord` first in `enemy_stat_ids`**, which puts it at index 0, `x = 1.6`, well inside frame.

Enemies face **−X**; heroes face **+X**. Facing is `rotation.y = PI` on the enemy `Combatant` node. **Never use negative scale** — it inverts the normals the inverted-hull outline depends on.

### 7.4 Parallax background

Orthographic projection gives no free parallax, so it is faked by scroll speed. Five layers, each a `Node3D` holding **three** copies of a tile that wrap.

| Layer | Node name | Z | Speed multiplier | Content (placeholder → M8 final) |
|---|---|---|---|---|
| 1 | `LayerHills` | -14 | 0.10 | wide low `#4A9E6F` quad with a rolling silhouette → sculpted hill mesh |
| 2 | `LayerFarTrees` | -9 | 0.28 | `#2E8B57` triangle-cluster quads → low-poly conifers |
| 3 | `LayerNearTrees` | -5 | 0.55 | `#1E6B45` bigger triangles → detailed trees |
| 4 | `LayerGround` | 0 | 1.00 | `#8FBF4F` ground plane w/ darker stripe bands → tiled ground + rocks |
| 5 | `LayerBrush` | +3 | 1.35 | `#14532D` bush silhouettes, in front of characters → grass/bush meshes |

```gdscript
@export var tile_width: float = 12.0
var scroll_speed: float = 0.0            # 0 = stopped; RunController tweens this

func _process(delta: float) -> void:
    if is_zero_approx(scroll_speed):
        return
    for layer: Node3D in _layers:
        var mult: float = layer.get_meta("speed_mult")
        for tile: Node3D in layer.get_children():
            tile.position.x -= scroll_speed * mult * delta
            if tile.position.x <= -tile_width:
                tile.position.x += tile_width * 3.0
```

Do not name any parameter `scale` in this file — it shadows `Node3D.scale`.

`RunController` starts travel by tweening `scroll_speed` `0 → Tuning.TRAVEL_SPEED` over `TRAVEL_ACCEL_TIME` with `TRANS_SINE/EASE_OUT`, and stops it by tweening back to `0` over `TRAVEL_DECEL_TIME` with `TRANS_CUBIC/EASE_OUT`.

---

## 8. Combatants

### 8.1 `combatant.tscn` / `combatant.gd`

```
Combatant (Node3D)                       # combatant.gd
├── Visual (Node3D)                      # squash/stretch and body lean applied here
│   ├── Rig (Node3D)                     # model_scale applied here (§8.2)
│   │                                    # M8: replaced by the imported Skeleton3D
│   └── AnimationPlayer                  # root_node = ".." (i.e. Visual)
├── BarAnchor (Marker3D)                 # position (0, 2.05, 0) × model_scale
├── HandAnchor (Marker3D)                # weapon/projectile spawn point × model_scale
├── HitAnchor (Marker3D)                 # position (0, 0.9, 0) × model_scale
└── AbilityTimer (Timer)                 # impact delays only, never cooldown
```

```gdscript
class_name Combatant
extends Node3D

enum State { IDLE, RUNNING, ATTACKING, HURT, DEAD }

signal died(c: Combatant)

@export var stats: CombatantStats        # per-character scenes preload their .tres (§0.1.1)

var current_hp: int
var max_hp: int
var state: State = State.IDLE
var cooldown_remaining: float = 0.0
var action_count: int = 0
var special_pending: bool = false         # [v2] §10.2, Q9
var damage_multiplier: float = 1.0        # party damage buff + item bonuses
var damage_reduction: float = 0.0         # warrior defend
var bonus_flat_damage: int = 0            # [v2] item dmg_flat + elemental, §13.5
var is_hero: bool

func setup(s: CombatantStats, starting_hp: int = -1) -> void
func tick(delta: float) -> void           # called by BattleDirector, NOT _process
func take_damage(amount: int, source: Combatant) -> void
func heal(amount: int) -> void
func is_alive() -> bool
func play_anim(name: StringName) -> void
func set_running(running: bool) -> void
func cancel_all_effects() -> void         # [v2] §8.5 — called on death
```

**Combatants do not run their own clocks.** `BattleDirector` calls `tick(delta)` on every living combatant each frame, in a fixed order (heroes left-to-right, then enemies left-to-right). Combat is deterministic given a seed and trivially pausable.

### 8.2 Placeholder rigs (through M7) **[Q4]**

**Q4 answered — `model_scale` goes on `Rig.scale`, not `Visual.scale`.** The squash/stretch tracks in §9.4 and §9.5 key `Visual.scale` absolutely, so with `model_scale` also on `Visual.scale` the first frame of an orc's attack would wipe its 1.15× scale and the 1.70× warlord would snap to human size mid-swing. Putting `model_scale` on `Rig.scale` leaves `Visual.scale` free for animation, and it survives M8 unchanged because the imported `Skeleton3D` replaces `Rig` in place.

The alternative — authoring squash/stretch as multipliers of `model_scale` — is rejected: it needs per-character clips and breaks the shared-clip design that M8's export plan depends on.

`BarAnchor` / `HitAnchor` / `HandAnchor` are positioned at `spec_position × model_scale`, unchanged.

Build `Rig` from Godot primitives via `add_mesh_instance`, as **named child nodes** with these exact names, because M8 swaps meshes while keeping animation tracks pointed at the same node paths:

`Root, Torso, Head, ArmL, ArmR, LegL, LegR, WeaponMain, WeaponOff`

| Part | Mesh | Size | Local position |
|---|---|---|---|
| `Torso` | CapsuleMesh | radius 0.28, height 0.85 | (0, 1.00, 0) |
| `Head` | SphereMesh | radius 0.22 | (0, 1.62, 0) |
| `ArmL` | CapsuleMesh | radius 0.09, height 0.55 | (-0.34, 1.38, 0.12) |
| `ArmR` | CapsuleMesh | radius 0.09, height 0.55 | (0.34, 1.38, 0.12) |
| `LegL` | CapsuleMesh | radius 0.11, height 0.60 | (-0.14, 0.32, 0) |
| `LegR` | CapsuleMesh | radius 0.11, height 0.60 | (0.14, 0.32, 0) |
| `WeaponMain` | per character | — | child of `ArmR`, offset (0, -0.32, 0.10) |
| `WeaponOff` | per character | — | child of `ArmL`, offset (0, -0.32, 0.10) |

Arm nodes sit at the shoulder (y 1.38) and the capsule hangs downward from there, so an arm rotation about Z pivots at the shoulder. This matters for §9.0's sign convention.

Per-character weapon placeholders:

- **Warrior** `WeaponMain`: `BoxMesh(0.07, 0.90, 0.14)` steel `#8C94A3` with a `#F2C230` crossguard box `(0.24, 0.07, 0.16)`. `WeaponOff`: `CylinderMesh(r 0.30, h 0.06)` `#4A6FA5` with a `#F2C230` rim.
- **Ranger** `WeaponMain`: `TorusMesh(inner 0.34, outer 0.40)` `#8B5A2B` rotated 90° about Y to read as a bow limb arc. `WeaponOff`: none.
- **Priest** `WeaponMain`: `CylinderMesh(r 0.045, h 1.30)` `#8B5A2B` topped with a `SphereMesh(r 0.13)` `#3B6FD4`, emission strength `1.5`.
- **Orc** `WeaponMain`: `BoxMesh(0.06, 1.05, 0.12)` haft `#6B4423` with a `BoxMesh(0.34, 0.30, 0.10)` head `#8C94A3` at the top.
- **Warlord**: identical to the orc plus a pair of `#F2C230` shoulder-pad boxes `(0.30, 0.14, 0.30)` on `Torso` at `(±0.34, 1.42, 0)`, so it silhouettes differently at a glance.
- **Shadow monster**: **no separate limbs.** Replace the whole rig with a single `SphereMesh(r 0.55)` at `(0, 1.0, 0)` using `smoke.gdshader` (§8.6), plus two `SphereMesh(r 0.055)` eyes at `(±0.16, 1.18, 0.44)` in `#FF2D2D`, emission strength `3.0`, plus the `SmokeWisps` emitter.

### 8.3 Animation set — mandatory names **[Q5]**

**Q5 answered — the required set is derived from data, not from a universal list.**

v1 contradicted itself: "Every combatant's AnimationPlayer must expose these exact animation names. Missing ones are a build failure," followed by a table qualifying `run` as heroes-only and `special` as warrior/ranger/priest-only. The implementer read the table, which was right — but that left "build failure" unenforceable, and it left M8's export validation with no fixed list to check.

Both problems are solved by `CombatantStats.required_anims()` (§4.1), which derives the set from `is_hero` and `special_every_n_actions`. Nothing new is authored, there is no second source of truth, and the check is now real:

```gdscript
# In Combatant.setup(), after the AnimationPlayer is populated:
for n: StringName in stats.required_anims():
    assert(anim_player.has_animation(n),
        "%s is missing required animation '%s'" % [stats.id, n])
```

Stub clips are **not** created for enemies. Authoring six dead Blender actions across three enemies to satisfy a list nothing reads is pure M8 cost. `play_anim()` still no-ops on an unknown name, so a mistake degrades instead of crashing.

| Name | Who | Length | Loop | Description |
|---|---|---|---|---|
| `idle` | all | 1.60 | yes | slow weave, combat stance, weapon raised |
| `run` | `is_hero` | 0.70 | yes | legs alternate, arms counter-pump, bob, forward lean |
| `attack` | all | per §9 | no | per-character |
| `special` | `special_every_n_actions > 0` | per §9 | no | per-character |
| `hurt` | all | 0.30 | no | recoil |
| `die` | all | 0.80 | no | topple, **holds the final pose** |

Author with `create_animation` + `add_animation_track` + `set_animation_keyframe`. Every animation sets `loop_mode` explicitly. `die` must not loop and must not reset.

### 8.4 Damage, defense, variance **[v2 — item bonuses]**

```gdscript
func compute_damage(attacker: Combatant) -> int:
    var raw := (float(attacker.stats.base_damage) + float(attacker.bonus_flat_damage)) \
        * attacker.damage_multiplier
    raw *= randf_range(1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE)
    return maxi(1, int(round(raw)))

# in take_damage:
var final := maxi(1, int(round(float(amount) * (1.0 - damage_reduction))))
```

Damage is always at least 1. `damage_reduction` is clamped to `[0.0, 0.9]`.

`bonus_flat_damage` and `damage_multiplier` are refreshed from `GameState.party_bonuses()` on `party_bonuses_changed` and at combat start (§13.5). The party damage buff multiplies into `damage_multiplier` on top.

### 8.5 State rules **[v2 — Q15]**

- A combatant in `HURT` still accumulates cooldown. Being hit never interrupts an attack already started; the `hurt` animation is skipped if `state == ATTACKING` — play a 0.08 s white `#FFFFFF` flash on the meshes instead, so the hit still reads.
- A combatant in `DEAD` cannot be targeted, cannot act, cannot be healed, and stops ticking. Remove it from the director's living lists **immediately** on death so no in-flight logic can pick it.
- On death, call `cancel_all_effects()`, which must:
  1. Cancel any in-progress attack and any scheduled impact call.
  2. Set `damage_reduction = 0.0` and kill the defend `SceneTreeTimer`.
  3. **Free every status icon this combatant owns**, without waiting for its fade-out.
  4. Free the combatant's bars (fade over 0.25 s).
- If a projectile is already in flight when its owner dies, it survives and resolves per §9.2.

**Q15 answered — cancel the icon.** v1 let the warrior's defend shield play out its full 4 seconds over a corpse, because nothing cancelled it on death. A defence buff icon hovering above a dead body is a legibility failure (pillar 1) and reads as a bug. Every status icon registers its owner and is freed in `cancel_all_effects()`.

### 8.6 Shadow monster smoke

`res://assets/shaders/smoke.gdshader`:

```glsl
shader_type spatial;
render_mode blend_mix, cull_back, unshaded, depth_draw_never;

uniform vec4 smoke_color : source_color = vec4(0.078, 0.071, 0.102, 1.0);
uniform float speed = 0.35;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.55;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453); }

void fragment() {
    float f = fract(hash(floor(NORMAL * 9.0)) + TIME * speed);
    float wobble = 0.75 + 0.25 * sin(TIME * 2.1 + f * 6.28);
    float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
    ALBEDO = smoke_color.rgb;
    ALPHA = clamp(wobble * (1.0 - fres * edge_softness), 0.15, 0.95) * alpha;
}
```

The `alpha` uniform is new in v2 so the shadow monster fades in and out on the same code path as everyone else.

Plus `GPUParticles3D` `SmokeWisps`: amount 24, lifetime 1.4, `ParticleProcessMaterial` with emission sphere radius 0.5, `direction (0,1,0)`, spread 35°, `initial_velocity 0.3–0.7`, `gravity (0,0.4,0)`, `scale 0.10 → 0.0` over life, colour ramp `#14121A` alpha 0.7 → 0.0. Draw pass: `SphereMesh(r 0.5)`.

### 8.7 Animation speed and the warlord **[Q6]**

**Q6 answered — the warlord plays slower, and the impact-drift trap is removed.**

`AnimationPlayer.speed_scale = 1.0 / 1.15 ≈ 0.87` for the warlord, so its clips take 1.15× longer in wall-clock time. "Heavier" is the stated intent and slower is what reads as heavy; `speed_scale = 1.15` would make the biggest thing on the battlefield the twitchiest.

The implementer correctly flagged the trap: at 0.87 speed the warlord's impact lands ~63 ms later than its `impact_delay` constant claims. v2 removes the trap rather than documenting it — **impacts are scheduled by a method-call track in the `AnimationPlayer`, never by a `SceneTreeTimer`** (§10.2 step 5). A call track is a position in the animation, so it scales with `speed_scale` automatically and the visual and the number can never drift. v1 listed the timer as an acceptable alternative; v2 forbids it.

---

## 9. Abilities (exact specifications)

### 9.0 Authoring conventions — read this before writing a single key **[Q2, Q3]**

**Q3 answered — one clip set, forward = local +X.** Every clip for every character is authored in a single space where **forward (toward the opponent) is local +X**. Heroes are unrotated. Enemies carry `rotation.y = PI` on the `Combatant` node, which flips their local +X to world −X. One authored animation therefore reads correctly for both sides, and M8 exports one action set per character instead of two.

This means **enemy X translations carry the opposite sign from v1's text.** v1 wrote the shadow monster's lunge as `Visual.position.x → -0.22 (toward heroes)`, which is only toward the heroes for an unrotated body; applied under `rotation.y = PI` it lunges backwards. The same bug was in the orc's swing. Every X translation below is written in the shared forward-is-+X space, so all of them are positive when moving toward the opponent. The alternative — separate hero and enemy clip sets — doubles M8's animation work for no gain and is rejected.

**Q2 answered — limb and body rotations are on Z, and every sign below has been re-derived.**

v1 wrote every limb key on `rotation.x`. With §7.2's dead-on side camera, an X-axis limb rotation swings the limb toward and away from the lens, where it is almost entirely foreshortened — the warrior's sword wind-up would read as the arm barely moving. Screen-plane motion is rotation about **Z**.

The implementer moved the keys to Z with v1's magnitudes intact. That was the right axis, but re-using v1's signs unexamined is not safe, because **the sign that means "forward" differs between a limb and a torso**:

> With a character facing screen-right, **positive Z rotation is counter-clockwise on screen**. A limb hangs *downward* from its pivot, so positive Z swings its tip **forward and up-in-front**. A torso rises *upward* from its pivot at the feet, so positive Z tips the head **backward**.

Author by physical intent and take the sign from the rule. Every key in §9.1–9.5 below has been worked out that way and includes a plain-language "reads as" note; **use these, not v1's, and not the current code's.** §21 lists the specific lines that change.

Each ability declares an `impact_delay` — the offset from animation start at which damage or healing is applied, scheduled as a method-call track (§8.7).

### 9.1 Warrior

**Primary — Sword Swing** (`attack`, length 0.70, impact_delay 0.30)

| Window | Keys | Reads as |
|---|---|---|
| 0.00 → 0.18 | `ArmR.rotation.z` → **−110°**; `Visual.rotation.z` → **+8°** | sword goes back and over the shoulder, torso coils back |
| 0.18 → 0.34 | `ArmR.rotation.z` → **+55°**; `Visual.rotation.z` → **−10°**; `Visual.position.x` → **+0.14** | sword drives forward and down, torso leans into it, half a step in |
| 0.34 → 0.70 | all → neutral | recover |

On impact (0.30): deal damage; spawn a **slash VFX** — a white `#FFF6E0` arc quad at the target's `HitAnchor`, scale 0 → 1.4, alpha 1 → 0 over 0.22 s.

**Special — Defend** (`special`, length 0.55, impact_delay 0.25)

| Window | Keys | Reads as |
|---|---|---|
| 0.00 → 0.25 | `ArmL.rotation.z` → **+75°**; `ArmL.position.z` → **+0.20**; `Visual.rotation.y` → **−12°** | shield comes up **in front**, toward the enemy, and turns its face to the camera |
| 0.25 → 0.45 | hold | braced |
| 0.45 → 0.55 | → neutral | lower |

v1 wrote `ArmL.rotation.x → -75°`; under the Z convention a negative value raises the shield *behind* the warrior. **+75° is correct** and the implementer's flip is ratified.

At impact: set `damage_reduction = Tuning.WARRIOR_DEFEND_REDUCTION` for `WARRIOR_DEFEND_DURATION` seconds via a `SceneTreeTimer`. Re-application **refreshes** the duration, it does not stack. The timer is cancelled on death (§8.5).

**Extra VFX:** spawn a `status_icon` in `BattleOverlay/VfxLayer` over the warrior — a blue circle (`#3B6FD4`, radius 46 px) containing a white shield glyph (§17.5). Fade in over 0.15 s, pulse scale 1.0 → 1.12 → 1.0 on a 1.0 s period, remain for the whole buff, fade out over 0.25 s. **Freed immediately if the warrior dies.**

The defend action deals **no damage**. It replaces that action entirely.

### 9.2 Ranger

**Primary — Shoot Arrow** (`attack`, length 0.80, projectile spawns at 0.30)

| Window | Keys | Reads as |
|---|---|---|
| 0.00 → 0.30 | `ArmL.rotation.z` → **+80°**; `ArmR.rotation.z` → **−20°** and `ArmR.position.x` → **−0.18**; `Visual.rotation.z` → **+14°** | bow arm extends forward, draw hand pulls back to the cheek, torso leans back so the bow **aims upward** |
| 0.30 | spawn projectile from `HandAnchor` | release |
| 0.30 → 0.55 | `ArmR.rotation.z` → **+30°**; `WeaponMain.rotation.z` ±6° damped | snap forward, bow limb wobble |
| 0.55 → 0.80 | → neutral | recover |

**Arrow (`arrow.tscn`, `projectile.gd`):**
- Mesh: `CylinderMesh(r 0.018, h 0.55)` shaft `#8B5A2B` + `BoxMesh(0.06, 0.10, 0.02)` fletching `#F5F0E6` + `ConeMesh` tip `#8C94A3`, rotated to lie along the travel axis.
- Travel: a **parabolic arc** from spawn to the target's `HitAnchor` over **0.55 s**:
  `pos = start.lerp(end, t) + Vector3(0, arc_height * 4.0 * t * (1.0 - t), 0)` with `arc_height = 1.6`.
  Set `rotation.z` each frame from the path derivative so the tip points along the flight path.
- **Retarget rule:** the arrow stores a target reference. On arrival, if the target is `DEAD`, pick a random living enemy and deal damage there. If no enemy is alive, play the impact VFX at the last position and deal no damage. This is the most common source of null crashes in this kind of game — `test_retarget.gd` (§19.3) covers it.
- Impact VFX: 8 small `#F5F0E6` sparks (`GPUParticles3D`, one_shot, lifetime 0.35).

**Special — Bomb Arrow** (`special`, same animation as `attack`, spawns `bomb_arrow.tscn`)
- Identical draw/release animation and identical flight path and arc.
- `bomb_arrow.tscn` is the arrow plus a `SphereMesh(r 0.14)` powder bag `#6B4423` near the tip, a `CylinderMesh(r 0.012, h 0.14)` fuse `#F5F0E6` angled out of it, a **lit fuse spark** (`GPUParticles3D`, amount 12, lifetime 0.25, `#F2C230` → `#E03131`), and an `OmniLight3D` (`#F2C230`, energy 1.5, range 1.2) so the fuse casts light in flight.
- **Plus the §9.6 telegraph** — this is what makes it readable as a special before it lands.
- On arrival: **explode.** Deal `base_damage × RANGER_BOMB_AOE_MULT` (variance rolled per enemy independently) to **every living enemy**, regardless of the original target's state. Resolve targets **left to right, staggered by `Tuning.AOE_STAGGER`** (§9.7).
- Explosion VFX: an expanding `SphereMesh` shell (scale 0.2 → 2.6 over 0.30 s, alpha 0.9 → 0, unshaded `#F2C230`), a 30-particle one-shot burst `#E03131` → `#F2C230`, an `OmniLight3D` flash (energy 6 → 0 over 0.30 s, range 4.0), and camera shake `h_offset` ±0.06 for 0.20 s, decaying.

### 9.3 Priest

**Primary — Magic Bolt** (`attack`, length 0.95, impact_delay 0.55)

| Window | Keys | Reads as |
|---|---|---|
| 0.00 → 0.30 | `ArmR.rotation.z` → **−130°**; `Visual.position.y` → **+0.05**; orb `emission_strength` 1.5 → 5.0 | staff swings up and behind, priest rises on the balls of the feet, orb charges |
| 0.30 | strike sequence begins over the target | — |
| 0.55 | impact | — |
| 0.55 → 0.95 | → neutral, orb back to 1.5 | lower the staff |

At 0.30:
- **Darkening pass** (`Tuning.PRIEST_DARKEN_ENABLED = true`): tween `WorldEnvironment.environment.adjustment_brightness` 1.0 → 0.55 over 0.12 s, hold 0.18 s, return to 1.0 over 0.25 s.
- A warning glow at the target's head: an unshaded `#3B82F6` sphere, scale 0 → 0.5, over 0.20 s.

At 0.55 the bolt lands:
- A **jagged bolt mesh** — an `ImmediateMesh` built at runtime as a 6-segment ribbon from `y = 5.2` down to the target's `HitAnchor`, each segment offset by `randf_range(-0.22, 0.22)` in X and Z, width 0.14, unshaded `#FFFFFF` core with a second slightly wider pass in `#3B82F6`. Alpha 1 → 0 over 0.28 s.
- `OmniLight3D` at the impact point: `#3B82F6`, energy 8 → 0 over 0.30 s, range 5.0.
- Ground flash: a flat `#FFFFFF` disc quad at `y = 0.02`, scale 0.3 → 2.0, alpha 0.9 → 0 over 0.30 s.
- 24-particle one-shot burst in `#3B82F6`.
- Camera shake: `h_offset`/`v_offset` ±0.05 for 0.18 s.
- Then deal damage.

**Special — Heal** (`special`, length 0.85, impact_delay 0.40)
- Same staff-raise keys, orb glows `#2FBF4F`, **no darkening**, plus the §9.6 telegraph.
- Heals **the living hero with the lowest current HP** for `round(priest_current_damage × PRIEST_HEAL_MULT)`, where `priest_current_damage` includes `damage_multiplier`, `bonus_flat_damage` and the same variance roll. Never above `max_hp`. If the priest is the lowest, it heals itself.
- **Skip rule:** see §10.2 — the rule changed in v2.
- **Extra VFX:** on the healed hero, a `status_icon` — a translucent green `+` inside a green circle (`#2FBF4F`, radius 52 px, alpha 0.75) which **shrinks while fading**: scale 1.0 → 0.55, alpha 0.75 → 0.0 over 0.70 s, `TRANS_SINE/EASE_IN`. Plus a green `+N` label rising 60 px, fading over 0.8 s.

### 9.4 Shadow monster

**Primary — Swipe** (`attack`, length 0.60, impact_delay 0.28)

| Window | Keys | Reads as |
|---|---|---|
| 0.00 → 0.20 | `Visual.position.x` → **+0.22**; `Visual.scale` → `(1.12, 0.90, 1.12)` | the blob lunges **toward the heroes** and squashes |
| 0.20 → 0.36 | `Visual.scale` → `(1, 1, 1)` | recoils to shape |
| 0.36 → 0.60 | `Visual.position.x` → 0 | drifts back |

The `+0.22` is the Q3 sign flip: authored forward is local +X, which under the enemy's `rotation.y = PI` points at the heroes.

- **Claw arc VFX** at the target: three parallel tapered quads in `#14121A` with `#FF2D2D` edges sweeping across the target's `HitAnchor`, scale 0 → 1.2, alpha 1 → 0 over 0.25 s.
- `SmokeWisps.amount_ratio` spikes to 1.0 for 0.3 s.

### 9.5 Orc barbarian / Orc warlord

**Primary — Melee** (`attack`, length 0.85, impact_delay 0.42)

| Window | Keys | Reads as |
|---|---|---|
| 0.00 → 0.28 | `ArmL.rotation.z` and `ArmR.rotation.z` → **−120°**; `Visual.rotation.z` → **+12°**; `Visual.position.y` → **+0.06** | axe hauled up overhead and behind, torso coils back, rises onto the toes |
| 0.28 → 0.48 | arms → **+95°**; `Visual.rotation.z` → **−18°**; `Visual.position.x` → **+0.20**; `Visual.scale` → `(0.92, 1.10, 0.92)` | swings with all its might, drives forward, body stretches through the blow |
| 0.48 → 0.85 | → neutral with a small overshoot | heavy recover |

v1 wrote the arms sweeping to `−95°` and the body moving `−0.20`; both are re-signed above per §9.0 and the implementer's flips are ratified.

- Impact VFX: a wide `#8C94A3` slash arc quad (scale 0 → 1.9, larger than the warrior's), a 12-particle dust puff at ground level, camera shake ±0.04 for 0.15 s.
- **Warlord** uses the identical scene and clips at `model_scale = 1.70`, `speed_scale = 0.87` (§8.7), `body_color = #4E7A2B`, `accent_color = #E03131`, plus the shoulder pads from §8.2.

### 9.6 Special-ability telegraph **[v2 — Q19]**

**Q19 answered — no, the bomb arrow was not telegraphed enough, and the fix generalises.**

v1 gave the ranger's special the same draw and release as the primary; the only difference before impact was a powder bag and fuse roughly 0.3 world units across, in a 640 px-tall viewport. A player watching the console will not register that a special is incoming until the explosion, which is exactly backwards — the special is the interesting event.

**Universal rule: every special ability flashes its caster at animation start.** At `t = 0` of any `special` clip, run `CelMaterials.flash(caster, color, Tuning.SPECIAL_CAST_FLASH_TIME)` over all the caster's meshes:

| Caster | Flash colour |
|---|---|
| Warrior (defend) | `#3B6FD4` defend blue |
| Ranger (bomb arrow) | `#F2C230` gold |
| Priest (heal) | `#2FBF4F` heal green |

This costs one line per ability, reuses the existing flash path, and gives every special a consistent "something is about to happen" beat. It is also the reason `flash()` must remember its base colour via metadata rather than reading the live albedo (§6.3) — specials fire often enough to overlap with hit flashes.

**Additionally, the bomb arrow gets a trail:** a `GPUParticles3D` emitter parented to the projectile, amount 40, lifetime 0.45, emission point, gravity `(0, -0.6, 0)`, colour ramp `#E03131` → `#F2C230` → alpha 0, scale 0.06 → 0. The ordinary arrow has no trail, so the two are distinguishable in flight from anywhere on screen.

### 9.7 Area-effect resolution order **[v2 — Q10]**

**Q10 answered — stagger everything, and spread the numbers.**

Three 42 px damage numbers with 6 px outlines landing in the same two frames inside a 640 px viewport is unreadable, and pillar 1 is legibility. v1 staggered the slot's lightning strikes but left the bomb arrow's three hits simultaneous.

**Rule: every multi-target effect resolves its targets one at a time, `Tuning.AOE_STAGGER` (0.06 s) apart, ordered left to right by world X.** This applies to:

- the ranger's bomb arrow (all living enemies)
- 2× and 3× slot lightning (all living enemies) — already did this
- 3× slot plus (all living heroes)

Aggregating into one number is rejected: a single "126" tells the player nothing about how the damage was distributed, and the per-target numbers are how you read whether an enemy is about to die.

**Plus an anti-overlap rule for the numbers themselves** (§11.4): a damage number spawning while another is still within its first 0.25 s offsets horizontally by `±Tuning.DAMAGE_NUMBER_SPREAD` (46 px) × its index in the current burst, alternating sign outward from centre.

---
## 10. Combat system

`battle_director.gd` owns a single fight from spawn to resolution.

### 10.1 Setup sequence (`start_combat(enemy_stat_ids: Array[StringName])`)

1. Refresh every hero's `bonus_flat_damage` and `damage_multiplier` from `GameState.party_bonuses()` (§13.5).
2. Spawn each enemy at its slot (§7.3) with `Visual` alpha 0, `state = IDLE`, `idle` **already playing**.
3. Tween every enemy's alpha 0 → 1 over `ENEMY_FADE_IN_TIME` via `CelMaterials.set_alpha()`, which now fades the outline too (§6.3).
4. Assign initial cooldowns:
   ```gdscript
   c.cooldown_remaining = c.stats.attack_cooldown \
       * Tuning.COOLDOWN_START_FRACTION \
       * randf_range(1.0 - Tuning.COOLDOWN_START_JITTER, 1.0 + Tuning.COOLDOWN_START_JITTER)
   ```
   The 0.5 factor is the vision's "start half full" rule; the ±10% jitter exists **only** to de-sync identical enemy types that would otherwise act on the same frame.
5. Emit `combatant_spawned` per combatant so `BattleOverlay` creates bars; bars **pop in** — scale 0.6 → 1.0 with `TRANS_BACK/EASE_OUT` over `BARS_POP_IN_TIME`, alpha 0 → 1.
6. Emit `combat_started`. The slot leaves attract mode and begins spinning for real (§16.6).

### 10.2 Per-frame loop **[v2 — Q8, Q9]**

```gdscript
func _process(delta: float) -> void:
    if not _active:
        return
    for c: Combatant in _living_in_order():
        if not c.is_alive():
            continue
        if c.state == Combatant.State.ATTACKING:
            continue                           # [v2] Q8 — no discarded decrement
        c.cooldown_remaining -= delta
        if c.cooldown_remaining <= 0.0 and c.state == Combatant.State.IDLE:
            _take_action(c)
```

`_living_in_order()` returns heroes left-to-right then enemies left-to-right. **Iterate over a copy** — actions can kill combatants mid-iteration.

The `ATTACKING` skip is the Q8 fix. v1 decremented the cooldown during an attack and then overwrote it when the animation finished, so the decrement was always discarded — dead code that made the loop look like the cooldown ran concurrently with the attack when it does not. Skipping is equivalent in behaviour and honest in intent, and it matches §11.3's bar, which reads 0 throughout an attack.

`_take_action(c)`:

1. `c.action_count += 1`
2. **Decide special vs primary:**
   ```gdscript
   var due := c.stats.special_every_n_actions > 0 \
       and c.action_count % c.stats.special_every_n_actions == 0
   var use_special := due or c.special_pending
   ```
3. **Priest skip rule** — if `use_special` and every living hero is at full HP:
   ```gdscript
   use_special = false
   c.special_pending = true      # [v2] retained, and the counter keeps its rhythm
   ```
   Otherwise, if the special is actually used, `c.special_pending = false`.
4. **Pick a target: uniformly random among living opponents.** Heroes target enemies, enemies target heroes. Bomb arrow and slot lightning ignore targeting and hit everything. Priest heal targets allies per §9.3.
5. `c.state = ATTACKING`; play `attack` or `special`.
6. **Schedule the impact with a method-call track in the `AnimationPlayer` at `impact_delay`.** Never a `SceneTreeTimer` — see §8.7.
7. On animation finish: `c.state = IDLE`; `c.cooldown_remaining = c.stats.attack_cooldown`. The bar reads `cooldown_remaining / attack_cooldown`, i.e. it fills to 100% the instant the attack ends and drains from there.

**Q9 answered — a `special_pending` flag replaces v1's `action_count` decrement.**

v1 decremented `action_count` by 1 when the priest skipped its heal, so the next action re-incremented to the same multiple of 3 and re-tested. That works, but it also freezes the counter: while the party is healthy the priest's primary attacks stop advancing the rhythm, so a long healthy stretch produces a heal on the very first action after anyone takes a scratch. The heal becomes reactive twitch rather than a rhythm the player can feel.

With a `special_pending` flag the counter advances normally through healthy stretches, so the every-third-action cadence stays intact and legible, **and** a heal that was skipped for lack of a target still fires as soon as one exists. It costs one bool and strictly dominates the old rule.

### 10.3 Damage application

```
attacker computes damage (§8.4)
→ EventBus.combatant_attacked(attacker, target, amount)
→ target.take_damage(amount, attacker)
   → apply damage_reduction, clamp minimum 1
   → previous_hp = current_hp ; current_hp = max(0, current_hp - final)
   → EventBus.combatant_damaged(target, final, previous_hp, current_hp)   # bar reacts (§11)
   → if attacker != null and attacker.is_hero: EventBus.hero_damage_dealt(final)
   → GameState.run_stats accumulates
   → if current_hp == 0: die()
   → else if state != ATTACKING: play "hurt", state = HURT for HURT_ANIM_TIME
```

Slot lightning calls `take_damage(rolled, null)` — a null source, so it never feeds `hero_damage_dealt` and never enters the slot's rolling buffer (§16.5). That is deliberate and load-bearing; a feedback loop where slot damage inflates the average that drives future slot damage would run away.

### 10.4 Death

- Play `die`, set `state = DEAD`, call `cancel_all_effects()` (§8.5), emit `combatant_died`, remove from living lists, fade the bars over 0.25 s and free them.
- **Enemies:** lie still for `ENEMY_DEATH_HOLD` (1.5 s), then fade `Visual` alpha 1 → 0 over `ENEMY_DEATH_FADE` (2.0 s) — body *and* outline, per §6.3 — then `queue_free()`.
- **Heroes:** lie motionless on the ground **indefinitely**. They are not freed. They stay in `GameState.hero_runtime` marked `alive = false`. On the next travel phase they slide off-screen left (§12.5).
- Death VFX: a one-shot 16-particle burst in the combatant's `body_color`, plus a 0.15 s white flash on all its meshes.

### 10.5 Resolution

- **All heroes dead** → `combat_ended(false)` → `game_over` (§18). **Check this before the victory check** so a mutual wipe is a loss.
- **All enemies dead** → victory. Wait `ENCOUNTER_RESOLVE_PAUSE`, emit `combat_ended(true)`, then `encounter_resolved`.
- Enemy corpses may still be fading when the party moves on; they scroll away with the world. Do not block travel on corpse cleanup.

---

## 11. Health and cooldown bars

Lives in `BattleOverlay`, not in 3D. `combatant_bars.tscn`:

```
CombatantBars (Control, size 140×34, pivot centered)
├── CooldownBg (ColorRect)   pos (0,0)   size 140×10   colour #231F2E
├── CooldownFill (ColorRect) pos (2,2)   size 136×6    colour #F2C230
├── HealthBg (ColorRect)     pos (0,14)  size 140×20   colour #231F2E
└── HealthFill (ColorRect)   pos (2,16)  size 136×16   colour #E03131
```

Cooldown bar sits **above** the health bar. Both get a 2 px `#0F0E14` border.

### 11.1 Positioning

Every `_process` frame, for each tracked combatant:

```gdscript
var world := combatant.get_node("BarAnchor").global_position
var vp := battle_camera.unproject_position(world)      # SubViewport coords
bars.position = vp - bars.size * 0.5                   # 1:1 into BattleOverlay
bars.visible = not battle_camera.is_position_behind(world)
```

Bar width is a constant 140 px regardless of `max_hp`. Only the fill fraction varies, which keeps the 280 HP boss's bar readable next to a 40 HP shadow monster's.

### 11.2 The detaching health chunk — the signature effect

On `combatant_damaged(target, amount, previous_hp, new_hp)`:

1. `f_prev = previous_hp / max_hp`, `f_new = new_hp / max_hp`.
2. The lost segment occupies, in `HealthFill`'s local space, `x ∈ [136 × f_new, 136 × f_prev]`, full height.
3. Instantiate `floating_health_chunk.tscn` (a bare `ColorRect`), reparent to `FloatingLayer`, set its **global** position and size to exactly that segment's on-screen rect, colour `#E03131`.
4. Immediately set `HealthFill.size.x = 136 × f_new` — **no tween.** The bar snaps; the chunk carries the motion.
5. Tween the chunk:
   - `position += Vector2(randf_range(-90, 90), randf_range(-130, -50))` over **0.70 s**, `TRANS_CUBIC/EASE_OUT`
   - `rotation` → `randf_range(-0.9, 0.9)` rad over 0.70 s
   - `modulate:a` 1.0 → 0.0 over 0.70 s, `TRANS_QUAD/EASE_IN`
   - then `queue_free()`
6. Flash `HealthBg` to `#FFFFFF` and back over 0.10 s.

**Worked example, which `test_damage_chunk.gd` asserts:** a 100 HP character hit for 20 gives `f_prev = 1.0`, `f_new = 0.8`, so the chunk is the rightmost 20% of the bar — `x` from **108.8 to 136.0**, width **27.2 px**, full 16 px height. This is the case v1 could not force through MCP; §19.3 makes it a headless test with exact arithmetic instead of a screenshot.

**Healing** does the reverse: tween `HealthFill.size.x` up over 0.25 s with `TRANS_SINE/EASE_OUT` and flash the fill to `#2FBF4F` and back over 0.30 s. No chunk spawns.

### 11.3 Cooldown fill

```gdscript
CooldownFill.size.x = 136.0 * clamp(c.cooldown_remaining / c.stats.attack_cooldown, 0.0, 1.0)
```

Full immediately after an attack finishes, draining to empty as the cooldown completes. While `state == ATTACKING` the bar reads 0 — the attack is happening, and with v2's loop change (§10.2) that is now literally true rather than an override.

### 11.4 Damage numbers **[v2 — Q10]**

On `combatant_damaged`, spawn `damage_number.tscn` (a `Label` with `theme_type_variation = &"DisplayLabel"`) in `FloatingLayer` at the target's bar position + `(randf_range(-30, 30), -20)`:

- Text `str(amount)`, font size 42, colour `#E03131`, outline 6 px `#0F0E14`.
- Tween: rise 80 px; `scale` 0.6 → 1.25 → 1.0 (punch over the first 0.18 s); alpha 1 → 0 over 0.85 s; free.
- Heals use `+N` in `#2FBF4F`. Slot lightning uses `#3B82F6`.
- **Elemental item damage** (§13.5) recolours the number to the dominant element the party carries: fire `#FF7A1A`, ice `#5BC8F5`, lightning `#3B82F6`. If the party carries none, it stays `#E03131`.
- **Anti-overlap (§9.7):** `BattleOverlay` tracks numbers spawned in the last 0.25 s. The *n*-th number in a burst offsets its X by `Tuning.DAMAGE_NUMBER_SPREAD × ceil(n/2) × (−1)^n`, i.e. 0, +46, −46, +92, … outward from centre.

---

## 12. Run flow

`run_controller.gd` is the top-level state machine:

```gdscript
enum RunState {
    BOOT, TRAVEL, ARRIVE, COMBAT, LOOT, SHOP,
    ENCOUNTER_EXIT, RUN_COMPLETE, GAME_OVER
}
```

### 12.1 The demo level **[v2 — Q7]**

**Q7 answered — `GameState.build_level()` is canonical, and `res://resources/levels/demo_level.tres` is deleted.**

v1 asked for both: a `.tres` in the directory tree and a runtime builder "so a future generator can replace that one function." Two sources of truth for the same six encounters, and the `.tres` was the one nothing loaded — a file that can only ever drift. Delete it and delete `res://resources/levels/`. The seam for a future generator is `build_level()` and nothing else.

Six encounters, built in code:

| # | Type | Contents | travel_duration |
|---|---|---|---|
| 0 | COMBAT | `shadow_monster`, `shadow_monster` | 2.0 |
| 1 | LOOT | 2 items | 3.0 |
| 2 | COMBAT | `shadow_monster`, `shadow_monster`, `orc_barbarian` | 3.0 |
| 3 | SHOP | 3 items for sale | 3.0 |
| 4 | COMBAT | `orc_barbarian`, `orc_barbarian`, `shadow_monster` | 3.0 |
| 5 | COMBAT (boss) | `orc_warlord`, `shadow_monster` | 4.0 |

`orc_warlord` is listed first so it lands at `x = 1.6` and does not clip the frame (§7.3). The level is a linear sequence with no branching and is **never shown to the player**.

### 12.2 State transitions

```
BOOT ──run_started──▶ TRAVEL
TRAVEL ──travel_duration elapsed──▶ ARRIVE
ARRIVE ──decel + heroes to idle──▶ COMBAT | LOOT | SHOP
COMBAT ──all enemies dead──▶ ENCOUNTER_EXIT
COMBAT ──all heroes dead──▶ GAME_OVER
LOOT ──chest animation done + items granted──▶ ENCOUNTER_EXIT
SHOP ──modal closed──▶ ENCOUNTER_EXIT
ENCOUNTER_EXIT ──dead heroes off-screen──▶ TRAVEL (next index) | RUN_COMPLETE (no more)
```

### 12.3 TRAVEL

- Living heroes: `set_running(true)` → `run` animation.
- `ParallaxBackground.scroll_speed` tweens up per §7.4.
- Runs for `def.travel_duration` seconds, then → `ARRIVE`.
- The slot is in attract mode (§16.6) and the upgrade tray is live (§17.6) — the console is not idle.

### 12.4 ARRIVE

1. Tween `scroll_speed` → 0 over `TRAVEL_DECEL_TIME`, `TRANS_CUBIC/EASE_OUT`.
2. When it reaches ~0, all living heroes `set_running(false)` → `idle`.
3. Branch on encounter type.

### 12.5 ENCOUNTER_EXIT **[Q11]**

If one or more heroes died during this encounter:

1. Each dead hero's `Combatant` node tweens `position.x` from its slot to `-7.0` over `DEAD_HERO_EXIT_TIME` with `TRANS_SINE/EASE_IN`, holding its `die` end pose, then sets `visible = false`.
2. Wait for that tween, then proceed.

**Q11 answered — "removed from the battlefield" means visually removed, not freed.** The node stays alive and stays in `director.heroes`, because the status panel's three rows are index-addressed and freeing the node would shift them. The hero is freed only on Retry (§18.3). Conceptually the party leaves *them* behind; visually, because the camera is fixed and the world scrolls, the corpse slides left off-screen. That is the correct read.

If **all** heroes are dead this state is never entered — go straight to `GAME_OVER`.

### 12.6 RUN_COMPLETE

After encounter 5 resolves: heroes run right for 2.0 s with the background scrolling, then `RunSummary` in Victory mode (§18).

---

## 13. Itemization

### 13.1 Component pools (`itemizer.gd`)

```gdscript
const WEAPON_TYPES := {
    &"axe":    { "base_value": 20, "nouns": ["Axe", "Hatchet", "Cleaver", "Chopper"] },
    &"sword":  { "base_value": 22, "nouns": ["Sword", "Blade", "Saber", "Longsword"] },
    &"bow":    { "base_value": 20, "nouns": ["Bow", "Longbow", "Shortbow", "Recurve"] },
    &"dagger": { "base_value": 18, "nouns": ["Dagger", "Knife", "Dirk", "Shiv"] },
    &"staff":  { "base_value": 25, "nouns": ["Staff", "Rod", "Cane", "Scepter"] },
}

const ADJECTIVES := [
    "Fat", "Wimpy", "Rusty", "Gleaming", "Crooked", "Humble", "Brash", "Sullen",
    "Chipped", "Peculiar", "Stout", "Lucky", "Grumbling", "Nimble", "Battered",
    "Radiant", "Sodden", "Hasty", "Bold", "Weeping", "Jagged", "Plucky",
]
```

Base values come from the initial vision and must not be changed.

**Modifier pool [v2 — expanded from 5 to 8].** The three `slot_*` entries are new and are what make the initial vision's core loop real (§0.4): *finding items in the world makes the slot machine give bigger bonuses.*

```gdscript
const MODIFIERS := [
    # Hero-damage modifiers
    { "id": &"dmg_flat",   "label": "+%d Damage",         "roll": [2, 9],   "value_mult": [0.28, 0.55] },
    { "id": &"dmg_pct",    "label": "+%d%% Damage",       "roll": [5, 18],  "value_mult": [0.30, 0.60] },
    { "id": &"elem_fire",  "label": "+%d Fire Damage",    "roll": [3, 11],  "value_mult": [0.35, 0.70] },
    { "id": &"elem_ice",   "label": "+%d Ice Damage",     "roll": [3, 11],  "value_mult": [0.35, 0.70] },
    { "id": &"elem_light", "label": "+%d Lightning Dmg",  "roll": [3, 11],  "value_mult": [0.35, 0.70] },
    # Slot modifiers                                                          [v2]
    { "id": &"slot_bolt",  "label": "+%d Bolt Power",     "roll": [2, 8],   "value_mult": [0.40, 0.75] },
    { "id": &"slot_purse", "label": "+%d Coin Yield",     "roll": [3, 10],  "value_mult": [0.38, 0.72] },
    { "id": &"slot_mend",  "label": "+%d%% Mend Power",   "roll": [3, 9],   "value_mult": [0.40, 0.75] },
]
```

Each generated modifier stores `{ "id", "label" (formatted), "roll" (the integer rolled), "value_mult" }`. The `roll` key is new and mandatory — v2's modifiers have effects, and storing only the formatted string made the magnitude unrecoverable.

### 13.2 Rarity **[Q13]**

| Rarity | Weight | Modifier count | Value multiplier |
|---|---|---|---|
| Common | 50 | 0 | `1.0` (fixed) |
| Uncommon | 30 | 1 | `randf_range(1.6, 2.2)` |
| Magic | 15 | 2 | `randf_range(2.8, 3.6)` |
| Rare | 5 | 3 | `randf_range(4.5, 6.0)` |

Modifier counts come from the initial vision (0/1/2/3) and must not be changed.

**Q13 answered — modifiers are drawn without replacement.** One item never carries the same modifier id twice; "+4 Damage" and "+7 Damage" on the same sword is a display bug waiting to happen and it widens the value spread for no design reason. With the pool now at 8 entries a Rare's three draws are comfortably distinct.

The multiplier is rolled **per item at generation time** within the ranges above.

> **TODO (post-demo):** replace the random multiplier ranges with a designed curve — rarity multipliers should be authored per-rarity constants, and each modifier's value contribution should scale with the magnitude actually rolled rather than being independently random. Leave this comment verbatim in `itemizer.gd`.

### 13.3 Value formula

```gdscript
value = int(round(
    base_value
    * rarity_multiplier
    * (1.0 + sum_of_modifier_value_mults)
))
```

Arithmetic bounds: cheapest is a common dagger at `18 × 1.0 × 1.0 = 18`; most expensive is a rare staff at up to `25 × 6.0 × (1 + 3 × 0.75) = 487`. Buy prices are `value × 1.5` → **27 to 731 gold**.

**Measured over 200 items with v1's 5-modifier pool:** value min/median/max **18 / 41 / 388**, buy price **27 / 62 / 582**, rarity split **50.0 / 27.5 / 16.0 / 6.5**. The three new `slot_*` modifiers have `value_mult` ranges in the same band, so the distribution should shift only slightly. `test_item_distribution.gd` re-runs and re-reports it in the M7 gate.

### 13.4 Naming

```gdscript
display_name = "%s %s" % [ADJECTIVES.pick_random(), WEAPON_TYPES[type].nouns.pick_random()]
```

→ "Fat Knife", "Wimpy Sword", "Radiant Scepter". `subtitle()` returns rarity + type: "Magic Sword", "Common Bow".

### 13.5 Items affect play **[v2 — new]**

This is half of the core-loop slice (§0.4). The initial vision calls *"by buying upgrades and finding items in the world, the slot machines give bigger and better bonuses more often"* the heart of the game; v1 generated, displayed and priced modifiers and gave them **no effect whatsoever**.

**Items are not equipped** — A6 stands, there is no equipping in the demo. Instead, **every item in the party inventory contributes its modifiers to a party-wide pool.** Carrying loot makes the party stronger; selling it makes them poorer and the console richer. That tension is the loop, and it is now a real decision at every shop.

```gdscript
# GameState.party_bonuses() -> Dictionary, recomputed on every inventory change
{
    "dmg_flat":   int,     # summed rolls of dmg_flat + elem_fire + elem_ice + elem_light
    "dmg_pct":    int,     # summed rolls of dmg_pct
    "element":    StringName,  # &"fire" | &"ice" | &"light" | &"" — largest elemental total
    "slot_bolt":  int,     # flat damage added to each slot lightning strike
    "slot_purse": int,     # flat gold added to each gold payout
    "slot_mend":  int,     # percentage points added to the heal fraction
}
```

Application:

| Bonus | Where it lands |
|---|---|
| `dmg_flat` | `Combatant.bonus_flat_damage` on every living hero (§8.4) |
| `dmg_pct` | multiplies into `Combatant.damage_multiplier`, alongside the party damage buff |
| `element` | recolours hero damage numbers (§11.4). Cosmetic — there are no resistances in the demo |
| `slot_bolt` | `lightning_damage = round(avg_last_three × mult × overcharge) + slot_bolt` |
| `slot_purse` | `gold_payout = round(base × fat_purse) + slot_purse` |
| `slot_mend` | `heal_fraction = 0.25 + slot_mend / 100.0` |

Emit `party_bonuses_changed(bonuses)` from `add_item` and `remove_item`. `BattleDirector` re-applies to living heroes on that signal and at combat start. The slot reads `GameState.party_bonuses()` at payout time.

**Expected magnitude.** A demo run holds at most 5 items (2 from the chest, up to 3 bought), and 50% of rolls are Common with zero modifiers, so the expected total is ~4 modifiers spread over 8 types. Typical end-of-run bonuses are on the order of +4 flat damage, +9% damage, +4 bolt, +6 gold, +5 pp heal. Meaningful, not run-defining. If a future build lets the inventory grow past ~8 items this wants diminishing returns; note it in §22, do not build it.

### 13.6 Shop stock generation **[v2 — Q14]**

**Q14 answered — an unbuyable card is good, three unbuyable cards is a dead encounter.**

The 27–731 gold spread is deliberate and stays: a Rare staff the player cannot afford is a teaser that makes the rarity ladder legible, and it is what exercises §15.2's graying-out logic. But with a single shop at encounter 3, an all-random roll can put every card out of reach, and two of three observed runs bought nothing at all.

Rather than price-checking against live gold (which would make the shop feel like it was reading the player's wallet), **the shop guarantees a rarity spread**:

```gdscript
func generate_shop_stock() -> Array[Item]:
    var stock: Array[Item] = [
        _generate_with_rarity_in([Item.Rarity.COMMON, Item.Rarity.UNCOMMON]),  # affordable
        generate_item(),                                                        # free roll
        _generate_with_rarity_in([Item.Rarity.MAGIC, Item.Rarity.RARE]),        # teaser
    ]
    stock.shuffle()          # so the expensive card is not always in the same slot
    return stock
```

Rarity is picked within each bucket using the §13.2 weights renormalised (62.5/37.5 for the cheap bucket, 75/25 for the teaser bucket). Card 1's worst case is an uncommon staff at `25 × 2.2 × 2.2 ≈ 121` value → 182 gold; its typical case is well under 100. Combined with §5.4's gold supply fix, at least one card is affordable in essentially every run, and the teaser is usually not. That is the intended read.

`SHOP_ITEMS_FOR_SALE = 3` still governs the count; if it changes, generate the two forced buckets first and free-roll the remainder.

### 13.7 Bulk API and kinds

```gdscript
func generate_items(count: int) -> Array[Item]
func generate_item() -> Item
func generate_shop_stock() -> Array[Item]      # [v2] §13.6
```

Loot chests call `generate_items`; shops call `generate_shop_stock`. Every other system requests items only through these.

`Kind.WEAPON` is the only kind generated. `POTION` and `RELIC` exist in the enum, are documented as deferred, and are never produced. `equipped` is always `false`, but `GameState.sellable_items()` must still filter on it — that filter is the seam for future equipment and the M7 gate tests it by flagging an item equipped by hand.

---

## 14. Encounters

### 14.1 Combat encounter

Covered by §10. Sequence: `ARRIVE` prelude → enemies fade in → bars pop in → cooldowns half-charged → fight.

### 14.2 Loot encounter

1. A closed `treasure_chest.tscn` **pops in** on the right at `(3.2, 0, 0)`: scale 0 → 1.15 → 1.0 over 0.45 s with `TRANS_BACK/EASE_OUT`, plus a landing dust puff.
   - Placeholder mesh: `BoxMesh(1.0, 0.62, 0.7)` body `#8B5A2B` with `#F2C230` corner boxes and a `CylinderMesh` half-round lid. `Lid` is a separate child rotating about a hinge at the back edge.
2. Beat of 0.5 s, then **open with juice**:
   - `Lid.rotation.x` 0° → -105° over 0.4 s, `TRANS_BACK/EASE_OUT`
   - Interior `OmniLight3D`, energy 0 → 5 over 0.25 s, colour `#F2C230`
   - A 40-particle one-shot gold burst upward, gravity pulling them back
   - Six `#F2C230` coin quads that arc out and fall
   - A white radial flash quad, scale 0 → 3.0, alpha 0.9 → 0 over 0.35 s
   - Chest squash-stretch: `scale` → `(1.1, 0.9, 1.1)` → `(1.0, 1.0, 1.0)` over 0.3 s
3. `Itemizer.generate_items(def.loot_item_count)`, added to `GameState.inventory` staggered 0.25 s apart. For each, a floating label in `FloatingLayer` at the chest's screen position showing `display_name` in the rarity colour (§17.9), rising 120 px and fading over 1.2 s.
   - Each `add_item` fires `party_bonuses_changed`, so the bonus strip (§17.6) updates live as the loot lands. Sir Fish cheers.
4. Encounter resolved. Chest fades out over 0.4 s as travel begins.

### 14.3 Shop encounter

1. A `shop_building` pops in on the right at `(3.4, 0, 0)` with the same pop-in tween.
   - Placeholder mesh: `BoxMesh(2.0, 1.6, 1.4)` walls `#F5F0E6`, `PrismMesh(2.4, 1.0, 1.6)` roof `#D9333F`, `BoxMesh(0.6, 1.0, 0.1)` door `#8B5A2B`, a `#F2C230` hanging sign quad, and a small warm `OmniLight3D` window glow.
2. After 0.4 s, show `ShopModal` (§15).
3. The encounter resolves **only** when the modal's close button is pressed.

---

## 15. Shop modal

`res://scenes/modals/shop_modal.tscn`, a child of `ModalLayer` (now a `Control`, §3.3 — it inherits `Main.theme` and must **not** declare its own).

### 15.1 Layout

- Full-screen `#0F0E14` scrim at 65% alpha, fading in over 0.2 s. Scrim clicks do **not** close the modal.
- Panel 960 × 1200, centred → (60, 360) to (1020, 1560). Enters with scale 0.85 → 1.0 and alpha 0 → 1 over 0.25 s, `TRANS_BACK/EASE_OUT`.
- Header row: title `SHOP` (`DisplayLabel`, font 56, `#F2C230`) on the left; **a red X close button in the upper right** — 72×72, `#E03131` background, `#FFF6E0` glyph, corner radius 16, inset 16 px from the panel's top-right corner.
- Gold readout under the header, right-aligned: coin glyph + `str(GameState.gold)`, `DisplayLabel` font 44, `#F2C230`. **Updates live** on every buy, sell and slot payout.
- **[v2] Party bonuses strip** under the gold readout — an instance of `bonus_strip.tscn` (§17.6), 880 × 34, showing the current aggregate from `GameState.party_bonuses()`. This is what makes selling a real decision instead of free money: the player can see exactly what leaves the party with the item.
- `TabContainer` with exactly two tabs: **`Buy`** then **`Sell`**, `Buy` selected on open.

### 15.2 Buy tab

- On the encounter's first open, call `Itemizer.generate_shop_stock()` **once** and cache it on the encounter. Reopening the tab shows the **same three items** — never reroll.
- Three `shop_buy_card.tscn` stacked vertically, each 880 × 260. **The card root must not be a bare `PanelContainer` child arrangement** — a `PanelContainer` force-resizes every child to fill it, which made v1's 12 px rarity edge cover the whole card. Structure: `PanelContainer > HBoxContainer > [Edge (ColorRect, custom_minimum_size = (12, 0)), Layout (VBoxContainer)]`.
  - Rarity-coloured left edge bar, 12 px (§17.9)
  - `display_name` — `DisplayLabel` font 44, `#FFF6E0`
  - `subtitle()` — font 30, rarity colour
  - Modifier lines — font 28, `#9B93AE`, one per modifier, using the formatted `label`
  - Price, right-aligned — `DisplayLabel` font 46, `#F2C230`, `str(buy_price)` with a coin glyph
- **Affordability:** a card is affordable when `GameState.gold >= buy_price`.
  - Affordable → full colour, `mouse_default_cursor_shape = POINTING_HAND`, tappable, subtle idle pulse on the price (scale 1.0 ↔ 1.04, 1.6 s period).
  - Unaffordable → whole card `modulate = Color(0.45, 0.45, 0.5, 1.0)`, not tappable.
- **On purchase:** deduct gold, add the item to `GameState.inventory` (which fires `party_bonuses_changed`, so the bonus strip updates immediately), then that card:
  - price text becomes **`SOLD!`** in `#E03131`
  - card grays out, permanently untappable for this shop visit
  - a `#F2C230` `-N` gold number floats up from the gold readout
- **Re-evaluate affordability of every card on every gold change** — purchases, sales, slot payouts, upgrade purchases. Connect to `EventBus.gold_changed`. This worked example must hold exactly:
  > Items cost 200, 250, 300; party has 350. All three affordable. Buy the 250 → it reads `SOLD!` and grays out; the 200 and 300 now gray out too, because 100 gold remains.

  Force it in the M7 gate with `Debug` command `shop 200 250 300` + `gold 350` (§19.2).

### 15.3 Sell tab

- Lists `GameState.sellable_items()` — **equipped items are neither displayed nor sellable.** Nothing is ever equipped in the demo, but the filter must be real.
- A `VBoxContainer` inside a `ScrollContainer`.
- Each `shop_sell_row.tscn` is 880 × 180, same `HBoxContainer` edge structure as the buy card: rarity edge, name, subtitle, **the full modifier list** (not just a count — v2's modifiers do something, so the player must see what they are giving up), and a button labelled `Sell for N` with a coin glyph.
- Pressing it: `GameState.add_gold(sell_price)`, `GameState.remove_item(item)`, the row collapses (height → 0, alpha → 0 over 0.25 s) and is freed, a `+N` gold number floats up, and both the Buy tab's affordability and the bonus strip re-evaluate.
- Empty state: centred `#9B93AE` label, "Nothing to sell."

### 15.4 Close

The red X fades the panel out (scale → 0.9, alpha → 0, 0.2 s), fades the scrim, `queue_free()`s, and emits encounter-resolved. Nothing else closes the modal. Accepting `ui_cancel` for desktop testing is allowed, not required.

---

## 16. The slot machine

### 16.1 Presentation

Housed in `SlotMachine` (1080 × 600 at console-local y 300). An American 1980s three-reel cabinet: heavy `#332C42` body, 6 px `#F2C230` bezel, rounded corners, three recessed reel windows, and a **single centre payline** — a 4 px `#E03131` horizontal line spanning all three windows with a small arrow marker each side.

| Element | Position | Size |
|---|---|---|
| Cabinet panel | (110, 20) | 860 × 560 |
| Reel window 0 | (160, 60) | 240 × 480 |
| Reel window 1 | (420, 60) | 240 × 480 |
| Reel window 2 | (680, 60) | 240 × 480 |
| Symbol cell | — | 240 × 160 (3 visible per reel = 480) |
| Payline | (140, 298) | 800 × 4 |

Three symbols visible per reel per stop; the **middle** cell of each reel is on the payline.

### 16.2 Reel strip and the 50% win rate

All three reels use the **same 27-stop strip**:

```gdscript
const SLOT_STRIP: Array[int] = [
    Sym.LIGHTNING, Sym.BLANK,     Sym.GOLD,      Sym.PLUS,      Sym.LIGHTNING,
    Sym.GOLD,      Sym.PLUS,      Sym.BLANK,     Sym.LIGHTNING, Sym.GOLD,
    Sym.PLUS,      Sym.LIGHTNING, Sym.BLANK,     Sym.GOLD,      Sym.PLUS,
    Sym.LIGHTNING, Sym.GOLD,      Sym.PLUS,      Sym.BLANK,     Sym.LIGHTNING,
    Sym.GOLD,      Sym.PLUS,      Sym.LIGHTNING, Sym.BLANK,     Sym.GOLD,
    Sym.PLUS,      Sym.BLANK,
]
# LIGHTNING 7, GOLD 7, PLUS 7, BLANK 6 → 27 stops
```

**Win rule:** 2 or 3 of the same non-blank symbol on the payline, counting any two of the three positions — they need not be adjacent. Blanks never pay.

- Total outcomes: 27³ = **19,683**
- Per paying symbol (7 stops, 20 non-s): exactly 3 = 7³ = **343**; exactly 2 = 3 × 7² × 20 = **2,940**; subtotal **3,283**
- Three paying symbols: 3 × 3,283 = **9,849**
- P(win) = 9,849 / 19,683 = **0.500381…**

| Outcome | Probability |
|---|---|
| 3 of a specific symbol | 1.743% |
| 2 of a specific symbol | 14.937% |
| Any win | 50.038% |
| No win | 49.962% |

Computed by exhaustive enumeration, and **independently reproduced by the implementation**: `test_slot_odds.gd` measured 0.50001 over 1,000,000 spins and the exhaustive enumeration returned 9,849 / 19,683 exactly, with the strip confirmed at 7/7/7/6.

**Do not change a single stop.** Nothing in v2 — not upgrades, not items — touches the strip or the win rate. Upgrades change how *often spins happen* and how *much a win pays*, never the odds. Recompute and re-run the test if the strip ever changes.

### 16.3 Spin cycle

Continuous, no player input. One cycle:

1. `slot_spin_started`. All three reels scroll upward at high speed; legibility drops naturally from the speed (no blur shader required).
2. Reel 0 decelerates and stops at a uniformly random stop index at `t = SLOT_SPIN_DURATION × quick_reels_mult`.
3. Reel 1 stops `+SLOT_REEL_STAGGER × quick_reels_mult` later; reel 2 `+2 ×` that.
4. Each stop tweens to the exact cell offset with `TRANS_BACK/EASE_OUT` over 0.18 s so it overshoots and snaps back — the physical thunk. Add a 4 px cabinet shake on each stop.
5. `slot_spin_stopped([s0, s1, s2])`. Evaluate the payline. On a win, run §16.4 and apply §16.5.
6. Hold `SLOT_RESULT_HOLD × quick_reels_mult`, then spin again if combat is still active.

`quick_reels_mult` is `Tuning.UPGRADE_QUICK_REELS_STEP ^ Upgrades.level(&"quick_reels")` — 1.00 / 0.86 / 0.74 / 0.64. Base cycle is 1.10 + 0.56 + 0.85 ≈ **2.51 s** (~6–10 spins per combat); at Quick Reels 3 it is **1.60 s** (~10–16 spins).

### 16.4 Win presentation

- The winning symbols on the payline pulse: scale 1.0 → 1.30 → 1.0 over 0.35 s, with a `#F2C230` glow ring behind each.
- The payline flashes `#E03131` → `#FFF6E0` → `#E03131` twice.
- A banner label (`DisplayLabel`, font 48, `#F2C230`, outline `#0F0E14`) appears centred above the reels for 1.0 s then fades: `"LIGHTNING ×2"` / `"GOLD ×3"` / `"HEAL ×2"`.
- 3-of-a-kind additionally: a 40-particle gold confetti burst and a scale punch 1.0 → 1.05 → 1.0 over 0.25 s on the whole `SlotMachine` node.
- Sir Fish reacts on every win (§17.7) — `cheer` for a pair, `smug` for a triple.

### 16.5 Payouts **[v2 — upgrades and items apply here]**

Rolling buffer of the last three hero damage instances, fed by `EventBus.hero_damage_dealt`:

```gdscript
var _last_hero_hits: Array[int] = []      # max length 3, newest appended, oldest popped

func _avg_last_three() -> float:
    if _last_hero_hits.is_empty():
        return float(Tuning.SLOT_LIGHTNING_FALLBACK)   # 12
    var total := 0
    for v: int in _last_hero_hits:
        total += v
    return float(total) / float(_last_hero_hits.size())
```

| Result | Effect |
|---|---|
| 2 × Lightning | **All living enemies** struck for `round(avg × SLOT_LIGHTNING_2_MULT × overcharge) + slot_bolt` |
| 3 × Lightning | **All living enemies** struck for `round(avg × SLOT_LIGHTNING_3_MULT × overcharge) + slot_bolt` |
| 2 × Gold | `round(SLOT_PAY_2_GOLD × fat_purse) + slot_purse` gold |
| 3 × Gold | `round(SLOT_PAY_3_GOLD × fat_purse) + slot_purse` gold |
| 2 × Plus | The **living hero with the lowest current HP** healed for `heal_fraction` of their max HP |
| 3 × Plus | The **entire living hero party** healed for `heal_fraction` of each hero's max HP |

where, from §17.6 and §13.5:

```gdscript
var overcharge := 1.0 + Tuning.UPGRADE_OVERCHARGE_STEP * Upgrades.level(&"overcharge")
var fat_purse  := 1.0 + Tuning.UPGRADE_FAT_PURSE_STEP  * Upgrades.level(&"fat_purse")
var b := GameState.party_bonuses()
# base is SLOT_HEAL_2_FRACTION for a pair, SLOT_HEAL_3_FRACTION for a triple
var heal_fraction := clampf(base_fraction + float(b["slot_mend"]) / 100.0, 0.0, 1.0)
```

Rules that remove ambiguity:

- "Enemies are struck" is plural → **all** living enemies, each taking the full amount, each rolling `DAMAGE_VARIANCE` independently, resolved left-to-right `AOE_STAGGER` apart (§9.7).
- Slot lightning is **not** attributed to a hero and must **not** feed `_last_hero_hits`. Call `take_damage(rolled, null)`.
- Slot heals cannot exceed `max_hp` and cannot revive the dead. `heal_fraction` is clamped to `[0.0, 1.0]`.
- If a payout has no valid target (lightning with everything already dead in the resolve window), skip it silently but still play the celebration.
- **Slot lightning VFX:** reuse the priest's bolt builder (§9.3) once per enemy, `AOE_STAGGER` apart, **without** the darkening pass — it fires far too often to darken the screen for.

### 16.6 When the slot runs — attract mode **[v2 — Q17]**

**Q17 answered — the reels never stop moving; they just stop mattering.**

Two rules were in direct conflict. The initial vision says *"between encounters and during non-combat encounters, the slot machine should do nothing."* Pillar 2 says *"the console is always doing something. Dead air is a bug."* v1's resolution — dim the cabinet to `Color(0.55, 0.55, 0.62)` and freeze it — meant a dark, motionless slot through all travel, the entire loot encounter and the entire shop encounter, which is most of the demo's runtime. The single largest element on screen is dead for most of the game.

**Attract mode** honours both. "Does nothing" is read as *nothing that affects the game* — no stops, no evaluation, no payouts — while the cabinet stays alive:

| State | Behaviour |
|---|---|
| **Combat** (`RunController.state == COMBAT`, fight active) | Full spin cycle (§16.3). Cabinet `modulate = Color.WHITE`. Payline lit `#E03131`. |
| **`combat_ended` transition** | The current spin finishes its stop sequence, evaluates, and pays out normally. Hold `SLOT_RESULT_HOLD`. Then decay into attract mode over 0.4 s. |
| **Attract** (everything else) | Reels drift upward continuously at `SLOT_ATTRACT_SPEED` (0.15× spin speed). **They never stop and the payline is never evaluated.** Cabinet `modulate = Tuning.SLOT_ATTRACT_DIM` (`0.78, 0.78, 0.82` — a hint of dimming, not a shutdown). Payline unlit `#5C5470`. A marquee label above the reels reads `OUT OF COMBAT` in `#9B93AE` font 34, alpha pulsing 0.4 ↔ 0.8 on a 2.0 s period. |
| **`combat_started`** | Undim over 0.2 s, payline lights, reels accelerate into the first real spin. |

The upgrade tray (§17.6) is live during attract mode, so out-of-combat time is when the player spends. The console genuinely always has something to do, and no payout ever fires outside combat.

### 16.7 Symbol rendering — fully procedural

`slot_symbol.tscn` is a `Control` that draws in `_draw()`. No image files. Coordinates are normalised to the control's size (240 × 160 cell; draw within a centred 140 × 140 square).

**These must be `static var`, not `const`** — `PackedVector2Array([...])` is not a constant expression in GDScript 4.7 and the file will fail to parse, which cascades into `SlotSymbol` never registering as a global class.

```gdscript
static var BOLT := PackedVector2Array([
    Vector2(0.55, 0.05), Vector2(0.22, 0.55), Vector2(0.45, 0.55),
    Vector2(0.30, 0.95), Vector2(0.78, 0.42), Vector2(0.52, 0.42),
    Vector2(0.72, 0.05),
])

static var PLUS := PackedVector2Array([
    Vector2(0.37, 0.10), Vector2(0.63, 0.10), Vector2(0.63, 0.37),
    Vector2(0.90, 0.37), Vector2(0.90, 0.63), Vector2(0.63, 0.63),
    Vector2(0.63, 0.90), Vector2(0.37, 0.90), Vector2(0.37, 0.63),
    Vector2(0.10, 0.63), Vector2(0.10, 0.37), Vector2(0.37, 0.37),
])
```

- **Lightning** — `draw_colored_polygon(BOLT, #3B82F6)` then `draw_polyline(BOLT + first point, #F2C230, 7.0, true)`. A blue stylised bolt with a gold outline.
- **Gold coin** — `draw_circle(c, 0.42, #F2C230)`, `draw_arc(c, 0.42, 0, TAU, 48, #0F0E14, 6.0)`, inner `draw_circle(c, 0.30, #FFDD66)`, `draw_arc(c, 0.30, 0, TAU, 48, #B8860B, 4.0)`, plus a small `#B8860B` 5-point star at 0.18 radius.
- **Green plus** — `draw_colored_polygon(PLUS, #2FBF4F)` then `draw_polyline(PLUS + first point, #000000, 6.0, true)`.
- **Blank** — draw nothing; the recessed `#231F2E` window shows through.

---

## 17. The management console

### 17.1 Console background

`Console` gets a `ColorRect` at `#231F2E` behind everything plus a 2 px `#4A4260` inner border. The gold `ConsoleDivider` above it separates it hard from the battlefield.

### 17.2 Status panel (1080 × 300)

A `PanelContainer` containing a `VBoxContainer`:

**Row A — resources (height 90):**
- Left: a procedurally drawn coin glyph (36 px, reusing §16.7's coin) + `str(GameState.gold)`, `DisplayLabel` font 52, `#F2C230`. On `gold_changed`, punch the label scale 1.0 → 1.22 → 1.0 over 0.25 s and float a `±N` label upward beside it in `#F2C230` (gain) or `#E03131` (spend).
- Right: `inventory_strip.tscn` — a horizontal `ScrollContainer` of 64×64 item chips, each a rounded rect in the item's rarity colour with the weapon-type initial (A/S/B/D/T) in `#0F0E14`. New items slide in from the right over 0.3 s. Tapping a chip shows `item_tooltip.tscn` (name, subtitle, modifier list, value) anchored above the chip, dismissed by tapping anywhere.
  - **Chips live inside a container.** Do not tween `position:x` on a child of an `HBoxContainer` — the container overwrites it every layout pass and every chip parks at x = 0 stacked on the others. Animate a wrapper inside a container-managed slot.
  - The strip **rebuilds on `EventBus.run_started`**, because `reset_run()` clears the inventory array without emitting `item_removed` per item.

**Rows B–D — hero status (3 × 70):** each `hero_status_row.tscn` (1080 × 70):

| Element | X | Width | Content |
|---|---|---|---|
| Class chip | 24 | 56 | rounded square in the hero's `accent_color`, initial letter |
| Name | 96 | 200 | `display_name`, font 34, `#FFF6E0` |
| HP bar | 312 | 420 | bg `#231F2E`, fill `#E03131`, 24 px tall, tweens over 0.25 s |
| HP text | 312 | 420 | `"%d / %d"` centred over the bar, font 28, `#FFF6E0`, outline 4 px `#0F0E14` |
| Buff icons | 756 | 220 | 44×44 chips, right-aligned: blue shield (defending), gold arrow-up (party damage buff) |

Dead heroes: whole row `modulate = Color(0.4, 0.4, 0.45)`, name struck through with a 3 px `#E03131` line, HP text reads `DEAD`.

### 17.3 Party damage button (720 × 160 at console-local (180, 900))

Text **`Increase Party Damage`**, `DisplayLabel` font 44, centred.

- **Idle:** enabled, subtle idle glow pulse on the gold border.
- **On press:** every living hero's `damage_multiplier` is multiplied by `Tuning.PARTY_DAMAGE_BUFF_MULT` (1.10) for `PARTY_DAMAGE_BUFF_DURATION` (30.0) s. Emit `party_damage_buff_started(30.0)`.
- **While active:** `disabled = true`, and a `ColorRect` child `BuffProgress` sits below the label and above the stylebox, `#F2C230` at 40% alpha, `size.x` starting at the full button width and draining to 0 over the duration. **Drive it in `_process` from the remaining time — never a Tween**, so it stays correct if the game is paused.
- **At 0%:** divide the multiplier back out of every hero (do not set to 1.0 — future stacking buffs and §13.5's `dmg_pct` must survive), `disabled = false`, hide `BuffProgress`, emit `party_damage_buff_ended`, play a 0.2 s scale punch.
- The timer is **real time and encounter-agnostic**: it drains through travel, loot and shop. Heroes who die while buffed are skipped on removal.

### 17.4 Sir Fish's tank — see §17.7

### 17.5 Status icon (`status_icon.tscn`)

A `Control` drawn procedurally. Every instance registers its owning `Combatant` and is freed by `cancel_all_effects()` (§8.5).

- **Defend:** `draw_circle(c, 46, #3B6FD4 @ 0.85)`, `draw_arc(c, 46, 0, TAU, 48, #FFF6E0, 5.0)`, and a white shield polygon `[(0.5,0.12),(0.82,0.26),(0.82,0.55),(0.5,0.88),(0.18,0.55),(0.18,0.26)]` normalised to a 60 px box, filled `#FFF6E0`.
- **Heal:** `draw_circle(c, 52, #2FBF4F @ 0.55)`, `draw_arc(c, 52, 0, TAU, 48, #2FBF4F @ 0.9, 5.0)`, and §16.7's `PLUS` polygon filled `#2FBF4F @ 0.75` scaled to a 62 px box. Translucent.

Both polygon constants must be `static var`, per §16.7.

### 17.6 The upgrade tray **[v2 — new]**

This is the other half of the core-loop slice (§0.4). The initial vision's console is *"slots as well as buttons for purchasing upgrades"*, and its loop is *"by buying upgrades and finding items in the world, the slot machines give bigger and better bonuses more often."* v1 built an empty `HBoxContainer` with a "coming soon" label. v2 builds three upgrades — enough that the loop closes and can be felt, and not one more.

`UpgradeTray` is a `Control` at console-local (0, 1060), 1080 × 212, **always visible and always interactive**, in combat and out.

```
UpgradeTray (Control)
├── BonusStrip (Control)         pos (0, 0)    size 1080 × 30    # bonus_strip.tscn
├── UpgradeButton0 (Button)      pos (12, 34)  size 340 × 178
├── UpgradeButton1 (Button)      pos (370, 34) size 340 × 178
└── UpgradeButton2 (Button)      pos (728, 34) size 340 × 178
```

**`bonus_strip.tscn`** — one line, font 22, `#9B93AE`, centred, rebuilt on `party_bonuses_changed`. Six procedurally drawn 20 px glyphs with values beside them, omitting any that are zero: sword (`dmg_flat`), chevron (`dmg_pct`), §16.7 `BOLT` (`slot_bolt`), coin (`slot_purse`), §16.7 `PLUS` (`slot_mend`). Empty state: `No party bonuses` in `#7A7290`. This is the only place the player can see what their inventory is doing, so it must be present in the console **and** in the shop modal (§15.1).

**`Upgrades` autoload** (`res://scripts/autoload/upgrades.gd`):

```gdscript
extends Node

const DEFS := {
    &"quick_reels": {
        "name": "Quick Reels",
        "blurb": "Reels spin %d%% faster",
        "base": Tuning.UPGRADE_QUICK_REELS_BASE,     # 60
    },
    &"overcharge": {
        "name": "Overcharge",
        "blurb": "Lightning pays +%d%%",
        "base": Tuning.UPGRADE_OVERCHARGE_BASE,      # 70
    },
    &"fat_purse": {
        "name": "Fat Purse",
        "blurb": "Gold pays +%d%%",
        "base": Tuning.UPGRADE_FAT_PURSE_BASE,       # 50
    },
}

var levels := { &"quick_reels": 0, &"overcharge": 0, &"fat_purse": 0 }

func level(id: StringName) -> int
func is_maxed(id: StringName) -> bool                # level >= Tuning.UPGRADE_MAX_LEVEL
func cost(id: StringName) -> int                     # for the NEXT level; -1 if maxed
func buy(id: StringName) -> bool                     # spends gold, emits upgrade_purchased
func reset() -> void                                 # all levels to 0, called from reset_run()
```

```gdscript
func cost(id: StringName) -> int:
    if is_maxed(id):
        return -1
    var base: int = DEFS[id]["base"]
    return int(round(float(base) * pow(Tuning.UPGRADE_COST_GROWTH, float(levels[id]))))
```

| Upgrade | Effect per level | L1 | L2 | L3 | Total | At max |
|---|---|---|---|---|---|---|
| **Quick Reels** | spin cycle × 0.86 (compounding) | 60 | 114 | 217 | 391 | cycle 2.51 s → **1.60 s** |
| **Overcharge** | lightning payout +25% (additive) | 70 | 133 | 253 | 456 | **×1.75** damage |
| **Fat Purse** | gold payout +40% (additive) | 50 | 95 | 181 | 326 | **×2.20** gold |

Maxing everything costs **1,173 gold**; a full run earns roughly 375 (75 starting + ~300 from the slot) before item sales. A run therefore buys **two to four levels total**, against three shop cards competing for the same gold. That is a real decision every time the tray is looked at, and it is the point.

Upgrades are **run-scoped**: `Upgrades.reset()` is called from `GameState.reset_run()`. The demo has no meta-progression.

**`upgrade_button.tscn`** (340 × 178, a `Button` with procedural children):

| Element | Position | Content |
|---|---|---|
| Title | (16, 12) | `DEFS[id].name`, `DisplayLabel` font 30, `#FFF6E0` |
| Blurb | (16, 50) | `DEFS[id].blurb` formatted with the *next* level's cumulative effect, font 22, `#9B93AE` |
| Level pips | (16, 92) | 3 × 18 px squares, 8 px apart; filled `#F2C230` up to `level`, outlined `#5C5470` beyond |
| Cost | (16, 128) | coin glyph + `str(cost)`, `DisplayLabel` font 32, `#F2C230` |

States:
- **Affordable** — full colour, enabled, gold border pulse 1.6 s period.
- **Unaffordable** — `modulate = Color(0.45, 0.45, 0.5, 1.0)`, `disabled = true`.
- **Maxed** — cost row replaced by `MAX` in `#4CC38A`, `disabled = true`, all three pips filled.

Re-evaluate every button on `gold_changed` and `upgrade_purchased`, exactly as the shop cards do.

On purchase: `GameState.spend_gold(cost)`, `levels[id] += 1`, `run_stats.upgrades_bought += 1`, emit `upgrade_purchased`, float a `#F2C230` `-N` from the gold readout, punch the button 1.0 → 1.06 → 1.0 over 0.25 s, and fill the newly-earned pip with a `TRANS_BACK/EASE_OUT` scale pop. Sir Fish plays `smug`.

**What upgrades must never do:** touch `SLOT_STRIP`, the win rule, or the win rate. §16.2's 50.038% is proved and tested. "More often" is delivered by Quick Reels compressing the cycle — the same 50% of *more spins per minute* — not by rigging the reels.

### 17.7 Sir Fish **[v2 — new, Q18]**

**Q18 answered — Sir Fish is the player, and he lives in the console.**

He is an armoured fish in a glass tank bolted to the console at console-local **(8, 898), 164 × 164**, immediately left of the party damage button. He has **no gameplay effect at all**. He is a face for the console and an emotional read on state that the numbers cannot give — and he makes the title true.

**`sir_fish_tank.tscn`:**

```
SirFishTank (SubViewportContainer, 164×164, stretch = true)
└── FishViewport (SubViewport, 164×164, transparent_bg = true)
    ├── FishCam (Camera3D)          orthographic, size 1.4, position (0, 0, 3), rotation (0,0,0)
    ├── FishLight (DirectionalLight3D)  rotation (-30°, -25°, 0°), energy 1.2, colour #FFF3D6
    ├── Tank (Node3D)
    │   ├── Glass (MeshInstance3D)  SphereMesh(r 0.62), water.gdshader
    │   ├── Base (MeshInstance3D)   CylinderMesh(r 0.50, h 0.10) #F2C230 at (0, -0.62, 0)
    │   ├── Gravel (MeshInstance3D) CylinderMesh(r 0.44, h 0.08) #8B5A2B at (0, -0.50, 0)
    │   └── Plaque (MeshInstance3D) BoxMesh(0.46, 0.12, 0.02) #F2C230 at (0, -0.72, 0.30)
    │                               # "SIR FISH" drawn on it via a procedural Label3D, font 16, #0F0E14
    ├── SirFish (Node3D)            sir_fish.gd
    │   ├── Body (MeshInstance3D)   SphereMesh(r 0.16) scaled (1.5, 1.0, 0.7), #4A9BE8
    │   ├── Tail (MeshInstance3D)   PrismMesh(0.18, 0.22, 0.04) #3B6FD4 at (-0.24, 0, 0)
    │   ├── FinTop / FinSide        PrismMesh(0.10, 0.12, 0.03) #3B6FD4
    │   ├── Helm (MeshInstance3D)   CylinderMesh(r 0.11, h 0.10) #8C94A3 at (0.06, 0.13, 0)
    │   ├── Visor (MeshInstance3D)  BoxMesh(0.14, 0.03, 0.02) #0F0E14
    │   ├── Circlet (MeshInstance3D) TorusMesh(inner 0.10, outer 0.12) #F2C230
    │   └── Eye (MeshInstance3D)    SphereMesh(r 0.025) #0F0E14 at (0.14, 0.05, 0.11)
    └── Bubbles (GPUParticles3D)    one_shot, amount 14, lifetime 0.9, #FFFFFF @ 0.5,
                                    gravity (0, 1.2, 0), scale 0.03 → 0.01
```

All meshes use the §6.2 cel material with the §6.3 outline `next_pass`, exactly like the combatants — he must read as part of the same world.

`water.gdshader` (`res://assets/shaders/water.gdshader`): `blend_mix, cull_back, unshaded, depth_draw_never`; `ALBEDO = #7EC8E3`, `ALPHA = 0.22 + 0.10 * fresnel`, plus a slow `sin(TIME)` ripple on the fresnel term. Glass, not water simulation.

**Reaction states** (`sir_fish.gd`), each an `AnimationPlayer` clip, driven entirely by `EventBus`:

| State | Trigger | Length | Behaviour |
|---|---|---|---|
| `idle` | default | 3.00 loop | slow figure-8 swim, gentle tail wag ±12° |
| `cheer` | `slot_payout` (2 of a kind) | 1.20 | fast tail wag, two vertical hops, 6-bubble burst |
| `smug` | `slot_payout` (3 of a kind), `upgrade_purchased` | 1.50 | slow 360° spin about Y, chest out, gold sparkle particles |
| `alarm` | `combatant_damaged` where the target is a hero | 0.80 | darts to the far side of the tank and back |
| `grieve` | `combatant_died` where the hero is a hero | 2.00 | sinks to the gravel, still, then rises back to `idle` |
| `slump` | `game_over` | 1.20 → hold | sinks, rolls onto his side, the helm tips off and lands on the gravel. **Holds.** |
| `triumph` | `run_completed` | 2.50 → loop | rapid spins, continuous bubbles, circlet glints |

**Priority**, highest first: `slump` / `triumph` > `grieve` > `alarm` > `smug` > `cheer` > `idle`. A higher-priority state interrupts a lower one; a lower one is dropped if a higher one is playing. Every non-looping state returns to `idle` on finish, except `slump` and `triumph`, which hold until `run_started`.

**Rate limit:** `alarm` fires at most once per 0.6 s — during a three-enemy fight it would otherwise trigger constantly and read as a seizure rather than a reaction. `cheer` is not rate-limited; slot wins are already paced by the spin cycle.

Sir Fish also appears in the run summary (§18.2) — the same scene at 2× scale in the panel header, already in `slump` or `triumph`.

### 17.8 Slot counter **[v2 — Q24]**

`slot_counter.tscn`, a `Control` at console-local **(900, 898), 172 × 164**, mirroring the fish tank across the party damage button.

| Element | Content |
|---|---|
| Label | `SLOT` — font 22, `#9B93AE`, centred, at y 8 |
| Wins | `str(run_stats.slot_wins)` — `DisplayLabel` font 52, `#F2C230`, centred, at y 34 |
| Divider | 100 × 2 `#4A4260` at y 92 |
| Spins | `%d spins` % `run_stats.slot_spins` — font 24, `#9B93AE`, centred, at y 104 |
| Streak pips | five 12 px squares at y 138, filled `#F2C230` for a win and `#4A4260` for a loss, newest on the right |

Updates on `slot_spin_stopped`. The wins number punches 1.0 → 1.18 → 1.0 on each increment.

**Q24 answered — no percentage anywhere a small sample can be read as a verdict.**

An observed defeat run reported 7 wins / 21 spins = 33.3% on the summary. That is not a defect — at 21 spins, 1σ is about 11 points, and the authoritative 1,000,000-spin test reports 0.50001 — but a player reading "33%" concludes the machine is rigged against them, which is precisely the opposite of the reassurance v1 wanted from putting it there.

So: **the percentage is removed from the run summary** (§18.2), which shows the raw win count. The console shows live `wins` over `spins` plus a five-spin streak strip, which is honest, immediate, and reads as texture rather than as a claim. The 50% sanity check lives where the sample size makes it meaningful — `test_slot_odds.gd`, one million spins (§19.3).

### 17.9 Rarity colours

| Rarity | Colour |
|---|---|
| Common | `#B8B2C4` |
| Uncommon | `#4CC38A` |
| Magic | `#4A9BE8` |
| Rare | `#F2C230` |

---
## 18. Game over and run summary

`res://scenes/modals/run_summary.tscn`, a child of `ModalLayer`.

### 18.1 Trigger

- **Defeat:** all heroes dead → `RunState.GAME_OVER`. Freeze combat, let the last `die` finish, hold 1.0 s on the battlefield so the player sees the wipe, fade a `#0F0E14` scrim to 75% over 0.5 s, then present. Sir Fish plays `slump` as `game_over` fires, before the scrim — the player should see him give up.
- **Victory:** encounter 5 resolved → heroes run right for 2.0 s, then the same presentation with victory styling. Sir Fish plays `triumph`.

### 18.2 Content **[v2 — Q24]**

Panel 900 × 1180, centred.

- **Sir Fish's tank** at the top of the panel, `sir_fish_tank.tscn` at 2× scale (328 × 328), centred, already holding `slump` or `triumph`. He is the first thing the player sees on this screen.
- Title: **`DEFEATED`** in `#E03131` (`DisplayLabel`, font 84) or **`LEVEL CLEARED`** in `#F2C230` (font 76). Slam in: scale 1.6 → 1.0 over 0.35 s, `TRANS_BACK/EASE_OUT`, 6 px `#0F0E14` outline.
- Subtitle: `"Reached encounter %d of %d"`.
- Stat table, `label` left / `value` right, font 38, rows revealing 0.08 s apart with a slide-in from the left:

| Label | Source |
|---|---|
| Encounters cleared | `run_stats.encounters_cleared` |
| Run time | `run_stats.run_time`, formatted `M:SS` |
| Gold earned | `run_stats.gold_earned` |
| Gold spent | `run_stats.gold_spent` **[v2]** |
| Gold on hand | `GameState.gold` |
| Damage dealt | `run_stats.damage_dealt` |
| Damage taken | `run_stats.damage_taken` |
| Slot spins | `run_stats.slot_spins` |
| Slot wins | `run_stats.slot_wins` — **the raw count, with no percentage** |
| Upgrades bought | `run_stats.upgrades_bought` **[v2]** |
| Items found | `run_stats.items_found` |
| Items sold | `run_stats.items_sold` |

`_format_time` must split its integer division explicitly — `@warning_ignore("integer_division")` plus separate `minutes` and `seconds` locals — or it emits a warning and fails the gate.

The slot-win percentage is **gone** from this screen, per §17.8 / Q24.

- A **`RETRY`** button, 560 × 140, centred at the bottom.

### 18.3 Retry

Full reset, no carryover:

1. Free all combatants (including the hidden dead heroes from §12.5), projectiles, props, bars, floating elements and status icons.
2. `GameState.reset_run()` — gold → `Tuning.STARTING_GOLD`, inventory cleared, `hero_runtime` rebuilt at full HP, `current_encounter_index = -1`, `run_stats` zeroed, `level = build_level()`.
   - `run_stats["run_time"] = 0.0` needs an explicit branch; `0.0 if key == "run_time" else 0` is an incompatible ternary and will not compile.
3. `Upgrades.reset()` — every level back to 0. **[v2]**
4. Clear the slot's `_last_hero_hits`, return the slot to attract mode, cancel any party damage buff.
5. Reset the parallax tiles to their starting offsets.
6. Rebuild the inventory strip and the bonus strip from the (now empty) inventory; reset the slot counter; Sir Fish returns to `idle`.
7. `RunController` → `BOOT` → `TRAVEL`.

Verify **three consecutive retries** with `get_editor_errors` clean each time and `get_game_scene_tree` node counts stable. Leaked nodes between runs are the most likely bug here.

---

## 19. Verification tooling **[v2 — Q21]**

### 19.1 The problem, and the decision

**Q21 answered — yes to a harness, and no to "temporary". Build it permanently, gate it behind a flag.**

This MCP build has no `execute_editor_script` and no `execute_game_script`. v1's gates were written assuming both, so several gate items had no route at all: forcing each of the six animations per character, forcing the exact 100 HP / 20 damage case, killing a ranger's target mid-flight, forcing each of the six slot payouts, and reproducing §15.2's exact 200/250/300-vs-350 scenario.

The implementer proposed a temporary debug harness, removed after the gate. Do not build a temporary one. A harness that gets deleted gets rebuilt from scratch every session, and the deletion itself is a change nobody verifies. Build **`res://scripts/autoload/debug.gd`**, autoload `Debug`, registered last, and keep it. It costs roughly 150 lines and unblocks every gate in this milestone and every gate after it.

### 19.2 The `Debug` harness

The constraint that shapes the design: `set_game_node_property` can set a property but cannot call a function. So the harness exposes **one string property with a setter that parses and executes**:

```gdscript
extends Node
## Debug harness. Driven over MCP with:
##   set_game_node_property("/root/Debug", "command", "slot 0 0 0")
## Every command writes one "[DEBUG] ..." line to the output log, readable
## with get_output_log(). Inert in release builds.

var enabled: bool = OS.is_debug_build() \
    and bool(ProjectSettings.get_setting("sir_fish/debug/harness", true))

var command: String = "":
    set(value):
        command = value
        if enabled and not value.is_empty():
            _run(value)
```

Commands — verb first, space-separated arguments:

| Command | Effect | Unblocks |
|---|---|---|
| `anim <combatant_id> <name>` | Force `play_anim(name)` on the named living combatant, ignoring state | M6 gate: the six animations per character |
| `spawn <stats_id>` | Spawn that character at the first free enemy slot, idle, for animation review | M6 gate: reviewing enemies outside a fight |
| `sethp <combatant_id> <hp> [<max>]` | Set current (and optionally max) HP directly, no events | M6 gate: the 100 HP setup |
| `damage <combatant_id> <amount>` | `take_damage(amount, null)` with **no variance roll** | M6 gate: the exact 20-damage chunk |
| `kill <combatant_id>` | Force HP to 0 and run the death path | M6 gate: killing a ranger's target mid-flight |
| `slot <s0> <s1> <s2>` | Force the **next** spin's payline symbols (0 LIGHTNING, 1 GOLD, 2 PLUS, 3 BLANK), then clear the override | M6 gate: each of the six payouts |
| `shop <p0> <p1> <p2>` | Override the next shop's three **buy prices**, rewriting each item's `value` to `price / SHOP_BUY_MARKUP` | M7 gate: §15.2's exact scenario |
| `gold <n>` | Set `GameState.gold` and emit `gold_changed` | M7 gate: affordability transitions |
| `upgrade <id> <level>` | Set an upgrade level directly, no cost | M7 gate: payout scaling at max level |
| `additem [rarity]` | Generate and add one item, optionally forcing rarity | M7 gate: bonus aggregation |
| `equip <index>` | Flag `inventory[index].equipped = true` | M7 gate: the `sellable_items()` filter |
| `state` | Dump run state, HP of all combatants, gold, upgrade levels and party bonuses to the log | every gate |

`<combatant_id>` resolves against `stats.id`; if two are alive with the same id (two shadow monsters), suffix an index: `shadow_monster:1`.

Every command logs exactly one line, `[DEBUG] <verb> → <result>`, so `get_output_log` is the read channel. Unknown verbs log `[DEBUG] unknown command: <verb>` and change nothing.

**Release safety.** `enabled` is false in an exported release build, so `_run` returns immediately and no command has any effect. Do not add UI for it; it is MCP-only.

### 19.3 Headless tests

Two of v1's numeric gates were closed by running a test scene from a terminal rather than through MCP, and that route worked better than screenshots for anything with a number in it. **Ratify it as the standard.** Every numeric gate item is a headless test:

```bash
godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_slot_odds.tscn
```

Each test scene prints `PASS`/`FAIL` lines and exits with a non-zero code on failure.

| Test | Asserts | Status |
|---|---|---|
| `test_slot_odds` | 1,000,000 spins, win rate ∈ [0.490, 0.510]; per-symbol 3-of-a-kind ∈ [0.014, 0.021]; exhaustive enumeration = 9,849/19,683; strip counts 7/7/7/6 | exists — last run **0.50001** |
| `test_item_distribution` | 200 items: rarity split near 50/30/15/5; reports value and buy-price min/median/max; **no item carries a duplicate modifier id** (Q13) | exists — extend with the duplicate check and the 8-modifier pool |
| `test_damage_chunk` | §11.2's arithmetic for 100 HP hit for 20: chunk `x ∈ [108.8, 136.0]`, width 27.2, and for a spread of other HP/damage pairs | **new** |
| `test_retarget` | Projectile arrival with (a) a live target, (b) a dead target and others alive, (c) all enemies dead — no null access in any case | **new** |
| `test_economy` | Simulated run: 14 pre-shop spins at §5.4's payouts puts gold on hand ∈ [150, 260]; `generate_shop_stock()` produces at least one card affordable at that gold in ≥ 95% of 1,000 trials | **new** |
| `test_upgrades` | Cost curve matches §17.6's table exactly; `is_maxed` at level 3; payout maths at every level combination; `reset()` clears everything | **new** |

### 19.4 Known non-issues

`ERROR: Class name cannot be empty.` lines in the output log are emitted by the Godot MCP addon's own runtime inspector while it reflects over script-based nodes. They never appear during play that is not being queried over MCP. **They are not game bugs — do not go hunting for them.**

---

## 20. Milestones and verification gates

M0–M5 are built and verified. Work M6, M7, M8 in order. **Do not start a milestone until the previous gate passes.** For each gate: `play_scene`, drive it with `Debug` and the runtime tools, screenshot it, run the headless tests, and check `get_editor_errors` and `get_output_log` — **zero errors and zero warnings**.

### M6 — Ratification pass

Apply every answer in this document to the existing code. **No new features.** The complete list of code changes is §21.

Build: `Debug` (§19.2); the four new tests (§19.3); the outline alpha uniform (§6.3); `ModalLayer` → `Control` (§3.3); `display_font.tres` + the `DisplayLabel` variation (§6.5); the re-signed animation keys (§9.0–9.5); `required_anims()` (§8.3); the `ATTACKING` skip and `special_pending` (§10.2); `cancel_all_effects()` (§8.5); AoE stagger and number spreading (§9.7, §11.4); the special-cast telegraph (§9.6); attract mode (§16.6); `msaa_3d = 2` (§2); delete `demo_level.tres` (§12.1); the corrected stat table (§5.2).

**Gate:**
- All six animations forced on all six characters via `Debug` `anim`, screenshotted, and every limb visibly swings **in the screen plane** — this is the Q2 fix and it is the whole point of the milestone. `die` ends lying down and holds.
- `test_damage_chunk` and `test_retarget` pass headless.
- The defend icon disappears the instant the warrior dies (force with `Debug` `kill warrior` during the buff).
- An enemy death fades body **and** outline together — no ink silhouette left behind.
- A bomb arrow is distinguishable from a normal arrow in a mid-flight screenshot.
- The slot's reels are visibly moving in a screenshot taken during the shop encounter.
- `DEFEATED` at font 84 reads as a bold display face, not thin default sans.
- A full hands-off run completes with zero errors and zero warnings.

### M7 — Core-loop slice

Build: `Upgrades` (§17.6); `upgrade_tray.tscn`, `upgrade_button.tscn`, `bonus_strip.tscn`; item modifier effects (§13.5) including the three new `slot_*` modifiers and the `roll` key; `generate_shop_stock()` (§13.6); the §5.4 economy numbers; `sir_fish_tank.tscn` + `sir_fish.gd` with placeholder primitives (§17.7); `slot_counter.tscn` (§17.8); the summary changes (§18.2); `test_economy` and `test_upgrades`.

**Gate:**
- `test_economy`, `test_upgrades` and the extended `test_item_distribution` pass headless; report the rarity split and the value min/median/max with the 8-modifier pool.
- §15.2's worked example reproduced exactly via `Debug` `shop 200 250 300` + `gold 350`: buy the 250, confirm it reads `SOLD!` and that the 200 and 300 gray out.
- The Sell tab excludes an item flagged with `Debug` `equip 0`.
- Buy one level of each upgrade in a real run; confirm from the log that a subsequent lightning payout is scaled by Overcharge, a gold payout by Fat Purse, and that the spin cycle is measurably shorter. Confirm the win rate is unchanged — force 20 spins with `Debug` `slot` and confirm the strip is untouched.
- Pick up two chest items and confirm the bonus strip changes, hero damage numbers rise, and selling one reverses both.
- The party damage button drains 720 → 0 px over 30 s, is unclickable throughout, then re-enables — and the `dmg_pct` item bonus survives its expiry (this is what the divide-back-out rule protects).
- Sir Fish visibly `cheer`s on a slot win, `alarm`s on a hero hit, `grieve`s on a hero death, and `slump`s on game over. Screenshot each.
- Game over shows all twelve stats, **no slot percentage**, and Sir Fish slumped in the header. Retry three times with clean errors and stable node counts.

### M8 — Blender assets

Build §23, **one character at a time**, re-running the M6 gate after each swap.

**Gate:** side-by-side screenshots of every character before and after the swap. Every animation still plays under its original name, and `required_anims()`'s assert passes for all six characters. Sir Fish's modelled version reads as an armoured fish at 164 px. Frame rate at or above 60 fps via `get_performance_monitors`. The M6 and M7 gates re-run clean.

---

## 21. Change log — every difference from v1 and from the current build

**If you disagree with one of these, do not silently change it.** Implement as specified and append a note to the bottom of this section.

### 21.1 Owner-resolved

| # | Question | Decision |
|---|---|---|
| A1 | Platform and orientation | **Portrait mobile, 1080×1920**, touch-first, mouse emulation on for development. |
| A2 | Asset strategy | **Placeholder primitives first, Blender models last (M8).** The whole loop must be playable before modelling starts. |
| A3 | Boss | **A scaled-up orc barbarian** (`orc_warlord`): 1.70×, 280 HP, 22 damage, distinct colouring, shoulder pads. No new asset. |
| A4 | Document shape | **Phased build plan with verification gates** (§20). |
| A5 | Game over | **Run summary with full stats**, then a Retry that fully resets. |
| A6 | Equipment | **No equipping in the demo.** Items are loot, sell fodder, and — new in v2 — a party-wide bonus pool. The `equipped` field and `sellable_items()` filter exist and must work. |
| A7 | Console HUD | **Full status panel** — gold, inventory strip, per-hero rows. |
| A8 | Level length | **6 encounters** (§12.1). |
| **A9** | **The fish** | **Sir Fish is the player** — the console operator, not a hero. A fish in a tank on the console, reacting to state, with no gameplay effect. Resolves D16 and Q18. (§1.2, §17.7) |
| **A10** | **The core loop** | **Build a vertical slice**, not the full system: three purchasable slot upgrades plus item modifiers that feed hero damage and slot payouts. (§13.5, §17.6) |

### 21.2 Interpretations carried forward from v1

| # | Ambiguity | Resolution |
|---|---|---|
| D1 | Specials had no trigger condition | Every Nth action (warrior 3, ranger 4, priest 3), replacing that action's primary. |
| D2 | "Cooldowns start half full" would still sync identical enemies | Half full **× ±10% jitter**. Two shadow monsters with identical 1.8 s cooldowns would otherwise act on the same frame — the exact first-turn chaos the rule exists to prevent. |
| D3 | Priest heal with nobody wounded | Skip the special, use the primary, retain the pending special. **Mechanism changed in v2** — see C9. |
| D4 | "2 of the same icon" — adjacent or any two? | **Any two of the three positions.** Gives the 50.038% in §16.2. |
| D5 | Lightning "enemies are struck" — one or all? | **All living enemies.** |
| D6 | Lightning damage and the rolling buffer | **Excluded.** Including it compounds into a runaway loop. |
| D7 | Fewer than 3 hero strikes recorded | Average whatever exists; if zero, `SLOT_LIGHTNING_FALLBACK = 12`. |
| D8 | Ranger's target dying mid-flight | Retarget to a random living enemy; fizzle harmlessly if none remain. |
| D9 | Priest's darkening pass | **Implemented and on**, behind `PRIEST_DARKEN_ENABLED`. |
| D10 | Hero HP between encounters | **Persists.** No free heals. |
| D11 | Where the shop rerolls | Generated **once per shop encounter** and cached. |
| D12 | Party damage buff during non-combat | The 30 s timer is **real time** and runs through travel, loot and shop. |
| D13 | Party damage buff removal | Divide the multiplier back out, never reset to 1.0. **Now load-bearing** — §13.5's `dmg_pct` lives in the same multiplier. |
| D14 | Starting gold | **75** (was 50) — see C23. |
| D15 | Rarity/modifier multipliers | Rolled per item within the §13.2 ranges, with the enhancement TODO left verbatim in code. |
| ~~D16~~ | ~~No fish anywhere in "Sir Fish"~~ | **Resolved — see A9.** |

### 21.3 Changes v2 makes to the existing build

Every line below is a concrete edit to code that exists today.

| # | File(s) | Change |
|---|---|---|
| C1 | project settings | `msaa_3d` 1 → **2** (4× MSAA). Add `sir_fish/debug/harness = true`. |
| C2 | `combatant_animations.gd` | Re-author every clip against §9.0's re-derived signs. The Z axis is ratified; **the signs are not simply v1's magnitudes** — torso and limb rotations take opposite signs for the same physical direction. Update the file header to state the finished convention rather than citing QUESTIONS.md. |
| C3 | `combatant_animations.gd`, enemy scenes | Enemy X translations stay positive (forward = local +X). Ratified as built. |
| C4 | `combatant_rig.gd`, `combatant.gd` | `model_scale` on `Rig.scale`. Ratified as built. |
| C5 | `combatant_stats.gd`, `combatant.gd` | Add `required_anims()`; assert it in `setup()`. Remove any universal-name assumption. |
| C6 | `battle_director.gd`, `ability.gd` | Impacts scheduled **only** by `AnimationPlayer` method-call tracks. Delete any `SceneTreeTimer` impact path. |
| C7 | `game_state.gd`, filesystem | Delete `res://resources/levels/demo_level.tres` and the `levels/` folder. `build_level()` is canonical. |
| C8 | `battle_director.gd` | Skip combatants in `ATTACKING` in the tick loop (§10.2). Update §5.2's stat table comment to name the real cycle. |
| C9 | `combatant.gd`, `battle_director.gd` | Add `special_pending: bool`. Replace the `action_count -= 1` skip with the flag (§10.2). |
| C10 | `ability.gd`, `slot_machine.gd`, `battle_overlay.gd` | AoE stagger (`Tuning.AOE_STAGGER`) on the bomb arrow and the 3× party heal; damage-number anti-overlap offsets. |
| C11 | `run_controller.gd` | Ratified: dead heroes are hidden, never freed until Retry. Add a comment saying so, since the next reader will wonder. |
| C12 | §3.1 | Ratified: the extra files stay. The tree in §3.1 is now complete. |
| C13 | `itemizer.gd` | Ratified: modifiers without replacement. Add the duplicate-id assertion to `test_item_distribution`. |
| C14 | `itemizer.gd` | Add `generate_shop_stock()` with the forced rarity spread (§13.6). |
| C15 | `combatant.gd`, `status_icon.gd` | Add `cancel_all_effects()`; status icons register their owner and are freed on death. |
| C16 | `outline.gdshader`, `cel_materials.gd`, `smoke.gdshader` | Add `blend_mix` + an `alpha` uniform to the outline and smoke shaders. `set_alpha()` drives both passes; **stop scaling `outline_width`**. |
| C17 | `slot_machine.gd`, `slot_reel.gd` | Attract mode (§16.6): continuous slow drift, no stops, no evaluation, `SLOT_ATTRACT_DIM`, `OUT OF COMBAT` marquee. |
| C18 | new | Sir Fish: `sir_fish_tank.tscn`, `sir_fish.gd`, `water.gdshader` (§17.7). |
| C19 | `ability.gd`, `bomb_arrow.tscn` | Special-cast flash on every special; particle trail on the bomb arrow (§9.6). |
| C20 | `theme.tres`, new `display_font.tres` | `FontVariation` display face + the `DisplayLabel` type variation; apply to every string ≥ font 40 (§6.5). |
| C21 | new | `debug.gd` autoload + four new test scenes (§19). |
| C22 | `main.tscn` | `ModalLayer` `CanvasLayer` → `Control`, full rect, `mouse_filter = IGNORE`, last child. **Remove both per-modal `theme` assignments** — they become redundant and are the only hand-edited lines in the project. |
| C23 | `tuning.gd` | `STARTING_GOLD` 50 → **75**; `SLOT_PAY_2_GOLD` 25 → **35**; `SLOT_PAY_3_GOLD` 50 → **90**. Add `AOE_STAGGER`, `DAMAGE_NUMBER_SPREAD`, `SPECIAL_CAST_FLASH_TIME`, `SLOT_ATTRACT_SPEED`, `SLOT_ATTRACT_DIM`, the §5.7 upgrade block, and the fire/ice/fish palette entries. |
| C24 | `run_summary.gd`, new `slot_counter.tscn` | Remove the win percentage from the summary; add the console slot counter with the streak strip. Add `gold_spent` and `upgrades_bought` rows. |
| C25 | `item.gd`, `itemizer.gd`, `game_state.gd` | Store `roll` on every modifier; add the three `slot_*` modifiers; add `party_bonuses()` and `party_bonuses_changed`. |
| C26 | new + `console.tscn` | `Upgrades` autoload, `upgrade_tray.tscn`, `upgrade_button.tscn`, `bonus_strip.tscn`; wire the tray into the console and the bonus strip into the shop modal. |

### 21.4 Fixes from session 2 — keep these, do not regress them

These were real bugs found against the running game. Every one is a trap the next author can fall back into.

| Where | Trap |
|---|---|
| `shop_modal.tscn` | A script declared as an `ext_resource` but never assigned to the root node. The shop encounter hangs forever. Always verify with `attach_script`. |
| `shop_buy_card.tscn`, `shop_sell_row.tscn` | A `PanelContainer` force-resizes every child to fill it. The rarity edge must live in an `HBoxContainer` with `custom_minimum_size = (12, 0)`. §15.2 now specifies the structure. |
| `inventory_strip.gd` | Never tween `position:x` on a direct child of an `HBoxContainer`. Animate a wrapper inside a container-managed slot. |
| `inventory_strip.gd` | `reset_run()` clears the inventory array without per-item signals — rebuild on `run_started`. |
| `cel_materials.gd` | `flash()` must remember the base colour once via `set_meta("base_albedo")`. Reading the live albedo latches white in permanently after two overlapping flashes. §9.6 makes flashes more frequent, so this matters more in v2. |
| `slot_symbol.gd`, `status_icon.gd`, `buff_chip.gd` | `const X := PackedVector2Array([...])` is not a constant expression in 4.7 — use `static var`. The parse failure cascades into the class never registering. |
| everywhere | `var x := <call on an untyped variable>` is a hard parse error. Annotate explicitly. |
| `game_state.gd` | `0.0 if cond else 0` is an incompatible ternary. Use an explicit branch. |
| `event_bus.gd` | `@warning_ignore_start("unused_signal")` for the whole file. |
| `parallax_background.gd` | Never name a parameter `scale` in a `Node3D` script. |
| `run_summary.gd` | Split and annotate the integer division in `_format_time`. |

### 21.5 Substitution log — append below this line

*(Append any API substitution or forced deviation here, with the file and the reason. Do not rewrite entries above.)*

**Implementation pass, M6 + M7.** Full detail and the open questions live in
`QUESTIONS-v2.md`; this is the required index.

| # | File | Substitution / deviation | Why | QUESTIONS-v2 |
|---|---|---|---|---|
| S1 | `cel_shade.gdshader` | `depth_draw_opaque` → **`depth_draw_always`** | §6.3 adding `blend_mix` to the outline moved the inverted hull into the transparent pass, where `next_pass` draws it *after* the body. A transparent material with `depth_draw_opaque` writes no depth, so the hull had nothing to test against and every character rendered as a solid black silhouette. Verified on screen. §6.2 said to write that shader verbatim, so this needs ratification. | V11 |
| S2 | `scenes/main.tscn` | Hand-edited the `ModalLayer` node header and removed the two per-modal `theme =` lines | C22 changes a node's *type*, which needs delete-and-recreate. **This MCP build exposes no `delete_node`** despite `CLAUDE.md` listing one. The alternative was leaving an orphan `CanvasLayer` in the root scene. | V2 |
| S3 | `project.godot` `[autoload]` | `Upgrades` is registered *after* `GameState`, not before | `add_autoload` only appends and there is no reorder/remove tool. Behaviourally identical: nothing reads a payout at `_ready()`. | V1 |
| S4 | `project.godot` | `msaa_3d` stored as `2.0` (TYPE_FLOAT) rather than `2` (TYPE_INT) | `set_project_setting` coerces every numeric argument to float. Godot casts it back to 2, so 4x MSAA is applied. | V3 |
| S5 | `resources/levels/` | **Not deleted.** | C7's deletion was blocked by the session's command permissions and no MCP tool deletes a `.tres`. Nothing loads the file, so `build_level()` is already canonical in behaviour. Needs one manual `rm`. | V4 |
| S6 | `sir_fish_tank.tscn` | Added `own_world_3d = true`, a `WorldEnvironment`, and a water backdrop disc | §17.7's listing omits `own_world_3d`, so the tank rendered the battlefield inside the bowl. The other two follow from that fix. Additive only. | V12 |
| S7 | `tests/test_economy.gd` | Asserts the **mean over 1,000 simulated runs**, not a single 14-spin sample | §19.3's literal assertion is stochastic: the measured single-run spread is min 75 / median 145 / max 450, so a literal test fails at random. The mean lands at 169.4, inside §19.3's [150, 260]. | V10 |
| S8 | `tests/*.gd` | `TestSupport` is `preload`ed rather than a `class_name` | A newly-added global class is not in the class cache when a headless run starts, so `class_name` resolution fails from the command line. | — |
| S9 | `scripts/autoload/debug.gd` | `shop` picks the `value` that round-trips to the requested price | §19.2's `price / SHOP_BUY_MARKUP` does not round-trip through an int `value`: 250 became 251. | V13 |
| S10 | `Upgrades`, `party_bonuses()`, `roll` key | Built during **M6** rather than M7 | §19.2's `Debug` command table (`upgrade`, `additem`, `state`) references them, so M6 cannot compile without them. The M7 *UI* stayed in M7. | V8 |

**Interpretations taken where the document was ambiguous** (all recorded in
`QUESTIONS-v2.md`, none changed silently): the priest-only guard on §10.2's skip
rule (V6); limb translations read as deltas from the limb's home position (V7);
`ModalLayer` before `RunController` per §3.3's tree (V5); five bonus-strip glyphs,
not six, because `element` has no numeric value (V9).

---

## 22. Deferred — build the seam, not the feature

- **Equipping weapons on heroes.** `Item.equipped` exists; `sellable_items()` filters on it; no UI. v2's item bonuses apply to the whole inventory precisely so that equipping is not needed yet.
- **Potions and relics.** `Item.Kind` includes them; `Itemizer` never produces them.
- **Diminishing returns on inventory bonuses.** §13.5's aggregate is a straight sum, which is correct at the demo's ≤5-item inventory. A build where the inventory grows large needs a curve. Leave the sum; note the need.
- **Additional slot machines.** The demo ships one.
- **A deeper upgrade tree.** Three upgrades at three levels is a vertical slice, not the system. The seam is `Upgrades.DEFS` — adding an entry and a button is all a fourth upgrade needs.
- **Upgrades that change the odds.** Nothing may touch `SLOT_STRIP` or the win rule; §16.2's 50.038% is proved and tested. A future "more often" beyond Quick Reels needs a second payline or a second machine, and a fresh proof.
- **Branching maps and a visible level map.** `GameState.build_level()` is the single function a generator replaces.
- **Multiple levels.** One level, six encounters.
- **Re-tuned cooldowns.** §5.2 documents real cycle times that differ from the nominal `attack_cooldown`; the numbers are deliberately not retuned without playtest data. Revisit with the data.
- **Designed (non-random) rarity and modifier multipliers** — see the TODO in §13.2.
- **Elemental resistances.** `element` is cosmetic in v2 (it recolours damage numbers). Resistances are the obvious next step and the reason the elements are stored separately rather than summed into one number.
- **Audio.** No sound in the demo. Do not add an `AudioStreamPlayer` anywhere.
- **Saving.** Nothing persists across application restarts, including upgrades.

---

## 23. Blender asset pipeline (M8)

Only start after M7 passes. Everything before this runs on primitives.

### 23.1 Rules

- All modelling happens in `C:\Projects\Godot\Sir Fish\blender\Sir Fish.blend` via the Blender MCP tools (`execute_blender_code`, `get_objects_summary`, `render_viewport_to_path`, `get_screenshot_of_window_as_image`).
- **Current file state, verified:** the default `Cube` is already deleted; `Camera` and `Light` remain in `Collection`; the collections `Heroes`, `Enemies`, `Props`, `Environment` exist and are empty. **Add a fifth collection, `Console`, for Sir Fish and his tank.**
- Everything is **low-poly, hard-surface, flat-shaded**, built for cel shading: chunky silhouettes, no bevel-heavy detail, no normal maps, no textures — **vertex colours or per-material flat colours only**, using §6.1's palette exactly.
- The camera is a fixed side view, so do not model detail never visible from −Z — but **keep both sides symmetric**, because heroes and enemies face opposite directions and share one clip set (§9.0).
- Character height: **1.8 Blender units at scale 1.0**, feet at the origin, facing **+X**.

### 23.2 Rigging and animation

- One armature per character. Bone names, exactly:
  `Root, Hips, Spine, Chest, Head, Shoulder.L, Arm.L, Hand.L, Shoulder.R, Arm.R, Hand.R, Thigh.L, Shin.L, Foot.L, Thigh.R, Shin.R, Foot.R`
  Weapons parent to `Hand.R` (main) and `Hand.L` (off).
- **Author every clip in the screen plane**, matching §9.0. A limb swing that reads correctly in Godot swings about the axis perpendicular to the camera; if it swings toward the lens in Blender it will be invisible in game. Check each action from a −Z orthographic view in Blender before exporting — that view is what the player sees.
- Author actions named exactly `idle`, `run`, `attack`, `special`, `hurt`, `die`, at the lengths in §5.2 and §8.3, **only for the names `CombatantStats.required_anims()` requires for that character**. Do not author `run` or `special` for enemies.
- Shadow monster: no armature. Animate via shape keys and object transforms, exporting actions under the same names.
- Orc barbarian and orc warlord share one mesh, one armature and one action set. The warlord differs only by `model_scale`, colours, shoulder pads and `speed_scale` (§8.7).

### 23.3 Export

- Export each character as glTF 2.0 (`.glb`) to `res://assets/meshes/`, `+Y up`, animations included, modifiers applied.
- In Godot, configure each import to generate a scene with an `AnimationPlayer`, then **swap the placeholder `Rig` node in each character scene for the imported model** and reassign the cel + outline materials. `combatant.gd`, `battle_director.gd`, and every animation *name* stay unchanged. `model_scale` still lands on `Rig.scale` (§8.2), so the swap needs no scale rework.
- After each swap, re-run the M6 gate for that character before touching the next one.

### 23.4 Environment meshes

Replace the five parallax layers' placeholder quads with tiling meshes: rolling hill silhouettes, two conifer variants and one broadleaf, ground with scattered rocks and grass tufts, and foreground bushes. Each tile must be **exactly `tile_width` (12.0) units wide** and seamless at its edges — §7.4's wrap logic depends on it.

### 23.5 Sir Fish

In the `Console` collection, at a scale where the whole fish is roughly **0.34 units long**, so he reads at 164 px through §17.7's orthographic `size 1.4` camera.

- **Body:** a chunky, rounded, low-poly fish — deep-bellied and short, not a streamlined torpedo. He should read as slightly pompous. Scales `#4A9BE8`, fins and tail `#3B6FD4`.
- **Armour:** a knight's helm `#8C94A3` with a dark `#0F0E14` visor slit, sized so the silhouette is unmistakably *fish plus helmet* at 164 px, and a `#F2C230` circlet around it. This is the whole joke; if the helm is not obvious in a 164 px render, make it bigger.
- **Rig:** a two-bone armature, `Root` and `Tail`, plus optional `Fin.L` / `Fin.R`. Actions named exactly `idle`, `cheer`, `smug`, `alarm`, `grieve`, `slump`, `triumph`, at §17.7's lengths.
- **Tank:** a rounded bowl, a gold base ring, a gravel bed, and a small gold plaque. The plaque reads `SIR FISH` — model the plaque, draw the text with a `Label3D` in Godot so no font asset is baked into the mesh.
- **`slump` must end with the helm on the gravel.** Animate it as a separate object with its own action, or key its parent constraint off at the end of the clip.

**Gate for this asset specifically:** render Sir Fish at 164 × 164 with `render_thumbnail_to_path` and confirm he reads as an armoured fish at that size, before rigging anything.

---

*End of specification. `QUESTIONS.md` is now closed — every question in it is answered above. Open a fresh questions file for v2 rather than appending to it, and follow the same discipline: implement as specified, record every deviation with the file and the reasoning, and change nothing silently.*


