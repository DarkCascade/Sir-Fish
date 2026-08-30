# Town Spec — Step 8 Implementation Questions

Raised while preparing §14 step 8 of *Sir Fish — Town, Quests & Forging
Implementation Spec* ("**§8 — `QuestDef`, the three `.tres` files,
`_build_quest_level()`**, and the victory/failure flows. The loop closes here:
this is the first commit where the game is the game this document describes.").

Step 8 is the step §14 calls "the one worth demoing". Unlike steps 4–7 it has a
full, detailed spec (§7.5, §8.1–§8.5) but **no itemised §14 changeset**, and the
spec is written scene-first — §8.5 in particular reads as a list of steps
`RunController` performs. The questions below are mostly about the seams that
prose glosses: a signature §3.2 pins that §8.5 then works around, a flow that
cannot live where §8.5 puts it because scene routing frees its owner, and three
data fields that need a home the spec names without wiring.

**Nothing here is a design fork.** §0.4 settled solo-warrior and the failure
cost; §8.2 fixed the three tiers; §8.5 fixed the two recovery buttons. These are
implementation gaps.

**Answers pending.** Each carries a recommendation. The step was built against
these; the "as built" section at the end records what shipped.

| Q | gap | recommendation | spec |
|---|---|---|---|
| Q1 | `present(victory)` keeps its signature (§3.2), but §8.5 nulls `GameState.quest` **before** `present()` — so the modal can't tell a quest ending from an endless one, or read the reward | add `GameState.completed_quest: QuestDef`, set before `quest` is nulled, cleared by `start_expedition()` | §3.2, §8.5 |
| Q2 | §8.5 writes the route-home + present + recovery flow as `RunController` steps, but `SceneRouter.go()` frees `main.tscn` and `RunController` with it | `RunController` does only the synchronous profile work + `EventBus.quest_finished.emit()`; `QuestResult` (a persistent `Hud` child) does `await go()` → `present()`, and owns the recovery-button `GameState`/`SaveGame` calls | §8.5, §3.2 |
| Q3 | §8.2/§8.3 never say how `quest.boss_drop_rarity_floor` reaches `battle_director.start_combat()` | new `EncounterDef.boss_drop_rarity_floor` (default **1**, preserving the endless boss's "never Common" floor), passed as a `start_combat()` param | §8.2, §8.3, drops §6 |
| Q4 | §7.5 wants a Meshy background for the mayor's office; §12 / step 11 is where art lands | placeholder `ColorRect` now; §14 already schedules the Meshy pass for step 11 | §7.5, §12, §14 |
| Q5 | `ExpeditionGold` / `ExpeditionScrap` rows have no data source until step 9's pickups | build the rows now (they are part of §8.5's modal), populated at step 9; they read **0** until then | §8.4, §8.5, §14 step 9 |
| Q6 | §13.1 lists only `test_quest_gen.gd` for step 8 | also ship `test_quest_flow.gd` — the §8.5 keep/drop/heal economy reduces to cheap headless invariants and is the riskiest logic in the step | §13.1, step-1 Q5 |
| Q7 | §8.2 writes sequences as "C, L, C, S, **B**", but `EncounterDef.Type` has only COMBAT / LOOT / SHOP | **B** is the last COMBAT, flagged `is_boss` by position; the `.tres` stores `[0, 1, 0, 2, 0]` | §8.1, §8.2 |
| Q8 | `enemy_count` is a `Vector2i` range; `_random_enemies()` takes a fixed count; the boss fight is `[boss] + adds` | draw `count` from the range once per combat; non-boss = `count`, boss = boss + `clampi(count − 1, 0, MAX_ENEMIES − 1)` adds, so the boss group total also lands inside `enemy_count` | §8.3 |
| Q9 | does `GameState.quest` / `start_expedition()`'s param tighten to `QuestDef`? | yes, both — `reset_run()` still calls `start_expedition()` on the `= null` default | §8.1, §2.3 |
| Q10 | headless test runs with a scene argument do **not** rescan `class_name`s — `QuestDef` was invisible until an `--editor --headless` pass | one `--editor --headless --quit-after` run after adding any `class_name`, same family as step-5 I8 / step-6 N2 | — |

---

## Q1. `present(victory)` cannot see that it is a quest

§3.2 is explicit: "`present(victory: bool)` keeps its current signature — the
Quest Reward row, the expedition gold/scrap rows and the recovery-button
variants are all §8.5." So `present()` must branch three ways (endless RETRY /
quest VICTORY / quest FAILURE) off `victory` alone.

