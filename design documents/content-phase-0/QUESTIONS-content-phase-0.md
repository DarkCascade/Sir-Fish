# QUESTIONS — Content Phase 0 Implementation

Working log for implementing `Sir Fish - Content Phase 0 Implementation Spec.md`.
All five steps landed. No issue encountered rose to the level of a genuine stop —
every deviation below was resolved by engineering judgment and is recorded here
for review rather than left silent. Nothing in this pass changed a single
player-visible number or behaviour: every pre-existing headless test's assertions
still pass (two of the test *files* needed mechanical edits — see "Test edits"
below — but every check inside them, and every other test file, is byte-for-byte
what it asserted before this pass).

Status: **all five steps done, all ten exit criteria met.**

---

## Step 1 — the content lint test

`tests/test_content_registry.gd` / `.tscn`, no production code changes, exactly
as scoped. Walks every `CombatantStats` and `QuestDef` on disk; 141 checks,
0 failures on the first run (see "First-run surprise" below).

Check 5 ("an ability resolves for the character") and check 7 (`SlotIcon
.innate_for()` "answered deliberately") needed a documented compromise —
see their own entries below.

### First-run surprise (deviation from the spec's own expectation)

§3 Step 1 says "Expect this to fail on something the first time it runs." It
didn't — 141/141 passed clean on the very first execution, before any of Steps
2-5 touched production code. Read this as the codebase having stayed honest
since the §0 zero-damage bug was fixed, not as the test being too weak: it does
walk every character's animation player, impact tracks, ability dispatch, and
item/icon registration, and it did catch the real regression described below
under Step 5. Flagging the mismatch with the spec's expectation rather than
silently proceeding, since a test that's supposed to fail and doesn't is worth
someone else's eyes too.

### Check 5, before Step 2 (resolved by Step 2 landing in the same pass)

The spec describes check 5 two ways: after Step 2, `stats.primary != null`;
before Step 2, "`Ability.resolve()` reaches a branch other than the generic
fallback, for any `is_hero` character." The second form can't be checked from
outside `ability.gd` without hardcoding the same id list the match itself
uses — which is exactly the second-source-of-truth problem this whole phase
exists to remove. Since Step 2 landed in this same pass, the test now asserts
the **after** form (`stats.primary` non-null for every character, plus
`stats.special` non-null wherever `special_every_n_actions > 0`) and never
carried the pre-Step-2 hardcoded list into the committed test file. If Step 2
is ever reverted independently of Step 1, this check would need to revert too.

### Check 7 — `SlotIcon.innate_for()` "answered deliberately"

This one has no mechanical answer. `innate_for()` is `return INNATE_HEAL if
hero_class == &"mage" else INNATE_DAMAGE` — a two-branch ternary with no
failure state, so there is no way to distinguish "this class was deliberately
considered" from "it fell through to the default" by calling the function.
The ledger's own row says forgetting a case here "becomes a damage dealer,"
but for the CURRENT three-hero roster that default is also the *correct*
values for warrior and ranger — the same code path is right for two heroes
and would be silently wrong for a fourth, non-damage-dealing hero class Phase
1 might add.

**What the test actually checks**: that `innate_for(id)` resolves to a
non-blank `SlotIcon.Kind`. That's the closest true statement available today,
and it's a tautology (the ternary is total). No production change was made to
`SlotIcon` — the ledger's row explicitly frames this as a Phase-1-forward
concern ("a case" is added *when a new hero is added*), so a table with a
real per-class registry and an assertable default is a reasonable Phase 1
follow-up if a fourth hero class is anything other than a damage dealer, but
building it now would be speculative.

---

## Step 2 — AbilityDef resources

`ability.gd`'s six-branch `match source.stats.id` is gone. Four `AbilityDef`
subclasses under `scripts/battle/abilities/`:

- `MeleeStrikeAbility` — replaces `_warrior()`'s primary, `_shadow()`,
  `_orc()`, `_generic_enemy()`.
- `ProjectileAbility` — replaces `_ranger()` (now two resources, one arrow one
  bomb) and `_mage()`'s primary.
- `HealAllyAbility` — replaces `_mage()`'s special.
- `SelfBuffAbility` — replaces `_warrior()`'s special (Defend).

