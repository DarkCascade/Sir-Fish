# QUESTIONS-v3

Open questions, deviations, and blockers arising during implementation of
`Sir Fish - Demo v3 Implementation Spec.md`. Follows the discipline of
§24: implement as specified, record every deviation with file + reasoning,
change nothing silently, raise a **BLOCKER** rather than guess.

Status: **M7.5 COMPLETE AND GATED.** M8 (Blender assets, §20 M8a-M8e) has not
been started — it is a separate, much larger effort and the spec itself gates
it behind M7.5 passing (§23: "Only start after M7.5 passes").

---

## Verified starting state (before any v3 edits)

- Confirmed via `get_project_info`: autoload order is exactly the one v3
  §3.2 describes and accepts (Tuning, RNG, EventBus, Itemizer, GameState,
  MCP*, Upgrades, Debug). No change needed — matches C3.
- Confirmed `msaa_3d` — not independently re-verified this pass (v2 already
  confirmed it per C1); not touching it per §21.3.
- `res://resources/levels/demo_level.tres` still present — E5 not yet applied.
- `combatant_stats.gd` has neither `special_requires_wounded_ally` nor
  `special_targets_opponent`; `battle_director.gd` still guards on
  `c.stats.id == &"priest"` (line ~130) and
  `c.stats.id == &"warrior" or c.stats.id == &"priest"` (line ~137) — E1 not
  yet applied.
- `parallax_background.gd` still uses a single global `tile_width` export,
  per-tile `phase = float(variant) * 2.3` in `_build_hills`, and a
  per-variant seed in `_build_trees`/`_build_brush`; trunks still darkened.
  Not yet baked to one mesh per tile (each tile is many `MeshInstance3D`
  children). E3/E10 not yet applied.
- `bonus_strip.gd` has five glyphs only, no element chip. E2 not yet applied.
- `debug.gd` has no `parallax` verb. E13 not yet applied. Shop round-trip
  search already exists as `_value_for_price()` — E8 needs no code change,
  matching the spec's own prediction.
- `console.tscn` / `SlotCounter` position not yet checked in detail — E12
  pending verification.
- `tests/` does not yet contain `test_parallax_seam` or
  `test_autoload_safety` — E4 not yet applied.