But §8.5's victory flow orders the steps: **2.** `GameState.quest = null`; …
**4.** `Hud.quest_result.present(true)`. `quest` is null by the time `present()`
runs — deliberately, because the route in step 3 swaps in the mayor's-office
scene and anything in *its* `_ready()` that reads `GameState.quest` should see
"not on a quest". So `present()` has no `quest` to read, and no reward.

### Recommendation — a `completed_quest` field

`GameState.completed_quest: QuestDef`, set to the finishing quest on both the
victory and failure paths *before* `quest` is nulled, read by `present()` as the
"this was a quest" flag and the source of `gold_reward`. Cleared by
`start_expedition()`. Null on the endless / fixed path, which is what keeps
`present()`'s RETRY branch reachable.

`expedition_gold` / `expedition_scrap` need no equivalent — they already live on
`GameState`, are not cleared until the *next* `start_expedition()`, and
`present()` reads them directly.

---

## Q2. The §8.5 flow cannot be driven from `RunController`

§8.5 writes victory as five `RunController` steps ending in
`await SceneRouter.go(Place.MAYOR)` then `Hud.quest_result.present(true)`, and
failure symmetrically with `go(Place.INN)`. Taken literally this puts an
`await go(...)` inside `RunController._run_complete()` / `_game_over()`.

`SceneRouter.go()` calls `change_scene_to_file()`, which **frees `main.tscn`** —
and `RunController` is a node inside `main.tscn`. A coroutine that awaited `go()`
from `RunController` resumes on a freed instance: `present()` on the line after
the await never runs. The recovery-button handlers have the same problem in
reverse — by the time the player presses "Rest at the Inn", `RunController` is
long gone, so it cannot be what spends the gold and heals.

### Recommendation — split the work; `QuestResult` drives the rest

- `RunController._run_complete()` / `_game_over()` do only the **synchronous**
  profile work: bank the reward *or* `discard_expedition_loot()`, set
  `completed_quest`, null `quest`, `SaveGame.save_profile()`, then
  `EventBus.quest_finished.emit(victory)` and **return**. No route, no present.
  They still do this *after* the existing jog-home tween / battlefield hold, and
  the endless / fixed `run_summary.present()` paths are untouched.
- `QuestResult` (instanced in `hud.tscn`, an autoload — it survives every scene
  swap) connects `EventBus.quest_finished` in `_ready()` and does
  `await SceneRouter.go(MAYOR|INN)` then `present(victory)`.
- The recovery buttons call `GameState.spend_gold` / `heal_party` /
  `street_sleep_recover` and `SaveGame.save_profile()` from `QuestResult`
  itself. The victory "Retire for the evening" button routes to the inn from
  `QuestResult` too (a `_dismiss_route` field, checked after `hide()`).

This is the same reasoning §3.2 used to justify the router driving `go()` rather
than a hand-rolled add/remove: the thing that outlives both scenes is the only
thing that can orchestrate a swap between them. `GameState` owns
`discard_expedition_loot()` and `street_sleep_recover()` (§2.2 says the failure
flow should reach the mark "through a GameState helper", not by touching the
field), and `QuestResult` calls them.

---

## Q3. How `boss_drop_rarity_floor` reaches the drop roll

§8.2 gives each tier a `boss_drop_rarity_floor` (1 / 2 / 3) and calls it "the
only cheap way to reach an Enhanced Rare". §8.3 says `_build_quest_level()`
marks the last encounter `is_boss` "with its enemy list **led** by a
`quest.boss_pool` pick". Neither says how the floor gets from the `QuestDef` to
`battle_director.start_combat()`, which is where `drop_rarity_floor` is actually
forced onto the boss-slot combatant (`battle_director.gd:220`, today a hardcoded
`maxi(stats.drop_rarity_floor, 1)`).

### Recommendation — carry it on the `EncounterDef`

`EncounterDef.boss_drop_rarity_floor: int = 1`, read only when `is_boss`.
`start_combat()` gains `boss_rarity_floor := 1` and applies
`maxi(stats.drop_rarity_floor, maxi(1, boss_rarity_floor))`. `RunController`
passes `def.boss_drop_rarity_floor`.