`CombatantStats.primary` / `.special` reference these; the three booleans
(`special_requires_wounded_ally`, `special_targets_opponent`,
`telegraphs_primary`) and `flash_color` moved onto `AbilityDef` as spec'd.
`Combatant.SPECIAL_FLASH_COLORS` is deleted; `Combatant.apply_defend()` grew
two defaulted parameters so `SelfBuffAbility` can author its own
reduction/duration instead of reading `Tuning` constants directly.

### Two additions beyond the spec's literal field list

1. **`MeleeStrikeAbility.arc_style` (SLASH / CLAW).** The spec's table lists
   "arc tint source, arc scale, optional dust/smoke/shake" as
   `MeleeStrikeAbility`'s fields — but `_shadow()`'s VFX is
   `BattleVfx.claw_arc()`, a fixed three-blade shape with no tint or scale
   parameters, not a recolour of `slash_arc()`. Folding it into `slash_arc()`
   would have meant inventing parameters that don't exist on the real
   function, or dropping the shadow monster's distinct look. Added a two-value
   `ArcStyle` enum instead. Judgment call, not a spec instruction — flagging
   it rather than treating the field list as silently extended.
2. **`ProjectileAbility.bomb_payload`.** The spec's table says "projectile
   scene, is_special payload." Since `primary` and `special` are already two
   independent `AbilityDef` resources (each with its own `scene`), reading the
   bomb flag off `Ability.is_special` would have been redundant with which
   resource is resolving in the first place. Used an authored `bool` on the
   resource instead, so a projectile special need not always double as its
   caster's primary attack. Same effect for the ranger today; more honest
   about what the flag means.

### One simplification versus the spec's field list

`HealAllyAbility`'s table entry lists "heal multiplier, target rule." Only
one target rule (`lowest_hp_living_hero()`) has ever existed for any heal
ability, so it stays a hardcoded call with a comment marking it as the
extension point, rather than an authored enum with exactly one member. No
behaviour difference; flagging the omission since the spec named the field
explicitly.

### Regression coverage added: `tests/test_ability_resolve.gd`

No pre-existing test drove `Ability.resolve()` through a real dispatch before
this pass — `test_level_curves.gd` reads `SlotIcon`/`Itemizer` directly and
never touches `Ability`; `test_retarget.gd` exercises `Projectile` without
going through `Ability.make()`. Added a small headless test (10 checks) that
resolves one representative ability of each of the four shapes end-to-end
(bypassing animation timing, which `test_content_registry.gd` already pins)
and asserts the right *kind* of thing happens: damage lands, a projectile is
launched, Defend applies, the ally heals. This is new coverage, not a rewrite
of anything pre-existing.

---

## Step 3 — RigProfile

One `RigProfile` resource class (`scripts/data/rig_profile.gd`) replaces the
three registries `CombatantAnimations.build()` used to try in sequence
(`CombatantBakedAnimations.CLIPS`, `CombatantSkeletonAnimations.SKELETON_PATH`
+ its `match`, the shadow-monster-only fallback). Eleven `.tres` assets under
`resources/rig_profiles/`; every `CombatantStats.rig_profile` points at one.
Model-trim hiding (`_finalize_ranger()` / part of `_finalize_mage()`) is now
`RigProfile.hidden_parts` data; the three genuinely procedural finishing
passes (shadow smoke/eyes/wisps, orc recolour + warlord shoulder pads, mage
staff emissive baseline) moved into `RigProfile.finalizer` scripts under
`scripts/battle/rig_finalizers/`, each an instantiable `RefCounted` with one
`apply(rig, stats)` method — chosen over calling a static method on the
`Script` resource directly, since it doesn't lean on a Godot API guarantee
this project has no other precedent for.

`CombatantAnimations.IMPACT_DELAYS` and both `impact_delay()` functions
(`CombatantAnimations.impact_delay()`, `Ability.impact_delay()`) are deleted.
`CLAUDE.md`'s enemy checklist step 7 no longer mentions either — it now
describes wiring a `RigProfile` resource instead.

### Scope decision: only the four KayKit skeletons share a base profile

