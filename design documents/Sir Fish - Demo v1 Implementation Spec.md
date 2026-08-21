# Sir Fish — Demo v1 Implementation Specification

**Document type:** build prompt for an implementing model
**Project:** `C:\Projects\Godot\Sir Fish` (Godot 4.x, Forward+)
**Source:** derived from `design documents/initial vision.txt`, with open questions resolved by the project owner (James). See §21 for every decision made beyond the source doc.

---

## 0. How to use this document

You are implementing the **Sir Fish demo** in an existing, effectively empty Godot project. This document is the complete specification. **Do not invent behavior that is specified here, and do not leave specified behavior unimplemented.** Where this document gives a number, use that exact number. Where it gives a name, use that exact name.

### 0.1 Non-negotiable working rules

1. **Use the Godot MCP Pro tools for all Godot work.** Read `CLAUDE.md` at the project root first — it lists the full editor/runtime toolset and the pitfalls. In particular:
   - Never edit `project.godot` by hand. Use `set_project_setting`.
   - Prefer `update_property` (inspector values) over hardcoding visual values in scripts. Scripts should hold *logic*; scenes should hold *configuration*.
   - Runtime tools (`get_game_screenshot`, `simulate_mouse_click`, `execute_game_script`, …) require `play_scene` first.
   - Use explicit type annotations in for-loops: `for hero: Combatant in heroes:`.
2. **Use the Blender MCP tools for all 3D asset work** (Milestone M6). Do not download, import, or reference any third-party asset. Every mesh, texture, icon, and material in this game must be generated — procedurally in Godot, or modeled in Blender via MCP.
3. **Verify visually, every milestone.** Each milestone in §20 has a *Verification gate*. You must `play_scene`, drive the game with runtime tools, take `get_game_screenshot` captures, and confirm each gate item before moving on. Also run `get_editor_errors` and `get_output_log` and fix everything reported — the gate is not passed while errors or warnings exist.
4. **Check `get_editor_errors` after every script write.** Use `validate_script` before `save_scene`.
5. **Commit tuning values to one place.** All balance numbers live in `res://scripts/autoload/tuning.gd` (§5). No magic numbers scattered through gameplay code.

### 0.2 Engine version

`project.godot` currently declares `config/features=PackedStringArray("4.7", "Forward Plus")`. The project brief says Godot 4.6. **Target whichever version the installed editor reports from `get_project_info` and do not attempt to change the declared feature set.** Everything in this spec uses APIs stable across Godot 4.4+. If any API in this document does not exist in the installed version, use the nearest equivalent and record the substitution in §21's log at the bottom of this file (append to it; do not rewrite it).

### 0.3 Scope discipline

This is a **demo**, not the game. Build exactly what is specified. Systems marked *Deferred* in §22 must be structurally accommodated (data fields present, seams left open) but must not be implemented.

---

## 1. What the game is

**Sir Fish** is an autobattler crossed with a slot-machine incremental.

- The **top third** of the screen is an autobattler: a party of three heroes travels left-to-right through a sequence of encounters and fights without any player input.
- The **bottom two thirds** is the **management console**: a slot machine that spins continuously during combat and pays out in damage, gold, and healing, plus buttons that buy the party temporary advantages.

The player never controls the heroes. The player's entire agency lives in the console. The fantasy is *running the war room while the heroes do the fighting*.

### 1.1 Design pillars (use these to break ties)

1. **Legibility over spectacle.** A player must be able to read what happened in combat at a glance. This is why cooldowns start staggered, why every hit detaches a visible chunk of health bar, and why targeting is simple.
2. **The console is always doing something.** Even when the player isn't tapping, the slot is spinning and paying out. Dead air is a bug.
3. **Juice on every state change.** Chests pop, bars detach and float, lightning cracks, symbols slam into place. Nothing appears or disappears without a tween.
4. **Bold, flat, primary color.** Positive references: *Breath of the Wild*, *CrossCode*, *Monster Train*. Negative references: *DOOM*, *Halls of Torment*, *Voin*. If it reads as gritty, desaturated, or brown, it is wrong.

---

## 2. Target platform and project settings

**Portrait mobile, 1080 × 1920.** Touch-first, but must be fully playable with a mouse in the editor (Godot maps mouse to touch when emulation is on, and all interactive elements are `Control` nodes with `gui_input` / `pressed` signals, so this is free).

Apply these with `set_project_setting`:

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
| `rendering/anti_aliasing/quality/msaa_3d` | `2` (2× MSAA — outlines need it) |
| `rendering/environment/defaults/default_clear_color` | `Color(0.494, 0.784, 0.890)` (`#7EC8E3`) |
| `input_devices/pointing/emulate_touch_from_mouse` | `true` |
| `application/run/main_scene` | `res://scenes/main.tscn` |
| `application/config/name` | `Sir Fish` (already set) |
| `physics/common/physics_ticks_per_second` | `60` |

The window override (540×960) exists so the game window fits on a development monitor while the logical viewport stays 1080×1920. All layout coordinates in this document are in **logical viewport pixels (1080×1920)**.

### 2.1 Screen budget (exact, sums to 1920)

| Region | Y range | Height | Owner |
|---|---|---|---|
| Battle viewport | 0 – 640 | 640 | `BattleView` (3D SubViewport) |
| Divider | 640 – 648 | 8 | `ConsoleDivider` (gold bar) |
| Status panel | 648 – 948 | 300 | `StatusPanel` |
| Slot machine | 948 – 1548 | 600 | `SlotMachine` |
| Party damage button | 1548 – 1708 | 160 | `PartyDamageButton` |
| Reserved upgrade area | 1708 – 1920 | 212 | `UpgradeTray` (empty in demo, see §22) |

640 is exactly one third of 1920, satisfying the "top third / bottom two thirds" requirement.

---

## 3. Architecture

### 3.1 Directory layout

Create exactly this structure. Do not deviate from these paths — later sections reference them literally.

```
res://
├── assets/
│   ├── materials/          # .tres materials (cel-shaded, per palette entry)
│   ├── meshes/             # .glb exports from Blender (M6); empty until then
│   └── shaders/
│       ├── cel_shade.gdshader
│       ├── outline.gdshader
│       ├── smoke.gdshader
│       └── parallax_layer.gdshader
├── scenes/
│   ├── main.tscn                       # root
│   ├── battle/
│   │   ├── battle_view.tscn            # SubViewportContainer + SubViewport + world
│   │   ├── battle_world.tscn           # Node3D: camera, lights, env, slots, parallax
│   │   ├── parallax_background.tscn
│   │   ├── combatant.tscn              # base combatant (see §7.1)
│   │   ├── heroes/
│   │   │   ├── warrior.tscn
│   │   │   ├── ranger.tscn
│   │   │   └── priest.tscn
│   │   ├── enemies/
│   │   │   ├── shadow_monster.tscn
│   │   │   ├── orc_barbarian.tscn
│   │   │   └── orc_warlord.tscn         # boss (scaled orc barbarian variant)
│   │   ├── props/
│   │   │   └── treasure_chest.tscn
│   │   └── projectiles/
│   │       ├── arrow.tscn
│   │       └── bomb_arrow.tscn
│   ├── overlay/
│   │   ├── battle_overlay.tscn         # 2D bars layer over the battle viewport
│   │   ├── combatant_bars.tscn         # health + cooldown pair
│   │   ├── floating_health_chunk.tscn
│   │   ├── damage_number.tscn
│   │   └── status_icon.tscn            # defend shield / heal plus overlays
│   ├── console/
│   │   ├── console.tscn
│   │   ├── status_panel.tscn
│   │   ├── hero_status_row.tscn
│   │   ├── inventory_strip.tscn
│   │   ├── slot_machine.tscn
│   │   ├── slot_reel.tscn
│   │   ├── slot_symbol.tscn
│   │   └── party_damage_button.tscn
│   └── modals/
│       ├── shop_modal.tscn
│       ├── shop_buy_card.tscn
│       ├── shop_sell_row.tscn
│       ├── item_tooltip.tscn
│       └── run_summary.tscn
├── scripts/
│   ├── autoload/
│   │   ├── tuning.gd            # Tuning   — all balance constants
│   │   ├── event_bus.gd         # EventBus — global signals
│   │   ├── game_state.gd        # GameState— party, gold, inventory, run progress
│   │   ├── itemizer.gd          # Itemizer — item generation
│   │   └── rng.gd               # RNG      — seeded RandomNumberGenerator wrapper
│   ├── data/
│   │   ├── combatant_stats.gd   # Resource
│   │   ├── item.gd              # Resource
│   │   ├── encounter_def.gd     # Resource
│   │   └── level_def.gd         # Resource
│   ├── battle/
│   │   ├── combatant.gd
│   │   ├── ability.gd
│   │   ├── battle_director.gd
│   │   ├── parallax_background.gd
│   │   └── projectile.gd
│   ├── run/
│   │   └── run_controller.gd
│   ├── console/ ...
│   └── modals/ ...
└── resources/
    ├── stats/                   # .tres CombatantStats per character
    └── levels/
        └── demo_level.tres
```

### 3.2 Autoloads

Register in this order (order matters — `Tuning` and `RNG` must exist before `GameState`):

| Name | Path |
|---|---|
| `Tuning` | `res://scripts/autoload/tuning.gd` |
| `RNG` | `res://scripts/autoload/rng.gd` |
| `EventBus` | `res://scripts/autoload/event_bus.gd` |
| `Itemizer` | `res://scripts/autoload/itemizer.gd` |
| `GameState` | `res://scripts/autoload/game_state.gd` |

The three `MCP*` autoloads already present must be left untouched.

### 3.3 Root scene tree (`res://scenes/main.tscn`)

```
Main (Control, anchors full rect, mouse_filter = IGNORE)
├── BattleView (SubViewportContainer)          # pos (0,0)   size 1080×640, stretch=true
│   └── BattleViewport (SubViewport)           # size 1080×640, transparent_bg=false
│       └── BattleWorld (Node3D)               # instance of battle_world.tscn
├── BattleOverlay (Control)                    # pos (0,0)   size 1080×640, mouse_filter=IGNORE
│   ├── BarsLayer (Control)
│   ├── FloatingLayer (Control)                # detached health chunks, damage numbers
│   └── VfxLayer (Control)                     # status icons
├── ConsoleDivider (ColorRect)                 # pos (0,640)  size 1080×8   color #F2C230
├── Console (Control)                          # pos (0,648)  size 1080×1272
│   ├── StatusPanel (PanelContainer)           # pos (0,0)    size 1080×300
│   ├── SlotMachine (Control)                  # pos (0,300)  size 1080×600
│   ├── PartyDamageButton (Button)             # pos (180,900) size 720×160
│   └── UpgradeTray (HBoxContainer)            # pos (0,1060) size 1080×212  (empty)
├── ModalLayer (CanvasLayer, layer = 10)
│   ├── ShopModal (hidden by default)
│   └── RunSummary (hidden by default)
└── RunController (Node)                       # run_controller.gd — drives everything
```

**Why a SubViewport:** the battlefield is 3D and must be clipped to the top 640px without the console bleeding into it, and the 2D health bars need pixel-exact placement over 3D characters. `BattleView` and `BattleOverlay` are the same size at the same position, so a point returned by `camera.unproject_position()` in viewport space maps **1:1** into `BattleOverlay` local coordinates with no extra transform.

### 3.4 EventBus signals

Define exactly these in `event_bus.gd`. All cross-system communication goes through them — no direct node-path lookups between the battle and the console.

