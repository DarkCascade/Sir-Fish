# Prompt — Replace the warrior's Defend special with Cleave

**Context:** backlog P7 (`design documents/Sir Fish - Backlog.md` §7), decision 7.4.
**Branch at time of writing:** `backlog-p3`, head `5449e21`.
**Prerequisite already built:** `BattleDirector.invoke_hero_special()` (commit `e7f8298`)
and the invoker button (`5449e21`). This task supplies the ability that button fires.

---

## Goal

The warrior's special becomes **Cleave: hit every living enemy**. It currently is
**Defend**, a self-buff granting 50% damage reduction for 4s.

The ranger keeps bomb arrow (already correct). The mage **keeps her party heal** — do
not touch it. Only two of the three specials are hit-all, deliberately (decision 7.4).

---

## What exists now

### The ability being replaced

`resources/abilities/warrior_special.tres` is a `SelfBuffAbility`:

```
script = self_buff_ability.gd
special_targets_opponent = false
flash_color = Color(0.85098, 0.658824, 0.145098, 1)   # C_DEFEND gold
damage_reduction = 0.5
duration = 4.0
```

`SelfBuffAbility.resolve()` calls `source.apply_defend(reduction, duration)` and
`BattleVfx.defend_icon(source, duration)`.

### The four AbilityDef subclasses that exist

`scripts/battle/abilities/` — `melee_strike_ability.gd`, `projectile_ability.gd`,
`self_buff_ability.gd`, `heal_ally_ability.gd`. **None of them hits all enemies.** You
must add one.

### The AbilityDef contract

`scripts/battle/ability_def.gd`. A `Resource`, shared and cached across every spawn, so
it must **never hold per-cast state**. Exports it already provides, which your new class
inherits and must not redeclare:

| Export | Meaning for Cleave |
|---|---|
| `special_requires_wounded_ally` | leave **false** |
| `special_targets_opponent` | leave **true** (Cleave needs a living enemy) |
| `telegraphs_primary` | irrelevant, primary-only |
| `flash_color` | the colour flashed at t=0 of the `special` clip |

Override `func resolve(source: Combatant, ability: Ability) -> void`.

### How the damage should be applied

`SlotMachine._hit_all()` already does board-driven AoE, but it lives on the slot machine
and is not reusable here. For the ability, iterate `ability.director.living_enemies()`
and deal damage per target.

Two damage sources are available and you must pick deliberately:

- `ability.fixed_damage` — set when the caller supplied a total. **For an invoked
  special this is -1**, because `Ability.make(c, true, target, self)` does not set it
  (only `Ability.make_slot_strike()` does). So Cleave must roll its own.
- `source.compute_damage(school)` — **this returns 1 for every hero.** All hero
  `weapon_power` / `magic_power` / `*_per_level` are 0 in `resources/stats/*.tres`;
  item Power drives damage now. Using it unmodified gives a 1-damage cleave.

**Therefore:** derive Cleave's damage from the warrior's equipped weapon Power, the way
the slot board does. `GameState.hero_weapon_power(&"warrior")` returns
`equipped_item(...).power()`. A sensible first cut, to be tuned:

```
base = GameState.hero_weapon_power(source.stats.id)
per_target = maxi(1, int(round(base * Tuning.WARRIOR_CLEAVE_MULT)))
```

Add `WARRIOR_CLEAVE_MULT` to `scripts/autoload/tuning.gd` near
`RANGER_BOMB_AOE_MULT := 0.75` (§5.3 Ability tuning), and document the reasoning in its
comment. Apply `Tuning.DAMAGE_VARIANCE` per target as `_strike()` does, and emit
`EventBus.combatant_attacked` before `victim.take_damage(amount, source)` so floating
numbers and hit reactions fire — copy the shape of `Ability.strike()`.

Stagger per-target resolution by `Tuning.AOE_STAGGER` if you make `resolve()` async;
check whether the call site awaits before relying on it.

### Animation

`resources/rig_profiles/warrior_rig.tres` currently has:

```
&"special": {"clip": "Block", "length": 0.55, "loop": false, "impact": 0.25, "cast": 0.0},
```

"Block" is a defensive animation and wrong for a sweep. **Clips actually present on
`assets/meshes/knight.glb`** (76 total) that suit a cleave:

- `1H_Melee_Attack_Slice_Horizontal` — a horizontal sweep, matches the warrior's 1H sword. **Recommended.**
- `1H_Melee_Attack_Slice_Diagonal`
- `2H_Melee_Attack_Spinning` / `2H_Melee_Attack_Spin` — a full spin, reads strongly as hit-all, but the warrior holds a 1H sword.

**Changing the clip requires two coordinated edits or the suite fails:**