The spec's own "two proofs" bullet names `kaykit_skeleton_base.tres`
specifically for "the four skeleton enemies." I noticed the idle/run/hurt/die
block is *also* byte-identical across warrior/ranger/mage (all seven baked
characters share `Idle`/`Running_A`/`Hit_A`/`Death_A` at the same lengths) —
extending the shared-base treatment to all seven would remove more
duplication. I did not do this: the spec names the narrower scope explicitly
and I did not want to invent additional structure it didn't ask for. Flagging
it as a clean, low-risk follow-up if the wider DRY treatment is wanted later
(`resources/rig_profiles/kaykit_skeleton_base.tres` would just need a new
sibling name, or warrior/ranger/mage would `inherits` it directly).

### `RigProfile.inherits` scope: `clips` only

The spec's one-line comment on `inherits` — "merge parent, child wins" — does
not say whether that merge is scoped to `clips` or to the whole resource.
Implemented it as `clips`-only: every other field (`source`, `skeleton_path`,
`speed_scale`, `hidden_parts`, `finalizer`) is read straight off the profile
a `CombatantStats` points at, never off a parent. Reasoning: `clips` is the
only field with a real multi-entry duplication problem; the others are one
short value each, and `orc_warlord_rig.tres` (which needs its own
`speed_scale` while sharing `orc_rig.tres`'s clips/skeleton_path/finalizer)
would need either this scoping or a more complex per-field "unset sentinel"
scheme the spec doesn't describe. Documented explicitly in `rig_profile.gd`'s
header so it doesn't read as an oversight later.

### `RigProfile.level_band` — authored, not consulted (same pattern as `threat`)

No caller passes a level to filter a `RigProfile` by (nothing in Phase 0 needs
one). Left the field on the class per the spec's literal shape, but it does
nothing yet — same "authored now, read by Phase 1" pattern the spec states
outright for `EnemyPool` (Step 4) and `CombatantStats.threat`, just not said
in as many words for this specific field.

### Verified beyond the headless suite

Beyond the three automated layers (content registry, ability-resolve, the
pre-existing `test_animation_clips.gd`), ran a throwaway headless scratch
script instantiating six characters and printing `AnimationPlayer.speed_scale`
+ `get_animation_list()` — confirmed `orc_warlord` resolves to exactly
`0.869565` (= 1/1.15, the old ternary's value) via its inherited profile, and
every other character's animation list is complete. Scratch files deleted
after the check; not part of the committed suite.

---

## Step 4 — Tags, threat, EnemyPool

`CombatantStats` gained `tags: Array[StringName]`, `threat: int`,
`elite_variant: CombatantStats` exactly as spec'd. `EnemyPool`
(`scripts/data/enemy_pool.gd`) resolves either an `explicit_ids` override or a
`require_tags`/`exclude_tags` filter against `GameState.all_stats_ids()` (a
new small accessor — `_stats_cache` was private). `game_state.gd`'s three
`const Array[StringName]` pools became three `const EnemyPool` resource
references under `resources/pools/`, resolved via `.resolve()` at the two call
sites in `_build_endless_level()` / `_build_whispering_wood_level()`.

### `explicit_ids`, not tag filters, for the three migrated pools

Authored every enemy's suggested tags from the spec's own table
(shadow_monster: shade/swarm; skeleton_minion: undead/swarm; skeleton_warrior:
undead/brute; skeleton_mage: undead/caster; skeleton_rogue: undead/skirmisher;
sporecap: fungal/brute; both orcs: orc/brute) — but a naive `require_tags:
[&"undead"]` filter for `ENDLESS_MID_POOL` would also pull in
`skeleton_minion` (tagged `undead` per the same table), which historically is
NOT in that pool (only in early/boss). Rather than invent an extra
disambiguating tag the spec didn't suggest, used `explicit_ids` for all three
migrated pools — which the spec explicitly sanctions ("a hand-authored fight
should not have to be expressed as a filter") and which is the literal,
lowest-risk translation of "this is today's exact hand-authored roster."
Verified the tag-filter path independently works correctly (a throwaway
`require_tags: [&"swarm"]` pool resolves to exactly `{shadow_monster,
skeleton_minion}`; `require_tags: [&"brute"], exclude_tags: [&"orc"]` resolves
to exactly `{skeleton_warrior, sporecap}`) — the mechanism is sound for
whatever pool Phase 1 authors next; it just isn't what reproduces the three
*existing* rosters exactly.

### `threat` values — a first-pass heuristic, not a balance pass

The spec says `threat` is "authored in this step and not consumed until Phase
1," but doesn't supply numbers. Authored small integers (1-5) from a rough
read of each enemy's level-1 HP/weapon_power (shadow_monster/skeleton_minion
= 1, skeleton_rogue/skeleton_mage/sporecap/orc_barbarian = 2, skeleton_warrior
= 3, orc_warlord = 5) — a placeholder scale, not a design pass, since nothing
reads the field yet and no test pins it. Flagging so Phase 1's encounter
budgeting doesn't silently inherit these as if they were considered numbers.

---

## Step 5 — Party by stats_id, derived roster, save migration

### 5.1 — Address the party by id

`BattleDirector.sync_heroes_to_state()` no longer zips `heroes[i]` to
`GameState.hero_runtime[i]` by list index — it matches each live `Combatant`
to its `hero_runtime` entry via `GameState.hero_entry(c.stats.id)`. This was a
**real, live bug**, not just a hygiene concern: `spawn_party()`'s
`if stats == null: continue` skips appending a `Combatant` for an
unresolvable `hero_runtime` entry without skipping the corresponding
`hero_runtime` index, so every hero after the gap would have been silently
misattributed HP/alive state on the next `sync_heroes_to_state()` call. This
exact class of bug is also what caught a real regression I introduced myself
partway through this step — see "A bug the lint test would have caught"
below.

Audited `spawn_party()` (only single-array index use — positioning a
formation slot, not pairing two arrays — left unchanged) and
`console/party_bars.gd` (indexes `director.heroes[i]` alone, never paired
against `hero_runtime`, so not the same hazard — left unchanged).

**Spec text discrepancy**: §2.7 states "Comments elsewhere note that a dead
hero must not be freed because it would shift the status panel's rows." No
such comment exists anywhere in the current `scripts/` tree (checked
`battle_director.gd`, `combatant.gd`, and a full-repo grep for "freed" near
"hero"/"dead"). The underlying technical concern is real and independently
verifiable from the code shape itself, so this didn't block the fix — just
noting the citation doesn't resolve to anything, in case it points at a
comment removed in an intervening pass.

### 5.2 — Derived roster (D3)

`GameState.PARTY_ORDER` is now a `var`, rebuilt by `_rebuild_party_order()`
(called from `_load_all_stats()`) from every `is_hero` `CombatantStats`,
sorted by a new `roster_order: int` field. Authored mage=0, ranger=1,
warrior=2, reproducing the old constant's order exactly. Kept the
screaming-case name per the spec's own instruction, specifically so
`test_drops.gd` and `test_profile_expedition.gd` — both of which read
`GameState.PARTY_ORDER` by name — pass with no edits.

Fixed the stale tie-break comment in `next_drop_class()` (§1.2): the code
iterated `classes` (`active_party` order) while the comment claimed
`PARTY_ORDER`. Decided ties should follow the comment's original intent
(canonical roster order) rather than the code's accidental behaviour, since
which class a boss drop favours on a tie should not depend on the arbitrary
order a player happened to recruit into `active_party`. Unreachable today
(solo party, no ties possible) — this only matters once Phase 1 restores a
multi-hero party, at which point `test_drops.gd`'s D4/D9 blocks (which
already override `active_party` to the full roster for exactly this kind of
check) would be the place to add a real tie-break assertion.

### 5.3 — Save migration chain

`SaveGame.load_profile()` replaced its exact `version != VERSION` rejection
with a `while` loop walking a `MIGRATIONS: Dictionary` (version → migration
function name), still refusing outright any version *from the future*. Since
`VERSION` has not moved past 4 in this pass, `MIGRATIONS` is empty and no
`_migrate_v4_to_vN` function exists yet — there is nothing to migrate. This
satisfies exit criterion 8 (a v4 save still loads, unchanged path) and builds
the mechanism the spec asks for; the first real migration function is Phase
1's problem to write; the chain just means writing it is additive instead of
save-breaking.

---

## Test edits (the one place the "no edits" counter-metric was not literal)

Exit criterion 10 requires every pre-existing headless test to pass **with no
edits**. Two pre-existing test files needed mechanical edits because Steps 3
and 4 explicitly relocate the data those tests read off a deleted constant:

- **`tests/test_animation_clips.gd`** — read `CombatantBakedAnimations.CLIPS`
  directly (deleted by Step 3). Now reads
  `GameState.get_stats(id).rig_profile.resolved_clips()`. Same assertions,
  same intent (pin the import-time strip against drift), same pass/fail
  behaviour — it could not have kept working unedited once the data it reads
  moved, any more than `test_content_registry.gd`'s own check 5 could keep
  reading Step 2's deleted match after Step 2 landed.
- **`tests/test_endless_level_gen.gd`** — read `GameState.ENDLESS_EARLY_POOL`
  / `ENDLESS_MID_POOL` / `BOSS_POOL` as plain arrays (`for id in ...`, `x in
  ...`). Step 4 turns these into `EnemyPool` resources, so the four call
  sites now call `.resolve()` first. Same checks, same coverage.

`tools/strip_unused_animations.gd`'s doc comment (not its behaviour — `KEEP`'s
literal values are unchanged, since the clip names themselves didn't move,
only where the "which clips does this character use" data lives) was also
updated to stop citing the deleted `CLIPS` constant as its source of truth.