```gdscript
extends Node

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

# --- Console ---
signal slot_spin_started()
signal slot_spin_stopped(symbols: Array)       # Array[int] of 3 SlotSymbol enum values
signal slot_payout(kind: String, count: int)   # kind in "lightning"|"gold"|"heal"
signal party_damage_buff_started(duration: float)
signal party_damage_buff_ended()
```

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
@export var attack_cooldown: float = 1.5      # seconds between actions
@export var special_every_n_actions: int = 0  # 0 = no special
@export var model_scale: float = 1.0
@export var body_color: Color = Color.WHITE
@export var accent_color: Color = Color.WHITE
@export var scene_path: String = ""
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
@export var modifiers: Array[Dictionary] = []# [{ "id": &"dmg_flat", "label": "+4 Damage", "value_mult": 0.42 }, ...]
@export var value: int = 0                   # computed intrinsic gold value
@export var equipped: bool = false           # always false in the demo (§13.6)

func subtitle() -> String:
    # "Magic Sword", "Common Bow" — rarity + type, per the source doc
    return "%s %s" % [rarity_name(), type_name()]

func rarity_name() -> String:
    return ["Common", "Uncommon", "Magic", "Rare"][rarity]

func type_name() -> String:
    # Weapons read as their weapon type ("Sword"); the deferred kinds fall back
    # to the kind name, so "Magic Potion" / "Rare Relic" work the day they exist.
    if kind == Kind.WEAPON and weapon_type != &"":
        return String(weapon_type).capitalize()
    return ["Weapon", "Potion", "Relic"][kind]
```

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

Owns everything that survives an encounter.

```gdscript
extends Node

var gold: int = 0
var inventory: Array[Item] = []
var hero_runtime: Array = []       # Array of Dictionaries: {stats_id, current_hp, max_hp, alive}
var current_encounter_index: int = -1
var level: LevelDef
var run_stats := {
    "encounters_cleared": 0,
    "gold_earned": 0,
    "damage_dealt": 0,
    "damage_taken": 0,
    "slot_spins": 0,
    "slot_wins": 0,
    "items_found": 0,
    "items_sold": 0,
    "run_time": 0.0,
}

func add_gold(amount: int) -> void      # emits gold_changed, tracks run_stats.gold_earned
func spend_gold(amount: int) -> bool    # returns false and changes nothing if insufficient
func add_item(item: Item) -> void
func remove_item(item: Item) -> void
func sellable_items() -> Array[Item]    # inventory.filter(func(i): return not i.equipped)
func reset_run() -> void                # full reset: §18
```

**Hero HP persists across encounters.** There is no between-encounter heal. Healing comes only from the priest and the slot machine. This is deliberate — it makes the slot's heal payouts matter.

---

## 5. Tuning — single source of truth

Everything below lives in `res://scripts/autoload/tuning.gd` as `const` values. **No other file may hardcode these numbers.**

### 5.1 Timing

```gdscript
const TRAVEL_SPEED := 4.0                 # world units/sec the parallax scrolls at full speed
const TRAVEL_ACCEL_TIME := 0.6            # ease-in when travel starts
const TRAVEL_DECEL_TIME := 0.9            # ease-out when arriving at an encounter
const ENEMY_FADE_IN_TIME := 0.35
const ENEMY_DEATH_HOLD := 1.5             # corpse lies still before fading (source doc)
const ENEMY_DEATH_FADE := 2.0             # then fades out over this long, then queue_free
const BARS_POP_IN_TIME := 0.25
const COOLDOWN_START_FRACTION := 0.5      # every combatant starts half-charged
const COOLDOWN_START_JITTER := 0.10       # ±10% (see §21-D2)
const HURT_ANIM_TIME := 0.30
const DEAD_HERO_EXIT_TIME := 1.6          # dead heroes slide off the left edge
const ENCOUNTER_RESOLVE_PAUSE := 0.8      # beat between "cleared" and travel starting
```

### 5.2 Combatant stats

| id | display_name | hero | max_hp | base_damage | attack_cooldown | special_every_n | model_scale |
|---|---|---|---|---|---|---|---|
| `warrior` | Warrior | yes | 120 | 12 | 1.6 | 3 | 1.00 |
| `ranger` | Ranger | yes | 80 | 14 | 1.4 | 4 | 0.95 |
| `priest` | Priest | yes | 70 | 10 | 2.0 | 3 | 0.95 |
| `shadow_monster` | Shadow Monster | no | 40 | 8 | 1.8 | 0 | 0.90 |
| `orc_barbarian` | Orc Barbarian | no | 70 | 15 | 2.4 | 0 | 1.15 |
| `orc_warlord` | Orc Warlord | no | 280 | 22 | 2.0 | 0 | 1.70 |

### 5.3 Ability tuning

```gdscript
const WARRIOR_DEFEND_REDUCTION := 0.50    # incoming damage × (1 - 0.50)
const WARRIOR_DEFEND_DURATION := 4.0
const RANGER_BOMB_AOE_MULT := 0.75        # bomb arrow hits every enemy for base_damage × 0.75
const PRIEST_HEAL_MULT := 1.0             # heal = priest current damage × 1.0 (source doc: "same strength")
const PRIEST_DARKEN_ENABLED := true       # §9.3 — battlefield darkens under the lightning bolt
const DAMAGE_VARIANCE := 0.15             # every hit rolls damage × randf_range(0.85, 1.15), rounded
```

### 5.3b Battlefield geometry

```gdscript
const HERO_SLOT_X := [-4.2, -3.0, -1.8]   # priest, ranger, warrior (left → right)
const ENEMY_X_MIN := 1.6
const ENEMY_X_MAX := 4.8
const MAX_ENEMIES := 3
```

### 5.4 Economy

```gdscript
const STARTING_GOLD := 50
const SHOP_BUY_MARKUP := 1.5              # buy price  = round(value × 1.5)
const SHOP_SELL_RATE := 0.5               # sell price = round(value × 0.5)
const LOOT_ITEMS_PER_CHEST := 2
const SHOP_ITEMS_FOR_SALE := 3
```

### 5.5 Slot machine

```gdscript
const SLOT_REEL_STOPS := 27
const SLOT_STRIP := [ ... ]               # see §16.2 — 27 entries, 7/7/7/6
const SLOT_SPIN_DURATION := 1.10          # reel 1 stop time
const SLOT_REEL_STAGGER := 0.28           # reel 2 stops +0.28s, reel 3 stops +0.56s
const SLOT_RESULT_HOLD := 0.85            # pause after reel 3 stops before the next spin
const SLOT_PAY_2_GOLD := 25
const SLOT_PAY_3_GOLD := 50
const SLOT_HEAL_2_FRACTION := 0.25        # lowest-hp hero healed 25% of max
const SLOT_HEAL_3_FRACTION := 0.25        # entire party healed 25% of max
const SLOT_LIGHTNING_2_MULT := 1.0        # damage = avg(last 3 hero strikes) × 1.0
const SLOT_LIGHTNING_3_MULT := 2.0        # × 2.0
const SLOT_LIGHTNING_FALLBACK := 12       # used if fewer than 1 hero strike recorded
```

### 5.6 Party damage button

```gdscript
const PARTY_DAMAGE_BUFF_MULT := 1.10      # +10%
const PARTY_DAMAGE_BUFF_DURATION := 30.0
```

---

## 6. Art direction

### 6.1 Palette (use these hex values literally)

| Role | Hex | Notes |
|---|---|---|
| Sky | `#7EC8E3` | also the viewport clear color |
| Far hills | `#4A9E6F` | parallax layer 1 |
| Mid trees | `#2E8B57` | parallax layer 2 |
| Near trees | `#1E6B45` | parallax layer 3 |
| Ground | `#8FBF4F` | parallax layer 4 (the strip heroes stand on) |
| Foreground brush | `#14532D` | parallax layer 5, in front of characters |
| Outline / ink | `#0F0E14` | inverted-hull outline color, everywhere |
| Warrior armor | `#4A6FA5` | steel blue |
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
| Console bg | `#231F2E` | |
| Console panel | `#332C42` | |
| Text primary | `#FFF6E0` | |
| Text dim | `#9B93AE` | |

**Do not desaturate.** If a color needs to recede, shift it toward the sky blue, not toward gray.

### 6.2 Cel shader — `res://assets/shaders/cel_shade.gdshader`

Write exactly this:

```glsl
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

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

To fade a character out (enemy death, enemy fade-in), tween the `alpha` uniform and set the material's `render_mode` variant — because `specular_disabled`/opaque cannot fade, **create a second material `cel_shade_transparent.tres`** from the same shader with `render_mode blend_mix, depth_draw_opaque, cull_back, specular_disabled` and swap `MeshInstance3D.material_override` to it for the duration of the fade. Simpler alternative that is also acceptable: keep one transparent variant and use it always, accepting the sorting cost — the scene has fewer than 40 meshes so this is fine. **Pick the always-transparent variant** unless you observe sorting artifacts in a verification screenshot.

### 6.3 Outline shader — `res://assets/shaders/outline.gdshader`

```glsl
shader_type spatial;
render_mode cull_front, depth_draw_opaque, unshaded;

uniform vec4 outline_color : source_color = vec4(0.059, 0.055, 0.078, 1.0);
uniform float outline_width : hint_range(0.0, 0.2) = 0.018;

void vertex() {
    VERTEX += normalize(NORMAL) * outline_width;
}

void fragment() {
    ALBEDO = outline_color.rgb;
}
```

Attach via `material.next_pass = outline_material` on every character and prop material. Because the camera is orthographic, a constant world-space width produces a constant screen-space width — no distance compensation needed.

### 6.4 Lighting and environment

`BattleWorld` contains:

- `WorldEnvironment` with a new `Environment`:
  - `background_mode = BG_COLOR`, `background_color = #7EC8E3`
  - `ambient_light_source = AMBIENT_SOURCE_COLOR`, `ambient_light_color = #A8D8E8`, `ambient_light_energy = 0.55`
  - `tonemap_mode = TONE_MAPPER_LINEAR` (do **not** use filmic/ACES — it desaturates the primaries)
  - `glow_enabled = true`, `glow_intensity = 0.5`, `glow_bloom = 0.15`, `glow_hdr_threshold = 1.1` (makes the lightning and shadow-eyes emission pop)
  - `adjustment_enabled = true`, `adjustment_saturation = 1.15`
- `DirectionalLight3D` named `KeyLight`: rotation `(-40°, -35°, 0°)`, energy `1.4`, color `#FFF3D6`, `shadow_enabled = true`, `directional_shadow_mode = SHADOW_ORTHOGONAL`, `shadow_bias = 0.03`
- `DirectionalLight3D` named `FillLight`: rotation `(-20°, 145°, 0°)`, energy `0.35`, color `#9BC8F5`, `shadow_enabled = false`

### 6.5 Typography

No font files may be shipped (generated assets only), so use Godot's built-in default font throughout, sized per §15/§17 and colored per §6.1. Set a project-wide `Theme` at `res://assets/theme.tres` with:

- `default_font_size = 34`
- `Label/colors/font_color = #FFF6E0`
- `Button` StyleBoxFlat: `bg_color = #4A6FA5`, `corner_radius_* = 16`, `border_width_* = 4`, `border_color = #F2C230`, content margins 24/24/18/18
- `Button:disabled` StyleBoxFlat: `bg_color = #3A3548`, `border_color = #5C5470`, font color `#7A7290`
- `PanelContainer` StyleBoxFlat: `bg_color = #332C42`, `corner_radius_* = 20`, `border_width_* = 3`, `border_color = #4A4260`

