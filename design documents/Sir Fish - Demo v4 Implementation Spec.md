# Sir Fish — Demo v4 Implementation Specification

**Document type:** build prompt for an implementing model
**Project:** `C:\Projects\Godot\Sir Fish` (Godot 4.7-stable, Forward+)
**Supersedes:** `Sir Fish - Demo v3 Implementation Spec.md` **and** `Sir Fish - Demo v3.5 Implementation Spec.md`. **Both are dead.** Do not read them, do not cite them, do not resolve a conflict in their favour. v1 and v2 were already dead and stay dead. **This document is the whole specification.**
**Answers:** every open item in `QUESTIONS-v3.5.md` and `QUESTIONS-v3-m8a.md`. See §0.2. Both files are **closed**, as are `QUESTIONS.md`, `QUESTIONS-v2.md` and `QUESTIONS-v3.md`.
**Source:** v3 (the whole specification), v3.5's twelve-item amendment (M7.6, complete), the M8a implementation pass, and the two questions files above.

---

## 0. How to use this document

**M0 through M8a are built and verified.** Roughly 120 source files exist. A run plays from encounter 0 to the run summary, eight headless tests pass, the upgrade loop closes, the parallax is provably seamless, the shop pauses the game, and Sir Fish is a rigged, seven-clip Blender model in a procedural tank.

Your job is:

- **M8b — the three heroes** (§20), the next unstarted milestone.
- **M8c, M8d, M8e** after it, in order, each independently gated.
- **The outstanding verification backlog in §24**, which is small, specific, and owed from the M7.6 and M8a gates. It is not a blocker for M8b and it is not optional either.

Where this document gives a number, use that exact number. Where it gives a name, use that exact name. Where it differs from the code that exists, **the document wins and the code changes** — every such difference is listed explicitly in §21.2.

### 0.1 Non-negotiable working rules

1. **Use the Godot MCP Pro tools for all Godot work.** Read `CLAUDE.md` at the project root first.
   - Never edit `project.godot` by hand. Use `set_project_setting`. The accepted deviations already in that file (§21.3 C1, C3) are closed and must not be "tidied".
   - Prefer `update_property` (inspector values) over hardcoding visual values in scripts. Scripts hold *logic*; scenes hold *configuration*.
   - **Exception — resource-valued properties.** No tool in this MCP build can assign an existing `.tres`/`.tscn` to a node property (`add_resource` only *creates* a new inline resource; `update_property` writes `null`). Do **not** hand-edit `.tscn` files to work around this. Instead declare the property as `@export var x: SomeType = preload("res://path.tres")` in the node's script.
   - **Exception — changing a node's type, and removing a node.** See §0.1.4. These are the only cases where touching a `.tscn` by hand is permitted.
   - Use explicit type annotations everywhere. `var x := <call on an untyped variable>` is a hard parse error in 4.7; `const X := PackedVector2Array([...])` is not a constant expression — use `static var`.
2. **Use the Blender MCP tools for all 3D asset work** (M8). Do not download, import, or reference any third-party asset. Every mesh, texture, icon, material and glyph in this game is generated — procedurally in Godot, or modelled in Blender via MCP. §7.5 and §23.4 divide the parallax background between those two routes explicitly.
3. **Verify every milestone.** Each sub-milestone in §20 has its own gate. Drive it with `play_scene` + the runtime tools + the `Debug` harness (§19) + the headless tests (§19.3), screenshot it, and run `get_editor_errors` / `get_output_log`. **The gate is not passed while any error or warning exists.**
4. **Check `get_editor_errors` after every script write.** Use `validate_script` before `save_scene`.
5. **All balance and timing numbers live in `res://scripts/autoload/tuning.gd`** (§5). No magic numbers anywhere else. No file may hardcode a number this document names.
6. **When this document makes a claim about existing code, it was checked against the working tree.** Hold the next document to the same standard. §24's habit 4 is why.

#### 0.1.4 Tool availability is a fact to be checked, not assumed

`CLAUDE.md` lists tools this MCP build does not expose. `delete_node` is listed and **does not exist** — re-confirmed during the M7.6 pass. There is no scene-node removal tool of any kind, and no tool that deletes a `.tres`.

**Rule:** before a step that depends on a tool you have not already used this session, confirm the tool exists by name lookup. If it does not:

- If a documented alternative exists, use it and log the substitution in §21.5.
- If the only routes are (a) hand-editing a `.tscn` or (b) leaving a permanent orphan node in a scene, **take (a)**, edit the minimum number of lines, and log it. An orphan node in the root scene is a permanent defect; one logged hand-edit is not.
- If neither is possible, stop and raise it as a **BLOCKER** in `QUESTIONS-v4.md`.

Hand-editing `project.godot` remains forbidden in all cases.

#### 0.1.5 Two tool behaviours that have already cost a session each

Both were found the hard way. They are in §21.4 as traps and are repeated here because they bite during *setup*, before anyone has opened the traps table.

- **`add_node`'s `properties` dict silently drops `script`.** It applies regular exported vars only. A node created with `"script": "res://…"` in that dict arrives **scriptless**, with no error — and every property that depended on the script being present is dropped along with it. Always `attach_script` as a separate call, then re-apply the exported properties with `update_property`.
- **`add_scene_instance` / `save_scene` operate on the MCP's *currently open editor scene*,** which is not necessarily the scene most recently created with `create_scene`. Always `open_scene` the intended target first, and verify `get_scene_tree`'s **content** (not its `scene_path` label, which can be stale) before calling `save_scene`.

#### 0.1.6 Source control — recommended, owner's call

This project is **not a git repository**. During M8a an `add_scene_instance` mis-target (§0.1.5) overwrote `scenes/battle/battle_world.tscn` with a corrupted 891-line version; it was caught and hand-reconstructed from the corrupted file's own surviving content, but there was no safety net and the recovery was luck plus care rather than a `git checkout`.

Initialising a repository is one command and removes that entire failure class:

```bash
cd "C:/Projects/Godot/Sir Fish" && git init && git add -A && git commit -m "baseline: M8a complete"
```

**This is a recommendation, not a gate item, and it is the owner's call** — it is outside the scope of any milestone below. If it is declined, §0.1.5's verify-before-save discipline is the only protection there is, and it must be followed literally.

### 0.2 Where each open question is answered