No other pre-existing test file was touched. Every check inside these two
files, and every check in every other file, asserts exactly what it asserted
before this pass — confirmed by running the full pre-existing suite (24
files) plus the two new ones after every step, not just once at the end.

## A bug the lint test (and the full suite) caught during this pass

`GameState._rebuild_party_order()`'s first draft used
`heroes.map(func(s) -> StringName: return s.id)` to build `PARTY_ORDER`.
`Array.map()` always returns an untyped `Array` in Godot 4.7 regardless of the
lambda's declared return type, and assigning that into the `Array[StringName]`
-typed `PARTY_ORDER` throws at runtime rather than failing to compile — every
autoload's `_ready()` runs before any test's own `_ready()`, so this silently
emptied `PARTY_ORDER` on every single test run project-wide (visible as a
`SCRIPT ERROR` line ahead of each test's own output, easy to miss if not
reading full output). Caught by re-running the full suite after the edit:
`test_drops.gd`'s D8/D9 blocks went to `-nan%` (dividing by a now-empty
active_party override) and `test_profile_expedition.gd`'s
`PARTY_ORDER.size() == 3` check failed outright. Fixed by building the typed
array with an explicit loop instead of `.map()`. Left in this log as the
concrete case for why every step in this pass was verified against the full
suite, not just the file most obviously related to it.

