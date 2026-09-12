# Sir Fish — Content Phase 0 Implementation Spec

**The authoring foundation.** Phase 0 of the Content initiative.

> Phase 0 ships **no new content and no new features**. If it is done correctly the
> game plays identically before and after, and the whole diff is structure. Phase 1
> (`../content-phase-1/`) is where new classes and generated quests land, and it
> assumes everything below already exists.

**Decisions in force** (resolved 12 Sep 2026, recorded in the Content Initiative PRD):

- **D3 — the roster becomes derived.** Lands in this phase, in Step 5.
- D1 (Executor) and D2 (every quest pays gold) shape Phase 1 only.

---

## 0. Why this phase exists at all

Every character in the game is a `StringName` id. `CombatantStats` holds what that
character **is**. What the engine should **do** with it lives in separate dictionaries
and `match` statements spread across the battle, console and overlay layers — each
keyed by the same id, none of them checked against the others.

This is not hypothetical. Four of the five enemies in the endless rotation played
their attack animation and dealt **zero damage** for an entire content pass, because
`Ability.resolve()` matched on the character id, had no case for them, and had no
default. The comment that introduced `_generic_enemy()` says exactly that. It was not
a bug testing found; it was a bug the dispatch style invited.

The same shape repeats with quieter symptoms:

- A class absent from `Itemizer.ITEM_TYPES` silently never receives a drop, because
  `droppable_classes()` derives its candidate list from that table.
- A class absent from `SlotIcon.innate_for()` silently becomes a damage dealer.
- Two tables that look load-bearing turn out to drive nothing at all (§1.1, §1.2).

None of these raise anything.

### 0.1 What is already right, and must be preserved

The fix should extend these patterns, not invent new ones.

- **Derived over stored.** `CombatantStats.required_anims()`, `Item.usable_by()` and
  `Item.slot()` all compute from one table rather than duplicating it. The comments
  state the reason: a second copy is a second thing to drift.
- **Data flags over id checks.** `special_targets_opponent` and `telegraphs_primary`
  already replaced hardcoded id branches. The instinct is correct; it simply has not
  reached the dispatch itself.
- **`HeroBars` falls back by design.** An unlisted class takes its own `accent_color`,
  and the comment states that a fourth hero is a resource edit and not a code change.
  **That is the target behaviour for every table in this document.**
- **A real headless harness.** Twenty-four test scenes with shared pass/fail
  bookkeeping and a `user://` file guard, runnable with no editor connection. This is
  the leverage for everything below, and Step 1 spends it.

---

## 1. The touch-point ledger

Every place a brand-new hero class — say a cleric — has to be registered today before
it works completely.

| Where | What you add | If you forget | Severity |
|---|---|---|---|
| `resources/stats/` | a new `.tres` | new file, auto-discovered by directory scan | fine |
| `scenes/battle/heroes/` | a new `.tscn` | new file, referenced by `scene_path` | fine |
| `Ability.resolve()` | a `match` branch | falls to the generic melee swing — a caster walks up and punches | **silent** |
| `CombatantBakedAnimations.CLIPS` | a clip block | falls to the skeleton builder, then the shadow-monster assert | loud |
| `CombatantAnimations.IMPACT_DELAYS` | a row | **nothing. See §1.1** | **dead** |
| `Itemizer.ITEM_TYPES` | `classes` on type rows | no wieldable type, so `droppable_classes()` drops the class entirely and it never receives loot | **silent** |
| `SlotIcon.innate_for()` | a case | becomes a damage dealer — its whole board identity is one ternary | **silent** |
| `Combatant.SPECIAL_FLASH_COLORS` | a row | telegraph flashes near-white instead of the class colour | cosmetic |
| `CombatantRig.build()` | a model-trim branch | every prop variant the source model ships renders at once | cosmetic |
| `ClassIconGlyph._draw()` | a case | no glyph on the party chip | cosmetic |
| `GameState.PARTY_ORDER` | an entry | **nothing in production. See §1.2** | **dead** |
| `HeroBars` | *nothing* | falls back to the stats accent colour, by design | fine |