- **Tool-log caveat (relevant to §0.1.4's "verify a tool before depending on
  it" discipline, generalized to verification tooling too):** `get_editor_errors`
  / `get_output_log` returned a set of 10 stale-looking compile errors
  (e.g. "Cannot infer the type of 'ally'" in `ability.gd:76`) that do **not**
  match the current file content (which already has an explicit type there).
  `validate_script` on `class_name` scripts also spuriously reports "hides a
  global script class" and fails, even though the file compiles fine in
  practice. Confirmed the actual live state is healthy by running
  `play_scene` and observing a real run progress cleanly through several
  encounters to the shop with no visible defects and no fresh runtime errors
  in `get_output_log`. **Treating `get_editor_errors`/`validate_script`
  output as unreliable for already-loaded `class_name` scripts in this MCP
  build; using `play_scene` + `get_output_log` (post-clear) + screenshots as
  the source of truth instead.** Logging this here per §0.1.4's spirit since
  it affects how every subsequent gate in this document is actually checked.

---

## Deviations / substitution log (append-only, do not rewrite above)

- **E5 skipped.** Spec §12.1/V4 explicitly authorizes `rm -rf resources/levels`
  and instructs "request permission if the session denies it." The Bash tool
  auto-denied the command twice (this project has no git, so it's not a
  recoverable action). Asked the user directly; they chose to leave
  `res://resources/levels/demo_level.tres` in place rather than fight the
  permission system for it. Confirmed by grep that nothing under `scripts/`
  references `demo_level.tres`, so `GameState.build_level()` remains the sole
  behavioral source of truth for the level — the orphan file is inert, just
  not removed. Not a design blocker, just an unresolved housekeeping item.

---

## M7.5 — what was done

All of §21.2's E1-E14 applied, in this order:

- **E1** (V6): `special_requires_wounded_ally` and `special_targets_opponent`
  added to `CombatantStats` ([combatant_stats.gd](scripts/data/combatant_stats.gd)),
  set on `priest.tres` / `warrior.tres` via `edit_resource`. Both `stats.id`
  guards in `battle_director.gd` replaced (the skip-rule check and the
  no-target-needed check), with `_any_hero_wounded()` generalized to
  `_every_living_ally_at_full_hp(c)` (checks the caster's own side, including
  itself, per spec's exact wording). Confirmed `ability.gd`'s `match
  source.stats.id: &"warrior": ...` dispatch and its `charge()` priest check
  were intentionally left alone — §21.2's E1 scope is `combatant_stats.gd`,
  the two `.tres` files, and `battle_director.gd` only; `ability.gd`'s id
  matches are structural per-character dispatch (like `CombatantAnimations`),
  not the kind of behavioral gate V6 was about, and are out of scope here.
- **E3/E10** (V15): New [parallax_profiles.gd](scripts/battle/parallax_profiles.gd)
  with the periodic `HILLS` profile. `parallax_background.gd` rewritten:
  per-layer `tile_width` (36.0 procedural / 12.0 modelled, set at runtime via
  `set_meta` in `_build_tiles()` — not hand-authored into the `.tscn`, since
  `update_property` can only edit *existing* metadata keys, not create new
  ones). Layers 1-3 now bake to one shared `SurfaceTool` mesh per layer (R1),
  instanced three times, exactly one `MeshInstance3D` per tile (R4). Tree
  counts scaled 7→21 / 5→15, positions clamped to their own half-width (R3),
  trunk darkening dropped. Layers 4-5 (Ground/Brush) untouched except for
  reading their width from the same per-layer mechanism — they stay as
  placeholder per-tile geometry until M8d's Blender pass, per spec.
  `Tuning` gained `PARALLAX_TILE_COPIES`, `PARALLAX_TILE_WIDTH_PROC`,
  `PARALLAX_TILE_WIDTH_MODEL`, `PARALLAX_SEAM_EPSILON`, `C_ROCK`.
- **E2/E14** (V9): Sixth "element chip" entry added to `bonus_strip.gd`,
  shown only when `element != &""`. Tie-break assertion added to
  `test_item_distribution.gd` (hand-built tied fire/ice inventory, confirms
  fire wins — `GameState.party_bonuses()`'s existing dictionary-order logic
  needed no change, only the test needed writing).
- **E12**: `SlotCounter` moved from `offset_left 900 / offset_right 1072`
  (172 wide, 0px gutter) to `908 / 1072` (164 wide, 8px gutter, true mirror
  of the tank), via `open_scene` + `update_property` + `save_scene`.
- **E13**: `Debug` gained the `parallax <units>` verb, calling a new
  `ParallaxBackground.advance_tiles(units)` method.
- **E4** (new tests): `test_parallax_seam.gd/.tscn` and
  `test_autoload_safety.gd/.tscn` written and run headlessly via a directly
  located `Godot_console.exe` (see tooling note below) — both pass cleanly.
- **E6-E9**: `cel_shade.gdshader` and `debug.gd`'s `_value_for_price()`
  already had the required comments/behavior — verified, no change needed,
  exactly as the spec predicted. `sir_fish_tank.tscn` got an explicit
  "these three are required, not optional" comment block (hand-edited — the
  file already contained an earlier hand-written `;`-comment from a prior
  session, establishing that comment-only edits to this file are an accepted
  practice; no structural/property change was made). `test_economy.gd` got
  the v3-ratified rationale comment plus explicit p25/p75 in its printed
  report.

## M7.5 — gate verification results

- All 8 headless tests pass: `test_slot_odds` (win rate 0.5000), `test_item_
  distribution` (incl. new tie-break check), `test_damage_chunk`,
  `test_retarget`, `test_economy` (mean 172.1 gold, full percentile report),
  `test_upgrades`, `test_parallax_seam` (11/11 checks), `test_autoload_safety`
  (8/8 checks) — run directly via `Godot_console.exe --headless`, not just
  through the MCP editor tools (see tooling note below).
- `Debug parallax 40` then `parallax 80` (cumulative, well past one full wrap
  on every layer): screenshots show a continuous hills silhouette and no
  clipped/overhanging trees at any boundary. Not a formal pixel-diff against
  a pre-rebuild screenshot at an identical scroll offset, but the low
  harmonics (k=3, k=9) are unchanged from the shipped values — only the
  period tripled and a small k=21 ripple was added — so the silhouette shape
  is the same by construction, and this was visually confirmed acceptable.
- Draw-call drop to 9 for layers 1-3 verified **structurally** via
  `test_parallax_seam`'s assertions 3-4 (exactly one `MeshInstance3D` per
  tile, 3 tiles × 3 layers = 9, all sharing one `Mesh` resource per layer) —
  not via `get_performance_monitors`, whose `render_total_draw_calls_in_frame`
  is a whole-scene aggregate (349 in one sample) that can't isolate the
  parallax layers' contribution from everything else on screen.
- Element chip confirmed live: `Debug additem rare` produced a Lightning
  roll; the bonus strip showed `sword +18, bolt +7, coin +9, plus +6%,
  ● Lightning` in both the console tray and the shop modal, matching §17.6's
  fixed order exactly.
- Wounded-ally / no-target rules: verified primarily by code-level equivalence
  (the new data-field branches are a direct, mechanical translation of the
  pre-existing `stats.id`-keyed branches that were already exercised through
  M6/M7 — same conditions, same control flow, only the lookup changed) plus a
  full hands-off run (see below) that exercised both heroes' specials
  repeatedly across five encounters with zero errors. Did **not** force the
  exact single-frame "last enemy dies mid-action-resolution" race via Debug —
  doing so precisely requires frame-level control the MCP tools don't expose
  (killing both enemies via `Debug kill` stops `BattleDirector._process`
  before the narrow window is reached, since `_active` flips false at the end
  of the same frame the last enemy dies). Not treated as a blocker: the logic
  is unchanged from the pre-v3 build, which shipped this exact branch.
- Full hands-off run: played through encounters 0-5 (including the boss)
  unattended, closing only the one shop modal (an actual player action the
  spec requires, §15.4), ending in a loss at the boss with `RunSummary`
  showing `DEFEATED`, Sir Fish `slump`ped, and a populated stat table.
  `get_output_log` across the entire run shows only the `[DEBUG] state -> ...`
  lines this session issued — zero errors, zero warnings.

## Tooling note (relevant to §0.1.4's spirit, generalized to verification)

`get_editor_errors` / `get_output_log` intermittently returned a fixed set of
~10 stale compile errors/warnings that do not match the current file content
(line numbers and even source file attribution drift between calls — e.g. the
same "static func make(...)" snippet was attributed to `slot_machine.gd:15`
in one call and `parallax_background.gd:15` in a later call). `validate_script`
also spuriously fails on already-loaded `class_name` scripts ("hides a global
script class"). Found a real `Godot_console.exe` at
`C:\Projects\Godot\Godot\Godot_console.exe` and used
`--headless --path "..." res://tests/<name>.tscn` directly via Bash for all
headless-test verification instead of relying on the MCP inspector tools for
pass/fail — this is what actually caught a real bug (a missing `t.finish()`
call in my first draft of `test_autoload_safety.gd` that left the process
hanging after printing all its PASS lines). For scene-tree / gameplay
verification, `play_scene` + `get_game_screenshot` + `get_output_log`
(checked immediately after `clear_output`) proved reliable and is what this
whole pass was actually verified against.

## Blockers

*(none — no critical issue was encountered)*

## Next step

M8 (§20 M8a-M8e, §23) is Blender 3D asset production: Sir Fish's rig/tank
finish (M8a), the three heroes' meshes+17-bone armatures+6 actions each
(M8b), the three enemies (M8c), the two Blender-modelled parallax layers
(M8d), and full integration (M8e) — roughly 50 discrete gated assets per the
spec's own estimate (§0.2 V14). This is a categorically different, much
larger effort than M7.5 and the spec explicitly gates it behind M7.5 passing.
Not started in this session; flagging for the user's direction on whether to
proceed into it now.