Assign it to `Main.theme` so every descendant inherits it.

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
├── EnemyRoot (Node3D)              # enemies parented here, positioned by §7.3
├── PropRoot (Node3D)               # chest / shop building spawn here
└── ProjectileRoot (Node3D)
```

**Hero order is fixed left-to-right: Priest, Ranger, Warrior** (source doc). Note that this places the warrior *closest to the enemies*, which reads correctly as a front line.

### 7.2 `BattleCamera` (Camera3D)

| Property | Value |
|---|---|
| `projection` | `PROJECTION_ORTHOGONAL` |
| `size` | `6.5` (vertical extent in world units) |
| `near` / `far` | `0.05` / `200.0` |
| `position` | `(0.0, 2.2, 12.0)` |
| `rotation` | `(0, 0, 0)` — dead-on side view, no tilt |

Derived, and relied on elsewhere: viewport aspect = 1080/640 = **1.6875**, so horizontal extent = 6.5 × 1.6875 = **10.97 units**, half-width = **±5.48**. Visible vertical range = **y ∈ [-1.05, 5.45]**. Ground plane is `y = 0`. A 1.0-scale character is **1.8 units tall**.

Do not add camera shake in the demo except where §11.4 specifies it.

### 7.3 Enemy slot placement (works for any count)

```gdscript
func enemy_slot_x(index: int, total: int) -> float:
    if total <= 1:
        return (Tuning.ENEMY_X_MIN + Tuning.ENEMY_X_MAX) * 0.5     # 3.2
    return Tuning.ENEMY_X_MIN \
        + (Tuning.ENEMY_X_MAX - Tuning.ENEMY_X_MIN) * (float(index) / float(total - 1))
```

Verified against §7.2's camera: the rightmost enemy at `x = 4.8` plus a ~0.4 half-width sits at 5.2, inside the ±5.48 half-extent; the leftmost hero at `x = -4.2` sits at -4.6, also inside. Nobody clips the frame edge, including the 1.70× warlord (its half-width is ~0.7, so at the `total == 2` position of 4.8 it reaches 5.5 — **place the warlord at index 0 and the shadow monster at index 1** in the boss encounter, i.e. list `orc_warlord` first in `enemy_stat_ids`, which puts the big model at x = 1.6 and keeps it well inside frame).

Enemies always face **-X** (toward the heroes); heroes always face **+X**. Implement facing by setting `rotation.y` to `PI` for one side, not by negative scale (negative scale breaks the inverted-hull outline normals).

### 7.4 Parallax background

Orthographic projection gives no free parallax, so it is faked by scroll speed. Five layers, each a `Node3D` holding **three** copies of a tile that wrap.

| Layer | Node name | Z | Speed multiplier | Content (M1 placeholder → M6 final) |
|---|---|---|---|---|
| 1 | `LayerHills` | -14 | 0.10 | wide low `#4A9E6F` quad with a rolling silhouette → sculpted hill mesh |
| 2 | `LayerFarTrees` | -9 | 0.28 | `#2E8B57` triangle-cluster quads → low-poly conifer meshes |
| 3 | `LayerNearTrees` | -5 | 0.55 | `#1E6B45` bigger triangles → detailed tree meshes |
| 4 | `LayerGround` | 0 | 1.00 | `#8FBF4F` ground plane w/ darker stripe bands → tiled ground mesh + rocks |
| 5 | `LayerBrush` | +3 | 1.35 | `#14532D` bush silhouettes, drawn in front of characters → grass/bush meshes |

`parallax_background.gd`:

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

`RunController` starts travel by tweening `scroll_speed` `0 → Tuning.TRAVEL_SPEED` over `TRAVEL_ACCEL_TIME` with `TRANS_SINE/EASE_OUT`, and stops it by tweening back to `0` over `TRAVEL_DECEL_TIME` with `TRANS_CUBIC/EASE_OUT` — this is the "easing tween" stop the source doc calls for.

---

## 8. Combatants

### 8.1 `combatant.tscn` / `combatant.gd`

Every hero and enemy is an instance of a per-character scene, all of which inherit this structure:

```
Combatant (Node3D)                       # combatant.gd
├── Visual (Node3D)                      # everything visible; squash/stretch applied here
│   ├── Rig (Node3D)                     # M1: primitive parts; M6: replaced by imported Skeleton3D
│   └── AnimationPlayer                  # animation names in §8.3
├── BarAnchor (Marker3D)                 # position (0, 2.05, 0) × model_scale — where bars project
├── HandAnchor (Marker3D)                # weapon/projectile spawn point
├── HitAnchor (Marker3D)                 # position (0, 0.9, 0) — where VFX/impacts land
└── AbilityTimer (Timer)                 # not used for cooldown; used for impact delays
```

`combatant.gd` public interface — implement exactly:

```gdscript
class_name Combatant
extends Node3D

enum State { IDLE, RUNNING, ATTACKING, HURT, DEAD }

signal died(c: Combatant)

@export var stats: CombatantStats

var current_hp: int
var max_hp: int
var state: State = State.IDLE
var cooldown_remaining: float = 0.0
var action_count: int = 0
var damage_multiplier: float = 1.0        # party damage buff lives here
var damage_reduction: float = 0.0         # warrior defend lives here
var is_hero: bool

func setup(s: CombatantStats, starting_hp: int = -1) -> void
func tick(delta: float) -> void           # called by BattleDirector, NOT _process
func take_damage(amount: int, source: Combatant) -> void
func heal(amount: int) -> void
func is_alive() -> bool
func play_anim(name: StringName) -> void
func set_running(running: bool) -> void
```

**Combatants do not run their own clocks.** `BattleDirector` calls `tick(delta)` on every living combatant each frame, in a fixed order (heroes left-to-right, then enemies left-to-right). This makes combat deterministic given a seed and makes it trivial to pause the whole fight.

### 8.2 Placeholder rigs (Milestone M1–M5)

Until M6, `Rig` is built from Godot primitives via `add_mesh_instance`. Each part is a `MeshInstance3D` with a cel-shaded material. Build them as **named child nodes** with these names, because M6 will swap meshes while keeping the animation tracks pointed at the same node paths:

`Root, Torso, Head, ArmL, ArmR, LegL, LegR, WeaponMain, WeaponOff`

Placeholder geometry (all `model_scale` is applied to `Visual.scale`):

| Part | Mesh | Size | Local position |
|---|---|---|---|
| `Torso` | CapsuleMesh | radius 0.28, height 0.85 | (0, 1.00, 0) |
| `Head` | SphereMesh | radius 0.22 | (0, 1.62, 0) |
| `ArmL` | CapsuleMesh | radius 0.09, height 0.55 | (-0.34, 1.10, 0.12) |
| `ArmR` | CapsuleMesh | radius 0.09, height 0.55 | (0.34, 1.10, 0.12) |
| `LegL` | CapsuleMesh | radius 0.11, height 0.60 | (-0.14, 0.32, 0) |
| `LegR` | CapsuleMesh | radius 0.11, height 0.60 | (0.14, 0.32, 0) |
| `WeaponMain` | see per-character | — | child of `ArmR`, offset (0, -0.32, 0.10) |
| `WeaponOff` | see per-character | — | child of `ArmL`, offset (0, -0.32, 0.10) |

Per-character weapon placeholders:

- Warrior `WeaponMain`: `BoxMesh(0.07, 0.90, 0.14)` steel `#8C94A3` with a `#F2C230` crossguard box `(0.24, 0.07, 0.16)`; `WeaponOff`: `CylinderMesh(r 0.30, h 0.06)` `#4A6FA5` with `#F2C230` rim.
- Ranger `WeaponMain`: `TorusMesh(inner 0.34, outer 0.40)` `#8B5A2B` rotated 90° about Y to read as a bow limb arc; `WeaponOff`: none.
- Priest `WeaponMain`: `CylinderMesh(r 0.045, h 1.30)` `#8B5A2B` topped with a `SphereMesh(r 0.13)` `#3B6FD4`, emission strength `1.5`.
- Orc `WeaponMain`: `BoxMesh(0.06, 1.05, 0.12)` haft `#6B4423` with a `BoxMesh(0.34, 0.30, 0.10)` head `#8C94A3` at the top.
- Shadow monster: **no separate limbs.** Replace the whole rig with a single `SphereMesh(r 0.55)` at `(0, 1.0, 0)` using `smoke.gdshader` (§8.6), plus two `SphereMesh(r 0.055)` eyes at `(±0.16, 1.18, 0.44)` in `#FF2D2D` with emission strength `3.0`. Add a `GPUParticles3D` smoke wisp emitter (§8.6).

### 8.3 Animation set — mandatory names

Every combatant's `AnimationPlayer` must expose these exact animation names. Missing ones are a build failure.

| Name | Who | Length | Loop | Description |
|---|---|---|---|---|
| `idle` | all | 1.60 | yes | slow weave: `Visual.rotation.z` ±3°, `Visual.position.y` ±0.04, arms counter-sway. Combat stance, weapon raised. |
| `run` | heroes only | 0.70 | yes | legs alternate ±35°, arms counter-pump, `Visual.position.y` bob 0.09, forward lean 6° |
| `attack` | all | per §9 | no | per-character, defined in §9 |
| `special` | warrior, ranger, priest | per §9 | no | per-character, defined in §9 |
| `hurt` | all | 0.30 | no | recoil: `Visual.position.x` -0.18 → 0 (ease out), `Visual.rotation.z` +14° → 0, head tucks down 0.06 |
| `die` | all | 0.80 | no | topple: `Visual.rotation.z` → 88°, `Visual.position.y` → 0.28, legs straighten, ends **lying on the ground and holds the final pose** |

Author these with `create_animation` + `add_animation_track` + `set_animation_keyframe`. Every animation must have `loop_mode` set explicitly. `die` must **not** loop and must **not** reset — the corpse stays down.

### 8.4 Damage, defense, variance

```gdscript
func compute_damage(attacker: Combatant) -> int:
    var raw := float(attacker.stats.base_damage) * attacker.damage_multiplier
    raw *= randf_range(1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE)
    return maxi(1, int(round(raw)))

# in take_damage:
var final := maxi(1, int(round(float(amount) * (1.0 - damage_reduction))))
```

Damage is always at least 1. `damage_reduction` is clamped to `[0.0, 0.9]`.

### 8.5 State rules

- A combatant in `HURT` still accumulates cooldown. Being hit never interrupts an attack that has already started; the `hurt` animation is skipped if `state == ATTACKING` (play a brief `Visual` color flash to `#FFFFFF` for 0.08s instead, so the hit still reads).
- A combatant in `DEAD`: cannot be targeted, cannot act, cannot be healed, stops ticking. Remove it from the director's living lists immediately on death so no in-flight logic can pick it.
- On death, cancel any in-progress attack. If a projectile is already in flight, it survives and resolves per §9.2.

### 8.6 Shadow monster smoke

`res://assets/shaders/smoke.gdshader` — a spatial shader on the body sphere:

```glsl
shader_type spatial;
render_mode blend_mix, cull_back, unshaded, depth_draw_never;

uniform vec4 smoke_color : source_color = vec4(0.078, 0.071, 0.102, 1.0);
uniform float speed = 0.35;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.55;

float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453); }

void fragment() {
    float f = fract(hash(floor(NORMAL * 9.0)) + TIME * speed);
    float wobble = 0.75 + 0.25 * sin(TIME * 2.1 + f * 6.28);
    float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
    ALBEDO = smoke_color.rgb;
    ALPHA = clamp(wobble * (1.0 - fres * edge_softness), 0.15, 0.95);
}
```

Plus a `GPUParticles3D` named `SmokeWisps`: amount 24, lifetime 1.4, `ParticleProcessMaterial` with emission sphere radius 0.5, `direction (0,1,0)`, spread 35°, `initial_velocity 0.3–0.7`, `gravity (0,0.4,0)`, `scale 0.10 → 0.0` over life, color ramp `#14121A` alpha 0.7 → alpha 0.0. Draw pass: `SphereMesh(r 0.5)` — the particle mesh is scaled down by the process material.

---

## 9. Abilities (exact specifications)

Each ability declares an `impact_delay` — the offset from animation start at which damage/healing is applied. This keeps the numbers landing on the visual beat.

### 9.1 Warrior