The **default of 1** is load-bearing: `_build_endless_level()` /
`_build_whispering_wood_level()` never set the field, so their bosses keep
exactly the "never Common" floor that hardcoded `1` gave them, and
`test_drops.gd` (on §13.3's no-edit list, and it reconstructs
`_effective_drop_rarity_floor` as `maxi(1, …)`) stays green untouched. Only
`_build_quest_level()` raises it.

---

## Q4. The mayor's-office background

§7.5: "New scene. Needs a static background of a village mayor's office
(§12.1)." §12 is the art pass at step 11; CLAUDE.md's rule 2 says to flag when
Meshy would beat procedural art, which it would here — but §14 has already
scheduled that pass.

### Recommendation — placeholder now, Meshy at step 11

`mayor_office.tscn` ships a dark `ColorRect` background with a centred layout
(title, flavour line, the generated quest buttons, a Back button) — the same
shape `inn.tscn` uses, so the real background slots straight behind it at step
11. No Meshy spend this step.

---

## Q5. The expedition gold / scrap rows have no data yet

§8.5's result modal shows "you brought home 47 scrap" — but the combat pickups
that fill `expedition_gold` / `expedition_scrap` are §9, at **step 9**. At step 8
both banks are always 0.

### Recommendation — build the rows, let them read 0

The rows are part of §8.5's modal and cost nothing to author now; wiring them at
step 8 means step 9 adds a faucet, not a modal change. They read "0" for every
quest until step 9, which is honest — nothing was picked up. `QuestReward` (win
only) has real data from step 8.

---

## Q6. A second permanent test

§13.1 names only `test_quest_gen.gd` for step 8 (encounter sequence, one boss and
it is last, boss leads with a `boss_pool` id, counts in range, ids in a pool).

But §8.5's **economy** — a lost quest keeps banked gold and scrap, drops every
*unequipped* item found this trip, keeps equipped gear and town gear; the free
half-heal is `ceil(half missing)` and once per expedition — is the part §8.5
itself argues hardest for ("keeps a failed hard quest from being pure profit").
It reduces to cheap headless invariants, unlike the scene-routing chain.

### Recommendation — ship `test_quest_flow.gd` too

`discard_expedition_loot()` keeps / drops the right items against
`_expedition_inventory_mark`; `street_sleep_recover()` heals the right amount,
sets the flag, revives a downed hero, and is cleared by `start_expedition()`;
`completed_quest` is cleared by `start_expedition()`. Nine checks, headless.

The live `quest_finished` → `await go()` → `present()` chain and the mayor's
button population have **no** permanent test — they need a full scene driven, so
they were covered by a throwaway runtime smoke during the step (boot → mayor →
`quest easy` → forest → simulated victory → mayor's office with the modal up →
"Retire" → inn), exactly as step 6's modal wiring was (step-6 Q7).

---

## Q7. "C, L, C, S, B" vs. the three-value enum

§8.2's sequences use five letters; `EncounterDef.Type` is
`{ COMBAT, LOOT, SHOP }`. There is no `BOSS` type.

### Recommendation — B is the last COMBAT, by position

`encounter_types` stores `EncounterDef.Type` ints; the **last** entry is always a
COMBAT and `_build_quest_level()` flags it `is_boss` and leads its enemy list
with a `boss_pool` pick. So easy's "C, L, C, S, B" is `[0, 1, 0, 2, 0]`.
`test_quest_gen` asserts exactly one `is_boss` and that it is last.

---

## Q8. `enemy_count` is a range; the builders want a number

`QuestDef.enemy_count: Vector2i` is an inclusive min/max. `_random_enemies(pool,
count)` — the shared helper the endless builder uses — takes a fixed `count`.
And the boss fight is `[boss_pool pick] + adds`, so its group size is
`1 + adds`, not a straight `count`.

### Recommendation — one draw per combat, boss total stays in range

`var count := RNG.randi_range(enemy_count.x, enemy_count.y)` per combat
encounter. Non-boss: `_random_enemies(pool, clampi(count, 1, MAX_ENEMIES))`.
Boss: `[boss] + _random_enemies(pool, clampi(count - 1, 0, MAX_ENEMIES - 1))`,
so the boss group **total** is `count`, which is inside `enemy_count` — which is
what `test_quest_gen`'s "every combat group size within `enemy_count`" check
requires (it does not exempt the boss row).

For easy (2–2) the boss fight is boss + 1 add; for hard (3–3), boss + 2.