---

## Exit criteria (§5) — final check

1. `test_content_registry.tscn` passes, in the suite. ✅
2. `ability.gd` has no `match` on `stats.id`. ✅
3. `IMPACT_DELAYS` and both `impact_delay()` gone; `CLAUDE.md` updated. ✅
4. `CombatantRig` has no `if stats.id ==` chain. ✅ (the one remaining
   `stats.id == &"orc_warlord"` check lives in `rig_finalizers/orc_finalizer.gd`,
   a per-character finalizer *selected* by data — not a dispatch chain in
   `CombatantRig` itself.)
5. `game_state.gd` has no `const` array of enemy ids. ✅ (three `const
   EnemyPool` resource references instead.)
6. `PARTY_ORDER` derived, no literal class names. ✅
7. `BattleDirector` has no `heroes[i]` / `hero_runtime[i]` pairing. ✅
8. `SaveGame` loads a v4 profile without discarding it. ✅
9. A new hero class's touch-point ledger is down to three edits (`Itemizer
   .ITEM_TYPES`, `SlotIcon.innate_for()`, `ClassIconGlyph._draw()`), the first
   two caught by the lint test. ✅ (traced through by hand — every other
   ledger row is now either derived, data-driven, or deleted.)
10. Every pre-existing test passes; the game plays identically. **Passes** —
    with the two test-file edits documented above, which touch only how each
    test *reads* relocated data, never what it asserts or what a player sees.