**Primary — Sword Swing** (`attack`, length 0.70, impact_delay 0.30)
- 0.00 → 0.18: wind up, `ArmR.rotation.x` → -110°, `Visual.rotation.z` → -8°
- 0.18 → 0.34: swing through, `ArmR.rotation.x` → +55°, `Visual.rotation.z` → +10°, `Visual.position.x` → +0.14
- 0.34 → 0.70: recover to neutral
- On impact (0.30): deal damage to target; spawn a **slash VFX** — a white `#FFF6E0` arc quad at the target's `HitAnchor`, scale 0 → 1.4, alpha 1 → 0 over 0.22s.

**Special — Defend** (`special`, length 0.55, impact_delay 0.25)
- Warrior plants and raises `WeaponOff` (shield): `ArmL.rotation.x` → -75°, `ArmL.position.z` → +0.20, `Visual.rotation.y` → -12°, holds from 0.25 to 0.45, then returns.
- At impact: set `damage_reduction = Tuning.WARRIOR_DEFEND_REDUCTION` for `WARRIOR_DEFEND_DURATION` seconds (use a `SceneTreeTimer`; if re-applied, refresh the duration rather than stacking).
- **Extra VFX (source doc):** spawn a `status_icon` in `BattleOverlay/VfxLayer` positioned over the warrior — a **blue circle (`#3B6FD4`, radius 46px) containing a white shield glyph**. It fades in over 0.15s, pulses scale 1.0 → 1.12 → 1.0 with a 1.0s period, and remains visible for the entire buff duration, then fades out over 0.25s. Draw the shield glyph procedurally (§17.5).
- The defend action deals **no damage**. It replaces that action entirely.

### 9.2 Ranger

**Primary — Shoot Arrow** (`attack`, length 0.80, impact resolved by projectile)
- 0.00 → 0.30: nock and draw — `ArmL` extends forward holding the bow, `ArmR` pulls back to the cheek, `Visual.rotation.z` → -14° so the bow **aims upward** (source doc).
- At **0.30**: spawn `arrow.tscn` from `HandAnchor`.
- 0.30 → 0.55: release snap, `ArmR` forward, bow limb wobble.
- 0.55 → 0.80: recover.

**Arrow projectile (`arrow.tscn`, `projectile.gd`):**
- Mesh: `CylinderMesh(r 0.018, h 0.55)` shaft `#8B5A2B` + `BoxMesh(0.06,0.10,0.02)` fletching `#F5F0E6` + `ConeMesh` tip `#8C94A3`, rotated to lie along its travel axis.
- Travel: a **parabolic arc** from spawn to the target's `HitAnchor` over **0.55s**, using
  `pos = start.lerp(end, t) + Vector3(0, arc_height * 4.0 * t * (1.0 - t), 0)` with `arc_height = 1.6`.
  The arrow's `rotation.z` each frame is set from the derivative so the tip points along the flight path.
- **Retarget rule:** the arrow stores a target reference. On arrival, if the target is `DEAD`, pick a random living enemy and deal damage there anyway; if no enemy is alive, play the impact VFX at the last position and deal no damage. This must be implemented — it is the most common source of null crashes in this kind of game.
- Impact VFX: 8 small `#F5F0E6` sparks (`GPUParticles3D`, one_shot, lifetime 0.35).

**Special — Bomb Arrow** (`special`, same animation as `attack`, spawn `bomb_arrow.tscn` instead)
- Identical draw/release animation and identical flight path/arc.
- `bomb_arrow.tscn` is the arrow plus a `SphereMesh(r 0.14)` powder bag `#6B4423` near the tip, a short `CylinderMesh(r 0.012, h 0.14)` fuse `#F5F0E6` angled out of it, and a **lit fuse spark**: a `GPUParticles3D` (amount 12, lifetime 0.25, color `#F2C230` → `#E03131`, emission point) parented at the fuse tip, plus an `OmniLight3D` (color `#F2C230`, energy 1.5, range 1.2) so the fuse casts light while flying.
- On arrival: **explode.** Deal `base_damage × RANGER_BOMB_AOE_MULT` (rounded, variance applied per enemy independently) to **every living enemy**, regardless of the original target's state.
- Explosion VFX: an expanding `SphereMesh` shell (scale 0.2 → 2.6 over 0.30s, alpha 0.9 → 0, unshaded `#F2C230`), a 30-particle one-shot burst `#E03131`→`#F2C230`, an `OmniLight3D` flash (energy 6 → 0 over 0.30s, range 4.0), and camera shake: `BattleCamera.h_offset` random ±0.06 for 0.20s, decaying.

### 9.3 Priest

**Primary — Magic Bolt** (`attack`, length 0.95, impact_delay 0.55)
- 0.00 → 0.30: raise the staff — `ArmR.rotation.x` → -130°, `Visual.position.y` +0.05, staff orb emission strength ramps `1.5 → 5.0`.
- At **0.30**: begin the strike sequence over the target:
  - The **darkening pass** (source doc asks whether this reads well — **implement it, on a toggle**): `Tuning.PRIEST_DARKEN_ENABLED := true`. Tween `WorldEnvironment.environment.adjustment_brightness` from 1.0 → 0.55 over 0.12s, hold 0.18s, return to 1.0 over 0.25s. Expose the constant so it can be flipped off after review.
  - A warning glow appears at the target's head: an unshaded `#3B82F6` sphere, scale 0 → 0.5, over 0.20s.
- At **0.55 (impact):** the bolt lands. Build it from:
  - A **jagged bolt mesh** — an `ImmediateMesh` built at runtime as a 6-segment ribbon from `y = 5.2` down to the target's `HitAnchor`, each segment offset by `randf_range(-0.22, 0.22)` in X and Z, width 0.14, unshaded `#FFFFFF` core with a second slightly wider pass in `#3B82F6`. Alpha 1 → 0 over 0.28s.
  - An `OmniLight3D` at the impact point: color `#3B82F6`, energy 8 → 0 over 0.30s, range 5.0.
  - A ground flash: a flat `#FFFFFF` disc quad at `y = 0.02`, scale 0.3 → 2.0, alpha 0.9 → 0 over 0.30s.
  - 24-particle one-shot burst in `#3B82F6`.
  - Camera shake: `h_offset`/`v_offset` random ±0.05 for 0.18s.
  - Then deal damage.
- 0.55 → 0.95: lower the staff, orb emission back to `1.5`.