---

## Q9. Typing `quest` and `start_expedition()`

Step 1 shipped `var quest = null` untyped ("Untyped until QuestDef exists") and
`func start_expedition(q = null)`.

### Recommendation — tighten both

`var quest: QuestDef = null`, `func start_expedition(q: QuestDef = null)`.
`reset_run()` still calls `start_expedition()` with no argument, hitting the
default. `EventBus.quest_started` tightens to `(quest: QuestDef)` in the same
edit (§3.3 always said it would "at step 8 alongside the class").

---

## Q10. The `class_name` cache footgun, again

After adding `scripts/data/quest_def.gd` (`class_name QuestDef`), every headless
test run failed with `Could not find type "QuestDef" in the current scope` and,
downstream, `game_state.gd does not inherit from 'Node'` — because
`game_state.gd` now names `QuestDef` as a type and could not resolve it.

`godot --headless res://tests/<x>.tscn` does **not** rebuild
`.godot/global_script_class_cache.cfg`. A single
`godot --headless --editor --quit-after 20` pass does (`update_scripts_classes |
QuestDef` in its log), after which every headless run resolves the class.

This is the same family as step-5 I8 and step-6 N2 (the running editor not
seeing a new autoload). Treat "add a `class_name` or an autoload → run one
`--editor --headless` pass before the suite" as standard.

---

## What step 8 ships (as built)

- **`scripts/data/quest_def.gd`** — new `QuestDef` (§8.1). `id`, `display_name`,
  `blurb`, `encounter_types: Array[int]`, `gold_reward`, `enemy_pool`,
  `enemy_count: Vector2i`, `boss_pool`, `boss_drop_rarity_floor`,
  `travel_durations: Array[float]`.
- **`resources/quests/{easy,medium,hard}.tres`** — §8.2's three tiers.
  Sequences `[0,1,0,2,0]` / `[0,0,1,0,0,2,0]` / `[0,1,0,0,0,1,2,0,0]`;
  `enemy_count` 2-2 / 2-3 / 3-3; boss drop floor 1 / 2 / 3; reward 200 / 400 /
  600; pools per §8.2's table; `boss_pool` an authoring choice per tier (1 / 2 /
  3 skeletons).
- **`scripts/data/encounter_def.gd`** — `boss_drop_rarity_floor: int = 1` (Q3).
- **`scripts/autoload/game_state.gd`** — `quest: QuestDef` and
  `completed_quest: QuestDef` (Q1, Q9); `build_level()` branches on `quest` first
  (§8.3); `_build_quest_level()` + `_default_quest_travel()` (Q7, Q8);
  `start_expedition(q: QuestDef = null)` clears `completed_quest` and emits
  `quest_started` when `q != null` (Q9); `discard_expedition_loot()` and
  `street_sleep_recover()` (Q2, §8.5).
- **`scripts/battle/battle_director.gd`** — `start_combat(…, boss_rarity_floor
  := 1)`, applied as `maxi(stats.drop_rarity_floor, maxi(1, boss_rarity_floor))`
  (Q3).
- **`scripts/run/run_controller.gd`** — `_next_encounter()` → `_run_complete()`
  when `quest != null` and encounters run out (§8.3); `_arrive()` passes
  `def.boss_drop_rarity_floor`; `_run_complete()` / `_game_over()` do sync
  profile work + `quest_finished.emit()` + `return` on the quest branch, endless
  paths untouched (Q2).
- **`scripts/modals/quest_result.gd` + `.tscn`** — RETRY / VICTORY / FAILURE
  modes. Listens for `EventBus.quest_finished` → `await SceneRouter.go(MAYOR|INN)`
  → `present()` (Q2). New rows `QuestReward` / `ExpeditionGold` /
  `ExpeditionScrap` (Q1, Q5). `PrimaryButton` + `SecondaryButton` HBox replaces
  the lone `RetryButton`; recovery buttons carry §8.5's affordability gates and
  run `GameState` / `SaveGame` in-modal (Q2).
- **`scenes/town/mayor_office.tscn` + `scripts/town/mayor_office.gd`** — new
  (§7.5, Q4). One button per `res://resources/quests/*.tres` in easy→hard order,
  built in `_ready()`; press → `start_expedition(q)` + `save_profile()` +
  `go(QUEST)`; Back / `ui_cancel` → `TOWN`; `_ready()` re-asserts
  `SceneRouter.place = Place.MAYOR`.