Nine open items came out of `QUESTIONS-v3.5.md` and `QUESTIONS-v3-m8a.md`. All nine are resolved here and both files are closed. Resolutions are labelled **R1–R9** (v3's `A`, `C` and `E` labels are still in use in §21 and are not reused).

| R | Source | Question | Answer | Section |
|---|---|---|---|---|
| **R1** | v3.5 §9 | F2's status-icon alphas (0.28 / 0.22) — art call, confirm or move | **Ratified as final.** Confirmed on screen during the M7.6 gate: the warrior's body reads through his Defend ring for the full 4.0 s. No longer an open art call. | §17.5 |
| **R2** | v3.5 §9 | F3's `BattleCamera.size = 5.8` — art call, confirm or move | **Ratified as final.** All four clearance cases re-derived arithmetically in this document, including the warlord case the gate did not screenshot. | §7.2, §7.3 |
| **R3** | v3.5 substitutions | D2 — `Marquee` removed by hand-editing `slot_machine.tscn` | **Ratified** under §0.1.4's standing rule. No `delete_node` exists; the alternative was a permanent orphan. | §21.3 C6 |
| **R4** | v3.5 substitutions | F4 — buy card's 18 px right margin achieved with a spacer `Control`, not a margin on `PriceBox` | **Ratified.** `PriceBox` is a `VBoxContainer` and has no per-instance margin property; changing its type is not one of §0.1.4's exceptions. The specified *outcome* — the price no longer touching the card edge — is met, and `PriceBox` was not widened, which was the trap's actual intent. | §15.2, §21.3 C7 |
| **R5** | v3.5 substitutions | F4 — sell button's coin glyph placed via a child `HBoxContainer`, not a button icon slot | **Ratified.** `Button` centres its own `text` and has no per-instance icon slot for a custom-drawn `Control`. The button remains the click target. | §15.3, §21.3 C8 |
| **R6** | m8a §1 | Sir Fish's rig grew a third bone, `Helm` — is that acceptable, or was "two-bone" a hard constraint? | **Accepted, and now normative: the fish armature is three bones — `Root`, `Tail`, `Helm`.** The detach requirement is specific and load-bearing; "two-bone" was a sketch of minimum complexity with no downstream dependency. | §23.5, §17.7 |
| **R7** | m8a §2 | The tank was left as the existing procedural GDScript build rather than re-modelled in Blender — confirm or mandate the move | **Confirmed, and now permanent: the tank stays procedural in `sir_fish_tank.gd`. Do not move it to Blender, ever.** | §17.7, §23.5 |
| **R8** | m8a §4 | Sir Fish's clips were authored in Blender's own axes rather than ported from §9.0's convention | **Ratified.** §9.0's screen-plane convention binds the **combatants' shared clip set** only. Sir Fish has his own camera and his own single-character clip set; Blender-native axes are correct for him. | §9.0, §23.5 |
| **R9** | m8a §3 | The `battle_world.tscn` overwrite incident | **Not a design question.** It produces one hard tool trap (§0.1.5, §21.4) and one recommendation (§0.1.6). No spec text changes as a result. | §0.1.5, §0.1.6 |

**Four discovered bugs and one rig defect** are also folded in, as traps rather than as questions — they had one correct fix each and needed no design input: D4's `tween_method`/`bind()` argument order, D4's corpse-rush deadlock, F4's dropped `script` property, and M8a's `parent_type = 'BONE'` glTF round-trip failure. All four are in §21.4.

### 0.3 Engine version

`get_project_info` reports **4.7-stable (official)**, `forward_plus`. Do not change the declared feature set. Everything here uses APIs stable in 4.4+. If an API in this document does not exist, use the nearest equivalent and append a note to §21.5.

### 0.4 What v4 changes

v4 adds **no features**. It is a consolidation document:

1. **v3.5's twelve amendments are folded inline.** F1–F6 and D1–D6 are no longer a diff against v3; they are simply what §7, §11, §15, §16, §17 and §18 now say. There is no longer a "superseded by" table to chase.
2. **Nine open questions are answered** (§0.2), including the two art calls v3.5 deliberately left to the owner and the two genuine spec-vs-spec conflicts M8a hit.
3. **Five new traps** are recorded from bugs found live during M7.6 and M8a (§21.4). Three of them are MCP-tool behaviours, not game bugs, and are the kind that cost a whole session to rediscover.
4. **The outstanding verification backlog is stated as a list** (§24) rather than buried in a gate log's closing paragraph. Seven items are owed. Four came from M7.6, three from M8a, and one M7.6 item was closed incidentally during M8a.
5. **Milestone status is current:** M7.5, M7.6 and M8a are complete; M8b is next.

### 0.5 Scope discipline

This is still a **demo**. Build exactly what is specified. Systems marked *Deferred* in §22 must be structurally accommodated and must not be implemented. Do not retune combat, do not touch `SLOT_STRIP` or the win rule, do not add audio.

---

## 1. What the game is

**Sir Fish** is an autobattler crossed with a slot-machine incremental.

- The **top third** of the screen is an autobattler: a party of three heroes travels left-to-right through a sequence of encounters and fights without any player input.
- The **bottom two thirds** is the **management console**: a slot machine that spins continuously during combat and pays out in damage, gold, and healing; a button that buys the party temporary advantages; and an upgrade tray that makes the slot pay bigger and more often.

The player never controls the heroes. The player's entire agency lives in the console.

### 1.1 Design pillars (use these to break ties)

1. **Legibility over spectacle.** A player must be able to read what happened in combat at a glance. This is why cooldowns start staggered, why every hit detaches a visible chunk of health bar, why area effects stagger, why targeting is simple — and why the health bars do not overlap and the status icons do not hide the character wearing them.
2. **The console is always doing something.** Even when the player isn't tapping, the slot is moving and the upgrade tray is live. Dead air is a bug.
3. **Juice on every state change.** Chests pop, bars detach and float, lightning cracks, symbols slam into place, the fish reacts. Nothing appears or disappears without a tween.
4. **Bold, flat, primary colour.** Positive references: *Breath of the Wild*, *CrossCode*, *Monster Train*. Negative references: *DOOM*, *Halls of Torment*, *Voin*. If it reads as gritty, desaturated, or brown, it is wrong.

### 1.2 Who Sir Fish is

**Sir Fish is the player.** He is a small armoured fish — a knight's helm, a gold circlet, blue scales — in a glass tank mounted on the left side of the management console, directly beside the button you press. He is the one running the war room. The heroes are his employees.

He is **purely decorative and has zero gameplay effect**, and that is deliberate: he is the emotional read on state the numbers can't give you. He cheers when the slot pays, darts when a hero is hit, sinks to the gravel when one dies, and lies on his side when the run ends. The full state table is §17.7.

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
| `rendering/anti_aliasing/quality/msaa_3d` | **`2`** — the enum value for **4× MSAA**. Stored as `2.0`; see below. |
| `rendering/environment/defaults/default_clear_color` | `Color(0.494, 0.784, 0.890)` (`#7EC8E3`) |
| `input_devices/pointing/emulate_touch_from_mouse` | `true` |
| `application/run/main_scene` | `res://scenes/main.tscn` |
| `application/config/name` | `Sir Fish` |
| `physics/common/physics_ticks_per_second` | `60` |
| `sir_fish/debug/harness` | `true` — custom setting, see §19 |

**`msaa_3d` is stored as `2.0` and that is fine.** `set_project_setting` coerces every numeric argument to a float, so the file reads `anti_aliasing/quality/msaa_3d=2.0` and `get_project_settings` reports TYPE_FLOAT. The rendering server casts it to `2` on read, so **4× MSAA is what is actually applied** — confirmed on screen. Hand-editing `project.godot` to change one Variant type would break §0.1.1 to fix nothing observable. **Leave it. Do not "fix" it in a later pass.** If a future MCP build gains a typed setter, changing it then is free.

The inverted-hull outline is the entire art direction and is 0.018 world units thin; it aliases visibly at 2×. The scene has under 40 meshes, so the cost is irrelevant on desktop. If a mobile export preset is ever added, override to `1` there and nowhere else.

The window override (540×960) exists so the game window fits a development monitor while the logical viewport stays 1080×1920. **All coordinates in this document are logical viewport pixels.**

### 2.1 Screen budget (exact, sums to 1920)

| Region | Y range | Height | Owner |
|---|---|---|---|
| Battle viewport | 0 – 640 | 640 | `BattleView` (3D SubViewport) |
| Divider | 640 – 648 | 8 | `ConsoleDivider` (gold bar) |
| Status panel | 648 – 948 | 300 | `StatusPanel` |
| Slot machine | 948 – 1548 | 600 | `SlotMachine` |
| Fish tank / damage button / slot counter | 1548 – 1708 | 160 | `SirFishTank`, `PartyDamageButton`, `SlotCounter` |
| Upgrade tray | 1708 – 1920 | 212 | `UpgradeTray` |

640 is exactly one third of 1920.

---

## 3. Architecture

### 3.1 Directory layout

This is the **complete** tree.

```
res://
├── assets/
│   ├── display_font.tres                       FontVariation, §6.5
│   ├── theme.tres
│   ├── materials/{cel_shade,outline}.tres
│   ├── meshes/
│   │   └── sir_fish.glb                        M8a — done
│   └── shaders/
│       ├── cel_shade.gdshader                  depth_draw_always, §6.2
│       ├── outline.gdshader
│       ├── smoke.gdshader
│       ├── parallax_layer.gdshader
│       └── water.gdshader
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
│   │   ├── sir_fish_tank.tscn
│   │   ├── slot_counter.tscn
│   │   ├── upgrade_tray.tscn
│   │   ├── upgrade_button.tscn
│   │   └── bonus_strip.tscn
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
│   │   ├── upgrades.gd          Upgrades
│   │   └── debug.gd             Debug
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
│   │   ├── parallax_profiles.gd
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
│   │   ├── sir_fish_tank.gd
│   │   ├── sir_fish.gd
│   │   ├── slot_counter.gd
│   │   ├── upgrade_tray.gd
│   │   ├── upgrade_button.gd
│   │   └── bonus_strip.gd
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
│   └── stats/{warrior,ranger,priest,shadow_monster,orc_barbarian,orc_warlord}.tres
└── tests/
    ├── test_support.gd                         preloaded, never class_name (§19.3)
    ├── test_slot_odds.{gd,tscn}
    ├── test_item_distribution.{gd,tscn}
    ├── test_damage_chunk.{gd,tscn}
    ├── test_retarget.{gd,tscn}
    ├── test_economy.{gd,tscn}
    ├── test_upgrades.{gd,tscn}
    ├── test_parallax_seam.{gd,tscn}
    └── test_autoload_safety.{gd,tscn}
```

**`res://resources/levels/` is gone**, as required — see §12.1. `res://resources/` holds only `stats/`.

### 3.2 Autoloads

The registration order is **not load-bearing**, and this document does not pretend it is. `add_autoload` in this MCP build only **appends**, and no tool reorders or removes an autoload, so the actual order is:

```
Tuning, RNG, EventBus, Itemizer, GameState, MCPScreenshot, MCPInputService,
MCPGameInspector, Upgrades, Debug
```

`Upgrades` sits after `GameState`. **This is accepted and must not be changed.** Hand-editing `project.godot`'s `[autoload]` block to reorder it would break §0.1.1 to fix nothing: the ordering constraint was only ever about load-time reads, and nothing reads a payout, a bonus, or another autoload's state during `_ready()`.

The real requirement was never an order. It is this invariant:

> **Autoload independence invariant.** No autoload may read state from, or call a method on, another autoload during `_init()` or `_ready()`. Autoloads may only reference each other from methods invoked after the scene tree is up — which, for every cross-autoload call in this project, means from `RunController` or later.

Current cross-references, all compliant: `Upgrades.buy()` touches `GameState`; `GameState.reset_run()` touches `Upgrades`; both are called long after every autoload exists. `Debug` touches everything, always from a command.

`test_autoload_safety.gd` (§19.3) asserts the invariant by static inspection of every autoload script: no autoload identifier may appear inside a `_ready()` or `_init()` body. This is strictly stronger than an ordering rule and it survives the MCP appending future autoloads anywhere it likes.

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
│   ├── SirFishTank (SubViewportContainer)     # pos (8,898)   size 164×164
│   ├── PartyDamageButton (Button)             # pos (180,900) size 720×160
│   ├── SlotCounter (Control)                  # pos (908,898) size 164×164
│   └── UpgradeTray (Control)                  # pos (0,1060)  size 1080×212
├── ModalLayer (Control)                       # full rect, mouse_filter = IGNORE
│   │                                          # process_mode = PROCESS_MODE_ALWAYS  (§15.5)
│   ├── ShopModal (hidden by default)
│   └── RunSummary (hidden by default)
└── RunController (Node)                       # run_controller.gd — drives everything
```

`ModalLayer` is a `Control`, not a `CanvasLayer`: theme inheritance walks the `Control` tree, and a `CanvasLayer` severs it. `Main.theme` is the only theme assignment in the project; neither modal declares its own.

> **Standing rule:** `ModalLayer` is the **last `Control` child of `Main`**. Nothing that draws may be added to `Main` after it. Non-drawing `Node`s (controllers, timers, services) may follow it freely. If something that draws must sit above the modals, add it as a child of `ModalLayer`.

`ModalLayer.process_mode` is `PROCESS_MODE_ALWAYS` and **must stay that way** — it is what keeps the shop modal's own close button alive while the shop has the tree paused (§15.5).

#### 3.3.1 The 900–1060 row, exactly

The tank / button / counter row is worth stating in full because two of its numbers look like typos and neither is.

**Vertical.** §2.1 gives the row 160 px (console-local 900–1060). The tank and the counter are **164** tall and sit at **y 898**, so each overhangs the band by 2 px top and bottom. That is deliberate centring: `900 − (164 − 160)/2 = 898`. The overhang lands on the slot machine's bottom edge and the upgrade tray's top edge, neither of which draws anything there. **Do not "fix" 898 to 900.**

**Horizontal.** At 164 wide the row closes exactly, with a uniform gutter and a true mirror:

```
8 + 164 + 8 + 720 + 8 + 164 + 8 = 1080
tank centre  90   button centre 540   counter centre 990
```

The counter's contents (§17.8) are all centred within it.

**Why a SubViewport:** the battlefield is 3D and must be clipped to the top 640 px. `BattleView` and `BattleOverlay` are the same size at the same position, so a point from `camera.unproject_position()` maps **1:1** into `BattleOverlay` local coordinates with no extra transform.

### 3.4 EventBus signals

Define exactly these. All cross-system communication goes through them — no direct node-path lookups between the battle and the console. Keep `@warning_ignore_start("unused_signal")` at the top of the file.

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
signal party_bonuses_changed(bonuses: Dictionary)

# --- Console ---
signal slot_spin_started()
signal slot_spin_stopped(symbols: Array)       # Array[int] of 3 Sym values
signal slot_payout(kind: String, count: int)   # kind in "lightning"|"gold"|"heal"
signal party_damage_buff_started(duration: float)
signal party_damage_buff_ended()
signal upgrade_purchased(id: StringName, new_level: int)
```

`BattleDirector` also connects `combatant_died` for its own per-death corpse fade (§10.4).

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
@export var special_requires_wounded_ally: bool = false   # §10.2 — priest only
@export var special_targets_opponent: bool = true         # §10.2 — false: warrior, priest
@export var telegraphs_primary: bool = false              # §9.3 — priest only
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

**Three behavioural flags, no id checks.** Each replaced a hardcoded `stats.id ==` branch:

| Field | True for | Encodes |
|---|---|---|
| `special_requires_wounded_ally` | priest | this special is pointless on a healthy party — bank it (§10.2) |
| `special_targets_opponent` | everyone except warrior and priest | this special needs a living opponent to aim at (§10.2) |
| `telegraphs_primary` | priest | this character's **primary** attack gets a charge telegraph (§9.3) |

`special_requires_wounded_ally` and `special_targets_opponent` are independent — the warrior needs no opponent *and* no wounded ally; the priest needs no opponent *but does* need a wounded ally — so one field cannot carry both.

> **Standing rule:** no combat branch may key on `stats.id`. Character-specific behaviour is a `CombatantStats` field. `id` is for lookup, logging and `Debug` addressing only. **Grep for `stats.id ==` after any combat change.** The only legitimate hits today are `combatant_rig.gd`'s three placeholder-building checks, which M8b/M8c delete wholesale. `debug.gd`'s combatant resolver is also legitimate (§19.2) and compares with `String(c.stats.id) != want`, so it does not match that grep at all.
>
> This rule has caught three separate violations across three passes, each time because someone fixed the instance they were shown and not its neighbour. **When you fix an instance of a bad pattern, grep for the pattern.**

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
@export var modifiers: Array[Dictionary] = []
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

A modifier entry looks like `{ "id": &"dmg_flat", "label": "+4 Damage", "roll": 4, "value_mult": 0.42 }`. The `"roll"` key is mandatory — modifiers have gameplay effects (§13.5), so the raw magnitude must survive alongside the formatted label.

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
    "gold_spent": 0,
    "damage_dealt": 0,
    "damage_taken": 0,
    "slot_spins": 0,
    "slot_wins": 0,
    "items_found": 0,
    "items_sold": 0,
    "upgrades_bought": 0,
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

**No method on `GameState` may be called from another autoload's `_ready()`** (§3.2).

**Hero HP persists across encounters.** There is no between-encounter heal. Healing comes only from the priest and the slot.

`run_stats["run_time"]` accrues in `RunController._process`, which stops while the shop is open — so **shop time is not run time** (§15.5).

---

## 5. Tuning — single source of truth

Everything below lives in `res://scripts/autoload/tuning.gd` as `const`. **No other file may hardcode these numbers.**

### 5.1 Timing

```gdscript
const TRAVEL_SPEED := 4.0                 # world units/sec at full scroll speed
const TRAVEL_ACCEL_TIME := 0.6
const TRAVEL_DECEL_TIME := 0.9
const ENEMY_FADE_IN_TIME := 0.35
const ENEMY_DEATH_HOLD := 1.5             # per-death corpse hold, slow path (§10.4)
const ENEMY_DEATH_FADE := 2.0             # per-death corpse fade, slow path (§10.4)
const ENEMY_DEATH_HOLD_RUSH := 0.30       # corpse hold when the fight is already won
const ENEMY_DEATH_FADE_RUSH := 0.45       # 0.30 + 0.45 = 0.75, inside ENCOUNTER_RESOLVE_PAUSE
const BARS_POP_IN_TIME := 0.25
const COOLDOWN_START_FRACTION := 0.5      # every combatant starts half-charged
const COOLDOWN_START_JITTER := 0.10       # ±10%, de-syncs identical enemies
const HURT_ANIM_TIME := 0.30
const DEAD_HERO_EXIT_TIME := 1.6
const ENCOUNTER_RESOLVE_PAUSE := 0.8
const AOE_STAGGER := 0.06                 # gap between per-target resolutions of any AoE
const DAMAGE_NUMBER_SPREAD := 46.0        # px offset per concurrent number, §11.4
```

### 5.2 Combatant stats

`attack_cooldown` is **recovery after an action ends**, not the interval between actions, per the initial vision: *"after their attack finishes, their cooldown bar would fill to 100% and drain as the cooldown completes."* The **real cycle** column is authoritative for balance discussion.

| id | display_name | hero | max_hp | base_damage | `attack_cooldown` | attack len | **real cycle** | special_every_n | special len | wounded-gated | targets opponent | telegraphs | model_scale |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `warrior` | Warrior | yes | 120 | 12 | 1.6 | 0.70 | **2.30** | 3 | 0.55 | no | **no** | no | 1.00 |
| `ranger` | Ranger | yes | 80 | 14 | 1.4 | 0.80 | **2.20** | 4 | 0.80 | no | yes | no | 0.95 |
| `priest` | Priest | yes | 70 | 10 | 2.0 | 0.95 | **2.95** | 3 | 0.85 | **yes** | **no** | **yes** | 0.95 |
| `shadow_monster` | Shadow Monster | no | 40 | 8 | 1.8 | 0.60 | **2.40** | 0 | — | no | yes | no | 0.90 |
| `orc_barbarian` | Orc Barbarian | no | 70 | 15 | 2.4 | 0.85 | **3.25** | 0 | — | no | yes | no | 1.15 |
| `orc_warlord` | Orc Warlord | no | 280 | 22 | 2.0 | 0.98 | **2.98** | 0 | — | no | yes | no | 1.70 |

The four flag columns are `special_requires_wounded_ally`, `special_targets_opponent` and `telegraphs_primary` (§4.1). "Targets opponent" is meaningless for a character with no special and is left at its `true` default. The warlord's attack length is 0.85 ÷ 0.87 = 0.98 s, because it plays at `speed_scale = 0.87` (§8.7).

The numbers are **not** retuned. Re-tuning is a post-demo task (§22).

### 5.3 Ability tuning

```gdscript
const WARRIOR_DEFEND_REDUCTION := 0.50    # incoming damage × (1 - 0.50)
const WARRIOR_DEFEND_DURATION := 4.0
const RANGER_BOMB_AOE_MULT := 0.75
const PRIEST_HEAL_MULT := 1.0
const PRIEST_DARKEN_ENABLED := true
const DAMAGE_VARIANCE := 0.15             # every hit rolls × randf_range(0.85, 1.15)
const SPECIAL_CAST_FLASH_TIME := 0.15     # §9.6
```

### 5.3b Battlefield geometry

```gdscript
const HERO_SLOT_X := [-4.0, -2.5, -1.0]   # priest, ranger, warrior (left → right)
                                          # 1.5 apart so 140px bars clear each other (§7.2)
const ENEMY_X_MIN := 1.2
const ENEMY_X_MAX := 4.0
const MAX_ENEMIES := 3
```

`BattleCamera.size` is **5.8** and is a scene property, not a constant — set it with `update_property` on `battle_world.tscn`, never in code. These four numbers are solved jointly; §7.2 has the derivation and the inequality that binds them.

### 5.4 Economy

```gdscript
const STARTING_GOLD := 75
const SHOP_BUY_MARKUP := 1.5              # buy price  = round(value × 1.5)
const SHOP_SELL_RATE := 0.5               # sell price = round(value × 0.5)
const LOOT_ITEMS_PER_CHEST := 2
const SHOP_ITEMS_FOR_SALE := 3
```

Expected gold per spin = `0.14937 × 35 + 0.01743 × 90` = **6.80**. Across the ~14 spins of encounters 0 and 2 that is ~95 gold; plus 75 starting and ~40 from selling the two chest items, the party reaches the shop with roughly **210 gold** on average. Across a full six-encounter run the slot pays roughly 300 gold. `test_economy.gd` (§19.3) asserts this **as a mean, not as a single sample**.

### 5.5 Slot machine

```gdscript
enum Sym { LIGHTNING, GOLD, PLUS, BLANK }

const SLOT_REEL_STOPS := 27
const SLOT_STRIP: Array[int] = [ ... ]    # see §16.2 — 27 entries, 7/7/7/6. DO NOT CHANGE.
const SLOT_SPIN_DURATION := 1.10          # reel 0 stop time
const SLOT_REEL_STAGGER := 0.28           # reel 1 stops +0.28s, reel 2 stops +0.56s
const SLOT_RESULT_HOLD := 0.85            # pause after reel 2 stops before the next spin
const SLOT_PAY_2_GOLD := 35
const SLOT_PAY_3_GOLD := 90
const SLOT_HEAL_2_FRACTION := 0.25        # lowest-hp hero healed 25% of max
const SLOT_HEAL_3_FRACTION := 0.25        # entire party healed 25% of max
const SLOT_LIGHTNING_2_MULT := 1.0
const SLOT_LIGHTNING_3_MULT := 2.0
const SLOT_LIGHTNING_FALLBACK := 12       # used if no hero strike is recorded yet
const SLOT_ATTRACT_SPEED := 0.15          # fraction of spin speed in attract mode, §16.6
const SLOT_ATTRACT_DIM := Color(0.78, 0.78, 0.82)
```

### 5.6 Party damage button

```gdscript
const PARTY_DAMAGE_BUFF_MULT := 1.10      # +10%
const PARTY_DAMAGE_BUFF_DURATION := 30.0
```

The duration is **real time, encounter-agnostic, and pause-aware** — it drains in `_process`, which stops while the shop modal holds the tree paused (§15.5).

### 5.7 Upgrades

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

### 5.8 Parallax

```gdscript
const PARALLAX_TILE_COPIES := 3
const PARALLAX_TILE_WIDTH_PROC := 36.0    # layers 1-3, generated (§7.5)
const PARALLAX_TILE_WIDTH_MODEL := 12.0   # layers 4-5, modelled (§23.4)
const PARALLAX_SEAM_EPSILON := 0.0001     # test_parallax_seam's tolerance
```

**Tile width is per-layer, not global**, carried as node metadata seeded from these two constants. §7.4.1 explains why the generated layers take three times the modelled ones.

### 5.9 Health chunk

```gdscript
const CHUNK_FLING_X := 45.0               # ± px sideways
const CHUNK_FLING_Y_MIN := 25.0           # px upward, lower bound
const CHUNK_FLING_Y_MAX := 65.0           # px upward, upper bound
const CHUNK_SPIN := 0.45                  # ± rad
const CHUNK_FLIGHT_TIME := 0.70           # NOT halved — pacing, not force (§11.2)
```

### 5.10 Status icons

```gdscript
const ICON_DEFEND_RADIUS := 36.0
const ICON_DEFEND_FILL_ALPHA := 0.28
const ICON_DEFEND_GLYPH_BOX := 46.0
const ICON_HEAL_RADIUS := 42.0
const ICON_HEAL_FILL_ALPHA := 0.22
const ICON_HEAL_GLYPH_BOX := 50.0
const ICON_RING_WIDTH := 5.0
```

These are **ratified final** (§0.2 R1), not provisional art values. See §17.5 for the constraint that governs any future change.

### 5.11 Colours

Every entry in §6.1's palette lives here as a `const C_*` — `C_FAR_HILLS`, `C_GOLD`, `C_TEXT_DIM`, `C_ROCK` and so on. **No file may write a hex literal.**

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
| Fire orange | `#FF7A1A` | fire-modifier damage numbers |
| Ice cyan | `#5BC8F5` | ice-modifier damage numbers |
| Fish scale | `#4A9BE8` | Sir Fish body |
| Fish fin | `#3B6FD4` | Sir Fish fins |
| Rock grey | `#7D8A6B` | layer-4 scatter rocks (§23.4) |
| Console bg | `#231F2E` | |
| Console panel | `#332C42` | |
| Panel border | `#4A4260` | |
| Text primary | `#FFF6E0` | |
| Text dim | `#9B93AE` | |

**Do not desaturate.** If a colour needs to recede, shift it toward the sky blue, not toward grey.

Every entry lives in `tuning.gd` as a `const C_*` (§5.11).

### 6.2 Cel shader — `res://assets/shaders/cel_shade.gdshader`

**Write exactly this, including `depth_draw_always`.**

An earlier draft mandated `depth_draw_opaque` while also adding `blend_mix` to the outline shader so the inverted hull could fade. Those two instructions are incompatible, and together they rendered **every character as a solid black silhouette.** The chain:

1. With an opaque outline, the hull rendered in the **opaque pass** — before all transparent geometry — and wrote depth.
2. The cel body is transparent (`blend_mix`), so it rendered afterwards and drew on top of the hull. Correct outline.
3. Adding `blend_mix` moved the hull into the **transparent pass**. Within one object, `next_pass` renders *after* the base material — so the hull now draws on top of the body.
4. A transparent material with `depth_draw_opaque` writes **no depth at all**, so the body left nothing for the hull to be depth-tested against. The hull covered it completely.

With `depth_draw_always` the body writes depth, the hull is rejected everywhere except the silhouette rim — which is exactly what an inverted-hull outline is for — and §6.3's alpha fade still works, because the hull is still transparent. Verified on screen before and after.

```glsl
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, specular_disabled;

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

One always-transparent variant is used everywhere. The scene has under 40 meshes, so the sorting cost is irrelevant.

> **Trap.** If a character ever renders as a flat black silhouette, this render mode is the first thing to check. The M8 gate screenshots exist partly to catch a regression here after a mesh swap.

### 6.3 Outline shader — `res://assets/shaders/outline.gdshader`

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

`CelMaterials.set_alpha(node, a)` sets the `alpha` uniform on **both** the cel material and its `next_pass` outline material, and **`outline_width` is never touched at runtime**.

`CelMaterials.flash()` remembers the base colour once via `set_meta("base_albedo")` on first use, never re-read from the live albedo. Reading the live albedo lets two overlapping flashes latch white in permanently.

**Meshes imported from Blender in M8 keep this exact pairing.** A `.glb` import arrives with `StandardMaterial3D`s; every one is replaced with the cel material plus this outline as `next_pass` during the swap (§23.3). A character that reads as untextured plastic after a swap has skipped this step.

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

**Any `SubViewport` with `own_world_3d = true` needs its own copy of this.** There is exactly one — Sir Fish's tank (§17.7).

### 6.5 Typography

`res://assets/display_font.tres` — a `FontVariation` with:

- `variation_embolden = 0.35`
- `variation_transform = Transform2D(1.06, 0, 0, 1.0, 0, 0)` — 6% wider, for weight without smearing
- `spacing_glyph = 2`
- `base_font` left **empty**, so it resolves to the theme's default font.

Godot's built-in font is part of the engine, not a third-party asset, and `FontVariation` synthesises a heavier face at runtime shipping nothing — so §0.1.2 holds.

Project-wide `Theme` at `res://assets/theme.tres`, assigned once to `Main.theme` (§3.3):

- `default_font_size = 34`
- `Label/colors/font_color = #FFF6E0`
- `Button` StyleBoxFlat: `bg_color = #4A6FA5`, `corner_radius_* = 16`, `border_width_* = 4`, `border_color = #F2C230`, content margins 24/24/18/18
- `Button:disabled` StyleBoxFlat: `bg_color = #3A3548`, `border_color = #5C5470`, font colour `#7A7290`
- `PanelContainer` StyleBoxFlat: `bg_color = #332C42`, `corner_radius_* = 20`, `border_width_* = 3`, `border_color = #4A4260`
- **Type variation `DisplayLabel`** (base type `Label`): `font = res://assets/display_font.tres`, `font_outline_size = 6`, `font_outline_color = #0F0E14`

**Every string at font size 40 or above must use `theme_type_variation = &"DisplayLabel"`.**

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
│   ├── Slot0 (Marker3D)            # Priest   (leftmost)
│   ├── Slot1 (Marker3D)            # Ranger
│   └── Slot2 (Marker3D)            # Warrior  (front line)
├── EnemyRoot (Node3D)
├── PropRoot (Node3D)
└── ProjectileRoot (Node3D)
```

**Hero order is fixed left-to-right: Priest, Ranger, Warrior.**

`Slot0`/`Slot1`/`Slot2` are **vestigial**. Positions come from `Tuning.HERO_SLOT_X` via `battle_world.gd`'s `hero_slot_position()`. Do not "sync" the markers and do not trust their stored values.

### 7.2 `BattleCamera` and the framing geometry

| Property | Value |
|---|---|
| `projection` | `PROJECTION_ORTHOGONAL` |
| `size` | **`5.8`** (vertical extent in world units) |
| `near` / `far` | `0.05` / `200.0` |
| `position` | `(0.0, 2.2, 12.0)` |
| `rotation` | `(0, 0, 0)` — dead-on side view, no tilt |

**Change `size` only.** Moving the camera's `position.y` shifts the horizon against parallax layer geometry authored for this framing, which is exactly the kind of unforced coupling to avoid.

**Derived, and relied on throughout:**

- Viewport aspect = 1080/640 = **1.6875**
- Scale: `640 / 5.8` = **110.3 px per world unit**. A 1.0-scale character (1.8 units) is **199 px** tall.
- Camera half-width: `5.8 × 0.84375` = **±4.89**. Visible horizontal extent **9.79 units**.
- Visible vertical range: **y ∈ [−0.7, 5.1]**. Ground plane is `y = 0`.

#### 7.2.1 Why the battle line is this narrow — the bar-overlap constraint

`CombatantBars` is **140 px wide** regardless of `max_hp` (§11), and is centred on each combatant's anchor. Two adjacent combatants therefore need more than 140 px of screen separation or their bars fuse into an unreadable block — which is a pillar-1 failure on the single most-read element in the battle.

> **The binding inequality:** `spacing × (640 / camera.size) > 148`
>
> 140 px of bar plus a minimum 8 px gutter. Any future change to `HERO_SLOT_X`, `ENEMY_X_MIN`/`MAX`, or `camera.size` must re-check it. **`HERO_SLOT_X` spacing and `CombatantBars`' 140 px width are coupled.**

Narrowing the enemy spread and the centre gap is what pays for the hero spread, and the narrowed line is in turn what permits `size = 5.8`. All four numbers are one solution, not four independent choices.

**Every clearance case, verified arithmetically. R2 ratifies `size = 5.8` on this basis:**

| Case | Position | Extent | Inside ±4.89? |
|---|---|---|---|
| Hero bar gutter | 1.5 units apart | `1.5 × 110.3 − 140` = **25.5 px** | ✔ no overlap |
| Enemy bar gutter, 3 enemies | 1.4 units apart | `1.4 × 110.3 − 140` = **14.4 px** | ✔ no overlap |
| Leftmost hero (priest) | −4.0 | half-width ~0.35 → **−4.35** | ✔ |
| Lone `orc_barbarian` | `(1.2 + 4.0)/2` = 2.6 | half-width ~0.5 → **3.1** | ✔ |
| Rightmost of 3 enemies | 4.0 | half-width ~0.5 → **4.5** | ✔ |
| **Warlord, at index 0** | 1.2 | `model_scale` 1.70, half-width ~0.7 → **1.9** | ✔ comfortably |
| **Warlord, if it landed at index 1 of 2** | 4.0 | half-width ~0.7 → **4.7** | ✔ (see below) |

**A note on the warlord rule.** §7.3 requires `orc_warlord` to be listed **first** in `enemy_stat_ids` so it takes index 0. At the old `size = 6.5` framing that rule was load-bearing — the warlord would have reached 5.5 against a ±5.48 half-width and clipped. At `size = 5.8` the narrowed line means it now fits at either position with 0.19 units to spare. **The rule stays anyway**: it costs nothing, it is already encoded in `build_level()`, and re-widening the line would make it binding again. Do not remove it on the grounds that it is currently slack.

**What this framing does *not* fix, stated plainly.** Characters occupy roughly a third of the frame height and the upper half is empty sky. That is **geometry, not a bug**: a 1.6875:1 viewport holding a ~9-unit battle line caps a 1.8-unit character at about a third of the frame whatever the camera does. There is no camera number that fixes it — zooming further in pushes the outermost combatant out of frame. The sky is an **art** problem, solved by taller hills and tree canopy in layers 1–3 and by the M8d environment pass. **Do not chase it with the camera.**

**The camera stays dead-on.** A tilt would break the 1:1 `unproject_position` → `BattleOverlay` mapping the bars depend on (§11.1) and put the parallax layers into perspective disagreement with their fake-parallax scroll speeds. Animations move in the screen plane instead (§9.0).

No camera shake except where §9 and §11.4 specify it.

### 7.3 Enemy slot placement

```gdscript
func enemy_slot_x(index: int, total: int) -> float:
    if total <= 1:
        return (Tuning.ENEMY_X_MIN + Tuning.ENEMY_X_MAX) * 0.5     # 2.6
    return Tuning.ENEMY_X_MIN \
        + (Tuning.ENEMY_X_MAX - Tuning.ENEMY_X_MIN) * (float(index) / float(total - 1))
```

**List `orc_warlord` first in `enemy_stat_ids`** so it takes index 0 — see §7.2.1.

Enemies face **−X**; heroes face **+X**. Facing is `rotation.y = PI` on the enemy `Combatant` node. **Never use negative scale** — it inverts the normals the inverted-hull outline depends on.

### 7.4 Parallax background — architecture

Orthographic projection gives no free parallax, so it is faked by scroll speed. Five layers, each a `Node3D` holding **three** copies of one tile that wrap.

| Layer | Node name | Z | Speed mult | Tile width | Route | Content |
|---|---|---|---|---|---|---|
| 1 | `LayerHills` | -14 | 0.10 | 36.0 | **procedural (§7.5)** | `#4A9E6F` rolling hill silhouette |
| 2 | `LayerFarTrees` | -9 | 0.28 | 36.0 | **procedural (§7.5)** | `#2E8B57` conifer silhouette cluster |
| 3 | `LayerNearTrees` | -5 | 0.55 | 36.0 | **procedural (§7.5)** | `#1E6B45` larger mixed tree silhouettes |
| 4 | `LayerGround` | 0 | 1.00 | 12.0 | **Blender (§23.4)** | ground plane, scattered rocks, grass tufts |
| 5 | `LayerBrush` | +3 | 1.35 | 12.0 | **Blender (§23.4)** | bush and grass meshes, in front of characters |

Each layer carries `speed_mult` and `tile_width` as node metadata. Tiles are **centred on their own origin** — a tile at `position.x = p` spans world `x ∈ [p − W/2, p + W/2]` — and start at `−W, 0, +W`:

```gdscript
var scroll_speed: float = 0.0             # 0 = stopped; RunController tweens this

func _process(delta: float) -> void:
    if is_zero_approx(scroll_speed):
        return
    for layer: Node3D in _layers:
        var mult: float = float(layer.get_meta("speed_mult", 1.0))
        var w: float = float(layer.get_meta("tile_width", Tuning.PARALLAX_TILE_WIDTH_MODEL))
        for tile: Node3D in layer.get_children():
            tile.position.x -= scroll_speed * mult * delta
            if tile.position.x <= -w:
                tile.position.x += w * float(Tuning.PARALLAX_TILE_COPIES)
```

`reset_tiles()` (§18.3) restores `−W, 0, +W` per layer using the same meta.

Do not name any parameter `scale` in this file — it shadows `Node3D.scale`.

`RunController` starts travel by tweening `scroll_speed` `0 → Tuning.TRAVEL_SPEED` over `TRAVEL_ACCEL_TIME` with `TRANS_SINE/EASE_OUT`, and stops it by tweening back to `0` over `TRAVEL_DECEL_TIME` with `TRANS_CUBIC/EASE_OUT`.

#### 7.4.1 Why the generated layers are three times wider

Three copies of one tile means the pattern repeats every `W` world units. How visible that is depends on the layer's speed, and the two effects pull in opposite directions:

| Layer | u/s at `TRAVEL_SPEED` 4.0 | W | Repeat period | A feature's dwell on screen |
|---|---|---|---|---|
| 1 Hills | 0.40 | 36 | 90.0 s | 24.5 s |
| 2 Far trees | 1.12 | 36 | 32.1 s | 8.7 s |
| 3 Near trees | 2.20 | 36 | 16.4 s | 4.4 s |
| 4 Ground | 4.00 | 12 | 3.0 s | 2.4 s |
| 5 Brush | 5.40 | 12 | 2.2 s | 1.8 s |

(Dwell = the 9.79-unit visible width ÷ the layer's speed.)

**A slow layer needs a long period; a fast one does not.** A near-tree cluster lingers for four seconds, so the eye registers it as a landmark and notices its return. A brush clump crosses the frame in under two seconds and reads as motion, not as an object worth remembering. Across the demo's ~21 s of total scrolling, a 12-unit near-tree tile would return close to four times — plainly a loop. At 36 units it returns once.

That the three layers needing a long period are exactly the three generated in code is a convenience, not a coincidence: distance and slowness go together. Tripling `W` on a generated layer costs three times the vertices of something already trivial, and §7.5.3's single-mesh rule makes even that free in draw calls. Tripling it on a **modelled** layer costs three times the modelling, which is why §23.4 keeps layers 4 and 5 at 12.0 — and their speed means they do not need it.

The wrap margin improves too. At `W = 36` the wrapping tile spans `[−54, −18]`, clear of the left edge at `−4.89` by **13.1 units**.

### 7.5 Parallax layers 1–3 — procedural, periodic, provably seamless

Layers 1–3 are generated in GDScript from a periodic profile; layers 4–5 are modelled in Blender (§23.4). The reasoning is about what these layers *are* rather than about tooling preference:

1. **The camera is orthographic and dead-on.** Z depth contributes nothing to size or apparent motion — §7.4 fakes parallax with scroll speed precisely because of this. Layers 1–3 gain nothing from being 3D.
2. **Layers 1–3 are already flat unshaded silhouettes.** Every tile assigns `CelMaterials.flat()` — the unshaded `parallax_layer.gdshader` — and sets `cast_shadow = OFF`. They receive no lighting and cast no shadows, and §6.1 gives each exactly one flat colour. Modelling them in Blender is 2D work done in a 3D tool.
3. **Seamlessness must be provable, not eyeballed.** Hand-modelled in Blender, a tile-boundary seam is invisible in the viewport and only appears in game after a wrap. Generated from a periodic function, it is seamless by construction and a headless test can assert it.
4. **An image-based 2D tool is excluded by §0.1.2 and §23.1** — no third-party assets, no textures. So the 2D-ness must be expressed as flat geometry from a 2D profile.

Layers 4 and 5 stay in Blender because they have real form: layer 4 sits at character depth and carries rocks and grass tufts; layer 5 renders *in front* of the characters and needs the cel + inverted-hull treatment so it reads as the same world rather than an overlay.

#### 7.5.1 The seam bug this fixed — kept as the rationale

An earlier hills layer had a **0.82-world-unit step in the horizon at every tile boundary**. The profile was periodic within a tile, but the phase differed per tile (`phase = float(variant) * 2.3`):

```
y(t, phase) = 1.5 + 0.75*sin(t*TAU + phase) + 0.35*sin(t*TAU*3 + phase)

tile 0, right edge (t = 1, phase 0.0)  ->  y = 1.5000
tile 1, left  edge (t = 0, phase 2.3)  ->  y = 2.3203
```

At the current 110.3 px per unit that is a **~90 px vertical jump**.

**Root cause: per-tile phase.** Three copies of a tile that wrap into each other are one infinite strip; giving each copy a different phase guarantees a discontinuity at every join. The fix is not a different phase, it is *no* per-tile phase.

#### 7.5.2 The three rules

Tile geometry is authored in **tile-local coordinates centred on the tile origin**: a tile of width `W` spans local `x ∈ [−W/2, +W/2]`, matching the wrap arithmetic in §7.4.

> **R1 — One mesh, shared.** All three copies of a layer hold the *same* `Mesh` resource. Variety comes from richness *within* one tile, never from per-tile variation.
>
> **R2 — Profiles are periodic in `W`.** A continuous silhouette is admissible only if `y(−W/2) == y(+W/2)` exactly, which is guaranteed when every harmonic's wavenumber is an **integer** multiple of `TAU / W`.
>
> **R3 — Discrete features stay inside the tile.** A scattered feature (a tree, a bush, a rock) must lie wholly within `[−W/2, +W/2]`, **including its own half-width**.

R3 matters *because of* R1: with different trees per tile, an overhanging tree is clipped against a different neighbour each wrap, which reads as flicker rather than as a seam — which is why the original overhang went unnoticed for two versions.

`res://scripts/battle/parallax_profiles.gd`:

```gdscript
class_name ParallaxProfiles
extends RefCounted

## Periodic silhouette profiles for parallax layers 1-3 (spec 7.5).
##
## Every harmonic's wavenumber k is an integer, so y(-W/2) == y(+W/2) by
## construction, and three copies of one tile join seamlessly. That is the
## whole guarantee. Do NOT add a per-tile phase or a per-tile seed - spec
## 7.5.1 records the horizon step that did.

## harmonics: Array of [k: int, amplitude: float, phase: float]
static func sample(x: float, tile_width: float, base: float,
        harmonics: Array) -> float:
    var y: float = base
    for h: Array in harmonics:
        y += float(h[1]) * sin(TAU * float(h[0]) * x / tile_width + float(h[2]))
    return y

## Wavenumbers are quoted against Tuning.PARALLAX_TILE_WIDTH_PROC (36.0), so
## k = 3 is one full wave every 12 world units - the wavelength the 12-unit
## build shipped with. Amplitudes are unchanged; only the period differs.
const HILLS := [[3, 0.75, 0.0], [9, 0.35, 1.10], [21, 0.12, 2.40]]
const HILLS_BASE := 1.50
const HILLS_FLOOR := -1.50
```

The `k = 3` and `k = 9` terms are the original two sines at their original wavelengths and amplitudes, so **the hills look the same**; `k = 21` adds a small ripple. Silhouette range is `1.5 ± 1.22 → y ∈ [0.28, 2.72]`, comfortably inside §7.2's visible `[−0.7, 5.1]`, with the floor at `−1.5` covering the bottom of frame.

**Sampling rule:** at least **12 segments per shortest wavelength**. With `k_max = 21` over 36 units the shortest wavelength is 1.71 units, so **288 segments** (13.7 per cycle). Any future harmonic change carries its own segment requirement; do not change `HILLS` without recomputing this.

#### 7.5.3 Building the tiles — one baked mesh each

> **Each procedural tile is a single `SurfaceTool` mesh with one material.** Not a `Node3D` full of `MeshInstance3D` children.

Giving every cone, trunk and hill its own `MeshInstance3D` with its own material costs 37 per tile index and **111 across the three copies**, for three flat single-colour silhouettes. Baking each tile collapses that to **9** — one per tile — which is where the budget for tripling `W` comes from. It is legitimate precisely because §6.1 gives each of these layers *exactly one* flat colour; there is nothing to keep separate. Trunks are **not** darkened: at layer 2's distance a trunk is a few pixels wide, and a second colour is one §6.1 does not grant it.

**Layer 1 — Hills.** A triangle strip between the profile and the floor:

- 288 segments across local `x ∈ [−W/2, +W/2]`, both ends inclusive (289 sample positions).
- Top vertex `(x, ParallaxProfiles.sample(x, W, HILLS_BASE, HILLS), 0)`, bottom `(x, HILLS_FLOOR, 0)`.
- Flat `Tuning.C_FAR_HILLS`.

**Layers 2 and 3 — tree clusters.** Feature counts scale with `W` so **density is unchanged**: layer 2 carries **21** conifers (one every 1.714 units), layer 3 carries **15** (one every 2.4 units). Heights and radii `1.7 / 0.55` and `2.6 / 0.85`, jittered `×[0.8, 1.25]` and `×[0.85, 1.15]`.

```gdscript
# Position, per feature. Jitter first, then clamp so R3 cannot be violated
# by any combination of jitter and radius roll.
var x: float = -w * 0.5 + w * (float(i) + 0.5) / float(count)
x += rand.randf_range(-0.35, 0.35)
x = clampf(x, -w * 0.5 + r, w * 0.5 - r)      # r = this feature's half-width
```

- **Seed the layout RNG from a script `const`, with the layer name but *not* the tile index** — `rand.seed = hash("%s-parallax" % layer_name)`. Deterministic across runs and Retries, identical across the three copies. Never use the `RNG` autoload here; the background must not vary with the run seed, or the "same world" read breaks.

All three layers keep `parallax_layer.gdshader` via `CelMaterials.flat()` and `cast_shadow = OFF`. **They get no outline `next_pass`** — an inked far hill fights the flat-silhouette read and is the one place in the game where the ink is wrong.

#### 7.5.4 Verification

`test_parallax_seam.gd` (§19.3) asserts, headlessly, for each of layers 1–3:

1. `abs(sample(−W/2) − sample(+W/2)) < Tuning.PARALLAX_SEAM_EPSILON` for the profile-driven layer, and that every wavenumber in `HILLS` is an exact integer.
2. Every vertex of every generated tile has local `x ∈ [−W/2, +W/2]` — nothing overhangs a boundary.
3. The three tile copies of a layer share the same `Mesh` resource (identity, not equality), which makes per-tile drift **impossible** rather than merely absent.
4. Each tile holds **exactly one** `MeshInstance3D`, enforcing §7.5.3's baking rule so the draw-call collapse cannot silently regress.
5. Wrapping a tile by `+3W` and re-sampling reproduces the same world-space silhouette to within epsilon.

Assertions 1–3 are the seam guarantee; 4 is the performance guarantee. None of them is expressible against hand-modelled geometry, which is the concrete reason layers 1–3 are generated.

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
var special_pending: bool = false
var damage_multiplier: float = 1.0        # party damage buff + item bonuses
var damage_reduction: float = 0.0         # warrior defend
var bonus_flat_damage: int = 0            # item dmg_flat + elemental, §13.5
var is_hero: bool

func setup(s: CombatantStats, starting_hp: int = -1) -> void
func tick(delta: float) -> void           # called by BattleDirector, NOT _process
func take_damage(amount: int, source: Combatant) -> void
func heal(amount: int) -> void
func is_alive() -> bool
func play_anim(name: StringName) -> void
func set_running(running: bool) -> void
func cancel_all_effects() -> void         # §8.5 — called on death
```

**Combatants do not run their own clocks.** `BattleDirector` calls `tick(delta)` on every living combatant each frame, in a fixed order (heroes left-to-right, then enemies left-to-right). Combat is deterministic given a seed and trivially pausable.

### 8.2 Placeholder rigs (superseded per character as M8b/M8c land)

`model_scale` goes on `Rig.scale`, not `Visual.scale`: §9.4 and §9.5 key `Visual.scale` absolutely, so `model_scale` there would wipe an orc's 1.15× scale on the first frame of its attack. `Rig.scale` survives the M8 swap unchanged because the imported `Skeleton3D` replaces `Rig` in place.

`BarAnchor` / `HitAnchor` / `HandAnchor` are positioned at `spec_position × model_scale`.

`Rig` is built from Godot primitives via `add_mesh_instance`, as **named child nodes** with these exact names, because M8 swaps meshes while keeping animation tracks pointed at the same node paths:

`Root, Torso, Head, ArmL, ArmR, LegL, LegR, WeaponMain, WeaponOff`

| Part | Mesh | Size | Local position (**home pose**) |
|---|---|---|---|
| `Torso` | CapsuleMesh | radius 0.28, height 0.85 | (0, 1.00, 0) |
| `Head` | SphereMesh | radius 0.22 | (0, 1.62, 0) |
| `ArmL` | CapsuleMesh | radius 0.09, height 0.55 | (-0.34, 1.38, 0.12) |
| `ArmR` | CapsuleMesh | radius 0.09, height 0.55 | (0.34, 1.38, 0.12) |
| `LegL` | CapsuleMesh | radius 0.11, height 0.60 | (-0.14, 0.32, 0) |
| `LegR` | CapsuleMesh | radius 0.11, height 0.60 | (0.14, 0.32, 0) |
| `WeaponMain` | per character | — | child of `ArmR`, offset (0, -0.32, 0.10) |
| `WeaponOff` | per character | — | child of `ArmL`, offset (0, -0.32, 0.10) |

**These are the home positions §9.0's delta convention refers to.** Arm nodes sit at the shoulder (y 1.38) and the capsule hangs downward, so an arm rotation about Z pivots at the shoulder.

Per-character weapon placeholders:

- **Warrior** `WeaponMain`: `BoxMesh(0.07, 0.90, 0.14)` steel `#8C94A3` with a `#F2C230` crossguard box `(0.24, 0.07, 0.16)`. `WeaponOff`: `CylinderMesh(r 0.30, h 0.06)` `#4A6FA5` with a `#F2C230` rim.
- **Ranger** `WeaponMain`: `TorusMesh(inner 0.34, outer 0.40)` `#8B5A2B` rotated 90° about Y to read as a bow limb arc. `WeaponOff`: none.
- **Priest** `WeaponMain`: `CylinderMesh(r 0.045, h 1.30)` `#8B5A2B` topped with a `SphereMesh(r 0.13)` `#3B6FD4`, emission strength `1.5`.
- **Orc** `WeaponMain`: `BoxMesh(0.06, 1.05, 0.12)` haft `#6B4423` with a `BoxMesh(0.34, 0.30, 0.10)` head `#8C94A3` at the top.
- **Warlord**: identical to the orc plus a pair of `#F2C230` shoulder-pad boxes `(0.30, 0.14, 0.30)` on `Torso` at `(±0.34, 1.42, 0)`.
- **Shadow monster**: **no separate limbs.** The whole rig is a single `SphereMesh(r 0.55)` at `(0, 1.0, 0)` using `smoke.gdshader` (§8.6), plus two `SphereMesh(r 0.055)` eyes at `(±0.16, 1.18, 0.44)` in `#FF2D2D`, emission strength `3.0`, plus the `SmokeWisps` emitter.

`combatant_rig.gd` carries three `stats.id ==` checks to build these placeholders. They are the **only** legitimate instances of that pattern in the battle code, they are explicitly exempt from §4.1's standing rule, and **M8b and M8c delete them wholesale** as each character's real mesh lands.

### 8.3 Animation set — mandatory names

The required set is derived from data by `CombatantStats.required_anims()` (§4.1), not from a universal list:

```gdscript
# In Combatant.setup(), after the AnimationPlayer is populated:
for n: StringName in stats.required_anims():
    assert(anim_player.has_animation(n),
        "%s is missing required animation '%s'" % [stats.id, n])
```

Stub clips are **not** created for enemies. `play_anim()` no-ops on an unknown name, so a mistake degrades instead of crashing.

| Name | Who | Length | Loop | Description |
|---|---|---|---|---|
| `idle` | all | 1.60 | yes | slow weave, combat stance, weapon raised |
| `run` | `is_hero` | 0.70 | yes | legs alternate, arms counter-pump, bob, forward lean |
| `attack` | all | per §9 | no | per-character |
| `special` | `special_every_n_actions > 0` | per §9 | no | per-character |
| `hurt` | all | 0.30 | no | recoil |
| `die` | all | 0.80 | no | topple, **holds the final pose** |

Every animation sets `loop_mode` explicitly. `die` must not loop and must not reset.

### 8.4 Damage, defense, variance

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

### 8.5 State rules

- A combatant in `HURT` still accumulates cooldown. Being hit never interrupts an attack already started; the `hurt` animation is skipped if `state == ATTACKING` — play a 0.08 s white `#FFFFFF` flash on the meshes instead.
- A combatant in `DEAD` cannot be targeted, cannot act, cannot be healed, and stops ticking. Remove it from the director's living lists **immediately** on death.
- On death, call `cancel_all_effects()`, which must:
  1. Cancel any in-progress attack and any scheduled impact call.
  2. Set `damage_reduction = 0.0` and kill the defend `SceneTreeTimer`.
  3. **Free every status icon this combatant owns**, without waiting for its fade-out.
  4. Free the combatant's bars (fade over 0.25 s).
- If a projectile is already in flight when its owner dies, it survives and resolves per §9.2.

A defence buff icon hovering above a corpse is a legibility failure (pillar 1). Every status icon registers its owner and is freed here.

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

`depth_draw_never` here is correct and is **not** the §6.2 case: this material has no inverted-hull `next_pass` to depth-test against.

Plus `GPUParticles3D` `SmokeWisps`: amount 24, lifetime 1.4, `ParticleProcessMaterial` with emission sphere radius 0.5, `direction (0,1,0)`, spread 35°, `initial_velocity 0.3–0.7`, `gravity (0,0.4,0)`, `scale 0.10 → 0.0` over life, colour ramp `#14121A` alpha 0.7 → 0.0. Draw pass: `SphereMesh(r 0.5)`.

### 8.7 Animation speed and the warlord

`AnimationPlayer.speed_scale = 1.0 / 1.15 ≈ 0.87` for the warlord, so its clips take 1.15× longer in wall-clock time. Slower is what reads as heavy.

**Impacts are scheduled by a method-call track in the `AnimationPlayer`, never by a `SceneTreeTimer`** (§10.2 step 6). A call track is a position in the animation, so it scales with `speed_scale` automatically and the visual and the number can never drift.

---

## 9. Abilities (exact specifications)

### 9.0 Authoring conventions — read this before writing a single key

**One clip set, forward = local +X.** Every clip for every **combatant** is authored in a single space where **forward (toward the opponent) is local +X**. Heroes are unrotated. Enemies carry `rotation.y = PI` on the `Combatant` node. Every X translation below is written in that shared space, so all of them are positive when moving toward the opponent.

**Limb and body rotations are on Z**, because §7.2's dead-on camera foreshortens X-axis rotation almost to nothing. Signs follow from physical intent:

> With a character facing screen-right, **positive Z rotation is counter-clockwise on screen**. A limb hangs *downward* from its pivot, so positive Z swings its tip **forward and up-in-front**. A torso rises *upward* from its pivot at the feet, so positive Z tips the head **backward**.

**Every translation in §9 is a delta from the home pose, never an absolute coordinate.**

> **Convention:** a key written `Node.position.x → v` means the track reaches `HOME(Node).x + v`, where `HOME` is §8.2's local-position table (and the origin for `Visual`). Rotations are absolute, because every home rotation is zero. When authoring in Blender (§23.2), the same rule applies to bone-local translation relative to the rest pose.

Each ability declares an `impact_delay` — the offset from animation start at which damage or healing is applied, scheduled as a method-call track (§8.7).

#### 9.0.1 Scope of this convention — R8

**This section binds the six combatants and nothing else.** It exists because heroes and enemies face opposite directions and share one authoring space through one camera (`BattleCamera`), so a clip authored against the wrong axis is invisible in game.

**Sir Fish is explicitly out of scope.** He has his own independent orthographic camera (`FishCam`, §17.7), a single-character clip set nothing else shares, and §17.7 describes his states in prose rather than in numeric axes. His seven clips are authored directly in Blender's own axes (Z-up, matching his modelled rest orientation) and verified by import plus live capture. **Do not "port" them into this section's convention** — there is nothing to port them *to*, and the result would be wrong. This is a reasonable-fit reading ratified as normative, not a deviation.

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

`ArmL.position.z → +0.20` is a delta: the track reaches `0.12 + 0.20 = 0.32` (§9.0).

At impact: set `damage_reduction = Tuning.WARRIOR_DEFEND_REDUCTION` for `WARRIOR_DEFEND_DURATION` seconds via a `SceneTreeTimer`. Re-application **refreshes** the duration, it does not stack. The timer is cancelled on death (§8.5).

**Defend is never skipped for a healthy party.** `special_requires_wounded_ally` is `false` on the warrior — Defend is pre-emptive mitigation, most useful *before* anyone is hurt.

**Extra VFX:** spawn a `status_icon` in `BattleOverlay/VfxLayer` over the warrior — a defend-blue **ring** with a white shield glyph (§17.5). Fade in over 0.15 s, pulse scale 1.0 → 1.12 → 1.0 on a 1.0 s period, remain for the whole buff, fade out over 0.25 s. **Freed immediately if the warrior dies.**

The defend action deals **no damage**. It replaces that action entirely.

### 9.2 Ranger

**Primary — Shoot Arrow** (`attack`, length 0.80, projectile spawns at 0.30)

| Window | Keys | Reads as |
|---|---|---|
| 0.00 → 0.30 | `ArmL.rotation.z` → **+80°**; `ArmR.rotation.z` → **−20°** and `ArmR.position.x` → **−0.18** (delta: reaches 0.16); `Visual.rotation.z` → **+14°** | bow arm extends forward, draw hand pulls back to the cheek, torso leans back so the bow **aims upward** |
| 0.30 | spawn projectile from `HandAnchor` | release |
| 0.30 → 0.55 | `ArmR.rotation.z` → **+30°**; `WeaponMain.rotation.z` ±6° damped | snap forward, bow limb wobble |
| 0.55 → 0.80 | → neutral | recover |

**Arrow (`arrow.tscn`, `projectile.gd`):**
- Mesh: `CylinderMesh(r 0.018, h 0.55)` shaft `#8B5A2B` + `BoxMesh(0.06, 0.10, 0.02)` fletching `#F5F0E6` + `ConeMesh` tip `#8C94A3`, rotated to lie along the travel axis.
- Travel: a **parabolic arc** from spawn to the target's `HitAnchor` over **0.55 s**:
  `pos = start.lerp(end, t) + Vector3(0, arc_height * 4.0 * t * (1.0 - t), 0)` with `arc_height = 1.6`.
  Set `rotation.z` each frame from the path derivative so the tip points along the flight path.
- **Retarget rule:** the arrow stores a target reference. On arrival, if the target is `DEAD`, pick a random living enemy and deal damage there. If no enemy is alive, play the impact VFX at the last position and deal no damage. `test_retarget.gd` (§19.3) covers all three cases.
- Impact VFX: 8 small `#F5F0E6` sparks (`GPUParticles3D`, one_shot, lifetime 0.35).

**Special — Bomb Arrow** (`special`, same animation as `attack`, spawns `bomb_arrow.tscn`)
- Identical draw/release animation and identical flight path and arc.
- `bomb_arrow.tscn` is the arrow plus a `SphereMesh(r 0.14)` powder bag `#6B4423` near the tip, a `CylinderMesh(r 0.012, h 0.14)` fuse `#F5F0E6` angled out of it, a **lit fuse spark** (`GPUParticles3D`, amount 12, lifetime 0.25, `#F2C230` → `#E03131`), and an `OmniLight3D` (`#F2C230`, energy 1.5, range 1.2).
- **Plus the §9.6 telegraph.**
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

At 0.30 — **the telegraph beat, gated on `stats.telegraphs_primary`, not on an id**:

```gdscript
## Telegraph beat - only characters flagged telegraphs_primary use it.
func charge(source: Combatant) -> void:
    if not source.stats.telegraphs_primary or is_special:
        return
    if Tuning.PRIEST_DARKEN_ENABLED:
        BattleVfx.darken_pass(source)
    if target != null and target.is_alive():
        BattleVfx.warning_glow(target)
```

- **Darkening pass:** tween `WorldEnvironment.environment.adjustment_brightness` 1.0 → 0.55 over 0.12 s, hold 0.18 s, return to 1.0 over 0.25 s.
- A warning glow at the target's head: an unshaded `#3B82F6` sphere, scale 0 → 0.5, over 0.20 s.

At 0.55 the bolt lands:
- A **jagged bolt mesh** — an `ImmediateMesh` built at runtime as a 6-segment ribbon from `y = 5.2` down to the target's `HitAnchor`, each segment offset by `randf_range(-0.22, 0.22)` in X and Z, width 0.14, unshaded `#FFFFFF` core with a second slightly wider pass in `#3B82F6`. Alpha 1 → 0 over 0.28 s.
- `OmniLight3D` at the impact point: `#3B82F6`, energy 8 → 0 over 0.30 s, range 5.0.
- Ground flash: a flat `#FFFFFF` disc quad at `y = 0.02`, scale 0.3 → 2.0, alpha 0.9 → 0 over 0.30 s.
- 24-particle one-shot burst in `#3B82F6`.
- Camera shake: `h_offset`/`v_offset` ±0.05 for 0.18 s.
- Then deal damage.

**Special — Heal** (`special`, length 0.85, impact_delay 0.40)
- Same staff-raise keys, orb glows `#2FBF4F`, **no darkening** (the telegraph is primary-only — note the `or is_special` in `charge()`), plus the §9.6 telegraph flash.
- Heals **the living hero with the lowest current HP** for `round(priest_current_damage × PRIEST_HEAL_MULT)`, where `priest_current_damage` includes `damage_multiplier`, `bonus_flat_damage` and the same variance roll. Never above `max_hp`. If the priest is the lowest, it heals itself.
- **Skip rule:** the priest is the only character with `special_requires_wounded_ally = true`; see §10.2.
- **Extra VFX:** on the healed hero, a `status_icon` — a heal-green **ring** with a green `+` glyph (§17.5) which **shrinks while fading**: scale 1.0 → 0.55, alpha → 0.0 over 0.70 s, `TRANS_SINE/EASE_IN`. Plus a green `+N` label rising 60 px, fading over 0.8 s.

### 9.4 Shadow monster

**Primary — Swipe** (`attack`, length 0.60, impact_delay 0.28)

| Window | Keys | Reads as |
|---|---|---|
| 0.00 → 0.20 | `Visual.position.x` → **+0.22**; `Visual.scale` → `(1.12, 0.90, 1.12)` | the blob lunges **toward the heroes** and squashes |
| 0.20 → 0.36 | `Visual.scale` → `(1, 1, 1)` | recoils to shape |
| 0.36 → 0.60 | `Visual.position.x` → 0 | drifts back |

- **Claw arc VFX** at the target: three parallel tapered quads in `#14121A` with `#FF2D2D` edges sweeping across the target's `HitAnchor`, scale 0 → 1.2, alpha 1 → 0 over 0.25 s.
- `SmokeWisps.amount_ratio` spikes to 1.0 for 0.3 s.

### 9.5 Orc barbarian / Orc warlord

**Primary — Melee** (`attack`, length 0.85, impact_delay 0.42)

| Window | Keys | Reads as |
|---|---|---|
| 0.00 → 0.28 | `ArmL.rotation.z` and `ArmR.rotation.z` → **−120°**; `Visual.rotation.z` → **+12°**; `Visual.position.y` → **+0.06** | axe hauled up overhead and behind, torso coils back, rises onto the toes |
| 0.28 → 0.48 | arms → **+95°**; `Visual.rotation.z` → **−18°**; `Visual.position.x` → **+0.20**; `Visual.scale` → `(0.92, 1.10, 0.92)` | swings with all its might, drives forward, body stretches through the blow |
| 0.48 → 0.85 | → neutral with a small overshoot | heavy recover |

- Impact VFX: a wide `#8C94A3` slash arc quad (scale 0 → 1.9), a 12-particle dust puff at ground level, camera shake ±0.04 for 0.15 s.
- **Warlord** uses the identical scene and clips at `model_scale = 1.70`, `speed_scale = 0.87` (§8.7), `body_color = #4E7A2B`, `accent_color = #E03131`, plus the shoulder pads from §8.2.

### 9.6 Special-ability telegraph

**Universal rule: every special ability flashes its caster at animation start.** At `t = 0` of any `special` clip, run `CelMaterials.flash(caster, color, Tuning.SPECIAL_CAST_FLASH_TIME)` over all the caster's meshes:

| Caster | Flash colour |
|---|---|
| Warrior (defend) | `#3B6FD4` defend blue |
| Ranger (bomb arrow) | `#F2C230` gold |
| Priest (heal) | `#2FBF4F` heal green |

This is also why `flash()` must remember its base colour via metadata rather than reading the live albedo (§6.3).

**The bomb arrow gets a trail:** a `GPUParticles3D` emitter parented to the projectile, amount 40, lifetime 0.45, emission point, gravity `(0, -0.6, 0)`, colour ramp `#E03131` → `#F2C230` → alpha 0, scale 0.06 → 0. The ordinary arrow has no trail.

### 9.7 Area-effect resolution order

**Rule: every multi-target effect resolves its targets one at a time, `Tuning.AOE_STAGGER` (0.06 s) apart, ordered left to right by world X.** This applies to:

- the ranger's bomb arrow (all living enemies)
- 2× and 3× slot lightning (all living enemies)
- 3× slot plus (all living heroes)

Aggregating into one number is rejected: per-target numbers are how you read whether an enemy is about to die.

**Plus an anti-overlap rule for the numbers themselves** (§11.4): a damage number spawning while another is still within its first 0.25 s offsets horizontally by `±Tuning.DAMAGE_NUMBER_SPREAD` (46 px) × its index in the current burst, alternating sign outward from centre.

---

## 10. Combat system

`battle_director.gd` owns a single fight from spawn to resolution.

### 10.1 Setup sequence (`start_combat(enemy_stat_ids: Array[StringName])`)

1. Refresh every hero's `bonus_flat_damage` and `damage_multiplier` from `GameState.party_bonuses()` (§13.5).
2. Spawn each enemy at its slot (§7.3) with `Visual` alpha 0, `state = IDLE`, `idle` **already playing**.
3. Tween every enemy's alpha 0 → 1 over `ENEMY_FADE_IN_TIME` via `CelMaterials.set_alpha()`, which fades the outline too (§6.3).
4. Assign initial cooldowns:
   ```gdscript
   c.cooldown_remaining = c.stats.attack_cooldown \
       * Tuning.COOLDOWN_START_FRACTION \
       * randf_range(1.0 - Tuning.COOLDOWN_START_JITTER, 1.0 + Tuning.COOLDOWN_START_JITTER)
   ```
5. Emit `combatant_spawned` per combatant so `BattleOverlay` creates bars; bars **pop in** — scale 0.6 → 1.0 with `TRANS_BACK/EASE_OUT` over `BARS_POP_IN_TIME`, alpha 0 → 1.
6. Emit `combat_started`. The slot leaves attract mode and begins spinning for real (§16.6).

### 10.2 Per-frame loop

```gdscript
func _process(delta: float) -> void:
    if not _active:
        return
    for c: Combatant in _living_in_order():
        if not c.is_alive():
            continue
        if c.state == Combatant.State.ATTACKING:
            continue                           # no discarded decrement
        c.cooldown_remaining -= delta
        if c.cooldown_remaining <= 0.0 and c.state == Combatant.State.IDLE:
            _take_action(c)
```

`_living_in_order()` returns heroes left-to-right then enemies left-to-right. **Iterate over a copy** — actions can kill combatants mid-iteration.

The `ATTACKING` skip matters: decrementing the cooldown during an attack and then overwriting it when the animation finishes discards the decrement entirely. Skipping is equivalent in behaviour, honest in intent, and matches §11.3's bar.

`_take_action(c)`:

1. `c.action_count += 1`
2. **Decide special vs primary:**
   ```gdscript
   var due := c.stats.special_every_n_actions > 0 \
       and c.action_count % c.stats.special_every_n_actions == 0
   var use_special := due or c.special_pending
   ```
3. **Wounded-ally gate:**
   ```gdscript
   if use_special and c.stats.special_requires_wounded_ally \
           and _every_living_ally_at_full_hp(c):
       use_special = false
       c.special_pending = true      # banked; the counter keeps its rhythm
   elif use_special:
       c.special_pending = false
   ```
   **The gate is keyed on the stat flag, not on `stats.id`, and it applies to the priest alone.** Applying it universally would suppress the warrior's Defend whenever the party is healthy, which is backwards, and would bank a `special_pending` that fires on the first scratch — reintroducing exactly the reactive twitch the `special_pending` design removed.

   `_every_living_ally_at_full_hp(c)` means **every living combatant on the caster's own side, including the caster**. The priest heals itself when it is the lowest (§9.3), so excluding self would strand a wounded priest in a healthy party.
4. **Pick a target — but only if this action needs one:**
   ```gdscript
   var target: Combatant = null
   if not (use_special and not c.stats.special_targets_opponent):
       target = _random_target_for(c)
       if target == null:                       # nobody left to hit
           c.cooldown_remaining = c.stats.attack_cooldown
           return
   ```
   Uniformly random among living opponents. Heroes target enemies, enemies target heroes.

   The guard exists because the warrior's Defend and the priest's Heal must still fire when no opponent is alive — during the resolve window after the last enemy dies, or the last hero. The ranger's bomb arrow is aimed, so it correctly aborts. Bomb arrow and slot lightning ignore the chosen target at resolution and hit everything (§9.7); the target only decides where the projectile flies. Priest heal picks its ally at impact, per §9.3.
5. `c.state = ATTACKING`; play `attack` or `special`.
6. **Schedule the impact with a method-call track in the `AnimationPlayer` at `impact_delay`.** Never a `SceneTreeTimer` — see §8.7.
7. On animation finish: `c.state = IDLE`; `c.cooldown_remaining = c.stats.attack_cooldown`.

The `special_pending` flag lets the counter advance normally through healthy stretches, so the every-third-action cadence stays legible **and** a heal skipped for lack of a target still fires as soon as one exists.

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

Slot lightning calls `take_damage(rolled, null)` — a null source, so it never feeds `hero_damage_dealt` and never enters the slot's rolling buffer (§16.5). That is deliberate and load-bearing.

### 10.4 Death, and the corpse fade

- Play `die`, set `state = DEAD`, call `cancel_all_effects()` (§8.5), emit `combatant_died`, remove from living lists, fade the bars over 0.25 s and free them.
- **Heroes:** lie motionless on the ground **indefinitely**. They are not freed. They stay in `GameState.hero_runtime` marked `alive = false`. On the next travel phase they slide off-screen left (§12.5).
- Death VFX: a one-shot 16-particle burst in the combatant's `body_color`, plus a 0.15 s white flash on all its meshes.

**Enemies fade on a per-death timer, and the fade is rushed if the fight ends first.**

> **The rule.** An enemy corpse fades on a timer that starts **when it dies**. If the fight ends while it is still holding or fading, the fade is **rushed** so that **no corpse is on screen when travel begins.**

This replaces an earlier design where corpses scrolled away with the world. Two defects made that untenable: the party walked off with corpses still fully opaque, and — because cleanup was only ever triggered on victory — the first enemy to die in a three-enemy fight lay on the battlefield at full opacity **for the rest of the fight**.

**Implementation.**

1. `_run_corpse_fade(c, hold, fade, gen)`. Slow path passes `ENEMY_DEATH_HOLD` / `ENEMY_DEATH_FADE` (1.5 / 2.0); rush path passes `ENEMY_DEATH_HOLD_RUSH` / `ENEMY_DEATH_FADE_RUSH` (0.30 / 0.45).
2. `BattleDirector` connects `EventBus.combatant_died` and starts the **slow** fade for any enemy that dies while `_active` is true.
3. `begin_corpse_cleanup()` is the rush trigger. For every enemy corpse it bumps the generation counter and re-enters the same function on the rush path, resuming from the corpse's current alpha.
4. `BattleDirector` exposes `await_corpse_cleanup() -> void`, which returns once every corpse has been freed.
5. `run_controller._encounter_resolved()` awaits **both** `ENCOUNTER_RESOLVE_PAUSE` and `director.await_corpse_cleanup()` before calling `_encounter_exit()`.

**Why 0.30 / 0.45.** They sum to 0.75, which fits inside the `ENCOUNTER_RESOLVE_PAUSE` of 0.8 that already elapses in parallel. **The rush therefore adds zero net time to the run** while guaranteeing the battlefield is clear before travel. Awaiting the signal rather than relying on two independent 0.8 s timers is what makes the ordering provable instead of coincidental.

#### 10.4.1 The generation counter — do not replace it with a boolean

**This is the single most expensive bug found in the M7.6 pass and the mechanism exists specifically to prevent it.**

A superseded slow-fade coroutine must be able to detect that it was overtaken and bail out. The obvious implementation — a boolean `corpse_rushed` meta flag that `begin_corpse_cleanup()` sets to `true` before launching the rush — **deadlocks the entire run**: the rush coroutine goes through the *same function*, reaches the *same* hold-phase check, sees the flag it just set, concludes it too was superseded, and returns without ever creating the fade tween or calling `_finish_corpse()`. `_pending_corpse_fades` never reaches zero, `await_corpse_cleanup()` never resolves, and the run sits in `COMBAT` forever the moment an encounter's enemies are all dead. There is no error in the log.

**The correct mechanism is a per-corpse generation counter (`corpse_gen` meta).** Every call captures the corpse's generation at launch and re-checks it is still current after each await; `begin_corpse_cleanup()` bumps the generation *before* starting its own call, which invalidates only the **older** in-flight coroutine and never itself.

The rush path must also **kill the in-flight slow tween** and resume from the current alpha, not stack a second tween on the same property.

### 10.5 Resolution

- **All heroes dead** → `combat_ended(false)` → `game_over` (§18). **Check this before the victory check** so a mutual wipe is a loss.
- **All enemies dead** → victory. Wait `ENCOUNTER_RESOLVE_PAUSE`, emit `combat_ended(true)`, then `encounter_resolved`.
- `_encounter_resolved()` awaits `await_corpse_cleanup()` as well, so **the battlefield is empty before travel begins** (§10.4).

The defeat path is untouched by corpse cleanup: `_game_over()` does not call it, and on a wipe the enemies are alive anyway.

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

```gdscript
var world := combatant.get_node("BarAnchor").global_position
var vp := battle_camera.unproject_position(world)      # SubViewport coords
bars.position = vp - bars.size * 0.5                   # 1:1 into BattleOverlay
bars.visible = not battle_camera.is_position_behind(world)
```

**Bar width is a constant 140 px regardless of `max_hp`, and `FILL_WIDTH := 136.0` is fixed.** Both are coupled to the battlefield spacing through §7.2.1's inequality — the geometry was widened precisely so these could stay put. Narrowing them would invalidate the twenty hardcoded expectations in `test_damage_chunk.gd` (108.8, 136.0, 27.2, …) for no gain. Staggering bars vertically per slot would break the 1:1 `unproject_position` mapping this section depends on, and reads as arbitrary.

### 11.2 The detaching health chunk — the signature effect

On `combatant_damaged(target, amount, previous_hp, new_hp)`:

1. `f_prev = previous_hp / max_hp`, `f_new = new_hp / max_hp`.
2. The lost segment occupies, in `HealthFill`'s local space, `x ∈ [136 × f_new, 136 × f_prev]`, full height.
3. Instantiate `floating_health_chunk.tscn` (a bare `ColorRect`), reparent to `FloatingLayer`, set its **global** position and size to exactly that segment's on-screen rect, colour `#E03131`.
4. Immediately set `HealthFill.size.x = 136 × f_new` — **no tween.** The bar snaps; the chunk carries the motion.
5. Tween the chunk, using §5.9's constants:
   - `position += Vector2(randf_range(-CHUNK_FLING_X, CHUNK_FLING_X), -randf_range(CHUNK_FLING_Y_MIN, CHUNK_FLING_Y_MAX))` over `CHUNK_FLIGHT_TIME`, `TRANS_CUBIC/EASE_OUT`
   - `rotation` → `randf_range(-CHUNK_SPIN, CHUNK_SPIN)` rad over the same time
   - `modulate:a` 1.0 → 0.0 over the same time, `TRANS_QUAD/EASE_IN`
   - then `queue_free()`
6. Flash `HealthBg` to `#FFFFFF` and back over 0.10 s.

**Displacement is deliberately half of what it once was**, because a chunk thrown 90 px sideways and 130 px up loses the eye's connection between the hit and the bar it came from. Rotation is halved with it: "explosiveness" is the whole gesture, and a chunk that travels half as far while spinning just as hard reads as tumbling rather than as flung.

> **`CHUNK_FLIGHT_TIME` is NOT halved.** That is pacing, not force. Shortening 0.70 makes the effect snappier, which is the opposite of the intent.

**Worked example, which `test_damage_chunk.gd` asserts:** a 100 HP character hit for 20 gives `f_prev = 1.0`, `f_new = 0.8`, so the chunk is `x` from **108.8 to 136.0**, width **27.2 px**, full 16 px height. The test asserts the **spawn** rect only, not the flight, so it is unaffected by the displacement values.

**Healing** does the reverse: tween `HealthFill.size.x` up over 0.25 s with `TRANS_SINE/EASE_OUT` and flash the fill to `#2FBF4F` and back over 0.30 s. No chunk spawns.

### 11.3 Cooldown fill

```gdscript
CooldownFill.size.x = 136.0 * clamp(c.cooldown_remaining / c.stats.attack_cooldown, 0.0, 1.0)
```

Full immediately after an attack finishes, draining to empty as the cooldown completes. While `state == ATTACKING` the bar reads 0, which with §10.2's loop is literally true rather than an override.

### 11.4 Damage numbers

On `combatant_damaged`, spawn `damage_number.tscn` (a `Label` with `theme_type_variation = &"DisplayLabel"`) in `FloatingLayer` at the target's bar position + `(randf_range(-30, 30), -20)`:

- Text `str(amount)`, font size 42, colour `#E03131`, outline 6 px `#0F0E14`.
- Tween: rise 80 px; `scale` 0.6 → 1.25 → 1.0 (punch over the first 0.18 s); alpha 1 → 0 over 0.85 s; free.
- Heals use `+N` in `#2FBF4F`. Slot lightning uses `#3B82F6`.
- **Elemental item damage** (§13.5) recolours the number to the dominant element the party carries: fire `#FF7A1A`, ice `#5BC8F5`, lightning `#3B82F6`. If the party carries none, it stays `#E03131`. The bonus strip's element chip (§17.6) is what tells the player *why* the colour changed.
- **Anti-overlap (§9.7):** `BattleOverlay` tracks numbers spawned in the last 0.25 s. The *n*-th number in a burst offsets its X by `Tuning.DAMAGE_NUMBER_SPREAD × ceil(n/2) × (−1)^n`, i.e. 0, +46, −46, +92, … outward from centre.

> **Structural trap.** `BattleOverlay` is a 2D `Control` composited over the whole SubViewport, so **no 3D geometry can ever occlude the bars, damage numbers or status icons** — they always draw on top. Do not "fix" foreground geometry to protect them; the thing at risk is the character underneath (§23.4).

---

## 12. Run flow

`run_controller.gd` is the top-level state machine:

```gdscript
enum RunState {
    BOOT, TRAVEL, ARRIVE, COMBAT, LOOT, SHOP,
    ENCOUNTER_EXIT, RUN_COMPLETE, GAME_OVER
}
```

### 12.1 The demo level

`GameState.build_level()` is canonical and is the **only** definition of the demo level.

Six encounters, built in code:

| # | Type | Contents | travel_duration |
|---|---|---|---|
| 0 | COMBAT | `shadow_monster`, `shadow_monster` | 2.0 |
| 1 | LOOT | 2 items | 3.0 |
| 2 | COMBAT | `shadow_monster`, `shadow_monster`, `orc_barbarian` | 3.0 |
| 3 | SHOP | 3 items for sale | 3.0 |
| 4 | COMBAT | `orc_barbarian`, `orc_barbarian`, `shadow_monster` | 3.0 |
| 5 | COMBAT (boss) | `orc_warlord`, `shadow_monster` | 4.0 |

`orc_warlord` is listed first so it lands at `x = 1.2` (§7.2.1, §7.3). The level is a linear sequence with no branching and is **never shown to the player**.

**`res://resources/levels/demo_level.tres` is an orphan and must be deleted.** Nothing in the game loads it — verified by search; the only references are in spec documents. It is a permanent drift hazard and a second source of truth for the thing this function defines. The implementer is **explicitly authorised** to run:

```bash
rm -rf "C:/Projects/Godot/Sir Fish/resources/levels"
```

Then confirm with `get_filesystem_tree` that `res://resources/` contains only `stats/`, and remove any leftover `.tres.uid` / `.import` residue the same way. **This is the only filesystem deletion this document authorises.**

**Done — 2026-08-14.** Outstanding since v3, now closed. Verified: no `demo_level` or `resources/levels` reference remains in any `.gd`, `.tscn`, `.tres`, `.cfg` or `.godot` file; no `.uid`/`.import` residue; `resources/` holds only `stats/`.

**This deletion was not cosmetic.** `export_presets.cfg` sets `export_filter="all_resources"`, which ships **every** resource in the project rather than only those reachable from the main scene — so the orphan was being bundled into real builds. Confirmed after the fact: the pre-deletion `builds/web/index.pck` contains four `demo_level` hits. A second definition of the demo level was shipping to players. Future exports cannot include it; the existing build in `builds/web/` is stale and is replaced on the next export.

> **Trap, inherited from this.** `export_filter="all_resources"` means **any** orphan file under `res://` reaches the build. An unreferenced resource is not inert here — it ships. Delete orphans rather than leaving them, and remember that a `grep` for references proving "nothing loads it" does **not** prove "nothing ships it".

### 12.2 State transitions

```
BOOT ──run_started──▶ TRAVEL
TRAVEL ──travel_duration elapsed──▶ ARRIVE
ARRIVE ──decel + heroes to idle──▶ COMBAT | LOOT | SHOP
COMBAT ──all enemies dead + corpses cleared──▶ ENCOUNTER_EXIT
COMBAT ──all heroes dead──▶ GAME_OVER
LOOT ──chest animation done + items granted──▶ ENCOUNTER_EXIT
SHOP ──modal closed──▶ ENCOUNTER_EXIT
ENCOUNTER_EXIT ──immediately──▶ TRAVEL (next index) | RUN_COMPLETE (no more)
```

### 12.3 TRAVEL

- Living heroes: `set_running(true)` → `run` animation.
- `ParallaxBackground.scroll_speed` tweens up per §7.4.
- Runs for `def.travel_duration` seconds, then → `ARRIVE`.
- The slot is in attract mode (§16.6) and the upgrade tray is live (§17.6).

### 12.4 ARRIVE

1. Tween `scroll_speed` → 0 over `TRAVEL_DECEL_TIME`, `TRANS_CUBIC/EASE_OUT`.
2. When it reaches ~0, all living heroes `set_running(false)` → `idle`.
3. Branch on encounter type.

### 12.5 ENCOUNTER_EXIT — the dead slide out *concurrently*

If one or more heroes died during this encounter:

1. Each dead hero's `Combatant` node tweens `position.x` from its slot to `-7.0` over `DEAD_HERO_EXIT_TIME` with `TRANS_SINE/EASE_IN`, holding its `die` end pose, then sets `visible = false`.
2. **Do not wait for that tween.** Travel begins on the same frame, so the world scrolls past the departing corpse.

> **The rule.** The dead-hero slide and the party's departure begin on the same frame, so the world scrolls past while the corpse falls behind — the dead are *left behind*, not sent ahead.

An earlier design blocked on the tween, so the corpse slid left across a **static** background for 1.6 s and only then did the world start scrolling. It read as the dead hero crawling away under its own power, which is the opposite of the intended beat.

- Living heroes get `set_running(true)` on the first line of `_travel()`, which now happens in the same frame.
- `DEAD_HERO_EXIT_TIME` (1.6) is comfortably shorter than the shortest `travel_duration` (2.5), so the slide always completes during travel.
- The tween target of `position:x = -7.0` still clears the camera half-width of 4.89.
- **The slide tween is owned by `RunController` and must survive the state change to `TRAVEL`.** Do not parent it to anything the next encounter tears down.

"Removed from the battlefield" means **visually removed, not freed**. The node stays alive and stays in `director.heroes`, because the status panel's three rows are index-addressed. The hero is freed only on Retry (§18.3).

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

```gdscript
const MODIFIERS := [
    # Hero-damage modifiers
    { "id": &"dmg_flat",   "label": "+%d Damage",         "roll": [2, 9],   "value_mult": [0.28, 0.55] },
    { "id": &"dmg_pct",    "label": "+%d%% Damage",       "roll": [5, 18],  "value_mult": [0.30, 0.60] },
    { "id": &"elem_fire",  "label": "+%d Fire Damage",    "roll": [3, 11],  "value_mult": [0.35, 0.70] },
    { "id": &"elem_ice",   "label": "+%d Ice Damage",     "roll": [3, 11],  "value_mult": [0.35, 0.70] },
    { "id": &"elem_light", "label": "+%d Lightning Dmg",  "roll": [3, 11],  "value_mult": [0.35, 0.70] },
    # Slot modifiers
    { "id": &"slot_bolt",  "label": "+%d Bolt Power",     "roll": [2, 8],   "value_mult": [0.40, 0.75] },
    { "id": &"slot_purse", "label": "+%d Coin Yield",     "roll": [3, 10],  "value_mult": [0.38, 0.72] },
    { "id": &"slot_mend",  "label": "+%d%% Mend Power",   "roll": [3, 9],   "value_mult": [0.40, 0.75] },
]
```

Each generated modifier stores `{ "id", "label" (formatted), "roll" (the integer rolled), "value_mult" }`.

### 13.2 Rarity

| Rarity | Weight | Modifier count | Value multiplier |
|---|---|---|---|
| Common | 50 | 0 | `1.0` (fixed) |
| Uncommon | 30 | 1 | `randf_range(1.6, 2.2)` |
| Magic | 15 | 2 | `randf_range(2.8, 3.6)` |
| Rare | 5 | 3 | `randf_range(4.5, 6.0)` |

Modifier counts come from the initial vision (0/1/2/3) and must not be changed. **Modifiers are drawn without replacement** — one item never carries the same modifier id twice.

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

Arithmetic bounds: cheapest is a common dagger at `18 × 1.0 × 1.0 = 18`; most expensive is a rare staff at up to `25 × 6.0 × (1 + 3 × 0.75) = 487`. Buy prices are `value × 1.5` → **27 to 731 gold**. `test_item_distribution.gd` re-measures and reports the real distribution over 200 items with the 8-modifier pool.

### 13.4 Naming

```gdscript
display_name = "%s %s" % [ADJECTIVES.pick_random(), WEAPON_TYPES[type].nouns.pick_random()]
```

### 13.5 Items affect play

**Items are not equipped** (§21.1 A6). Instead, **every item in the party inventory contributes its modifiers to a party-wide pool.** Carrying loot makes the party stronger; selling it makes them poorer and the console richer.

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
| `element` | recolours hero damage numbers (§11.4) **and drives the bonus strip's element chip (§17.6)**. Cosmetic — there are no resistances in the demo |
| `slot_bolt` | `lightning_damage = round(avg_last_three × mult × overcharge) + slot_bolt` |
| `slot_purse` | `gold_payout = round(base × fat_purse) + slot_purse` |
| `slot_mend` | `heal_fraction = 0.25 + slot_mend / 100.0` |

Emit `party_bonuses_changed(bonuses)` from `add_item` and `remove_item`. `BattleDirector` re-applies to living heroes on that signal and at combat start. The slot reads `GameState.party_bonuses()` at payout time.

**Expected magnitude.** A demo run holds at most 5 items and 50% of rolls are Common with zero modifiers, so the expected total is ~4 modifiers spread over 8 types. Typical end-of-run bonuses are on the order of +4 flat damage, +9% damage, +4 bolt, +6 gold, +5 pp heal. Meaningful, not run-defining.

### 13.6 Shop stock generation

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

Rarity is picked within each bucket using the §13.2 weights renormalised (62.5/37.5 for the cheap bucket, 75/25 for the teaser bucket). A Rare the player cannot afford is a teaser that makes the rarity ladder legible; three of them is a dead encounter.

`SHOP_ITEMS_FOR_SALE = 3` still governs the count; if it changes, generate the two forced buckets first and free-roll the remainder.

### 13.7 Bulk API and kinds

```gdscript
func generate_items(count: int) -> Array[Item]
func generate_item() -> Item
func generate_item_with_rarity(r: Item.Rarity) -> Item    # used by Debug additem
func generate_shop_stock() -> Array[Item]
```

Loot chests call `generate_items`; shops call `generate_shop_stock`.

`Kind.WEAPON` is the only kind generated. `POTION` and `RELIC` exist in the enum, are documented as deferred, and are never produced. `equipped` is always `false`, but `GameState.sellable_items()` must still filter on it.

---

## 14. Encounters

### 14.1 Combat encounter

Covered by §10. Sequence: `ARRIVE` prelude → enemies fade in → bars pop in → cooldowns half-charged → fight → corpses cleared (§10.4) → exit.

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

**LOOT does not pause the game** (§15.5).

### 14.3 Shop encounter

1. A `shop_building` pops in on the right at `(3.4, 0, 0)` with the same pop-in tween.
   - Placeholder mesh: `BoxMesh(2.0, 1.6, 1.4)` walls `#F5F0E6`, `PrismMesh(2.4, 1.0, 1.6)` roof `#D9333F`, `BoxMesh(0.6, 1.0, 0.1)` door `#8B5A2B`, a `#F2C230` hanging sign quad, and a small warm `OmniLight3D` window glow.
2. After 0.4 s, show `ShopModal` (§15). **Opening it pauses the game** (§15.5).
3. The encounter resolves **only** when the modal's close button is pressed.

---

## 15. Shop modal

`res://scenes/modals/shop_modal.tscn`, a child of `ModalLayer` — it inherits `Main.theme` and must **not** declare its own.

### 15.1 Layout

- Full-screen `#0F0E14` scrim at 65% alpha, fading in over 0.2 s. Scrim clicks do **not** close the modal.
- Panel 960 × 1200, centred → (60, 360) to (1020, 1560). Enters with scale 0.85 → 1.0 and alpha 0 → 1 over 0.25 s, `TRANS_BACK/EASE_OUT`.
- Header row: title `SHOP` (`DisplayLabel`, font 56, `#F2C230`) on the left; **a red X close button in the upper right** — 72×72, `#E03131` background, `#FFF6E0` glyph, corner radius 16, inset 16 px from the panel's top-right corner.
- Gold readout under the header, right-aligned: **a `CoinGlyph` instance at radius 16** + `str(GameState.gold)`, `DisplayLabel` font 44, `#F2C230`. **Updates live** on every buy, sell and slot payout.
- **Party bonuses strip** under the gold readout — an instance of `bonus_strip.tscn` (§17.6), 880 × 34. This is what makes selling a real decision instead of free money.
- `TabContainer` with exactly two tabs: **`Buy`** then **`Sell`**, `Buy` selected on open.

**Coin glyphs are mandatory in all three places** the shop shows a gold amount — header, buy price, sell button. `coin_glyph.gd`'s own docstring names them, and all three shipped as bare numbers for two versions. Sizes: **radius 16** header, **radius 15** buy card price, **radius 13** sell button. Each sits immediately left of the number with an 8 px gap, vertically centred.

> **Trap, and it cost a debugging cycle.** `add_node`'s `properties` dict **does not apply the `script` property**. A `CoinGlyph` created that way arrives as a bare scriptless `Control` — no `_draw()`, nothing renders, no error — and its `radius` is silently dropped along with the script. `attach_script` first, then `update_property` for `radius`. See §0.1.5.

### 15.2 Buy tab

- On the encounter's first open, call `Itemizer.generate_shop_stock()` **once** and cache it on the encounter. Reopening the tab shows the **same three items** — never reroll.
- Three `shop_buy_card.tscn` stacked vertically, each 880 × 260. **The card root must not be a bare `PanelContainer` child arrangement** — a `PanelContainer` force-resizes every child to fill it. Structure: `PanelContainer > HBoxContainer > [Edge (ColorRect, custom_minimum_size = (12, 0)), Layout (VBoxContainer)]`.
  - Rarity-coloured left edge bar, 12 px (§17.9)
  - `display_name` — `DisplayLabel` font 44, `#FFF6E0`
  - `subtitle()` — font 30, rarity colour
  - Modifier lines — font 28, `#9B93AE`, one per modifier, using the formatted `label`
  - Price, right-aligned — `DisplayLabel` font 46, `#F2C230`, `str(buy_price)` with a radius-15 coin glyph
- **The price must not touch the card's right edge.** A 3-digit price flush against the border is the defect this fixes; 18 px of clearance is the requirement.

  > **R4 — ratified substitution.** The price lives in `Row/Layout/PriceBox`, a `VBoxContainer`, which has **no per-instance margin property** — that is `MarginContainer`-only — and changing its node type is not one of §0.1.4's permitted hand-edits. The clearance is therefore achieved with an **18 px-wide invisible `Control` spacer (`RightMargin`) as the last sibling in `Row/Layout`, after `PriceBox`**. `PriceBox` itself is **not widened**, which was the actual intent. Do not "correct" this to a literal margin.
- **Affordability:** a card is affordable when `GameState.gold >= buy_price`.
  - Affordable → full colour, `mouse_default_cursor_shape = POINTING_HAND`, tappable, subtle idle pulse on the price (scale 1.0 ↔ 1.04, 1.6 s period).
  - Unaffordable → whole card `modulate = Color(0.45, 0.45, 0.5, 1.0)`, not tappable.
- **On purchase:** deduct gold, add the item to `GameState.inventory` (which fires `party_bonuses_changed`), then that card:
  - price text becomes **`SOLD!`** in `#E03131`
  - card grays out, permanently untappable for this shop visit
  - a `#F2C230` `-N` gold number floats up from the gold readout
- **Re-evaluate affordability of every card on every gold change** — purchases, sales, slot payouts, upgrade purchases. Connect to `EventBus.gold_changed`. This worked example must hold exactly:
  > Items cost 200, 250, 300; party has 350. All three affordable. Buy the 250 → it reads `SOLD!` and grays out; the 200 and 300 now gray out too, because 100 gold remains.

  Force it with `Debug` `shop 200 250 300` + `gold 350` (§19.2).

### 15.3 Sell tab

- Lists `GameState.sellable_items()` — **equipped items are neither displayed nor sellable.**
- A `VBoxContainer` inside a `ScrollContainer`.
- Each `shop_sell_row.tscn` is 880 × 180, same `HBoxContainer` edge structure as the buy card: rarity edge, name, subtitle, **the full modifier list** (not just a count), and a sell button showing a radius-13 coin glyph beside `Sell for N`.

  > **R5 — ratified substitution.** Godot's `Button` centres its own `text` and has no per-instance icon slot for a custom-drawn `Control`. The button's `text` is therefore **blanked**, and a child `HBoxContainer` (`Content`, `mouse_filter = IGNORE`, full-rect anchors) holds the `CoinGlyph` and an `AmountLabel` carrying the `"Sell for %d"` string. **The button itself remains the click target.** Do not "correct" this back to a `text` assignment — the coin would disappear.
- Pressing it: `GameState.add_gold(sell_price)`, `GameState.remove_item(item)`, the row collapses (height → 0, alpha → 0 over 0.25 s) and is freed, a `+N` gold number floats up, and both the Buy tab's affordability and the bonus strip re-evaluate.
- Empty state: centred `#9B93AE` label, "Nothing to sell."

### 15.4 Close

The red X fades the panel out (scale → 0.9, alpha → 0, 0.2 s), fades the scrim, unpauses (§15.5), `queue_free()`s, and emits encounter-resolved. Nothing else closes the modal. Accepting `ui_cancel` for desktop testing is allowed, not required.

### 15.5 An open shop pauses the game

> **The rule.** An open shop modal pauses the game. **`SHOP` is the only state that pauses**; `LOOT` and the run summary do not.

The motivating problem: `PARTY_DAMAGE_BUFF_DURATION` is 30.0 s and drains in `_process`. A player who buys the buff and then browses the shop would watch 30 seconds of it evaporate against nothing.

**Implementation.**

1. `shop_modal.open()` sets `get_tree().paused = true`. `shop_modal.close()` sets it back to `false` — **before** `queue_free()`, and on **every** exit path, so a modal torn down unexpectedly can never strand the tree paused.
2. `ModalLayer` is `PROCESS_MODE_ALWAYS`. It is inherited, so `ShopModal`, `RunSummary` and every child keep processing: the scrim fade, the panel scale-in, the price pulse, the gold float, the sell-row collapse, and — critically — the **X button**.
3. Nothing else changes its `process_mode`. Everything under `Console` and `BattleView` stays `PROCESS_MODE_INHERIT`, which is what makes the pause do its job.

**Consequences, all intended:**

- `party_damage_button._process` stops, so `_remaining` and `BuffProgress` freeze.
- `run_controller._process` stops, so **shop time does not accrue into `run_stats["run_time"]`**. Run time is time spent playing (§18.2).
- The slot cabinet freezes mid-drift. Acceptable — it is behind a full-screen scrim.
- Sir Fish's tank freezes. Acceptable, same reason. **Do not exempt it**; an animating fish behind a scrim is not worth a `process_mode` exception.

> **Trap — read this before writing any coroutine.** `SceneTree.create_timer()` takes `process_always` and it **defaults to `true`**. Every `await get_tree().create_timer(...)` in the project therefore keeps counting through a paused tree. The three coroutine sites — `run_controller.gd`, `slot_machine.gd`, `battle_director.gd` — were audited and **none has a timer in flight when the shop opens**: `_run_shop` finishes its 0.85 s prop-entry timer before calling `open()`, and `_spin_loop` has already exited because `_should_spin` is false out of combat. If a future change puts a timer in flight across a pause, pass `process_always = false` at that call site rather than restructuring the pause.

> **Trap.** `get_tree().paused = false` must run on **every** exit path, before `queue_free()`. A stranded pause is an unrecoverable soft-lock with no error in the log.

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
- Per paying symbol: exactly 3 = 7³ = **343**; exactly 2 = 3 × 7² × 20 = **2,940**; subtotal **3,283**
- Three paying symbols: 3 × 3,283 = **9,849**
- P(win) = 9,849 / 19,683 = **0.500381…**

| Outcome | Probability |
|---|---|
| 3 of a specific symbol | 1.743% |
| 2 of a specific symbol | 14.937% |
| Any win | 50.038% |
| No win | 49.962% |

Independently reproduced by the implementation: `test_slot_odds.gd` measured 0.50001 over 1,000,000 spins and the exhaustive enumeration returned 9,849 / 19,683 exactly.

**Do not change a single stop.** Nothing touches the strip or the win rate. Upgrades change how *often spins happen* and how *much a win pays*, never the odds.

### 16.3 Spin cycle

Continuous, no player input. One cycle:

1. `slot_spin_started`. All three reels scroll upward at high speed.
2. Reel 0 decelerates and stops at a uniformly random stop index at `t = SLOT_SPIN_DURATION × quick_reels_mult`.
3. Reel 1 stops `+SLOT_REEL_STAGGER × quick_reels_mult` later; reel 2 `+2 ×` that.
4. Each stop tweens to the exact cell offset with `TRANS_BACK/EASE_OUT` over 0.18 s so it overshoots and snaps back — the physical thunk. Add a 4 px cabinet shake on each stop.
5. `slot_spin_stopped([s0, s1, s2])`. Evaluate the payline. On a win, run §16.4 and apply §16.5.
6. Hold `SLOT_RESULT_HOLD × quick_reels_mult`, then spin again if combat is still active.

`quick_reels_mult` is `Tuning.UPGRADE_QUICK_REELS_STEP ^ Upgrades.level(&"quick_reels")` — 1.00 / 0.86 / 0.74 / 0.64. Base cycle is 1.10 + 0.56 + 0.85 ≈ **2.51 s** (~6–10 spins per combat); at Quick Reels 3 it is **1.60 s** (~10–16 spins).

### 16.4 Win presentation

- The winning symbols on the payline pulse: scale 1.0 → 1.30 → 1.0 over 0.35 s, with a `#F2C230` glow ring behind each.
- The payline flashes `#E03131` → `#FFF6E0` → `#E03131` twice.
- **The result banner is centred on the payline, not above the reels.** `Banner` fills the whole `SlotMachine` rect and centres both ways:

  | Property | Value |
  |---|---|
  | `offset_left` / `offset_top` | 0 / 0 |
  | `offset_right` / `offset_bottom` | **1080 / 600** |
  | `horizontal_alignment` / `vertical_alignment` | 1 / 1 (centre) |
  | `font_size` | **72** |
  | `outline_size` | **14** |

  `SlotMachine` is 1080 × 600 and `Payline` spans y 298–302, so a full-rect vertically-centred label puts its text centre at y = 300 — **on the payline**, which is where the player is looking when the reels stop. The outline is 14 rather than 8 because the banner now sits over the symbols rather than over empty cabinet, and `#0F0E14` at 14 px is what keeps `#F2C230` text legible against a gold coin or a blue bolt.

  Text is `"%s x%d"` — `"LIGHTNING x2"` / `"GOLD x3"` / `"HEAL x2"` — with timing 0.12 s in, 1.0 s hold, 0.25 s out.

  > **Trap.** `Banner` must stay **declared after all three `ReelWindow`s** in `slot_machine.tscn` or it composites behind the symbols. If you reorder anything in this scene, re-check it.

  > **Verify, do not assume:** the longest string is `"LIGHTNING x3"` (12 characters). At font 72 it must fit inside 1080 px without clipping. **Screenshot it** (§24 item 2). If it clips, drop to 64 and record the change — do not enable `autowrap`, which would break the single-line read.
- 3-of-a-kind additionally: a 40-particle gold confetti burst and a scale punch 1.0 → 1.05 → 1.0 over 0.25 s on the whole `SlotMachine` node.
- Sir Fish reacts on every win (§17.7) — `cheer` for a pair, `smug` for a triple.

### 16.5 Payouts

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
- If a payout has no valid target, skip it silently but still play the celebration.
- **Slot lightning VFX:** reuse the priest's bolt builder (§9.3) once per enemy, `AOE_STAGGER` apart, **without** the darkening pass.

### 16.6 When the slot runs — attract mode

"Does nothing" is read as *nothing that affects the game* — no stops, no evaluation, no payouts — while the cabinet stays alive:

| State | Behaviour |
|---|---|
| **Combat** (`RunController.state == COMBAT`, fight active) | Full spin cycle (§16.3). Cabinet `modulate = Color.WHITE`. Payline lit `#E03131`. |
| **`combat_ended` transition** | The current spin finishes its stop sequence, evaluates, and pays out normally. Hold `SLOT_RESULT_HOLD`. Then decay into attract mode over 0.4 s. |
| **Attract** (everything else) | Reels drift upward continuously at `SLOT_ATTRACT_SPEED` (0.15× spin speed). **They never stop and the payline is never evaluated.** Cabinet `modulate = Tuning.SLOT_ATTRACT_DIM`. Payline unlit `#5C5470`. |
| **`combat_started`** | Undim over 0.2 s, payline lights, reels accelerate into the first real spin. |

**There is no `OUT OF COMBAT` marquee.** The drifting reels, the dimmed cabinet and the unlit payline already say "not live" without a label saying it in words. The `Marquee` label, the `marquee` and `_marquee_tween` members, `_start_marquee_pulse()` and the two `marquee.visible` assignments are all **removed and must not come back**.

The upgrade tray (§17.6) is live during attract mode, so out-of-combat time is when the player spends.

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

- **Lightning** — `draw_colored_polygon(BOLT, #3B82F6)` then `draw_polyline(BOLT + first point, #F2C230, 7.0, true)`.
- **Gold coin** — `draw_circle(c, 0.42, #F2C230)`, `draw_arc(c, 0.42, 0, TAU, 48, #0F0E14, 6.0)`, inner `draw_circle(c, 0.30, #FFDD66)`, `draw_arc(c, 0.30, 0, TAU, 48, #B8860B, 4.0)`, plus a small `#B8860B` 5-point star at 0.18 radius.
- **Green plus** — `draw_colored_polygon(PLUS, #2FBF4F)` then `draw_polyline(PLUS + first point, #000000, 6.0, true)`.
- **Blank** — draw nothing; the recessed `#231F2E` window shows through.

`coin_glyph.gd` reuses the coin drawing and is the shared component for **every** gold amount in the UI: status panel, shop header, shop buy prices, sell buttons, upgrade costs. Drawn, never an image file.

---

## 17. The management console

### 17.1 Console background

`Console` gets a `ColorRect` at `#231F2E` behind everything plus a 2 px `#4A4260` inner border. The gold `ConsoleDivider` above it separates it hard from the battlefield.

### 17.2 Status panel (1080 × 300)

A `PanelContainer` containing a `VBoxContainer`:

**Row A — resources (height 90):**
- Left: a `CoinGlyph` (36 px) + `str(GameState.gold)`, `DisplayLabel` font 52, `#F2C230`. On `gold_changed`, punch the label scale 1.0 → 1.22 → 1.0 over 0.25 s and float a `±N` label upward beside it in `#F2C230` (gain) or `#E03131` (spend).
- Right: `inventory_strip.tscn` — a horizontal `ScrollContainer` of 64×64 item chips, each a rounded rect in the item's rarity colour with the weapon-type initial (A/S/B/D/T) in `#0F0E14`. New items slide in from the right over 0.3 s. Tapping a chip shows `item_tooltip.tscn` anchored above the chip, dismissed by tapping anywhere.
  - **Chips live inside a container.** Do not tween `position:x` on a child of an `HBoxContainer` — the container overwrites it every layout pass. Animate a wrapper inside a container-managed slot.
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
- **While active:** `disabled = true`, and a `ColorRect` child `BuffProgress` sits below the label and above the stylebox, `#F2C230` at 40% alpha, `size.x` starting at the full button width and draining to 0 over the duration. **Drive it in `_process` from the remaining time — never a Tween.**
- **At 0%:** divide the multiplier back out of every hero (do not set to 1.0 — §13.5's `dmg_pct` lives in the same multiplier), `disabled = false`, hide `BuffProgress`, emit `party_damage_buff_ended`, play a 0.2 s scale punch.
- The timer is **real time, encounter-agnostic, and pause-aware** — driving it from `_process` is exactly what makes it freeze while the shop holds the tree paused (§15.5). Heroes who die while buffed are skipped on removal.

### 17.4 Sir Fish's tank — see §17.7

### 17.5 Status icon (`status_icon.tscn`)

A `Control` (140 × 140) drawn procedurally. Every instance registers its owning `Combatant` and is freed by `cancel_all_effects()` (§8.5).

> **These read as rings over the character, never as discs in front of it.** A 92 px disc at 85% opacity over a ~199 px tall, ~75 px wide character covers the torso completely — the warrior disappeared behind his own Defend icon for the full 4.0 s. That is a pillar-1 failure, and it also makes his `special` — one of the six clips M8b must author and gate **by watching it play** — impossible to verify. You cannot check a swing you cannot see.

Using §5.10's constants:

- **Defend:** `draw_circle(c, ICON_DEFEND_RADIUS, C_DEFEND @ ICON_DEFEND_FILL_ALPHA)`, `draw_arc(c, ICON_DEFEND_RADIUS, 0, TAU, 48, #FFF6E0, ICON_RING_WIDTH)`, and a white shield polygon `[(0.5,0.12),(0.82,0.26),(0.82,0.55),(0.5,0.88),(0.18,0.55),(0.18,0.26)]` normalised to an `ICON_DEFEND_GLYPH_BOX` box, filled `#FFF6E0`.
- **Heal:** `draw_circle(c, ICON_HEAL_RADIUS, C_HEAL @ ICON_HEAL_FILL_ALPHA)`, `draw_arc(c, ICON_HEAL_RADIUS, 0, TAU, 48, C_HEAL @ 0.9, ICON_RING_WIDTH)`, and §16.7's `PLUS` polygon scaled to an `ICON_HEAL_GLYPH_BOX` box.

**The glyph stays fully opaque** — it is what identifies the effect; the fill was only ever a backdrop for it. Ring colours and the 140 × 140 `Control` size are unchanged from the original design.

> **The constraint on any future change (R1).** The alphas are ratified at 0.28 / 0.22 and confirmed on screen. If the effect ever stops reading at 164 px on a phone, raising them is permitted — **but never past the point where the character's silhouette stops showing through**, or the defect is simply back. That trade is the whole of this section.

Both polygon constants must be `static var`, per §16.7.

### 17.6 The upgrade tray

`UpgradeTray` is a `Control` at console-local (0, 1060), 1080 × 212, **always visible and always interactive**, in combat and out.

```
UpgradeTray (Control)
├── BonusStrip (Control)         pos (0, 0)    size 1080 × 30    # bonus_strip.tscn
├── UpgradeButton0 (Button)      pos (12, 34)  size 340 × 178
├── UpgradeButton1 (Button)      pos (370, 34) size 340 × 178
└── UpgradeButton2 (Button)      pos (728, 34) size 340 × 178
```

#### `bonus_strip.tscn` — six entries

One line, font 22, `#9B93AE`, centred, rebuilt on `party_bonuses_changed`.

The five numeric bonuses each get a procedurally drawn 20 px glyph with its value beside it, **omitting any whose value is zero**:

| # | Glyph | Bonus key | Value shown |
|---|---|---|---|
| 1 | sword | `dmg_flat` | `+N` |
| 2 | chevron | `dmg_pct` | `+N%` |
| 3 | §16.7 `BOLT` | `slot_bolt` | `+N` |
| 4 | coin (§16.7) | `slot_purse` | `+N` |
| 5 | §16.7 `PLUS` | `slot_mend` | `+N%` |

**Sixth entry — the element chip.** The sixth key in §13.5's dictionary is `element`, a `StringName` with no number to put beside a glyph. But `element` is **not** invisible in play: it recolours every hero damage number (§11.4). A player whose numbers turned orange with no way to find out why is a pillar-1 failure.

Shown **only when `element != &""`**: a 20 px filled circle in the element's colour (fire `C_FIRE`, ice `C_ICE`, lightning `C_LIGHTNING`) with a 2 px `C_INK` ring, followed by the word `Fire` / `Ice` / `Lightning` in that same colour at font 22. It carries no number because it has no magnitude — it is a label for a colour the player is already seeing.

Order: the five numeric glyphs in table order, then the element chip last. The order is fixed so the strip does not reshuffle as it fills. Empty state (all zero and no element): `No party bonuses` in `#7A7290`.

**Element ties resolve fire → ice → lightning.** `party_bonuses()` picks the element with the largest summed roll; two elements can tie, and an undefined winner would make the damage-number colour flicker between hits. Build the accumulator as `{ &"fire": 0, &"ice": 0, &"light": 0 }` and iterate with a strict `>`; GDScript dictionaries preserve insertion order, so that yields the precedence. **This is a specified rule, not an accident of iteration order** — `test_item_distribution` asserts it with a hand-built tied inventory.

**The strip is width-flexible.** It is 1080 × 30 in the tray and 880 × 34 in the shop modal (§15.1). Glyph size, font size and spacing are constant; the row lays out centred within whatever width it is given. Do not hardcode either width in `bonus_strip.gd`.

This strip is the only place the player can see what their inventory is doing, so it must be present in the console **and** in the shop modal.

#### `Upgrades` autoload (`res://scripts/autoload/upgrades.gd`)

```gdscript
extends Node

const DEFS := {
    &"quick_reels": { "name": "Quick Reels", "blurb": "Reels spin %d%% faster",
                      "base": Tuning.UPGRADE_QUICK_REELS_BASE },     # 60
    &"overcharge":  { "name": "Overcharge",  "blurb": "Lightning pays +%d%%",
                      "base": Tuning.UPGRADE_OVERCHARGE_BASE },      # 70
    &"fat_purse":   { "name": "Fat Purse",   "blurb": "Gold pays +%d%%",
                      "base": Tuning.UPGRADE_FAT_PURSE_BASE },       # 50
}

var levels := { &"quick_reels": 0, &"overcharge": 0, &"fat_purse": 0 }

func level(id: StringName) -> int
func is_maxed(id: StringName) -> bool                # level >= Tuning.UPGRADE_MAX_LEVEL
func cost(id: StringName) -> int                     # for the NEXT level; -1 if maxed
func buy(id: StringName) -> bool                     # spends gold, emits upgrade_purchased
func reset() -> void                                 # all levels to 0, called from reset_run()

func cost(id: StringName) -> int:
    if is_maxed(id):
        return -1
    var base: int = DEFS[id]["base"]
    return int(round(float(base) * pow(Tuning.UPGRADE_COST_GROWTH, float(levels[id]))))
```

**`Upgrades` must not touch `GameState` (or anything else) in `_ready()`** — §3.2's invariant. `DEFS` reads `Tuning` constants at parse time, which is a constant expression and not a cross-autoload call.

| Upgrade | Effect per level | L1 | L2 | L3 | Total | At max |
|---|---|---|---|---|---|---|
| **Quick Reels** | spin cycle × 0.86 (compounding) | 60 | 114 | 217 | 391 | cycle 2.51 s → **1.60 s** |
| **Overcharge** | lightning payout +25% (additive) | 70 | 133 | 253 | 456 | **×1.75** damage |
| **Fat Purse** | gold payout +40% (additive) | 50 | 95 | 181 | 326 | **×2.20** gold |

Maxing everything costs **1,173 gold**; a full run earns roughly 375 before item sales. A run therefore buys **two to four levels total**, against three shop cards competing for the same gold.

Upgrades are **run-scoped**: `Upgrades.reset()` is called from `GameState.reset_run()`.

**`upgrade_button.tscn`** (340 × 178, a `Button` with procedural children):

| Element | Position | Content |
|---|---|---|
| Title | (16, 12) | `DEFS[id].name`, `DisplayLabel` font 30, `#FFF6E0` |
| Blurb | (16, 50) | `DEFS[id].blurb` formatted with the *next* level's cumulative effect, font 22, `#9B93AE` |
| Level pips | (16, 92) | 3 × 18 px squares, 8 px apart; filled `#F2C230` up to `level`, outlined `#5C5470` beyond |
| Cost | (16, 128) | `CoinGlyph` + `str(cost)`, `DisplayLabel` font 32, `#F2C230` |

States:
- **Affordable** — full colour, enabled, gold border pulse 1.6 s period.
- **Unaffordable** — `modulate = Color(0.45, 0.45, 0.5, 1.0)`, `disabled = true`.
- **Maxed** — cost row replaced by `MAX` in `#4CC38A`, `disabled = true`, all three pips filled.

Re-evaluate every button on `gold_changed` and `upgrade_purchased`.

On purchase: `GameState.spend_gold(cost)`, `levels[id] += 1`, `run_stats.upgrades_bought += 1`, emit `upgrade_purchased`, float a `#F2C230` `-N` from the gold readout, punch the button 1.0 → 1.06 → 1.0 over 0.25 s, and fill the newly-earned pip with a `TRANS_BACK/EASE_OUT` scale pop. Sir Fish plays `smug`.

**What upgrades must never do:** touch `SLOT_STRIP`, the win rule, or the win rate. "More often" is delivered by Quick Reels compressing the cycle — the same 50% of *more spins per minute* — not by rigging the reels.

### 17.7 Sir Fish

He is an armoured fish in a glass tank bolted to the console at console-local **(8, 898), 164 × 164**, immediately left of the party damage button. He has **no gameplay effect at all**.

**`sir_fish_tank.tscn` — the three viewport requirements are load-bearing:**

```
SirFishTank (SubViewportContainer, 164×164, stretch = true)
└── FishViewport (SubViewport, 164×164, transparent_bg = true, own_world_3d = true)
    ├── FishEnvironment (WorldEnvironment)      # mirrors §6.4's ambient values:
    │                                           #   BG_COLOR, ambient AMBIENT_SOURCE_COLOR
    │                                           #   #A8D8E8 at energy 0.55,
    │                                           #   TONE_MAPPER_LINEAR, saturation 1.15
    ├── FishCam (Camera3D)          orthographic, size 1.4, position (0, 0, 3), rotation (0,0,0)
    ├── FishLight (DirectionalLight3D)  rotation (-30°, -25°, 0°), energy 1.2, colour #FFF3D6
    ├── Tank (Node3D)               # built procedurally by sir_fish_tank.gd — see R7 below
    │   ├── WaterBackdrop (MeshInstance3D)  QuadMesh at z -0.9,
    │   │                              unshaded #7EC8E3 at 0.35 alpha — the water read
    │   ├── Glass (MeshInstance3D)  SphereMesh(r 0.62), water.gdshader
    │   ├── Base (MeshInstance3D)   CylinderMesh(r 0.50, h 0.10) #F2C230 at (0, -0.62, 0)
    │   ├── Gravel (MeshInstance3D) CylinderMesh(r 0.44, h 0.08) #8B5A2B at (0, -0.50, 0)
    │   └── Plaque (MeshInstance3D) BoxMesh(0.46, 0.12, 0.02) #F2C230 at (0, -0.72, 0.30)
    │       └── PlaqueText (Label3D)  "SIR FISH", font 16, #0F0E14
    ├── SirFish (Node3D)            sir_fish.gd
    │   └── Model                   instance of res://assets/meshes/sir_fish.glb  [M8a]
    └── Bubbles (GPUParticles3D)    one_shot, amount 14, lifetime 0.9, #FFFFFF @ 0.5,
                                    gravity (0, 1.2, 0), scale 0.03 → 0.01
```

**Three viewport settings are mandatory, not optional.** Losing any one of them reproduces a bug that shipped:

1. **`own_world_3d = true`.** Without it a `SubViewport` shares its parent's `World3D`, so `FishCam` renders the *battlefield* — sky, hills and all — inside the tank.
2. **`FishEnvironment` follows from (1).** An own world has no `WorldEnvironment`, hence no ambient light, so the cel shader has only the key light and the whole bowl reads as a dark blob.
3. **`WaterBackdrop` follows from `transparent_bg`.** The glass sphere tints straight onto the console's `#231F2E` panel, so the tank interior stays dark. An unshaded water-blue quad behind the fish gives the interior a colour to be.

**Carry all three through any future model swap** — they belong to the viewport, not the meshes.

> Note the node is named **`WaterBackdrop`**, not `Backdrop`. Earlier spec drafts listed the shorter name; the code is the authority here and the name is not worth churning.

#### R7 — the tank is procedural, permanently

**`sir_fish_tank.gd`'s `_build_tank()` builds the bowl, gold base ring, gravel bed and plaque in GDScript, and that is where they stay. Do not re-model the tank in Blender.**

§0.1.2 permits either route, and the M8a brief's "Tank: a rounded bowl, a gold base ring, a gravel bed, and a small gold plaque" describes **content that must exist** — which it does, and which already passed the lit-fish-bowl regression check — not a mandate to move its authoring route. Re-modelling four primitives in Blender for a visually indistinguishable result would be pure churn, and it would put the three viewport settings above at risk for no gain. The plaque's `Label3D` approach stays too, so no font asset is ever baked into a mesh.

`water.gdshader` (`res://assets/shaders/water.gdshader`): `blend_mix, cull_back, unshaded, depth_draw_never`; `ALBEDO = #7EC8E3`, `ALPHA = 0.22 + 0.10 * fresnel`, plus a slow `sin(TIME)` ripple on the fresnel term. Glass, not water simulation.

All fish meshes use the §6.2 cel material with the §6.3 outline `next_pass`, reassigned from the arriving `StandardMaterial3D`s by `RIG.reassign_materials` on load, exactly like the combatants.

**Reaction states** (`sir_fish.gd`), each an `AnimationPlayer` clip in the exported `.glb`, driven entirely by `EventBus`:

| State | Trigger | Length | Behaviour |
|---|---|---|---|
| `idle` | default | 3.00 loop | slow figure-8 swim, gentle tail wag ±12° |
| `cheer` | `slot_payout` (2 of a kind) | 1.20 | fast tail wag, two vertical hops, 6-bubble burst |
| `smug` | `slot_payout` (3 of a kind), `upgrade_purchased` | 1.50 | slow 360° spin about Y, chest out, gold sparkle particles |
| `alarm` | `combatant_damaged` where the target is a hero | 0.80 | darts to the far side of the tank and back |
| `grieve` | `combatant_died` where the combatant is a hero | 2.00 | sinks to the gravel, still, then rises back to `idle` |
| `slump` | `game_over` | 1.20 → hold | sinks, rolls onto his side, the helm tips off and lands on the gravel. **Holds.** |
| `triumph` | `run_completed` | 2.50 → loop | rapid spins, continuous bubbles, circlet glints |

**Priority**, highest first: `slump` / `triumph` > `grieve` > `alarm` > `smug` > `cheer` > `idle`. A higher-priority state interrupts a lower one; a lower one is dropped if a higher one is playing. Every non-looping state returns to `idle` on finish, except `slump` and `triumph`, which hold until `run_started`.

**Rate limit:** `alarm` fires at most once per 0.6 s. `cheer` is not rate-limited; slot wins are already paced by the spin cycle.

Sir Fish also appears in the run summary (§18.2) — the same `sir_fish_tank.tscn` at 2× scale in the panel header, with **no separate authored variant**, already in `slump` or `triumph`.

### 17.8 Slot counter

`slot_counter.tscn`, a `Control` at console-local **(908, 898), 164 × 164** — a true mirror of the fish tank across the party damage button (§3.3.1).

| Element | Content |
|---|---|
| Label | `SLOT` — font 22, `#9B93AE`, centred, at y 8 |
| Wins | `str(run_stats.slot_wins)` — `DisplayLabel` font 52, `#F2C230`, centred, at y 34 |
| Divider | 100 × 2 `#4A4260` at y 92 |
| Spins | `%d spins` % `run_stats.slot_spins` — font 24, `#9B93AE`, centred, at y 104 |
| Streak pips | five 12 px squares at y 138, filled `#F2C230` for a win and `#4A4260` for a loss, newest on the right |

Updates on `slot_spin_stopped`. The wins number punches 1.0 → 1.18 → 1.0 on each increment.

**No percentage anywhere a small sample can be read as a verdict.** At 21 spins, 1σ is about 11 points, so a run showing "33%" reads as a rigged machine when it is ordinary variance. The 50% sanity check lives where the sample size makes it meaningful — `test_slot_odds.gd`, one million spins.

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

- **Defeat:** all heroes dead → `RunState.GAME_OVER`. Freeze combat, let the last `die` finish, hold 1.0 s on the battlefield, fade a `#0F0E14` scrim to 75% over 0.5 s, then present. Sir Fish plays `slump` as `game_over` fires, **before** the scrim — the player should see him give up.
- **Victory:** encounter 5 resolved → heroes run right for 2.0 s, then the same presentation with victory styling. Sir Fish plays `triumph`.

**The run summary does not pause the tree** (§15.5) — `SHOP` is the only state that does.

### 18.2 Content

Panel 900 × 1180, centred.

- **Sir Fish's tank** at the top of the panel, `sir_fish_tank.tscn` at 2× scale (328 × 328), centred, already holding `slump` or `triumph`.
- Title: **`DEFEATED`** in `#E03131` (`DisplayLabel`, font 84) or **`LEVEL CLEARED`** in `#F2C230` (font 76). Slam in: scale 1.6 → 1.0 over 0.35 s, `TRANS_BACK/EASE_OUT`, 6 px `#0F0E14` outline.
- **Subtitle — branch on the `victory` flag `present()` already receives:**

  ```gdscript
  if victory:
      subtitle.text = "Cleared all %d encounters" % GameState.level.encounters.size()
  else:
      var shown_index: int = clampi(GameState.current_encounter_index + 1,
          1, GameState.level.encounters.size())
      subtitle.text = "Reached encounter %d of %d" % [shown_index,
          GameState.level.encounters.size()]
  ```

  A single unconditional `"Reached encounter %d of %d"` prints **"Reached encounter 7 of 6"** under a `LEVEL CLEARED` title, because `_next_encounter()` has already incremented `current_encounter_index` past the last encounter before `_run_complete()` fires. The defeat index is **clamped** so that path can never print an out-of-range index either.

- Stat table, `label` left / `value` right, font 38, rows revealing 0.08 s apart with a slide-in from the left:

| Label | Source |
|---|---|
| Encounters cleared | `run_stats.encounters_cleared` |
| Run time | `run_stats.run_time`, formatted `M:SS` — **excludes time spent in the shop** (§15.5) |
| Gold earned | `run_stats.gold_earned` |
| Gold spent | `run_stats.gold_spent` |
| Gold on hand | `GameState.gold` |
| Damage dealt | `run_stats.damage_dealt` |
| Damage taken | `run_stats.damage_taken` |
| Slot spins | `run_stats.slot_spins` |
| Slot wins | `run_stats.slot_wins` — **the raw count, with no percentage** |
| Upgrades bought | `run_stats.upgrades_bought` |
| Items found | `run_stats.items_found` |
| Items sold | `run_stats.items_sold` |

`_format_time` must split its integer division explicitly — `@warning_ignore("integer_division")` plus separate `minutes` and `seconds` locals — or it emits a warning and fails the gate.

- A **`RETRY`** button, 560 × 140, centred at the bottom.

### 18.3 Retry

Full reset, no carryover:

1. Free all combatants (including the hidden dead heroes from §12.5), projectiles, props, bars, floating elements and status icons.
2. `GameState.reset_run()` — gold → `Tuning.STARTING_GOLD`, inventory cleared, `hero_runtime` rebuilt at full HP, `current_encounter_index = -1`, `run_stats` zeroed, `level = build_level()`.
   - `run_stats["run_time"] = 0.0` needs an explicit branch; `0.0 if key == "run_time" else 0` is an incompatible ternary and will not compile.
3. `Upgrades.reset()` — every level back to 0.
4. Clear the slot's `_last_hero_hits`, return the slot to attract mode, cancel any party damage buff.
5. Reset the parallax tiles to their starting offsets. **Do not rebuild the tile meshes** — they are deterministic (§7.5.3) and rebuilding them each retry is pure garbage.
6. Rebuild the inventory strip and the bonus strip from the (now empty) inventory; reset the slot counter; Sir Fish returns to `idle`.
7. `RunController` → `BOOT` → `TRAVEL`.

Verify **three consecutive retries** with `get_editor_errors` clean each time and `get_game_scene_tree` node counts stable.

---

## 19. Verification tooling

### 19.1 The harness is permanent

This MCP build has no `execute_editor_script` and no `execute_game_script`. `res://scripts/autoload/debug.gd`, autoload `Debug`, is **permanent and flag-gated**, not temporary. A harness that gets deleted gets rebuilt from scratch every session, and the deletion itself is a change nobody verifies.

### 19.2 The `Debug` harness

`set_game_node_property` can set a property but cannot call a function, so the harness exposes **one string property with a setter that parses and executes**:

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

`Debug` reads other autoloads only from `_run()` — never from `_ready()` (§3.2).

Commands — verb first, space-separated arguments:

| Command | Effect |
|---|---|
| `anim <combatant_id> <name>` | Force `play_anim(name)` on the named living combatant, ignoring state |
| `spawn <stats_id>` | Spawn that character at the first free enemy slot, idle, for animation review |
| `sethp <combatant_id> <hp> [<max>]` | Set current (and optionally max) HP directly, no events |
| `damage <combatant_id> <amount>` | `take_damage(amount, null)` with **no variance roll** |
| `kill <combatant_id>` | Force HP to 0 and run the death path |
| `slot <s0> <s1> <s2>` | Force the **next** spin's payline symbols (0 LIGHTNING, 1 GOLD, 2 PLUS, 3 BLANK), then clear the override |
| `shop <p0> <p1> <p2>` | Override the next shop's three **buy prices** — see the round-trip rule below |
| `gold <n>` | Set `GameState.gold` and emit `gold_changed` |
| `upgrade <id> <level>` | Set an upgrade level directly, no cost |
| `additem [rarity]` | Generate and add one item, optionally forcing rarity |
| `equip <index>` | Flag `inventory[index].equipped = true` |
| `parallax <units>` | Advance every parallax layer by `units` world units at its own speed multiplier, wrapping normally, without changing `scroll_speed` or the run state |
| `state` | Dump run state, HP of all combatants, gold, upgrade levels and party bonuses to the log |

`<combatant_id>` resolves against `stats.id`; if two are alive with the same id, suffix an index: `shadow_monster:1`. **This resolver is the only legitimate id comparison outside `combatant_rig.gd`** (§4.1); it compares with `String(c.stats.id) != want`.

**`parallax` exists because §7.5's gate is otherwise undrivable.** A tile boundary on layer 1 sits 13.1 world units off-screen and the layer scrolls at 0.4 units/sec, so reaching it takes **over 30 seconds of continuous travel** — longer than the entire demo's travel time. `parallax 40` walks every layer past at least one wrap in one command.

**`shop` searches for a `value` that round-trips.** The naive `value = price / SHOP_BUY_MARKUP` does not survive the int round-trip: `250 / 1.5 = 166.67 → 167`, and `167 × 1.5` rounds back to **251**, which makes a gate whose whole purpose is exact numbers inexact.

```gdscript
# Debug.apply_shop_override — pick the value that reproduces the requested price exactly.
func _value_for_price(price: int) -> int:
    var base := int(round(float(price) / Tuning.SHOP_BUY_MARKUP))
    for candidate: int in [base, base - 1, base + 1]:
        if int(round(float(candidate) * Tuning.SHOP_BUY_MARKUP)) == price:
            return candidate
    return base      # unreachable for any price the gate uses; log if hit
```

Every command logs exactly one line, `[DEBUG] <verb> → <result>`. Unknown verbs log `[DEBUG] unknown command: <verb>` and change nothing.

**Release safety.** `enabled` is false in an exported release build. Do not add UI for it; it is MCP-only.

### 19.3 Headless tests

Every numeric gate item is a headless test. Run them **directly**, not through the MCP inspector:

```bash
godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_slot_odds.tscn
```

Each test scene prints `PASS`/`FAIL` lines and exits with a non-zero code on failure.

**`TestSupport` is `preload`ed, never declared with `class_name`.** A newly-added global class is not in the class cache when a headless run starts, so `class_name` resolution fails from the command line. This applies to every future test helper.

| Test | Asserts | Status |
|---|---|---|
| `test_slot_odds` | 1,000,000 spins, win rate ∈ [0.490, 0.510]; per-symbol 3-of-a-kind ∈ [0.014, 0.021]; exhaustive enumeration = 9,849/19,683; strip counts 7/7/7/6 | passing — **0.50001** |
| `test_item_distribution` | 200 items: rarity split near 50/30/15/5; reports value and buy-price min/median/max; no item carries a duplicate modifier id; the fire→ice→lightning tie-break | passing |
| `test_damage_chunk` | §11.2's arithmetic for 100 HP hit for 20: chunk `x ∈ [108.8, 136.0]`, width 27.2, and a spread of other HP/damage pairs | passing |
| `test_retarget` | Projectile arrival with (a) a live target, (b) a dead target and others alive, (c) all enemies dead — no null access in any case | passing |
| `test_economy` | Mean over 1,000 runs — see below | passing — mean 169.4 |
| `test_upgrades` | Cost curve matches §17.6's table exactly; `is_maxed` at level 3; payout maths at every level combination; `reset()` clears everything | passing |
| `test_parallax_seam` | §7.5.4's five assertions for layers 1–3 | passing |
| `test_autoload_safety` | §3.2's invariant, as a source lint | passing |

**Eight tests. `test_damage_chunk` and `test_parallax_seam` are the two to watch** after any geometry or overlay change — neither should ever move, and if either does, something went further than it should have.

#### `test_autoload_safety`'s scope, and its limits

The test reads each autoload script with `FileAccess`, isolates the body of `_ready()` and `_init()` (from the `func` line to the next line at top-level indentation), and fails if any other autoload's name appears in it.

**Two exemptions, both deliberate:**

- **`const` and `static var` initializers are exempt.** `Upgrades.DEFS` reads `Tuning.UPGRADE_QUICK_REELS_BASE` at parse time; that is constant folding, not a call into a live node, and it carries no ordering dependency. The lint must not flag it or it will be disabled within a week, which is worse than not having it.
- **The three `MCP*` autoloads are exempt.** They are not ours and §3.2 says leave them untouched.

**It is a lint, not a proof.** An indirect call — `get_node("/root/GameState")`, or a helper invoked from `_ready()` — slips past it. That is acceptable: the failure it guards against is someone adding a new autoload and reaching for a sibling in `_ready()`, which is the direct form. Say so in the file header rather than letting a reader mistake it for a guarantee.

#### `test_economy`'s assertion, stated literally

A single 14-spin sample has enormous variance. Gold payouts land on roughly 16.7% of spins, so a run with zero gold wins is entirely ordinary and finishes on 75 gold. The measured single-run spread is min 75 / median 145 / max 450. A test asserting a single run's gold falls in `[150, 260]` fails at random, which makes it worse than useless — a flaky gate teaches the next author to ignore red.

The test asserts, and must keep asserting:

1. **The mean over 1,000 simulated 14-spin runs falls in [150, 260].** Last measured: **169.4**.
2. It **reports** the single-run distribution (min / p25 / median / p75 / max) as informational output, so the spread stays visible and nobody re-derives the same wrong conclusion from the mean alone.
3. `generate_shop_stock()` produces at least one card affordable at the *sampled* gold of that trial in **≥ 95% of 1,000 trials**.

> **General rule this establishes:** an assertion on a random quantity states the statistic and the sample size. **A test that can fail on a fair run is a defect in the test.**

### 19.4 Known non-issues

`ERROR: Class name cannot be empty.` lines in the output log are emitted by the Godot MCP addon's own runtime inspector while it reflects over script-based nodes. They never appear during play that is not being queried over MCP. **They are not game bugs — do not go hunting for them.**

---

## 20. Milestones and verification gates

**M0 through M8a are built and verified.** The remaining work is **M8b, M8c, M8d, M8e**, plus §24's verification backlog.

For each gate: `play_scene`, drive it with `Debug` and the runtime tools, screenshot it, run the headless tests, and check `get_editor_errors` and `get_output_log` — **zero errors and zero warnings**.

### 20.1 Status

| Milestone | Content | Status |
|---|---|---|
| M0–M7 | Everything through the closed upgrade loop | **Complete and gated** |
| M7.5 | v3 ratification: two stat fields, parallax rebuild, element chip, slot counter geometry, `Debug parallax`, two new tests | **Complete and gated** |
| M7.6 | Twelve items: bar overlap, status icons, framing, coin glyphs, victory subtitle, third id check, shop pause, marquee removal, banner, corpse fade, dead-hero slide, chunk fling | **Complete and gated**, with four screenshot items owed (§24) |
| M8a | Sir Fish: three-bone rig, seven clips, glTF export, Godot swap | **Complete and gated**, with three items owed (§24) |
| **M8b** | **The three heroes** | **Next — not started** |
| M8c | The three enemies | Not started |
| M8d | Environment layers 4 and 5 | Not started |
| M8e | Full integration | Not started |

### 20.2 Why M8 is split at all

An earlier plan made M8 one milestone containing ~50 discrete assets — 6 characters, 6 rigs, ~26 actions, a fish rig with 7 actions, a tank, 2 environment tile sets — with a single gate at the end. That is more work than M6 and M7 combined behind one pass/fail. Each sub-milestone below is independently gated and independently revertible, and any one of them can be the stopping point of a session without leaving half-rigged assets in the `.blend`.

The split follows a rule worth restating: **milestones split along logic-versus-presentation lines, not along feature lines**, because the harness depends on logic and the gates depend on the harness.

### 20.3 M8a — Sir Fish, finished *(complete)*

Recorded here because M8b inherits its pipeline and its traps.

**What was built:** a **three-bone** armature (`Root`, `Tail`, `Helm` — see R6 in §23.5), the seven actions from §17.7's table, glTF export to `res://assets/meshes/sir_fish.glb`, and the Godot swap with `FishViewport`'s three settings intact. The tank stayed procedural (R7).

**Confirmed live:** `idle` (visibly animating across `capture_frames`, not a T-pose), `alarm` (via `Debug damage warrior 5`), `grieve` (via `Debug kill ranger`), `slump` (whole-party wipe; holds correctly under a `DEFEATED` screen), `triumph` (a run cleared all six encounters; fish spinning with bubbles at 2× in the run summary). Materials verified: every `MeshInstance3D` under the swapped model carries a `CelMaterials.cel(...)` `material_override`, not the arriving `StandardMaterial3D`. Zero editor errors; all eight tests pass.

**Owed:** `cheer` / `smug` captures, the 164 px isolated read-gate, and `slump`'s helm-vs-gravel placement — §24 items 5–7.

### 20.4 M8b — The three heroes *(next)*

One character at a time: mesh, 17-bone armature (§23.2), the **six** actions `required_anims()` demands for a hero with a special — `idle`, `run`, `attack`, `special`, `hurt`, `die` — export, swap, material reassignment. Eighteen actions across the three heroes.

Delete that character's branch from `combatant_rig.gd` as its real mesh lands (§8.2).

**Gate, per hero, before starting the next one:**
- Side-by-side screenshots before and after the swap.
- Every required animation forced via `Debug anim` and **captured as a sequence, not a single frame** — `capture_frames` at roughly 6 frames across the clip's length. A still cannot show that a limb swings; it can only show that a limb exists. Confirm the swing is **in the screen plane** (§9.0), the most likely thing to be lost in a Blender re-author.
- **The warrior's `special` is the one to watch.** Defend now renders as a ring (§17.5) specifically so this clip is verifiable — check the body reads through it for the full 4.0 s.
- `die` ends lying down and holds its final pose.
- `required_anims()`'s assert passes.
- **Materials verified structurally, not visually.** Query the swapped mesh with `get_game_node_properties` and confirm each surface's material is the cel shader **and** that its `next_pass` is non-null. A `.glb` arrives with `StandardMaterial3D`s; a character with the cel material but no `next_pass` looks *almost* right in a screenshot and has silently lost the outline that is the entire art direction.
- **The character is not a black silhouette** — the §6.2 depth-mode check, the other way this fails.
- The combat gate re-runs clean for an encounter containing that hero.

### 20.5 M8c — The three enemies

Shadow monster (**no armature** — shape keys and object transforms), orc barbarian, orc warlord. The barbarian and warlord share one mesh, one armature and one action set; the warlord differs only by `model_scale`, colours, shoulder pads and `speed_scale`.

Enemies need only `idle`, `attack`, `hurt`, `die` — **do not author `run` or `special` for them** (§8.3).

**Gate:** as M8b, per enemy, plus:
- Enemies still face the heroes under `rotation.y = PI` with no mirrored geometry (§7.3 — never negative scale).
- The death fade takes body **and** outline together, on both the slow and the **rush** path (§10.4).
- The warlord reads as heavier than the barbarian at `speed_scale = 0.87`.
- **A warlord encounter screenshotted for framing** — this also closes §24 item 1.

### 20.6 M8d — Environment: layers 4 and 5

The two Blender parallax layers only (§23.4). Layers 1–3 were finished in M7.5 and are not touched here.

**Gate:**
- Each tile is exactly 12.0 units wide and centred on its origin, verified numerically from the imported mesh AABB — not by eye.
- No scatter feature's AABB crosses `x = ±6` (§7.5.2 R3, applied to modelled geometry).
- The three copies of each layer share one `Mesh` (R1).
- `Debug parallax 40` then screenshots at each join: no seam in either layer.
- Layer 5 renders in front of the characters, carries the cel + outline treatment, and stays below `y ≈ 1.2` so a hero is readable behind it.
- **This is also the milestone that addresses the empty sky** (§7.2): taller hills and tree canopy are an art fix, not a camera fix.

### 20.7 M8e — Full integration

No new assets. Re-run everything.

**Gate:**
- The M7.5, M7.6, M8a, M8b, M8c and M8d gates all re-run clean in one session.
- **Every item in §24 is closed.**
- All eight headless tests pass.
- Three consecutive full hands-off runs — closing only the shop modal, which §15.4 requires a real click for — zero errors and zero warnings, with stable node counts across retries.
- Frame rate at or above 60 fps via `get_performance_monitors` during the encounter-5 boss fight — the heaviest frame in the game.
- A final screenshot set: one per encounter type, plus the run summary in both victory and defeat.

---

## 21. Change log and standing decisions

**If you disagree with one of these, do not silently change it.** Implement as specified and append a note to §21.5.

### 21.1 Owner-resolved (carried forward, unchanged)

| # | Question | Decision |
|---|---|---|
| A1 | Platform and orientation | **Portrait mobile, 1080×1920**, touch-first, mouse emulation on for development. |
| A2 | Asset strategy | **Placeholder primitives first, Blender models last (M8).** |
| A3 | Boss | **A scaled-up orc barbarian** (`orc_warlord`): 1.70×, 280 HP, 22 damage, distinct colouring, shoulder pads. No new asset. |
| A4 | Document shape | **Phased build plan with verification gates** (§20). |
| A5 | Game over | **Run summary with full stats**, then a Retry that fully resets. |
| A6 | Equipment | **No equipping in the demo.** Items are loot, sell fodder, and a party-wide bonus pool. The `equipped` field and `sellable_items()` filter exist and must work. |
| A7 | Console HUD | **Full status panel** — gold, inventory strip, per-hero rows. |
| A8 | Level length | **6 encounters** (§12.1). |
| A9 | The fish | **Sir Fish is the player** — the console operator, not a hero. |
| A10 | The core loop | **A vertical slice**: three purchasable slot upgrades plus item modifiers that feed hero damage and slot payouts. |

### 21.2 Outstanding edits to the existing build

Everything from v3's E1–E14 and v3.5's twelve items is **implemented and verified on disk**, with one exception:

| # | File(s) | Change | Status |
|---|---|---|---|
| **E5** | filesystem | `rm -rf resources/levels` — the orphaned `demo_level.tres` (§12.1) | **Done, 2026-08-14.** Outstanding since v3. It had been shipping into builds via `export_filter="all_resources"` — see §12.1. |

**Nothing in v3's E1–E14 or v3.5's twelve items now remains outstanding.**

Verified applied during this document's preparation: the three `CombatantStats` flags and all three id-guard replacements; `parallax_profiles.gd` and the layer 1–3 rebuild; the element chip and tie-break; `SlotCounter` at (908, 898) 164×164; `Debug parallax`; `test_parallax_seam` and `test_autoload_safety`; `HERO_SLOT_X`/`ENEMY_X_MIN`/`ENEMY_X_MAX`; `BattleCamera.size = 5.8`; all seven `ICON_*` constants; both `*_RUSH` constants; all five `CHUNK_*` constants; the corpse generation counter; `shop_modal`'s paired pause/unpause; the victory subtitle branch; `telegraphs_primary`; coin glyphs in all three shop scenes; the `Marquee`'s removal; the banner at 1080×600 / font 72 / outline 14; the concurrent dead-hero slide; and Sir Fish's three-bone `.glb` with all seven clips.

### 21.3 Accepted permanent deviations — do not "fix" these

| # | Where | Deviation | Why it stands |
|---|---|---|---|
| **C1** | `project.godot` | `msaa_3d` stored as `2.0` (TYPE_FLOAT) | `set_project_setting` coerces numerics to float; Godot casts back to 2 and applies 4× MSAA. Fixing it requires a forbidden hand-edit to change nothing observable. (§2) |
| **C2** | `scenes/main.tscn` | `ModalLayer`'s node header and the two per-modal `theme =` lines were hand-edited | Changing a node's *type* needs delete-and-recreate; this build has no `delete_node`. The alternative was a permanent orphan `CanvasLayer`. (§0.1.4) |
| **C3** | `project.godot` `[autoload]` | `Upgrades` registered after `GameState` | `add_autoload` only appends. The ordering constraint was about load-time reads; §3.2 replaces it with a tested invariant. |
| **C4** | `scenes/main.tscn` | `RunController` declared after `ModalLayer` | It draws nothing, so it cannot occlude a modal. §3.3's rule reads "last **`Control`** child". |
| **C5** | `tests/*.gd` | `TestSupport` is `preload`ed, not `class_name` | A new global class is not in the class cache at headless start. Applies to every future helper. (§19.3) |
| **C6** | `scenes/console/slot_machine.tscn` | The `Marquee` node block was removed by hand-editing the `.tscn` | **R3.** No `delete_node` exists in this build; the alternative was a permanent orphan label in the console. Minimum lines touched, no orphan left behind. (§16.6) |
| **C7** | `scenes/modals/shop_buy_card.tscn` | The buy card's 18 px right clearance is an invisible `Control` spacer (`RightMargin`), not a margin on `PriceBox` | **R4.** `PriceBox` is a `VBoxContainer` with no per-instance margin property, and retyping it is not a permitted hand-edit. The specified outcome is met and `PriceBox` is not widened. (§15.2) |
| **C8** | `scenes/modals/shop_sell_row.tscn` | The sell button's label lives in a child `HBoxContainer` (`Content`), not in `Button.text` | **R5.** `Button` centres its own text and has no per-instance icon slot for a custom-drawn `Control`. The button stays the click target. (§15.3) |
| **C9** | `scripts/console/sir_fish_tank.gd` | The water backdrop node is named `WaterBackdrop`, not `Backdrop` | Cosmetic naming drift from an earlier spec draft. The code is the authority; renaming it is churn with a regression risk attached. (§17.7) |
| **C10** | `blender/Sir Fish.blend` | Sir Fish's armature has **three** bones, not two | **R6.** The `slump` helm-detach requirement needs an attachment point to detach *from*. (§23.5) |

### 21.4 Traps — do not regress these

**Engine and language**

| Where | Trap |
|---|---|
| `cel_shade.gdshader` | `depth_draw_opaque` on a transparent material writes no depth, so the inverted hull covers the body and every character renders as a **black silhouette**. Use `depth_draw_always`. (§6.2) |
| everywhere | `SceneTree.create_timer()` defaults to `process_always = true` — it **ignores** pause. Any timer that must respect the shop pause has to pass `false` explicitly. (§15.5) |
| `shop_modal.gd` | `get_tree().paused = false` must run on **every** exit path, before `queue_free()`. A stranded pause is an unrecoverable soft-lock with no error in the log. |
| `main.tscn` | `ModalLayer` must be `PROCESS_MODE_ALWAYS` or the shop's own X button stops working the instant the tree pauses. |
| `slot_symbol.gd`, `status_icon.gd`, `buff_chip.gd` | `const X := PackedVector2Array([...])` is not a constant expression in 4.7 — use `static var`. The parse failure cascades into the class never registering. |
| everywhere | `var x := <call on an untyped variable>` is a hard parse error. Annotate explicitly. |
| `game_state.gd` | `0.0 if cond else 0` is an incompatible ternary. Use an explicit branch. |
| `event_bus.gd` | `@warning_ignore_start("unused_signal")` for the whole file. |
| `parallax_background.gd` | Never name a parameter `scale` in a `Node3D` script — it shadows `Node3D.scale`. |
| `run_summary.gd` | Split and annotate the integer division in `_format_time`. |
| `inventory_strip.gd` | Never tween `position:x` on a direct child of an `HBoxContainer`. Animate a wrapper inside a container-managed slot. |
| `inventory_strip.gd` | `reset_run()` clears the inventory array without per-item signals — rebuild on `run_started`. |
| `shop_buy_card.tscn`, `shop_sell_row.tscn` | A `PanelContainer` force-resizes every child to fill it. The rarity edge lives in an `HBoxContainer` with `custom_minimum_size = (12, 0)`. |
| `shop_modal.tscn` | A script declared as an `ext_resource` but never assigned to the root node. The shop encounter hangs forever. Verify with `attach_script`. |
| `cel_materials.gd` | `flash()` must remember the base colour once via `set_meta("base_albedo")`. Reading the live albedo latches white in permanently after two overlapping flashes. |

**Asynchrony and coroutines — all three cost live debugging time**

| Where | Trap |
|---|---|
| `battle_director.gd` | **A boolean "superseded" flag shared by the superseder and the superseded deadlocks.** `begin_corpse_cleanup()` setting `corpse_rushed = true` before entering the same fade function makes the *rush* coroutine conclude it was itself superseded, so it returns without ever finishing — and the run hangs in `COMBAT` forever with nothing in the log. **Use a per-corpse generation counter.** (§10.4.1) |
| `battle_director.gd` | `Tween.tween_method` calls its callable with **the tweened value as the leading positional argument**, then appends `.bind()`'s arguments after it. `tween_method(Callable(self, "_set_alpha").bind(c), ...)` calls `_set_alpha(alpha, c)` — declare the parameter list in that order, and check the callee's own signature matches too. Two functions were backwards in the same chain. |
| `battle_director.gd` | A corpse can be mid-slow-fade when victory lands. The rush path must **kill the in-flight tween** and resume from the current alpha, not stack a second tween on the same property. |
| `run_controller.gd` | The dead-hero slide tween is owned by `RunController` and must survive the state change to `TRAVEL`. Do not parent it to anything the next encounter tears down. |

**Geometry and layout**

| Where | Trap |
|---|---|
| `tuning.gd` | `HERO_SLOT_X` spacing and `CombatantBars`' 140 px width are **coupled**. Any change to either must keep `spacing × (640 / camera.size) > 148`. (§7.2.1) |
| `battle_world.tscn` | Change `BattleCamera.size` **only**. Moving `position.y` shifts the horizon against parallax geometry authored for this framing. |
| `battle_world.tscn` | `Slot0`/`Slot1`/`Slot2` are vestigial — positions come from `Tuning.HERO_SLOT_X`. Do not "sync" them and do not trust them. |
| `slot_machine.tscn` | `Banner` must stay declared after all three `ReelWindow`s or it composites behind the symbols. |
| `parallax_background.gd` | A per-tile phase offset — or a per-tile RNG seed — on tiles that wrap into each other guarantees a discontinuity at every join. All copies share one mesh. (§7.5 R1) |
| `parallax_background.gd` | Jitter applied to a feature position without clamping for the feature's own radius lets geometry overhang the tile boundary. Clamp to `[−W/2 + r, W/2 − r]`. (§7.5 R3) |
| `floating_health_chunk.gd` | Halve displacement, **not** flight time. Shortening 0.70 makes the effect snappier, which is the opposite of the ask. |
| `battle_overlay.gd` and any 3D layer | `BattleOverlay` is a 2D `Control` composited over the whole SubViewport, so **no 3D geometry can ever occlude the bars, damage numbers or status icons**. Do not "fix" foreground geometry to protect them; the thing at risk is the character underneath. (§23.4) |
| `status_icon.gd` | A filled disc over a character hides it. These are **rings**. Raising the fill alphas past the point where the silhouette shows through un-fixes the finding. (§17.5) |
| `sir_fish_tank.tscn` | A `SubViewport` without `own_world_3d` renders the parent world; with it and no `WorldEnvironment`, everything is unlit; with `transparent_bg` and no backdrop, the interior is dark. All three. (§17.7) |

**MCP tooling — these are not game bugs and each cost a session**

| Where | Trap |
|---|---|
| `add_node` | The `properties` dict **silently drops `script`**. The node arrives scriptless with no error, and every property depending on it is dropped too. `attach_script` separately, then `update_property`. (§0.1.5) |
| `add_scene_instance`, `save_scene` | They operate on the MCP's **currently open editor scene**, not the last one `create_scene` made. `open_scene` the target and verify `get_scene_tree`'s **content** — its `scene_path` label can be stale — before saving. This overwrote `battle_world.tscn` once. (§0.1.5) |
| `CLAUDE.md`'s tool list | It lists tools this build does not expose, `delete_node` among them. Verify by name lookup before depending on one. (§0.1.4) |
| `update_property` | Cannot assign an existing `.tres`/`.tscn` to a node property — it writes `null`. Use `@export var x := preload(...)` in the node's script instead. (§0.1.1) |

**Blender pipeline**

| Where | Trap |
|---|---|
| any rig | **Never use `parent_type = 'BONE'` for an attachment intended to survive a glTF round-trip.** Blender anchors such a child at the parent bone's **tail** for viewport display via an implicit `Translation(0, bone.length, 0)` folded in outside `matrix_parent_inverse` — and the glTF exporter does **not** reproduce that offset, so Blender and Godot actively disagree and no correction from either side reconciles them. **Skin it instead** (one vertex group per bone, full weight, plus an Armature modifier), even for a single-bone, zero-deform attachment. (§23.2) |
| M8 swaps | An imported `.glb` arrives with `StandardMaterial3D`s. Reassign the cel material **and** its outline `next_pass` on every surface, or the character reads as untextured plastic — or as a silhouette, if the depth mode is wrong. |
| `.blend` gate renders | Restore any render settings borrowed for a gate render. |

**Testing**

| Where | Trap |
|---|---|
| tests | An assertion on a random quantity must state the statistic and the sample size. **A test that can fail on a fair run is a defect in the test.** (§19.3) |

### 21.5 Substitution log — append below this line

*(Append any API substitution or forced deviation here, with the file and the reason. Do not rewrite entries above. Substitutions resolved into §21.3 as C1–C10 are not repeated.)*

---

## 22. Deferred — build the seam, not the feature

- **Equipping weapons on heroes.** `Item.equipped` exists; `sellable_items()` filters on it; no UI.
- **Potions and relics.** `Item.Kind` includes them; `Itemizer` never produces them.
- **Diminishing returns on inventory bonuses.** §13.5's aggregate is a straight sum, correct at ≤5 items. A build where the inventory grows large needs a curve.
- **Additional slot machines.** The demo ships one.
- **A deeper upgrade tree.** The seam is `Upgrades.DEFS` — an entry and a button is all a fourth upgrade needs.
- **Upgrades that change the odds.** Nothing may touch `SLOT_STRIP` or the win rule. A future "more often" beyond Quick Reels needs a second payline or a second machine, and a fresh proof.
- **Branching maps and a visible level map.** `GameState.build_level()` is the single function a generator replaces.
- **Multiple levels.** One level, six encounters.
- **Re-tuned cooldowns.** §5.2 documents real cycle times that differ from the nominal `attack_cooldown`; not retuned without playtest data.
- **Designed (non-random) rarity and modifier multipliers** — see the TODO in §13.2.
- **Elemental resistances.** The elemental *modifiers* are not cosmetic — their rolls sum into `dmg_flat` and do real damage (§13.5). What is cosmetic is the `element` **key**: it only chooses the damage-number colour and the §17.6 chip. Resistances are the obvious next step and the reason the three elements are accumulated separately instead of being summed into one number.
- **Per-tile parallax variety.** §7.5's R1 uses one tile mesh per layer, because variety and seamlessness are in tension and seamlessness won. The right answer is a longer period, not more tiles — and layers 1–3 **take** that, which is free because they are generated (§7.4.1). What remains deferred is the same treatment for layers 4–5, which would triple the Blender modelling for the two layers whose speed means they need it least. If a later build slows the foreground down, revisit this first.
- **Audio.** No sound in the demo. Do not add an `AudioStreamPlayer` anywhere.
- **Saving.** Nothing persists across application restarts, including upgrades.

---

## 23. Blender asset pipeline (M8)

**Work the sub-milestones in §20's order and gate each one.**

### 23.1 Rules

- All modelling happens in `C:\Projects\Godot\Sir Fish\blender\Sir Fish.blend` via the Blender MCP tools (`execute_blender_code`, `get_objects_summary`, `render_viewport_to_path`, `get_screenshot_of_window_as_image`, `render_thumbnail_to_path`).
- **Current file state:** the default `Cube` is deleted; `Camera` and `Light` remain in `Collection`; the collections `Heroes`, `Enemies`, `Props`, `Environment` and `Console` exist. `Console` contains the finished, rigged Sir Fish (13 meshes + a three-bone armature, seven actions).
- Everything is **low-poly, hard-surface, flat-shaded**, built for cel shading: chunky silhouettes, no bevel-heavy detail, no normal maps, no textures — **vertex colours or per-material flat colours only**, using §6.1's palette exactly.
- The camera is a fixed side view, so do not model detail never visible from −Z — but **keep both sides symmetric**, because heroes and enemies face opposite directions and share one clip set (§9.0).
- Character height: **1.8 Blender units at scale 1.0**, feet at the origin, facing **+X**.
- **Restore any render settings you borrow for a gate render.**

### 23.2 Rigging and animation

- One armature per character. Bone names for the six combatants, exactly:
  `Root, Hips, Spine, Chest, Head, Shoulder.L, Arm.L, Hand.L, Shoulder.R, Arm.R, Hand.R, Thigh.L, Shin.L, Foot.L, Thigh.R, Shin.R, Foot.R`
  Weapons parent to `Hand.R` (main) and `Hand.L` (off).
- **Author every combatant clip in the screen plane**, matching §9.0. A limb swing that reads correctly in Godot swings about the axis perpendicular to the camera; if it swings toward the lens in Blender it will be invisible in game. **Check each action from a −Z orthographic view in Blender before exporting** — that view is what the player sees. This check is not optional and it is why M8b gates per character.
- §9.0's delta convention applies here too: a translation written `→ +0.14` is relative to the rest pose, not an absolute bone location.
- Author actions named exactly `idle`, `run`, `attack`, `special`, `hurt`, `die`, at the lengths in §5.2 and §8.3, **only for the names `CombatantStats.required_anims()` requires for that character**. Do not author `run` or `special` for enemies.
- Shadow monster: no armature. Animate via shape keys and object transforms, exporting actions under the same names.
- Orc barbarian and orc warlord share one mesh, one armature and one action set.

> **Attachment trap — this cost three fix attempts on M8a and will recur on every helmet, pauldron and weapon in M8b/M8c.**
>
> **Never use `parent_type = 'BONE'` for a rigid attachment intended to survive a glTF round-trip.** Blender silently anchors such a child at the parent bone's **tail** for viewport display, via an automatic `Translation(0, bone.length, 0)` folded into the evaluated transform *outside* `matrix_parent_inverse` — so no adjustment to the inverse matrix can cancel it. Worse, the glTF exporter does **not** reproduce that viewport-only offset: it exports the child's raw `matrix_local`, so the Blender viewport and the Godot import actively disagree and neither is simply "the modelled position".
>
> Two plausible corrections both fail. Correcting `matrix_parent_inverse` fixes Blender's viewport and leaves Godot unchanged. Shifting the object's own `.location` by the negative tail-offset changes nothing in Godot either — the baked offset is a fixed function of the *bone*, not of the child's transform.
>
> **The fix is to skin it:** make every mesh a real vertex-group-skinned child of the armature (one group per bone, full weight, plus an Armature modifier). That is the standard, well-supported glTF/Godot path and it is immune to the head/tail ambiguity because skin binding is explicit data rather than an implicit parenting convention. It applies **even for a single-bone, zero-deform attachment**.
>
> Symptom to recognise: a part rendering roughly one bone-length away from where it was modelled.

### 23.3 Export

- Export each character as glTF 2.0 (`.glb`) to `res://assets/meshes/`, `+Y up`, animations included, modifiers applied.
- In Godot, configure each import to generate a scene with an `AnimationPlayer`, then **swap the placeholder `Rig` node in each character scene for the imported model** and reassign the cel + outline materials (§6.3). `combatant.gd`, `battle_director.gd`, and every animation *name* stay unchanged. `model_scale` still lands on `Rig.scale` (§8.2), so the swap needs no scale rework.
- **Material reassignment is the step that gets skipped.** See §21.4.
- After each swap, re-run that sub-milestone's gate before touching the next character.
- **Before any `save_scene` during a swap, confirm the open scene is the one you think it is** (§0.1.5).

### 23.4 Environment meshes — layers 4 and 5 only

**Only parallax layers 4 (`LayerGround`) and 5 (`LayerBrush`) are modelled in Blender.** Layers 1–3 are generated procedurally in Godot per §7.5 and were finished in M7.5.

For each of the two layers:

- **Exactly 12.0 units wide** (`Tuning.PARALLAX_TILE_WIDTH_MODEL`), authored **centred on the origin** so the tile spans local `x ∈ [−6, +6]`, matching §7.4's wrap arithmetic. Verify numerically from the imported mesh AABB in the M8d gate, not by eye.
- **Seamless at its edges.** The admissible constructions are §7.5.2's R2 and R3: either the boundary geometry matches exactly (a ground slab's edge vertices at identical Y and Z), or every feature lies wholly inside `[−6, +6]` including its own half-width. **Prefer the second for scatter** — a rock crossing the seam is the single most likely defect in this milestone.
- **One tile mesh per layer, instanced three times.** Do not model three variants; R1 applies here exactly as it does to the generated layers.

| Layer | Content |
|---|---|
| 4 `LayerGround` (Z 0, speed 1.00) | A ground slab in `C_GROUND` with darker stripe banding, plus scattered rocks in `C_ROCK` and grass tufts in `C_NEAR_TREES`. Sits at character depth, so it takes the full cel + outline treatment and casts/receives shadow normally. The slab's own edges are flat and match trivially; only the scatter needs the margin rule. |
| 5 `LayerBrush` (Z +3, speed 1.35) | Bush and grass-clump meshes in `C_BRUSH`, rendering **in front** of the characters. Full cel + outline treatment — this layer must read as the same world, not as an overlay. |

**Why these two stay at 12.0 while layers 1–3 go to 36.0.** §7.4.1 has the argument: a repeat is only visible if a feature dwells long enough on screen to be remembered. At speeds 1.00 and 1.35 these tiles repeat every 3.0 s and 2.2 s, but any given bush crosses the frame in under 2.5 s and reads as motion, not as a landmark. Tripling the width of a *generated* layer is free; tripling a *modelled* one triples the modelling.

**On layer 5 and the health bars.** Brush silhouette height is an art call, not a technical constraint: the bars live in `BattleOverlay`, a 2D `Control` composited **over** the whole SubViewport (§3.3), so 3D foreground geometry can never occlude them. The real consideration is that a tall foreground bush hides the **characters**, and a bar floating over foliage with no visible owner beneath it is the legibility failure. Keep the brush below roughly `y = 1.2` — under a 1.8-unit character's shoulder — so a hero is always readable behind it.

### 23.5 Sir Fish *(built — recorded for reference and for any future re-model)*

In the `Console` collection, at a scale where the whole fish is roughly **0.34 units long**, so he reads at 164 px through §17.7's orthographic `size 1.4` camera.

**Mesh:** 13 low-poly flat-shaded objects, per-material flat palette colours, no textures, facing +X, symmetric across Y. The 164 px read gate passed — rendered at 164 × 164 with `render_thumbnail_to_path` he reads as an armoured fish, with a deep-bellied blue body, a barbute helm with a gold circlet and crest, a visor slit and an eye. It took three iterations, which is exactly why that gate exists.

#### R6 — the armature is three bones: `Root`, `Tail`, `Helm`

Two instructions were in tension: a "two-bone armature, `Root` and `Tail`, plus optional `Fin.L`/`Fin.R`", and *"`slump` must end with the helm on the gravel — animate it as a separate object with its own action, or key its parent constraint off at the end of the clip."* The helm assembly is six meshes, none of them named in the two-bone list, and a detachment needs **some** attachment point to detach from.

**Resolution: the third bone is correct and is now normative.**

- `Helm` is a child of `Root`. It carries **no keys** in the other six clips, so it silently inherits `Root`'s motion — i.e. "attached" — and carries a divergent pose only in `slump`'s back half.
- This makes the detach an ordinary pose-bone track **inside the same `slump` Action** as `Root` and `Tail`, rather than a second Action datablock on a separate object, which was tried first and abandoned.
- "Two-bone" was a sketch of minimum complexity with **no downstream dependency** — unlike the combatants' 17 bone names, which are load-bearing because six characters share one clip set. Nothing in the codebase reads the fish's bone count.
- The alternative — accepting a less literal detach, e.g. a colour/alpha cue only — would have traded a designed beat (§17.7's `slump`) for adherence to a number that buys nothing.

`Fin.L` / `Fin.R` were optional and were not built. That is fine.

#### R8 — axis convention

Sir Fish's seven clips are authored in **Blender's own axes** (Z-up, matching the modelled rest orientation) and verified by import plus live capture. **They are not a port of any earlier procedural keyframes and must not be re-authored into §9.0's convention** — see §9.0.1. §9.0 exists because six combatants share one camera and one clip set; Sir Fish shares neither.

#### R7 — the tank is procedural

See §17.7. `sir_fish_tank.gd` builds the bowl, gold base ring, gravel bed and plaque, and **that is where they stay.** The plaque's text is a `Label3D` so no font asset is ever baked into a mesh.

**Gate for any future re-model:** render at 164 × 164 with `render_thumbnail_to_path` and confirm he reads as an armoured fish at that size, **before rigging anything.**

---

## 24. Outstanding verification backlog

Eight items are owed. **None is a blocker for M8b** — every one is a screenshot or a command against behaviour that is already implemented and code-reviewed, not an unresolved design question. All eight must be closed before M8e signs off, and the milestone that most naturally closes each is named.

They are listed because "implemented and code-reviewed" is not the same as "seen working", and the M7.6 pass proved the difference: the corpse-cleanup deadlock (§10.4.1) was found **only** by driving it live, and it would have passed any amount of reading.

| # | Item | Source | What closes it | Natural home |
|---|---|---|---|---|
| 1 | **Warlord framing** — a warlord encounter screenshotted, confirming no combatant or bar is clipped at either viewport edge | M7.6 F3 | Reach or force encounter 5. The arithmetic is re-derived in §7.2.1 and holds with 2.99 units of margin; this is the picture, not the proof. | M8c |
| 2 | **`"LIGHTNING x3"` clip check** — the longest banner string at font 72 inside 1080 px | M7.6 D3 | `Debug slot 0 0 0` during combat, screenshot the banner. If it clips, drop to 64 and record it (§16.4). | M8e, or any session touching the slot |
| 3 | **Dead-hero concurrent slide** — `capture_frames` across the transition after a hero dies, showing the corpse sliding left **while** the background already scrolls | M7.6 D5 | `Debug kill <hero>` in a non-final encounter, then capture the exit. | M8b (hero deaths are easy to force there) |
| 4 | **Chunk flight measurement** — confirm chunks stay near their bar at the halved displacement | M7.6 D6 | `capture_frames` a hit and measure, rather than eyeball. `test_damage_chunk` covers the spawn rect only, not the flight. | M8b |
| 5 | **`cheer` and `smug` captured live** | M8a | `Debug slot 1 1 1` (pair → `cheer`) and `0 0 0` (triple → `smug`) during combat, or buy an upgrade for `smug`. Both are wired through the same `play()`/priority machinery already proven live by `alarm` and `grieve`. | M8e |
| 6 | **The 164 px read gate, pixel-inspected in isolation** | M8a | Render `SirFishTank` alone at native 164×164 — a dedicated debug scene or `render_thumbnail_to_path`-style framing. Full-board screenshots do not isolate it. | M8e |
| 7 | **`slump`'s helm-on-gravel placement** verified against the live tank | M8a | The helm bone's final pose was checked geometrically in Blender, but the gravel is built by `sir_fish_tank.gd` and the two only meet at runtime. Needs a close capture of a `DEFEATED` screen. | M8e |
| ~~8~~ | ~~**Delete `res://resources/levels/`**~~ | v3 E5 | **CLOSED 2026-08-14.** Deleted and verified; `resources/` holds only `stats/`. It had been shipping into builds — §12.1. | — |

**Seven items remain open. Item 8 is closed.**

**Project-root housekeeping — done, and the outcome recorded.** `_to_delete/_sirfish_payload.tgz` and `project.godot.pre_sirfish_backup` were stray artefacts flagged for an owner decision; both have since been removed by the owner. The root is clean. No further deletion is authorised by this document beyond §12.1's, which is now spent.

**One residue is expected and must not be chased.** `.godot/exported/…-demo_level.res` may persist as a stale export-cache entry. `.godot/` is gitignored and engine-regenerated, the entry is orphaned because its source no longer exists, and the next export rebuilds the cache without it. Likewise `builds/web/index.pck` still contains the resource because it was exported before the deletion; it is replaced on the next export. **Neither is a defect and neither needs hand-editing.**

---

## 25. Open questions

**None.** Every entry in `QUESTIONS.md` (Q0–Q24), `QUESTIONS-v2.md` (V0–V15), `QUESTIONS-v3.md`, `QUESTIONS-v3.5.md` and `QUESTIONS-v3-m8a.md` is answered — the last two by §0.2's R1–R9. All five files are **closed**.

Open a fresh `QUESTIONS-v4.md` rather than appending to any of them, and follow the same discipline: **implement as specified, record every deviation with the file and the reasoning, change nothing silently, and raise a BLOCKER rather than guessing** when a design decision is genuinely missing.

### 25.1 Standing habits

Six, each earned by a specific failure:

1. **Verify a tool exists before depending on it** (§0.1.4). Two findings in one pass were caused by trusting `CLAUDE.md`'s tool list.
2. **Say plainly what is not done.** A report of "M8 started, far from complete" with a work table is correct behaviour; half-rigged characters left in the file are not. §20's sub-milestones exist to make honesty cheap, and §24 exists so unverified work stays visible instead of dissolving into a gate log's closing paragraph.
3. **When the spec and the screen disagree, believe the screen** — and then fix the spec. The black-silhouette bug (§6.2) was found by taking a screenshot, not by reading.
4. **When a spec makes a claim about existing code, open the file.** Doing this found three defects in one document's own first draft. A specification that describes code it has not read is a second source of truth, which is the thing §12.1 deletes a `.tres` to avoid.
5. **When you fix an instance of a bad pattern, grep for the pattern.** The `stats.id` rule (§4.1) caught three violations across three passes, each time because someone fixed the instance they were shown and not its neighbour.
6. **Code review does not substitute for driving it.** The corpse-cleanup deadlock (§10.4.1) was a five-line coroutine that read correctly, deadlocked the entire run, and logged nothing. It was found by killing two enemies and watching the state machine sit still. Anything with an `await` in it gets exercised, not just read.

---

*End of specification.*