**Special — Heal** (`special`, length 0.85, impact_delay 0.40)
- Same staff-raise, but the orb glows `#2FBF4F` instead of blue and no darkening occurs.
- Heals **the living hero with the lowest current HP** for `round(priest_current_damage × PRIEST_HEAL_MULT)`, where `priest_current_damage` includes `damage_multiplier` and the same variance roll. Never heals above `max_hp`. Never targets the priest preferentially — if the priest is the lowest, it heals itself.
- **Skip rule:** if every living hero is at full HP, the priest does **not** waste the special — it performs a primary attack instead and **retains** the pending special (do not reset `action_count`'s special flag), so the special fires on the next action where a wounded ally exists.
- **Extra VFX (source doc):** on the healed hero, spawn a `status_icon` — a **translucent green `+` inside a green circle** (`#2FBF4F`, circle radius 52px, alpha 0.75). It then **shrinks while fading out**: scale 1.0 → 0.55 and alpha 0.75 → 0.0 over 0.70s with `TRANS_SINE/EASE_IN`. Also spawn a green damage-number-style label showing `+N` that rises 60px and fades over 0.8s.

### 9.4 Shadow monster

**Primary — Swipe** (`attack`, length 0.60, impact_delay 0.28)
- The body lunges: `Visual.position.x` → -0.22 (toward heroes) then back, `Visual.scale` squashes to `(1.12, 0.90, 1.12)` at 0.20 and returns.
- A **claw arc VFX** at the target: three parallel tapered quads in `#14121A` with `#FF2D2D` edges, sweeping across the target's `HitAnchor`, scale 0 → 1.2, alpha 1 → 0 over 0.25s.
- Smoke wisp emitter burst: `SmokeWisps.amount_ratio` spikes to 1.0 for 0.3s.

### 9.5 Orc barbarian / Orc warlord

**Primary — Melee** (`attack`, length 0.85, impact_delay 0.42)
- 0.00 → 0.28: overhead wind up — both arms up, axe raised behind the head, `Visual.rotation.z` → +12°, `Visual.position.y` → +0.06.
- 0.28 → 0.48: **swing with all its might** — arms sweep to -95°, `Visual.rotation.z` → -18°, `Visual.position.x` → -0.20, brief `Visual.scale` stretch to `(0.92, 1.10, 0.92)`.
- 0.48 → 0.85: heavy recover with a small overshoot back to neutral.
- Impact VFX: a wide `#8C94A3` slash arc quad (larger than the warrior's, scale 0 → 1.9) plus a 12-particle dust puff at ground level, plus camera shake ±0.04 for 0.15s.
- **Warlord** uses the identical scene and animations at `model_scale = 1.70`, with `body_color` darkened to `#4E7A2B` and `accent_color` `#E03131`, and a 1.15× longer animation time scale so the bigger body reads as heavier. Give the warlord an extra pair of `#F2C230` shoulder-pad boxes on `Torso` so it silhouettes differently at a glance.

---

## 10. Combat system

`battle_director.gd` owns a single fight from spawn to resolution.

### 10.1 Setup sequence (`start_combat(enemy_stat_ids: Array[StringName])`)

1. Spawn each enemy at its slot (§7.3) with `Visual` alpha 0, `state = IDLE`, `idle` animation **already playing**.
2. Tween every enemy's alpha 0 → 1 over `ENEMY_FADE_IN_TIME` (source doc: "fade in quickly … with idle animations already playing").
3. Assign initial cooldowns:
   ```gdscript
   c.cooldown_remaining = c.stats.attack_cooldown \
       * Tuning.COOLDOWN_START_FRACTION \
       * randf_range(1.0 - Tuning.COOLDOWN_START_JITTER, 1.0 + Tuning.COOLDOWN_START_JITTER)
   ```
   The 0.5 factor is the source doc's "start half full" rule; the ±10% jitter exists **only** to de-sync identical enemy types that would otherwise act on the same frame (see §21-D2).
4. Emit `combatant_spawned` per combatant so `BattleOverlay` creates bars; bars **pop in** — scale 0.6 → 1.0 with `TRANS_BACK/EASE_OUT` over `BARS_POP_IN_TIME`, alpha 0 → 1.
5. Emit `combat_started`. The slot machine begins spinning here (§16.6).

### 10.2 Per-frame loop

```gdscript
func _process(delta: float) -> void:
    if not _active:
        return
    for c: Combatant in _living_in_order():
        if not c.is_alive():
            continue
        c.cooldown_remaining -= delta          # source doc: decrement by frame delta
        if c.cooldown_remaining <= 0.0 and c.state == Combatant.State.IDLE:
            _take_action(c)
```

`_living_in_order()` returns heroes left-to-right then enemies left-to-right. Iterate over a **copy** — actions can kill combatants mid-iteration.

`_take_action(c)`:
1. `c.action_count += 1`
2. Decide special vs primary: `use_special = c.stats.special_every_n_actions > 0 and c.action_count % c.stats.special_every_n_actions == 0`. For the priest, apply the §9.3 skip rule (if skipped, decrement `action_count` by 1 so the special is retained for next action).
3. Pick a target: **uniformly random among living opponents** (source doc: "keep attack targeting random"). Heroes target enemies, enemies target heroes. Bomb arrow and slot lightning ignore targeting and hit all enemies. Priest heal targets allies per §9.3.
4. `c.state = ATTACKING`; play `attack` or `special`.
5. Schedule the impact at `impact_delay` (a `SceneTreeTimer`, or a `call` track in the animation — **prefer a method call track in the AnimationPlayer**, so the visual and the number can never drift).
6. On animation finish: `c.state = IDLE`; `c.cooldown_remaining = c.stats.attack_cooldown` — i.e. **the cooldown starts refilling after the attack finishes** (source doc: "after their attack finishes, their cooldown bar would fill to 100% and drain"). Emit nothing; the bar reads `cooldown_remaining / attack_cooldown`.

### 10.3 Damage application

```
attacker computes damage (§8.4)
→ EventBus.combatant_attacked(attacker, target, amount)
→ target.take_damage(amount, attacker)
   → apply damage_reduction, clamp minimum 1
   → previous_hp = current_hp ; current_hp = max(0, current_hp - final)
   → EventBus.combatant_damaged(target, final, previous_hp, current_hp)   # bar reacts (§11)
   → if attacker.is_hero: EventBus.hero_damage_dealt(final)               # slot buffer (§16.5)
   → GameState.run_stats accumulates
   → if current_hp == 0: die()
   → else if state != ATTACKING: play "hurt", state = HURT for HURT_ANIM_TIME
```

### 10.4 Death

- Play `die`, set `state = DEAD`, emit `combatant_died`, remove from living lists, hide the combatant's bars (fade over 0.25s and free them).
- **Enemies:** lie still for `ENEMY_DEATH_HOLD` (1.5s), then fade `Visual` alpha 1 → 0 over `ENEMY_DEATH_FADE` (2.0s), then `queue_free()`.
- **Heroes:** lie motionless on the ground **indefinitely**. They are not freed. They stay in `GameState.hero_runtime` marked `alive = false`. On the next travel phase they slide off-screen left (§12.5).
- Death VFX: a one-shot 16-particle burst in the combatant's `body_color`, plus a 0.15s white flash on all its meshes.

### 10.5 Resolution

- **All enemies dead** → victory. Wait `ENCOUNTER_RESOLVE_PAUSE`, emit `combat_ended(true)`, then `encounter_resolved`.
- **All heroes dead** → `combat_ended(false)` → `game_over` (§18). Check this *before* the victory check so a mutual wipe is a loss.
- Enemy corpses are still fading when the party moves on; that is fine — they scroll away with the world. Do not block travel on corpse cleanup.

---

## 11. Health and cooldown bars

Lives in `BattleOverlay`, not in 3D. `combatant_bars.tscn`:

```
CombatantBars (Control, size 140×34, pivot centered)
├── CooldownBg (ColorRect)   pos (0,0)   size 140×10   color #231F2E
├── CooldownFill (ColorRect) pos (2,2)   size 136×6    color #F2C230
├── HealthBg (ColorRect)     pos (0,14)  size 140×20   color #231F2E
└── HealthFill (ColorRect)   pos (2,16)  size 136×16   color #E03131
```

Cooldown bar sits **above** the health bar (source doc). Both have a 2px `#0F0E14` border via a StyleBox or an extra ColorRect behind.

### 11.1 Positioning

Every `_process` frame, for each tracked combatant:

```gdscript
var world := combatant.get_node("BarAnchor").global_position
var vp := battle_camera.unproject_position(world)      # SubViewport coords
bars.position = vp - bars.size * 0.5                   # 1:1 into BattleOverlay
bars.visible = not battle_camera.is_position_behind(world)
```

Bar width is constant regardless of the combatant's `max_hp` — 140px for everyone. Only the *fill fraction* varies. (This keeps the boss's bar readable next to a shadow monster's.)

### 11.2 The detaching health chunk — the signature effect

On `combatant_damaged(target, amount, previous_hp, new_hp)`:

1. Compute fractions: `f_prev = previous_hp / max_hp`, `f_new = new_hp / max_hp`.
2. The lost segment occupies, in `HealthFill`'s local space, `x ∈ [136 × f_new, 136 × f_prev]`, full height.
3. Instantiate `floating_health_chunk.tscn` (a bare `ColorRect`), reparent it to `FloatingLayer`, set its **global** position and size to exactly match that segment's on-screen rect, color `#E03131`.
4. Immediately set `HealthFill.size.x = 136 × f_new` (no tween — the bar snaps, the chunk carries the motion).
5. Tween the chunk:
   - `position += Vector2(randf_range(-90, 90), randf_range(-130, -50))` over **0.70s**, `TRANS_CUBIC/EASE_OUT`
   - `rotation` → `randf_range(-0.9, 0.9)` rad over 0.70s
   - `modulate:a` 1.0 → 0.0 over 0.70s, `TRANS_QUAD/EASE_IN`
   - then `queue_free()`
6. Flash `HealthBg` to `#FFFFFF` and back over 0.10s.

Worked example from the source doc, to verify against: a 100 HP character hit for 20 → `f_prev = 1.0`, `f_new = 0.8` → the chunk is the rightmost 20% of the bar (x from 108.8 to 136), which detaches and floats away while fading. Confirm this exact case in the M2 verification gate.

**Healing** does the reverse: tween `HealthFill.size.x` up over 0.25s with `TRANS_SINE/EASE_OUT` and flash the fill to `#2FBF4F` and back over 0.30s. No chunk spawns.

### 11.3 Cooldown fill

```gdscript
CooldownFill.size.x = 136.0 * clamp(c.cooldown_remaining / c.stats.attack_cooldown, 0.0, 1.0)
```

So it is **full immediately after an attack finishes and drains to empty as the cooldown completes**, exactly as the source doc describes. While `state == ATTACKING` the bar reads 0 (the attack is happening); that's correct and legible.

### 11.4 Damage numbers

On `combatant_damaged`, spawn a `damage_number.tscn` `Label` in `FloatingLayer` at the target's bar position + `(randf_range(-30,30), -20)`:
- Text `str(amount)`, font size 42, color `#E03131`, outline 6px `#0F0E14`
- Tween: rise 80px, `scale` 0.6 → 1.25 → 1.0 (punch, over the first 0.18s), alpha 1 → 0 over 0.85s, then free.
- Heals use `+N` in `#2FBF4F`. Slot lightning damage uses `#3B82F6`.

---

## 12. Run flow

`run_controller.gd` is the top-level state machine. Exactly these states:

```gdscript
enum RunState {
    BOOT, TRAVEL, ARRIVE, COMBAT, LOOT, SHOP,
    ENCOUNTER_EXIT, RUN_COMPLETE, GAME_OVER
}
```

### 12.1 The demo level (`res://resources/levels/demo_level.tres`)

Six encounters (source of truth — build this `.tres` exactly):

| # | Type | Contents | travel_duration |
|---|---|---|---|
| 0 | COMBAT | `shadow_monster`, `shadow_monster` | 2.0 |
| 1 | LOOT | 2 items | 3.0 |
| 2 | COMBAT | `shadow_monster`, `shadow_monster`, `orc_barbarian` | 3.0 |
| 3 | SHOP | 3 items for sale | 3.0 |
| 4 | COMBAT | `orc_barbarian`, `orc_barbarian`, `shadow_monster` | 3.0 |
| 5 | COMBAT (boss) | `orc_warlord`, `shadow_monster` | 4.0 |

The level map is **generated as a linear sequence with no branching, and is never shown to the player** (source doc). Build the `LevelDef` at runtime in `GameState.reset_run()` from the table above, so a future generator can replace that one function.

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
- Dead heroes: remain lying down and are **already gone** (removed in the previous `ENCOUNTER_EXIT`).
- `ParallaxBackground.scroll_speed` tweens up per §7.4.
- Runs for `def.travel_duration` seconds, then → `ARRIVE`.

### 12.4 ARRIVE

Source doc's shared prelude, in order:
1. Tween `scroll_speed` → 0 over `TRAVEL_DECEL_TIME`, `TRANS_CUBIC/EASE_OUT`.
2. When it reaches ~0, all living heroes `set_running(false)` → `idle`.
3. Then branch on encounter type.

### 12.5 ENCOUNTER_EXIT

If one or more heroes died during this encounter (source doc):
1. Each dead hero's `Combatant` node tweens `position.x` from its slot to `-7.0` over `DEAD_HERO_EXIT_TIME` with `TRANS_SINE/EASE_IN`, staying in its `die` end pose, then is hidden and removed from the battlefield.
   - Conceptually the party leaves *them* behind; visually, because the camera is fixed and the world scrolls, the corpse slides left off-screen. That is the correct read.
2. Wait for that tween, then proceed.

If **all** heroes are dead this state is never entered — go straight to `GAME_OVER` (source doc caveat).

### 12.6 RUN_COMPLETE

After encounter 5 resolves: heroes run right for 2.0s with the background scrolling, then show the `RunSummary` screen in "Victory" mode (§18).

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
```

Base values are from the source doc and must not be changed.

```gdscript
const ADJECTIVES := [
    "Fat", "Wimpy", "Rusty", "Gleaming", "Crooked", "Humble", "Brash", "Sullen",
    "Chipped", "Peculiar", "Stout", "Lucky", "Grumbling", "Nimble", "Battered",
    "Radiant", "Sodden", "Hasty", "Bold", "Weeping", "Jagged", "Plucky",
]

const MODIFIERS := [
    { "id": &"dmg_flat",   "label": "+%d Damage",        "roll": [2, 9],   "value_mult": [0.28, 0.55] },
    { "id": &"dmg_pct",    "label": "+%d%% Damage",      "roll": [5, 18],  "value_mult": [0.30, 0.60] },
    { "id": &"elem_fire",  "label": "+%d Fire Damage",   "roll": [3, 11],  "value_mult": [0.35, 0.70] },
    { "id": &"elem_ice",   "label": "+%d Ice Damage",    "roll": [3, 11],  "value_mult": [0.35, 0.70] },
    { "id": &"elem_light", "label": "+%d Lightning Dmg", "roll": [3, 11],  "value_mult": [0.35, 0.70] },
]
```

### 13.2 Rarity

| Rarity | Weight | Modifier count | Value multiplier |
|---|---|---|---|
| Common | 50 | 0 | `1.0` (fixed) |
| Uncommon | 30 | 1 | `randf_range(1.6, 2.2)` |
| Magic | 15 | 2 | `randf_range(2.8, 3.6)` |
| Rare | 5 | 3 | `randf_range(4.5, 6.0)` |

Modifier counts are from the source doc (0/1/2/3) and must not be changed.

The source doc says rarity and modifier multipliers should be **randomized for now, with a note to enhance the system later**. Implement that as: the multiplier is rolled **per item at generation time** within the ranges above.

> **TODO (post-demo):** replace the random multiplier ranges with a designed curve — rarity multipliers should be authored per-rarity constants, and each modifier's value contribution should scale with the magnitude actually rolled rather than being independently random. Leave this comment verbatim in `itemizer.gd`.

### 13.3 Value formula

```gdscript
value = int(round(
    base_value
    * rarity_multiplier
    * (1.0 + sum_of_modifier_value_mults)
))
```

Range check (verified arithmetic): cheapest is a common dagger at `18 × 1.0 × 1.0 = 18`; most expensive is a rare staff at up to `25 × 6.0 × (1 + 3×0.70) = 465`. Shop prices are `value × 1.5` → **27 to 697 gold**. That spread is intentional: it guarantees the shop's affordability graying-out logic (§15.2) actually gets exercised — with typical gold-on-hand at the first shop of roughly 150–260 (starting 50, plus ~30 gold per combat from slot payouts, plus sales of the two loot items), some cards will be affordable and some will not.

### 13.4 Naming

```gdscript
display_name = "%s %s" % [ADJECTIVES.pick_random(), WEAPON_TYPES[type].nouns.pick_random()]
```
→ "Fat Knife", "Wimpy Sword", "Radiant Scepter". Matches the source doc's examples.
`subtitle()` returns rarity + type: "Magic Sword", "Common Bow".

### 13.5 Bulk API (required by the source doc)

```gdscript
func generate_items(count: int) -> Array[Item]
func generate_item() -> Item
```

`generate_items` is what loot chests and shops call. Every other system requests items **only** through it.

### 13.6 Kinds

`Kind.WEAPON` is the only kind generated in the demo. `POTION` and `RELIC` exist in the enum and in `Item`, are documented as deferred, and are never produced. `equipped` is always `false`, but `GameState.sellable_items()` must still filter on it — this proves the Sell tab's filter works and is the seam for future equipment.

---

## 14. Encounters

### 14.1 Combat encounter

Covered by §10. Sequence: `ARRIVE` prelude → enemies fade in → bars pop in → cooldowns half-charged → fight.

### 14.2 Loot encounter

1. A closed `treasure_chest.tscn` **pops in** on the right at `(3.2, 0, 0)`: scale 0 → 1.15 → 1.0 over 0.45s with `TRANS_BACK/EASE_OUT`, plus a landing dust puff.
   - Chest placeholder mesh: `BoxMesh(1.0, 0.62, 0.7)` body `#8B5A2B` with `#F2C230` corner boxes and a `CylinderMesh` half-round lid; `Lid` is a separate child rotating about a hinge at the back edge.
2. Beat of 0.5s, then **open with juice**:
   - `Lid.rotation.x` 0° → -105° over 0.4s, `TRANS_BACK/EASE_OUT`
   - Interior glow: an `OmniLight3D` inside, energy 0 → 5 over 0.25s, color `#F2C230`
   - A 40-particle one-shot gold burst shooting upward, gravity pulling them back down
   - Six `#F2C230` coin quads that arc out and fall
   - A white radial flash quad, scale 0 → 3.0, alpha 0.9 → 0 over 0.35s
   - Chest squash-stretch: `scale` → `(1.1, 0.9, 1.1)` → `(1.0, 1.0, 1.0)` over 0.3s
3. Generate `Itemizer.generate_items(def.loot_item_count)` and add each to `GameState.inventory`, staggered 0.25s apart. For each, spawn a floating item label in `BattleOverlay/FloatingLayer` at the chest's screen position showing the item's `display_name` colored by rarity (§17.6), which rises 120px and fades over 1.2s.
4. Encounter resolved. Chest fades out over 0.4s as travel begins.

### 14.3 Shop encounter

1. A `shop_building` pops in on the right at `(3.4, 0, 0)` with the same pop-in tween.
   - Placeholder mesh: `BoxMesh(2.0, 1.6, 1.4)` walls `#F5F0E6`, `PrismMesh(2.4, 1.0, 1.6)` roof `#D9333F`, `BoxMesh(0.6,1.0,0.1)` door `#8B5A2B`, a `#F2C230` hanging sign quad, and a small `OmniLight3D` warm window glow.
2. After 0.4s, show `ShopModal` (§15).
3. The encounter resolves **only** when the modal's close button is pressed (source doc).

---

## 15. Shop modal

`res://scenes/modals/shop_modal.tscn`, inside `ModalLayer`.

### 15.1 Layout

- Full-screen `#0F0E14` scrim at 65% alpha, fading in over 0.2s. Scrim clicks do **not** close the modal (source doc specifies an explicit X only).
- Panel: 960 × 1200, centered at viewport center (60, 360) → (1020, 1560). `PanelContainer` per §6.5, entering with scale 0.85 → 1.0 and alpha 0 → 1 over 0.25s, `TRANS_BACK/EASE_OUT`.
- Header row: title `SHOP` (font 56, `#F2C230`) on the left; **a small red X close button in the upper right** — 72×72, `#E03131` background, `#FFF6E0` glyph, corner radius 16, offset 16px in from the panel's top-right corner.
- Gold readout under the header, right-aligned: a coin glyph + `str(GameState.gold)`, font 44, `#F2C230`. **This must update live** as items are bought and sold.
- `TabContainer` with exactly two tabs: **`Buy`** and **`Sell`**, in that order, `Buy` selected on open.

### 15.2 Buy tab

- On the encounter's first open, call `Itemizer.generate_items(3)` once and cache the result on the encounter. Reopening the tab must show the **same three items** — never reroll.
- Three `shop_buy_card.tscn` stacked vertically, each 880 × 260:
  - Rarity-colored left edge bar, 12px wide (§17.6)
  - `display_name` — font 44, `#FFF6E0`
  - `subtitle()` — font 30, rarity color
  - Modifier lines — font 28, `#9B93AE`, one per modifier, using the formatted `label`
  - Price, right-aligned — font 46, `#F2C230`, text `str(buy_price)` with a coin glyph
- **Affordability:** a card is affordable when `GameState.gold >= buy_price`.
  - Affordable → full color, `mouse_default_cursor_shape = POINTING_HAND`, tappable, and a subtle idle pulse on the price (scale 1.0 ↔ 1.04, 1.6s period).
  - Unaffordable → the entire card `modulate = Color(0.45, 0.45, 0.5, 1.0)` (grayed out), not tappable.
- **On purchase:** deduct gold, add the item to `GameState.inventory`, then that card:
  - price text changes to **`SOLD!`** in `#E03131`
  - card grays out and becomes permanently untappable for this shop visit
  - a small `#F2C230` "-N" gold number floats up from the gold readout
- **Re-evaluate affordability of every card whenever gold changes** — on purchase, on sale, and on slot gold payouts. Connect to `EventBus.gold_changed`. The source doc's worked example must hold exactly:
  > Items cost 200, 250, 300; party has 350. All three are affordable. Player buys the 250 item → it reads `SOLD!` and grays out; the 200 and 300 items now gray out too, because the party has 100 gold left.

  Reproduce this exact scenario in the M5 verification gate.

### 15.3 Sell tab

- Lists `GameState.sellable_items()` — i.e. **equipped items are neither displayed nor sellable** (source doc). In the demo nothing is ever equipped, but the filter must be real.
- A `VBoxContainer` inside a `ScrollContainer` (the inventory can grow past the panel height).
- Each `shop_sell_row.tscn` is 880 × 180: rarity edge bar, name, subtitle, modifier count, and **a button underneath showing the item's sale value** — label `Sell for N` with a coin glyph, per the source doc's "a button under each item showing its value."
- Pressing it: `GameState.add_gold(sell_price)`, `GameState.remove_item(item)`, the row collapses (height → 0 and alpha → 0 over 0.25s) and is freed, a `+N` gold number floats up, and Buy-tab affordability re-evaluates.
- Empty state: centered `#9B93AE` label, "Nothing to sell."

### 15.4 Close

The red X: fade the panel out (scale → 0.9, alpha → 0, 0.2s), fade the scrim, `queue_free()`, and emit the encounter-resolved signal. Nothing else closes the modal — not the Escape key, not a scrim tap. (Optional nicety: also accept `ui_cancel` for desktop testing. Allowed, not required.)

---

## 16. The slot machine

### 16.1 Presentation

Housed in `SlotMachine` (1080 × 600 at console-local y 300). Style it as an American 1980s three-reel cabinet: a heavy `#332C42` cabinet with a 6px `#F2C230` bezel and rounded corners, three vertical reel windows recessed into it, and a **single center payline** — a 4px `#E03131` horizontal line spanning all three windows, with a small arrow marker on each side.

Exact geometry (console-local coordinates, origin at the SlotMachine node):

| Element | Position | Size |
|---|---|---|
| Cabinet panel | (110, 20) | 860 × 560 |
| Reel window 0 | (160, 60) | 240 × 480 |
| Reel window 1 | (420, 60) | 240 × 480 |
| Reel window 2 | (680, 60) | 240 × 480 |
| Symbol cell | — | 240 × 160 (3 visible per reel = 480) |
| Payline | (140, 298) | 800 × 4 |

Three symbols visible per reel per stop (source doc); the **middle** cell of each reel is on the payline.

### 16.2 Reel strip and the 50% win rate

All three reels use the **same 27-stop strip**:

```gdscript
enum Sym { LIGHTNING, GOLD, PLUS, BLANK }

const SLOT_STRIP: Array[int] = [
    Sym.LIGHTNING, Sym.BLANK, Sym.GOLD,      Sym.PLUS,     Sym.LIGHTNING,
    Sym.GOLD,      Sym.PLUS,  Sym.BLANK,     Sym.LIGHTNING,Sym.GOLD,
    Sym.PLUS,      Sym.LIGHTNING, Sym.BLANK, Sym.GOLD,     Sym.PLUS,
    Sym.LIGHTNING, Sym.GOLD,  Sym.PLUS,      Sym.BLANK,    Sym.LIGHTNING,
    Sym.GOLD,      Sym.PLUS,  Sym.LIGHTNING, Sym.BLANK,    Sym.GOLD,
    Sym.PLUS,      Sym.BLANK,
]
# Counts: LIGHTNING 7, GOLD 7, PLUS 7, BLANK 6  →  27 stops
```

**Win rule:** a win is **2 or 3 of the same non-blank symbol on the payline**, counting any two of the three positions (they need not be adjacent). Blanks never pay.

**The math, which you must verify numerically:**

- Total outcomes: 27³ = **19,683**
- Per paying symbol s (7 stops of s, 20 non-s):
  - exactly 3 of s: 7³ = **343**
  - exactly 2 of s: 3 × 7² × 20 = 3 × 49 × 20 = **2,940**
  - subtotal: **3,283**
- Three paying symbols: 3 × 3,283 = **9,849**
- P(win) = 9,849 / 19,683 = **0.500381…** → **50.04%**

That satisfies the source doc's "engineer the reels such that wins occur on roughly 50% of spins" essentially exactly. Per-outcome probabilities, for reference:

| Outcome | Probability |
|---|---|
| 3 of a specific symbol | 1.743% |
| 2 of a specific symbol | 14.937% |
| Any win | 50.038% |
| No win | 49.962% |

These figures were computed by exhaustive enumeration of all 19,683 outcomes of the strip above, not estimated. If you change a single stop in `SLOT_STRIP`, recompute before shipping.

**Required test:** write `res://tests/test_slot_odds.gd` that simulates 1,000,000 spins with the real reel logic and asserts the observed win rate is within `[0.490, 0.510]`, and that each symbol's 3-of-a-kind rate is within `[0.014, 0.021]`. Run it and report the numbers in the M3 gate.

### 16.3 Spin cycle

Continuous, no player input (source doc). One cycle:

1. `slot_spin_started`. All three reels begin scrolling upward at high speed with motion blur (a vertical blur is not required; a 3-frame ghost via lowered symbol alpha during motion is sufficient — or simply scroll fast enough that legibility naturally drops).
2. Reel 0 decelerates and stops at a uniformly random stop index at `t = SLOT_SPIN_DURATION` (1.10s).
3. Reel 1 stops at `t = 1.10 + 0.28`; reel 2 at `t = 1.10 + 0.56`.
4. Each reel's stop is a tween to the exact cell offset with `TRANS_BACK/EASE_OUT` over 0.18s so it **overshoots slightly and snaps back** — the physical thunk of a real reel. Add a 4px cabinet shake on each stop.
5. `slot_spin_stopped([s0, s1, s2])`. Evaluate the payline. If it's a win, run §16.4 celebration and apply §16.5 payout.
6. Hold `SLOT_RESULT_HOLD` (0.85s), then spin again — as long as combat is still active.

Full cycle length: 1.10 + 0.56 + 0.85 ≈ **2.51s**, so roughly 6–10 spins per combat encounter.

### 16.4 Win presentation

- The winning symbols on the payline pulse: scale 1.0 → 1.30 → 1.0 over 0.35s, with a `#F2C230` glow ring behind each.
- The payline flashes `#E03131` → `#FFF6E0` → `#E03131` twice.
- A banner label appears centered above the reels for 1.0s, then fades: `"LIGHTNING ×2"` / `"GOLD ×3"` / `"HEAL ×2"` — font 48, `#F2C230`, outlined `#0F0E14`.
- 3-of-a-kind additionally: a 40-particle gold confetti burst from the cabinet, and the whole `SlotMachine` node punches scale 1.0 → 1.05 → 1.0 over 0.25s.

### 16.5 Payouts (exact, from the source doc)

Maintain a rolling buffer of the **last three hero damage instances**, fed by `EventBus.hero_damage_dealt`:

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
| 2 × Lightning | **All living enemies** are struck for `round(avg_last_three × 1.0)` |
| 3 × Lightning | **All living enemies** are struck for `round(avg_last_three × 2.0)` |
| 2 × Gold | Party receives **25 gold** |
| 3 × Gold | Party receives **50 gold** |
| 2 × Plus | The **living hero with the lowest current HP** is healed for **25% of their max HP** |
| 3 × Plus | The **entire living hero party** is healed for **25% of each hero's max HP** |

Notes that remove ambiguity:
- "Enemies are struck" is plural → **all** living enemies, each taking the full amount, each rolling `DAMAGE_VARIANCE` independently.
- Slot lightning damage is **not** attributed to a hero and must **not** feed back into `_last_hero_hits` (that would create a runaway feedback loop). Only hero attacks feed the buffer.
- Slot heals cannot exceed `max_hp` and cannot revive the dead.
- If a payout has no valid target (e.g. lightning with all enemies already dead in the resolve window), skip it silently but still play the celebration.

**Slot lightning VFX:** reuse the priest's bolt builder (§9.3) once per enemy, with a 0.06s stagger between them, and **without** the darkening pass (it would fire far too often).

### 16.6 When the slot runs

- Spins **only** while `RunController.state == COMBAT` and the fight is active.
- On `combat_ended` or any non-combat state: let the current spin finish its stop sequence, evaluate and pay it out normally, then stop. Reels hold their final symbols and the whole cabinet dims to `modulate = Color(0.55, 0.55, 0.62)`.
- On the next `combat_started`: undim over 0.2s and resume spinning.
- Between encounters and during loot/shop encounters, the slot machine does nothing (source doc).

### 16.7 Symbol rendering — fully procedural

`slot_symbol.tscn` is a `Control` with a script that draws in `_draw()`. No image files. Coordinates below are normalized to the control's size (240 × 160 cell; draw within a centered 140 × 140 square).

```gdscript
const BOLT := PackedVector2Array([
    Vector2(0.55, 0.05), Vector2(0.22, 0.55), Vector2(0.45, 0.55),
    Vector2(0.30, 0.95), Vector2(0.78, 0.42), Vector2(0.52, 0.42),
    Vector2(0.72, 0.05),
])

const PLUS := PackedVector2Array([
    Vector2(0.37, 0.10), Vector2(0.63, 0.10), Vector2(0.63, 0.37),
    Vector2(0.90, 0.37), Vector2(0.90, 0.63), Vector2(0.63, 0.63),
    Vector2(0.63, 0.90), Vector2(0.37, 0.90), Vector2(0.37, 0.63),
    Vector2(0.10, 0.63), Vector2(0.10, 0.37), Vector2(0.37, 0.37),
])
```

- **Lightning** — `draw_colored_polygon(BOLT, #3B82F6)` then `draw_polyline(BOLT + first point, #F2C230, 7.0, true)`. *A blue stylized lightning bolt with a gold outline* (source doc). Verify the polygon reads as a bolt in a screenshot; if it doesn't, adjust the points and record the change in §21.
- **Gold coin** — `draw_circle(center, r=0.42, #F2C230)`, `draw_arc(center, 0.42, 0, TAU, 48, #0F0E14, 6.0)`, inner `draw_circle(center, 0.30, #FFDD66)`, `draw_arc(center, 0.30, 0, TAU, 48, #B8860B, 4.0)`, plus a small `#B8860B` "★"-ish 5-point polygon or a bold `S` glyph at 0.18 radius.
- **Green plus** — `draw_colored_polygon(PLUS, #2FBF4F)` then `draw_polyline(PLUS + first point, #000000, 6.0, true)`. *A green plus sign with a black outline* (source doc).
- **Blank** — draw nothing (the recessed `#231F2E` reel window shows through). *An empty space* (source doc).

---

## 17. The management console

### 17.1 Console background

`Console` gets a `ColorRect` at `#231F2E` behind everything, plus a subtle 2px `#4A4260` inner border. The `ConsoleDivider` gold bar above it (§3.3) separates it hard from the battlefield.

### 17.2 Status panel (1080 × 300)

A `PanelContainer` containing a `VBoxContainer`:

**Row A — resources (height 90):**
- Left: a procedurally drawn coin glyph (36px, reuse §16.7's coin) + `str(GameState.gold)`, font 52, `#F2C230`. On `gold_changed`, punch the label scale 1.0 → 1.22 → 1.0 over 0.25s and float a `±N` label upward beside it in `#F2C230` (gain) or `#E03131` (spend).
- Right: `inventory_strip.tscn` — a horizontal `ScrollContainer` of 64×64 item chips, each a rounded rect in the item's rarity color with the weapon-type initial letter (A/S/B/D/T for axe/sword/bow/dagger/staff) in `#0F0E14`. New items slide in from the right with a 0.3s tween. Tapping a chip shows `item_tooltip.tscn` (name, subtitle, modifier list, value) anchored above the chip, dismissed by tapping anywhere.

**Rows B–D — hero status (3 × 70):**

Each `hero_status_row.tscn` (1080 × 70):

| Element | X | Width | Content |
|---|---|---|---|
| Class chip | 24 | 56 | rounded square in the hero's `accent_color`, initial letter |
| Name | 96 | 200 | `display_name`, font 34, `#FFF6E0` |
| HP bar | 312 | 420 | bg `#231F2E`, fill `#E03131`, 24px tall, tweens over 0.25s on change |
| HP text | 312 | 420 | `"%d / %d"` centered over the bar, font 28, `#FFF6E0`, outline 4px `#0F0E14` |
| Buff icons | 756 | 220 | 44×44 chips, right-aligned: blue shield (warrior defending), gold arrow-up (party damage buff active) |

Dead heroes: the whole row `modulate = Color(0.4, 0.4, 0.45)`, name gets a strikethrough drawn as a 3px `#E03131` line, HP text reads `DEAD`.

### 17.3 Party damage button (720 × 160 at console-local (180, 900))

Text: **`Increase Party Damage`**, font 44, centered.

Behavior (source doc, exactly):
- **Idle:** enabled, normal styling, subtle idle glow pulse on the gold border.
- **On press:** every living hero's `damage_multiplier` is multiplied by `Tuning.PARTY_DAMAGE_BUFF_MULT` (1.10) for `PARTY_DAMAGE_BUFF_DURATION` (30.0) seconds. Emit `party_damage_buff_started(30.0)`.
- **While active:** the button is **unclickable** (`disabled = true`) and **a progress bar appears behind the text on the button itself**. Implement this as a `ColorRect` child named `BuffProgress` at z-index below the label and above the button's stylebox, color `#F2C230` at 40% alpha, whose `size.x` **starts at the full button width (100%) and drains to 0 over the buff duration**. Drive it in `_process` from the remaining time — do not use a Tween, so it stays correct if the game is paused.
- **When the bar reaches 0%:** remove the multiplier from every hero (divide back out; do not just set to 1.0, so future stacking buffs remain correct), `disabled = false`, hide `BuffProgress`, emit `party_damage_buff_ended`, and play a 0.2s scale punch to signal readiness.
- The buff timer is **real time and encounter-agnostic**: it keeps draining through travel, loot, and shop encounters. Heroes who die while buffed are simply skipped on removal. Heroes cannot be revived, so no re-application logic is needed.

### 17.4 Upgrade tray

An empty `HBoxContainer` at console-local (0, 1060), 1080 × 212, with a centered `#9B93AE` label reading `More upgrades coming soon`. It exists to reserve the space and to be the obvious insertion point for the source doc's "buttons for purchasing upgrades."

### 17.5 Status icon (`status_icon.tscn`)

A `Control` drawn procedurally, used for the defend shield and the heal plus:

- **Defend:** `draw_circle(c, 46, #3B6FD4 @ 0.85)`, `draw_arc(c, 46, 0, TAU, 48, #FFF6E0, 5.0)`, and a white shield polygon —
  `[(0.5,0.12),(0.82,0.26),(0.82,0.55),(0.5,0.88),(0.18,0.55),(0.18,0.26)]` normalized to a 60px box, filled `#FFF6E0`.
- **Heal:** `draw_circle(c, 52, #2FBF4F @ 0.55)`, `draw_arc(c, 52, 0, TAU, 48, #2FBF4F @ 0.9, 5.0)`, and the §16.7 `PLUS` polygon filled `#2FBF4F @ 0.75` scaled to a 62px box. **Translucent, per the source doc.**

### 17.6 Rarity colors (used by shop cards, inventory chips, loot labels)

| Rarity | Color |
|---|---|
| Common | `#B8B2C4` |
| Uncommon | `#4CC38A` |
| Magic | `#4A9BE8` |
| Rare | `#F2C230` |

---

## 18. Game over and run summary

`res://scenes/modals/run_summary.tscn`, shown in `ModalLayer`.

### 18.1 Trigger

- **Defeat:** all heroes dead. `RunState.GAME_OVER`. Before showing the screen: freeze combat, let the last `die` animation finish, hold 1.0s on the battlefield (so the player sees the wipe), fade a `#0F0E14` scrim in to 75% over 0.5s, then present.
- **Victory:** encounter 5 resolved. Heroes run right for 2.0s, then the same presentation with victory styling.

### 18.2 Content

Panel 900 × 1180, centered.

- Title: **`DEFEATED`** in `#E03131` (font 84) or **`LEVEL CLEARED`** in `#F2C230` (font 76). Slam in: scale 1.6 → 1.0 over 0.35s, `TRANS_BACK/EASE_OUT`, with a 6px `#0F0E14` outline.
- Subtitle: `"Reached encounter %d of %d"`.
- A stat table, each row `label` left / `value` right, font 38, rows revealing one at a time 0.08s apart with a slide-in from the left:

| Label | Source |
|---|---|
| Encounters cleared | `run_stats.encounters_cleared` |
| Run time | `run_stats.run_time`, formatted `M:SS` |
| Gold earned | `run_stats.gold_earned` |
| Gold on hand | `GameState.gold` |
| Damage dealt | `run_stats.damage_dealt` |
| Damage taken | `run_stats.damage_taken` |
| Slot spins | `run_stats.slot_spins` |
| Slot wins | `run_stats.slot_wins` (+ percentage) |
| Items found | `run_stats.items_found` |
| Items sold | `run_stats.items_sold` |

The slot-win percentage on this screen doubles as a live sanity check on §16.2 — it should hover near 50%.

- A **`RETRY`** button, 560 × 140, centered at the bottom.

### 18.3 Retry

Full reset, no carryover (the demo has no meta-progression):

1. Free all combatants, projectiles, props, bars, and floating elements.
2. `GameState.reset_run()` — gold → `Tuning.STARTING_GOLD`, inventory cleared, `hero_runtime` rebuilt at full HP, `current_encounter_index = -1`, `run_stats` zeroed, `level` rebuilt.
3. Clear the slot's `_last_hero_hits` buffer and cancel any party damage buff.
4. Reset the parallax tiles to their starting offsets.
5. `RunController` → `BOOT` → `TRAVEL`.

The retry path must be reliably re-runnable: verify three consecutive retries in the M5 gate with `get_editor_errors` clean each time. Leaked nodes between runs are the most likely bug here — check `get_game_scene_tree` node counts before and after.

---

## 19. Blender asset pipeline (Milestone M6)

Only start this after M5 passes. Everything before this point runs on primitives.

### 19.1 Rules

- All modeling happens in `C:\Projects\Godot\Sir Fish\blender\Sir Fish.blend` via the Blender MCP tools (`execute_blender_code`, `get_objects_summary`, `render_viewport_to_path`, `get_screenshot_of_window_as_image`).
- The file currently contains only Blender's default `Cube`, `Camera`, `Light`. **Delete the default cube** before building.
- Organize into collections: `Heroes`, `Enemies`, `Props`, `Environment`.
- Everything is **low-poly, hard-surface, flat-shaded**, built for cel shading: chunky silhouettes, no bevel-heavy detail, no normal maps, no textures — **vertex colors or per-material flat colors only**, using the §6.1 palette exactly.
- Because the camera is a fixed side view, do not model detail that is never visible from -Z... but **do** keep both sides symmetric, since heroes and enemies face opposite directions.
- Character height: **1.8 Blender units at scale 1.0**, feet at the origin, facing **+X**.

### 19.2 Rigging and animation

- One armature per character. Bone names, exactly: `Root, Hips, Spine, Chest, Head, Shoulder.L, Arm.L, Hand.L, Shoulder.R, Arm.R, Hand.R, Thigh.L, Shin.L, Foot.L, Thigh.R, Shin.R, Foot.R`. Weapons are parented to `Hand.R` (main) and `Hand.L` (off).
- Author the animations as **NLA-strip actions named exactly** `idle`, `run`, `attack`, `special`, `hurt`, `die` — matching §8.3's names and lengths, so the Godot-side `AnimationPlayer` calls in `combatant.gd` need **zero changes**.
- Shadow monster: no armature. Animate the mesh via shape keys / object transforms only, but still export actions under the same names.

### 19.3 Export

- Export each character as glTF 2.0 (`.glb`) to `res://assets/meshes/`, with `+Y up`, animations included, apply modifiers on.
- In Godot, configure each import to generate a scene with an `AnimationPlayer`, then **swap the placeholder `Rig` node in each character scene for the imported model** and reassign the cel + outline materials. `combatant.gd`, `battle_director.gd`, and every animation *name* stay unchanged.
- After each swap, re-run the M1/M2 verification gates to confirm nothing regressed.

### 19.4 Environment meshes

Replace the five parallax layers' placeholder quads with Blender-built tiling meshes: rolling hill silhouettes, two conifer variants and one broadleaf, ground with scattered rocks and grass tufts, and foreground bushes. Each tile must be **exactly `tile_width` (12.0) units wide** and seamless at its edges, since §7.4's wrap logic depends on it.

---

## 20. Milestones and verification gates

Work these in order. **Do not start a milestone until the previous gate passes.** For each gate: `play_scene`, drive it, screenshot it, check `get_editor_errors` and `get_output_log`, then report the result before continuing.

### M0 — Project skeleton
Build: project settings (§2), directory tree (§3.1), autoloads (§3.2), `EventBus` signals (§3.4), data resources (§4), `Tuning` (§5), theme (§6.5), shaders (§6.2, §6.3, §8.6), `main.tscn` with all regions blocked out in flat placeholder colors.

**Gate:** screenshot shows the exact §2.1 region split with correct colors and no overlap. `get_project_info` confirms the 1080×1920 viewport. Zero editor errors.

### M1 — Battlefield and characters standing
Build: `battle_world.tscn` (§7), camera (§7.2), lighting (§6.4), parallax with placeholder layers (§7.4), all six combatant scenes with placeholder rigs (§8.2) and the full animation set (§8.3).

**Gate:** screenshot shows three heroes on the left in the order priest/ranger/warrior and enemies on the right, all cel-shaded with visible dark outlines, all playing `idle`. Use `execute_game_script` to force each animation on each character in turn and screenshot `run`, `attack`, `special`, `hurt`, and `die` — confirm `die` ends lying on the ground and holds. Confirm parallax scrolls at five different speeds when `scroll_speed` is set, and that layer 5 draws in front of the characters.

### M2 — Combat core
Build: `combatant.gd` (§8), `battle_director.gd` (§10), bars and the detaching-chunk effect (§11), all six abilities with their VFX (§9).

**Gate:** a full fight (3 heroes vs 3 enemies) runs to completion without input. Capture frames and confirm: cooldowns start staggered and no two combatants act on the same frame at the start; bars sit above heads and track correctly; **the source doc's 100-HP-hit-for-20 case detaches exactly the rightmost 20% of the bar and floats it away** (verify by forcing that exact case via `execute_game_script`); the ranger's arrow visibly arcs and lands; the bomb arrow explodes and damages all enemies; the priest's bolt crashes down with the darkening pass; the defend shield icon appears and persists 4s; the heal plus shrinks and fades; dead enemies hold 1.5s then fade over 2s and free; dead heroes stay down. Kill a ranger target mid-flight and confirm no crash (§9.2 retarget rule).

### M3 — Slot machine
Build: the cabinet (§16.1), reels and strip (§16.2), spin cycle (§16.3), win presentation (§16.4), payouts (§16.5), gating (§16.6), procedural symbols (§16.7).

**Gate:** run `test_slot_odds.gd` and report the observed win rate (must be 0.490–0.510). Screenshot the cabinet and confirm three visible symbols per reel, one center payline, and that each symbol matches its source-doc description. Confirm all six payouts fire correctly by forcing each result via `execute_game_script`. Confirm the slot spins only during combat and dims otherwise. Confirm slot lightning damage does **not** feed the `_last_hero_hits` buffer.

### M4 — Run flow, travel, loot
Build: `run_controller.gd` and the state machine (§12), the demo level (§12.1), travel and arrival easing (§12.3–12.4), dead-hero exit (§12.5), the loot encounter (§14.2).

**Gate:** the run plays from encounter 0 through 5 hands-off. Confirm the background eases to a stop rather than snapping, heroes switch run↔idle at the right moments, a hero killed in encounter 0 slides off-screen left during the next travel and never reappears, and the chest pops, opens with the full effects list, and grants exactly 2 items into the inventory.

### M5 — Items, shop, console, game over
Build: `Itemizer` (§13), the shop encounter and modal (§14.3, §15), the status panel (§17.2), the party damage button (§17.3), run summary and retry (§18).

**Gate:** generate 200 items via `execute_game_script` and report the rarity distribution (must be near 50/30/15/5) and the min/median/max value. Reproduce the source doc's shop scenario exactly (§15.2). Confirm the Sell tab excludes `equipped` items by temporarily flagging one item equipped. Confirm the party damage button drains its progress bar from 100% to 0% over 30s, is unclickable throughout, and restores damage exactly on expiry. Trigger a game over, confirm the summary numbers are correct, and retry three times with clean errors and no node leaks.

### M6 — Blender assets
Build: §19, one character at a time, re-running M1/M2 gates after each swap.

**Gate:** side-by-side screenshots of every character before and after the swap. All animations still play under their original names. Frame rate at or above 60fps with `get_performance_monitors`.

---

## 21. Decisions made beyond the source document

Everything here was either resolved by the project owner or is an explicit interpretation. **If you disagree with one during implementation, do not silently change it — implement as specified and append a note at the bottom of this section.**

### Owner-resolved

| # | Question | Decision |
|---|---|---|
| A1 | Platform and orientation | **Portrait mobile, 1080×1920.** Resolves the "tap" vs "click" ambiguity in favor of touch, with mouse emulation on for development. |
| A2 | Asset strategy | **Placeholder primitives first (M0–M5), Blender models after (M6).** The whole game loop must be playable before any modeling starts. |
| A3 | Boss | **A scaled-up orc barbarian** (`orc_warlord`): 1.70× scale, 280 HP, 22 damage, distinct coloring and shoulder pads. No new asset. |
| A4 | Document shape | **Phased build plan with verification gates** (§20). |
| A5 | Game over | **Run summary screen** with full stats, then a Retry that fully resets. |
| A6 | Equipment | **No equipping in the demo.** Items are loot and sell fodder only. The `equipped` field and `sellable_items()` filter exist and must work. |
| A7 | Console HUD | **Full status panel** — gold, inventory strip, and a per-hero row with name, HP numbers, and buff icons. |
| A8 | Level length | **6 encounters** (§12.1). |

### Interpretations made while writing this spec

| # | Ambiguity | Resolution and reasoning |
|---|---|---|
| D1 | Special abilities had no trigger condition | Every Nth action (warrior 3, ranger 4, priest 3), replacing that action's primary. Deterministic and readable, unlike a second independent timer. |
| D2 | "Cooldowns start half full" would still sync identical enemies | Half full **× a ±10% jitter**. Two shadow monsters with identical 1.8s cooldowns would otherwise act on the same frame — exactly the first-turn chaos the source doc's rule exists to prevent. The jitter serves the stated intent. |
| D3 | Priest heal with nobody wounded | Skip the special, use the primary, **retain** the pending special for the next action. Prevents a wasted heal without adding a targeting system. |
| D4 | "2 of the same icon" — adjacent or any two? | **Any two of the three positions.** Gives the clean 50.04% in §16.2. |
| D5 | Lightning payout "enemies are struck" — one or all? | **All living enemies.** Plural in the source doc, and it makes the lightning payout feel distinct from a hero attack. |
| D6 | Lightning damage source for the rolling buffer | Slot damage is **excluded** from `_last_hero_hits`. Including it would create a compounding feedback loop where slot damage inflates the average that drives future slot damage. |
| D7 | Fewer than 3 hero strikes recorded | Average whatever exists; if zero, use `SLOT_LIGHTNING_FALLBACK = 12`. |
| D8 | Ranger's target dying mid-flight | Retarget to a random living enemy; fizzle harmlessly if none remain. |
| D9 | Priest's "consider whether darkening looks good" | **Implemented and on**, behind `PRIEST_DARKEN_ENABLED`, so it can be evaluated from a screenshot and flipped off in one line. |
| D10 | Hero HP between encounters | **Persists.** No free heals. Makes the slot's plus payouts meaningful. |
| D11 | Where the shop rerolls | Items are generated **once per shop encounter** and cached. Reopening a tab never rerolls. |
| D12 | Party damage buff during non-combat | The 30s timer is **real time** and keeps running through travel, loot, and shop. |
| D13 | Party damage buff removal | Divide the multiplier back out rather than resetting to 1.0, so future stacking buffs stay correct. |
| D14 | Starting gold | **50.** Enough that the first shop is not empty-handed, low enough that slot gold and item sales matter. |
| D15 | Rarity/modifier value multipliers | Rolled per item within the §13.2 ranges, per the source doc's "randomize for now," with the enhancement TODO left verbatim in code. |
| D16 | No fish anywhere in "Sir Fish" | **Not resolved.** The name is treated as a working title with no in-game representation. Flag this for the owner rather than inventing fish content. |

---

## 22. Deferred — build the seam, not the feature

These are named in the source doc as future work. Leave the data fields and insertion points; do not implement.

- **Equipping weapons on heroes.** `Item.equipped` exists; `sellable_items()` filters on it; no UI or combat effect.
- **Potions and relics.** `Item.Kind` includes them; `Itemizer` never generates them.
- **Item modifiers affecting combat.** Modifiers are generated, displayed, and priced, but have **no gameplay effect** in the demo.
- **Additional slot machines**, and slot upgrades that raise payout frequency or magnitude. The source doc's core loop ("buying upgrades and finding items makes the slots give bigger and better bonuses more often") is the eventual heart of the game; the demo ships one fixed slot.
- **More upgrade buttons.** `UpgradeTray` (§17.4) reserves the space.
- **Branching maps and a visible level map.** The demo generates a linear, hidden sequence. `GameState.reset_run()` is the single function a future generator replaces.
- **Multiple levels.** One level, six encounters.
- **Designed (non-random) rarity and modifier multipliers** — see the TODO in §13.2.
- **Audio.** No sound in the demo. Do not add an `AudioStreamPlayer` anywhere; generated audio is out of scope.
- **Saving.** Nothing persists across application restarts.