- **`scripts/autoload/tuning.gd`** — `INN_STREET_HEAL_FRACTION := 0.5` (§11).
- **`scripts/autoload/event_bus.gd`** — `quest_started(quest: QuestDef)` (Q9).
- **`scripts/autoload/debug.gd`** — `quest <easy|medium|hard>` (§13.4): `load`
  the `.tres`, `start_expedition(q)`, `go(QUEST)`.
- **`scripts/autoload/scene_router.gd`, `scripts/town/town.gd`** — comments:
  `mayor_office.tscn` exists now; only `blacksmith` still hits the bail.
- **`tests/test_quest_gen.{gd,tscn}`** — new (§13.1); 24 checks over 60 builds
  per tier. **`tests/test_quest_flow.{gd,tscn}`** — new (Q6); 9 checks.
  **`tests/test_scene_router.gd`** — MAYOR existence check widened in (§13.1 /
  §13.4).
- **spec** — §14 step 8 marked **Done** with the changeset above; §3.3's
  `quest_started` paragraph updated to past tense with the step-8 emitters named.

**Green bar:** §13.3's no-edit list (`test_economy`, `test_slot_odds`,
`test_upgrades`, `test_autoload_safety`, `test_retarget`, `test_parallax_seam`,
`test_damage_chunk`, `test_endless_level_gen`) plus `test_enhanced_rarity`,
`test_profile_save`, `test_profile_expedition`, `test_drops`,
`test_item_distribution`, `test_scene_router` (14), `test_quest_gen` (24) and
`test_quest_flow` (9) — all passing. A headless runtime smoke drove
boot → `route mayor` → `quest easy` → forest (`quest=easy`, 5-encounter level) →
simulated victory (banked +200 gold, routed to the mayor's office with
`QuestResult` visible) → "Retire for the evening" → inn.

---

## Implementation notes — issues found while building step 8

### N1. `class_name` cache — see Q10

The whole suite hung / errored until one `--editor --headless --quit-after` pass
rebuilt `global_script_class_cache.cfg` to include `QuestDef`. A headless run
with a scene argument does not do this itself. Fold "run one editor pass after
adding a `class_name`" into the step cost, alongside step-5 I8's editor restart.

### N2. `SceneRouter.go()` frees the caller — the whole shape of Q2

The first cut followed §8.5 literally and put `await SceneRouter.go(Place.MAYOR)`
in `RunController._run_complete()`. It silently did nothing after the await:
`change_scene_to_file()` had freed `main.tscn`, and the coroutine's `self` with
it. Moving the route + present onto `QuestResult` (a `Hud` child, so persistent)
and leaving `RunController` with only synchronous work + an `EventBus` emit is
what made the flow reachable. This is worth stating as a rule: **a scene node
must not `await` its own removal.** Anything that has to run *after* a route has
to live on something the route does not free — an autoload, or a `Hud` child.

### N3. A runtime smoke that survives its own scene swaps

Driving boot → town → quest → forest → home headless meant the driver node kept
getting freed by the `change_scene_to_file()` calls it was triggering. The fix
was `reparent.call_deferred(get_tree().root)` in the driver's `_ready()` (the
tree is mid-build during `_ready()`, so the reparent must defer) — it becomes a
persistent sibling of `current_scene` under `/root` and rides out every swap.
Same trick a permanent HUD-level test would need; noted here for whoever writes
the step-9 pickup smoke.

### N4. `RunController._ready()` still connects `dismissed` → `_on_retry`

Left as-is. On a quest ending the route frees `RunController`, so Godot
auto-drops that connection and only `QuestResult`'s own dismiss handling runs.
On an endless game-over nothing routes, `RunController` is alive, and
`_on_retry` fires as before. The two never collide because
`EventBus.quest_finished` is only emitted on the quest branch.

### N5. `add_gold(reward)` counts the reward into `run_stats["gold_earned"]`

`_run_complete()` banks the quest reward through `GameState.add_gold()`, which
bumps `gold_earned`. So the result modal's "Gold earned" row includes the 200 /
400 / 600 reward *and* the separate "Quest reward" row shows it again. Read as
"gold earned this expedition, of which N was the reward" it is not wrong, and
`add_gold()` is the only sane way to credit it (it emits `gold_changed` for the
HUD plate). Left as-is; flagged so it is a decision, not a bug.