**Nine edits to shared code.** Three fail silently, one fails loudly, three are
cosmetic, and **two do nothing at all**. Two further touch points are new files, which
is correct and unavoidable, and one table already degrades correctly on its own.

Note what is *not* on this list: a registry for joining the party. A hero enters
`GameState.active_party` only through the hardcoded assignment in `new_profile()` (and
the field's own initialiser), or from a save. That is a Phase 1 concern and is picked
up by the recruitment outline.

A new **monster** is cheaper, at three code edits — one of them the dead impact table —
because `_generic_enemy()` now covers its behaviour. It still needs a hand edit to a
`const` array in `game_state.gd` before anything will ever spawn it.

### 1.1 IMPACT_DELAYS is dead code

`CombatantAnimations.IMPACT_DELAYS` is read only by
`CombatantAnimations.impact_delay()`, which is called only by
`Ability.impact_delay()`, **which has no callers at all**. The table has eleven
entries and drives nothing.

The impact times that actually fire come from method-call tracks, authored in three
separate places:

- `CombatantBakedAnimations.CLIPS[id][clip]["impact"]` — the seven baked characters.
- A hardcoded `_call(a, 0.42, &"_anim_impact")` in `_orc_attack()` and `0.40` in
  `_sporecap_attack()`.
- A hardcoded `_call(a, 0.28, &"_anim_impact")` in `_shadow_swipe()`.

The values in `IMPACT_DELAYS` currently agree with all of these, so nothing is broken
today — but the table is a second source of truth that cannot drift *visibly*, which
is the worst kind.

**`CLAUDE.md`'s "Adding a new enemy" section, step 7, instructs the author to add an
`IMPACT_DELAYS` entry.** That instruction is busywork that looks load-bearing. Fix the
doc as part of Step 3, when the table is deleted.

### 1.2 PARTY_ORDER has no production reads

`GameState.PARTY_ORDER` is declared, and documented at length as "the canonical
roster", but **no production code reads it**. Its only readers are two tests:
`test_drops.gd`, which iterates it, and `test_profile_expedition.gd`, which asserts its
size is 3.

The one production comment that cites it is stale. `next_drop_class()` says boss-drop
ties "break in PARTY_ORDER", but the loop iterates `Itemizer.droppable_classes()`,
which walks `active_party`. Ties actually break in party order. That is harmless with a
solo warrior and wrong the moment a second class joins.

So forgetting to add a class to `PARTY_ORDER` changes nothing a player sees. Decision
D3 derives it anyway: a roster that is canonical in name should be canonical in fact,
and future recruitment needs something real to read.

---

## 2. Findings this phase closes

### 2.1 Ability dispatch is a match on the character id

`Ability.resolve()` switches on `source.stats.id` into six private methods
(`_warrior`, `_ranger`, `_mage`, `_shadow`, `_orc`, `_generic_enemy`). Every new
class, and every variant of an existing one, edits this file. It is also where the
silent-zero-damage bug lived.

### 2.2 Four booleans on CombatantStats are facts about an ability

`special_every_n_actions`, `special_requires_wounded_ally`,
`special_targets_opponent` and `telegraphs_primary` all describe **one ability**. They
sit on the character because the ability has no resource of its own. Every new ability
shape adds another boolean here.

### 2.3 Hero stat rows are half dead since the slot redesign

The hero `.tres` files carry `weapon_power = 0` with a comment saying the field is
enemy-only now, and `BattleDirector._process()` skips heroes entirely
(`if c.is_hero: continue`), so `attack_cooldown` on a hero drives nothing. A class
author reading `warrior.tres` cannot tell which fields still matter.

### 2.4 Animation binding is three parallel registries plus an assert

`CombatantAnimations.build()` tries `CombatantBakedAnimations`, then
`CombatantSkeletonAnimations`, then asserts the character is the shadow monster.
Meanwhile the four KayKit skeleton enemies each duplicate a five-entry `CLIPS` block
that differs **only in the attack clip**.

`CombatantRig.build()` has the same shape one layer down: an `if stats.id ==` chain
mixing pure data (which prop meshes to hide) with genuinely procedural work (smoke
materials, runtime recolours).

### 2.5 Encounter pools are const arrays inside GameState

`ENDLESS_EARLY_POOL`, `ENDLESS_MID_POOL` and `BOSS_POOL` are content living in a
1,148-line autoload. Adding a monster to the rotation is a code edit, and the rotation
cannot vary by area or theme without more arrays beside them.

### 2.6 There is no way to describe a monster except by naming it

No tags, families or roles exist anywhere in the data (verified: zero hits for
tag/family/archetype across `scripts/`). A quest can only list ids, so "three undead
in the level 10–20 band" is not expressible. **This is the single finding that couples
the monster work to the quest work**, and it is why Step 4 lands in Phase 0 rather
than Phase 1.

### 2.7 The party is coupled by list index

`BattleDirector.sync_heroes_to_state()` zips `heroes[i]` to
`GameState.hero_runtime[i]`, and `spawn_party()` walks `hero_runtime` by index.
Comments elsewhere note that a dead hero must **not** be freed because it would shift
the status panel's rows. A party whose composition changes — which is the entire point
of Phase 1 — breaks this quietly.

Credit where due: `_reset_hero_runtime()` and `party_status()` already match on
`stats_id`. The offenders are the two `BattleDirector` functions.

### 2.8 The save gate rejects rather than migrates

`SaveGame.VERSION` is at 4 and every bump discards the file wholesale. That was
correct while the only player was the developer. Phase 1 adds per-class levels,
per-class equipment and a persisted quest board, so the next few bumps are already
scheduled.

---

## 3. Scope — five steps, in order

Each step is independently shippable and independently revertible. The order is not
cosmetic: each removes a class of regression the next one could otherwise introduce.

### Step 1 — The content lint test

**One new headless scene. No production code changes.**

This is the highest-leverage single change in the whole initiative and it is a test,
not a refactor. Walk every `CombatantStats` on disk and assert:

1. `scene_path` is non-empty, the scene exists, and it instantiates as a `Combatant`.
2. `CombatantAnimations.build()` completes without assertion.
3. Every name in `required_anims()` is present on the resulting `AnimationPlayer`.
4. Every clip that should resolve damage carries an `_anim_impact` call track, and its
   time is inside the clip's length.
5. An ability resolves for the character — after Step 2, that `stats.primary` is
   non-null; before Step 2, that `Ability.resolve()` reaches a branch other than the
   generic fallback for any `is_hero` character.
6. For heroes: `Itemizer.weapon_types_for(id)` is non-empty, so the class can receive
   drops.
7. For heroes: `SlotIcon.innate_for(id)` was answered deliberately rather than by
   falling through the ternary.

And one check that is not about characters, added now because Phase 1 depends on it:

8. Every `QuestDef` on disk has `gold_reward > 0` (decision D2).

Every **silent** row in the §1 ledger becomes a red test. Expect this to fail on
something the first time it runs.

Name it `tests/test_content_registry.tscn` / `.gd`, following the existing harness
(`tests/test_support.gd`, `t.check(cond, label)`, non-zero exit on failure).

### Step 2 — AbilityDef resources

Kill the `match` in `Ability.resolve()`. Port the six existing behaviours one at a
time; each `.tres` replaces one branch, and `test_animation_clips.gd` plus
`test_level_curves.gd` pin the behaviour while it moves.

**Critical structural note.** `Ability` today conflates two lifetimes: authored data
(which anim, what it does) and per-action state (`target`, `fixed_damage`, `school`).
Keep them apart, for exactly the reason `Combatant.level` is not stored on
`CombatantStats` — a Resource is cached and shared across every spawn.

- `AbilityDef extends Resource` — authored, shared, cached. Never holds a target.
- The existing `Ability extends RefCounted` stays as the in-flight instance, holding
  `def`, `target`, `fixed_damage`, `school`.

Four subclasses cover all six current branches:

| Subclass | Replaces | Authored fields |
|---|---|---|
| `MeleeStrikeAbility` | `_warrior` primary, `_shadow`, `_orc`, `_generic_enemy` | arc tint source, arc scale, optional dust / smoke / shake |
| `ProjectileAbility` | `_ranger` primary + special, `_mage` primary | projectile scene, `is_special` payload |
| `HealAllyAbility` | `_mage` special | heal multiplier, target rule |
| `SelfBuffAbility` | `_warrior` special | reduction fraction, duration, status icon |

`CombatantStats` then carries `primary: AbilityDef`, `special: AbilityDef` and keeps
only `special_every_n_actions`. The other three booleans move onto `AbilityDef`, along
with `flash_color` (retiring `Combatant.SPECIAL_FLASH_COLORS`).

`_generic_enemy()` becomes the default `MeleeStrike` asset that every enemy `.tres`
points at — which is honest about what it already is.

### Step 3 — RigProfile, folding three registries into one

Mechanical. Collapse `CombatantBakedAnimations`, `CombatantSkeletonAnimations` and
`CombatantAnimations._build_shadow()` behind one resource referenced from
`CombatantStats.rig_profile`.

```gdscript
class_name RigProfile extends Resource
enum Source { BAKED, AUTHORED_SKELETON, SHAPE_KEYS }
@export var inherits: RigProfile                  # merge parent, child wins
@export var source: Source = Source.BAKED
@export var skeleton_path: String = ""            # was SKELETON_PATH
@export var clips: Dictionary = {}                # StringName -> ClipSpec
@export var speed_scale: float = 1.0              # was the orc_warlord ternary
@export var hidden_parts: PackedStringArray = []  # was _finalize_ranger / _mage trims
@export var finalizer: Script                     # optional procedural material pass
```

`ClipSpec` carries what `CLIPS` already encodes: source clip name, target length, loop
mode, and optional `impact` / `cast` / `charge` / `glow_node`.

**Model trims become data too.** Hiding surplus prop meshes — the ranger's crossbow and
knives, the mage's wand and open spellbook — is pure data, so it moves to
`hidden_parts`. The genuinely procedural finalisers stay as code: the shadow monster's
smoke material, eyes and wisps; the orc pair's runtime recolour and shoulder pads; the
mage staff's emissive baseline. They are reached through `finalizer` on the profile
instead of an `if stats.id ==` chain in `CombatantRig`.

Two proofs that it worked:

- The four skeleton enemies collapse onto one `kaykit_skeleton_base.tres` and override
  only `attack`.
- `IMPACT_DELAYS`, `CombatantAnimations.impact_delay()` and `Ability.impact_delay()`
  are all **deleted** (see §1.1), and `CLAUDE.md`'s enemy checklist loses its step 7.

### Step 4 — Tags, threat, and EnemyPool resources

```gdscript
# on CombatantStats
@export var tags: Array[StringName] = []   # &"undead" &"fungal" &"caster" &"brute" ...
@export var threat: int = 1                # rough encounter-budget cost
@export var elite_variant: CombatantStats  # optional named boss form

# resources/pools/<name>.tres
class_name EnemyPool extends Resource
@export var require_tags: Array[StringName] = []
@export var exclude_tags: Array[StringName] = []
@export var level_band: Vector2i = Vector2i(1, 99)
@export var explicit_ids: Array[StringName] = []   # hand-pin a set-piece roster
```

A pool resolves against `GameState._stats_cache` at build time, so a monster joins
every pool it qualifies for the moment its `.tres` lands. Keep `explicit_ids` as an
override — a hand-authored fight should not have to be expressed as a filter.

Suggested starting tags for the existing roster:

| Character | Tags |
|---|---|
| `shadow_monster` | `shade`, `swarm` |
| `skeleton_minion` | `undead`, `swarm` |
| `skeleton_warrior` | `undead`, `brute` |
| `skeleton_mage` | `undead`, `caster` |
| `skeleton_rogue` | `undead`, `skirmisher` |
| `sporecap` | `fungal`, `brute` |
| `orc_barbarian` / `orc_warlord` | `orc`, `brute` (out of rotation) |

`ENDLESS_EARLY_POOL`, `ENDLESS_MID_POOL` and `BOSS_POOL` move out of `game_state.gd`
and become the first three pool assets. Nothing about play changes.

`threat` is the seed for encounter budgeting — "roughly this hard" instead of "this
many bodies" — which is what stops Phase 1's generated encounters reading as flat. It
is authored in this step and **not consumed until Phase 1**.

### Step 5 — Party by stats_id, a derived roster, and a save migration chain

Three small changes, all of which are cheap now and archaeology later.

1. **Address the party by id.** Rewrite `BattleDirector.sync_heroes_to_state()` and
   `spawn_party()` to match on `stats_id` via the existing `GameState.hero_entry(id)`,
   not on list index. Audit the status panel's row addressing at the same time — the
   comment about not freeing dead heroes becomes unnecessary once nothing is positional.

2. **Derive the roster (D3).** Replace `const PARTY_ORDER` with a roster computed in
   `_load_all_stats()` from every `CombatantStats` where `is_hero` is true, sorted by a
   new authored `roster_order: int`.
   - Author mage `0`, ranger `1`, warrior `2`, so the derived list is identical to
     today's constant. Do not rely on alphabetical order happening to match.
   - Keep it readable as `GameState.PARTY_ORDER` — a derived `var` populated at load —
     so `test_drops.gd` and `test_profile_expedition.gd` pass **unedited**, which the
     §5 counter-metric requires. A screaming-case name on a `var` is the price of that.
     Rename it to `roster()` later, when those tests are touched for their own reasons.
   - Fix the stale tie-break comment in `next_drop_class()` in the same commit (§1.2),
     and decide deliberately whether boss-drop ties follow roster order or party order.
   - In Phase 1, `roster_order` moves onto `ClassDef` with the rest of a class's
     identity.
   - **Not in scope:** the *starting* party. `new_profile()` and the `active_party`
     initialiser both hardcode `[&"warrior"]`. That is a different question from what
     the roster is.

3. **Migrate saves instead of rejecting them.** Replace `SaveGame.load_profile()`'s
   exact-match version gate with a migration chain — `_migrate_v4_to_v5(d)` and so on —
   falling back to `new_profile()` only when no path exists. Keep the existing
   rejection for versions *from the future*.

---

## 4. Out of scope for Phase 0

All of the following belong to `../content-phase-1/`:

- `ClassDef`, the Executor rule (D1), and re-enabling the ranger and mage.
- `QuestObjective`, the reward extras list (D2), `AreaDef`, `QuestTemplate`, and the
  generated quest board.
- Any new monster, class, quest, area or item.
- `Tuning`'s size. It is a 917-line god-constant autoload and it will eventually want
  sectioning or resource backing, but nothing in either phase is blocked on it.

---

## 5. Exit criteria

Phase 0 is done when **all** of these hold:

1. `tests/test_content_registry.tscn` passes, and it is in the suite.
2. `ability.gd` contains no `match` on `stats.id`.
3. `CombatantAnimations.IMPACT_DELAYS` and both `impact_delay()` functions are gone,
   and `CLAUDE.md`'s enemy checklist reflects that.
4. `CombatantRig` contains no `if stats.id ==` chain.
5. `game_state.gd` contains no `const` array of enemy ids.
6. `PARTY_ORDER` is derived from hero resources and contains no literal class names.
7. `BattleDirector` contains no `heroes[i]` / `hero_runtime[i]` index pairing.
8. `SaveGame` can load a version-4 profile without discarding it.
9. **The §1 ledger for a new hero class is down to three code edits, all of which
   Phase 1 removes:** class eligibility in `Itemizer.ITEM_TYPES`, the innate icon in
   `SlotIcon.innate_for()`, and the glyph in `ClassIconGlyph._draw()`. The lint test
   catches the first two if they are missed.
10. **Counter-metric.** Every pre-existing headless test still passes with **no edits**,
    and the game plays identically. Phase 0 ships nothing a player can see.