1. `tools/strip_unused_animations.gd` — the `KEEP` dict, currently
   `"knight": ["Idle", "Running_A", "1H_Melee_Attack_Chop", "Block", "Hit_A", "Death_A"]`.
   This is a post-import script that **deletes every clip not in the list**, so a clip
   the RigProfile names but KEEP omits is gone at runtime. Replace `"Block"` with your
   chosen clip (or add it and keep Block if anything still needs it — nothing does; see
   below).
2. `resources/rig_profiles/warrior_rig.tres` — the `special` entry's `clip`, `length`
   and `impact`. Measure the real clip length rather than guessing; `impact` is when the
   damage lands within the clip.

`tests/test_animation_clips.gd` walks each RigProfile and asserts every clip it names
exists in the **imported** scene, and that the strip actually ran
(`MAX_CLIPS_AFTER_STRIP = 12`). It will catch a mismatch between the two edits above.

**After editing a `.glb.import` dependency or the strip script, the model must be
reimported.** See the "Reimport" warning at the bottom — it has a trap.

### What removing Defend leaves orphaned

`warrior_special.tres` is the **only** user of `SelfBuffAbility` (checked:
`grep -rln self_buff_ability resources/`). After this change, these become unused by any
shipped content:

- `scripts/battle/abilities/self_buff_ability.gd`
- `Tuning.WARRIOR_DEFEND_REDUCTION` (0.50) and `WARRIOR_DEFEND_DURATION` (4.0)
- `Combatant.apply_defend()`, `Combatant.is_defending()`, `Combatant.damage_reduction`
- `BattleVfx.defend_icon()`

**Do not delete any of it.** `damage_reduction` is still read by
`Combatant.take_damage()` (the percent cut applied before flat armor), and BLOCK icons
plus a future ability may want the machinery back. Leave it in place and unused; say so
in the commit message so it does not read as dead code nobody noticed.

The party loses its only damage-reduction special. That is an accepted cost of decision
7.4 and is already recorded in the backlog — do not re-litigate it, but do mention in
the commit that BLOCK icons (`armor_block`, `BASE_ARMOR`) remain the party's mitigation.

---

## Acceptance

1. **New class** `scripts/battle/abilities/cleave_ability.gd`, `class_name CleaveAbility`,
   extending `AbilityDef`, overriding `resolve()` to damage every living enemy.
2. **`resources/abilities/warrior_special.tres` rewritten** to that script, keeping
   `special_targets_opponent = true` and a `flash_color` that suits a sweep (the
   warrior's chip gold `Color(0.8509804, 0.65882355, 0.14509805, 1)` is consistent).
3. **`warrior_rig.tres`'s `special` clip** swapped, with `KEEP` updated to match.
4. **`Tuning.WARRIOR_CLEAVE_MULT`** added and commented.
5. **Tests.** Extend `tests/test_specials.gd` (it already stands up a real
   `BattleDirector` in `_check_invoke_guards` — reuse that pattern):
   - invoking the warrior's special damages **every** living enemy, not just one;
   - it scales off equipped weapon Power, not `compute_damage()` — put two enemies up,
     give the warrior a known weapon, assert per-target damage is well above 1 (this is
     the regression that bit `ProjectileAbility`, see `66298b9`);
   - the meter is spent and the warrior enters `ATTACKING`;
   - `_check_authored_specials()` already asserts every hero has a special and a
     `special` clip — extend it to assert the warrior's is now a `CleaveAbility`.
6. **Full suite green:** `python tools/run_tests.py` — 32 suites at time of writing.
   `test_animation_clips`, `test_ability_resolve`, `test_executor` and `test_specials`
   are the ones this can break.
7. **Look at it.** Headless tests cannot show an animation. Render it: the pattern is
   `scratch/invoker_preview.gd` (gitignored) — a scene that instantiates combatants,
   fires the ability, and saves a PNG via
   `get_viewport().get_texture().get_image().save_png(...)` after two
   `await RenderingServer.frame_post_draw`. Confirm the sweep plays and every enemy
   reacts.

---

## Traps

- **`godot --headless --path . --import` strips the three MCP addon autoloads from
  `project.godot`** (`MCPScreenshot`, `MCPInputService`, `MCPGameInspector`). This is
  real and was hit twice in the session that wrote this. Run the import, then
  immediately `git checkout project.godot`. Never hand-edit `project.godot` otherwise.
- **A new `class_name` is not visible until the project is reimported**, so a test
  referencing `CleaveAbility` will fail to parse until you do.
- **GDScript type inference on autoload members.** `var x := Tuning.SOMETHING` fails to
  infer and is a parse error the editor reports but a headless run may compile anyway.
  Annotate explicitly: `var x: float = Tuning.SOMETHING`. (CLAUDE.md pitfall 2.)
- **Do not save `.tscn`/`.tres` through the editor** — edit on disk. The editor
  reformats and strips `;` comments.
- `resolve()` receives `ability.director`; `ability.target` is one chosen enemy and
  Cleave should ignore it in favour of `living_enemies()`.
