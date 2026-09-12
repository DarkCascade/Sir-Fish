# Sir Fish — Content Phase 1 Implementation Spec

**Classes and generated quests.** Phase 1 of the Content initiative.

> Phase 1 **depends entirely on Phase 0** (`../content-phase-0/`). Every step below
> assumes abilities are resources, rigs are profiles, monsters carry tags, the party is
> keyed by id, the roster is derived, and the save file migrates rather than resets.
> Attempting any of this first means doing it twice.
>
> Unlike Phase 0, this phase is all player-visible. It is where the ranger and mage
> come back, where a quest can ask for something other than "walk to the end", and
> where the mayor's office stops offering the same three quests forever.

**Decisions in force** (resolved 12 Sep 2026, recorded in the Content Initiative PRD):

- **D1 — Executor.** Classes differentiate by owning icon kinds on the slot board.
  Board rules are parked in `Sir Fish - Class Idea - Board Rules.md` in this folder.
- **D2 — every quest pays gold.** Other rewards, such as scrap or experience, may join
  it later through an extensible list.
- **D3 — the roster is derived.** Built in Phase 0; `roster_order` moves onto
  `ClassDef` here.

---

## 0. What Phase 1 delivers

Three things, in dependency order:

1. **Quests can have goals and a reward shape that grows.** A quest asks for something
   and reports progress toward it, instead of ending when the encounter list runs out.
   It always pays gold, and can carry more later.
2. **Classes play differently.** A class's identity lives in data and reaches the slot
   board, so three heroes are three heroes and not three reskins.
3. **Quests generate.** The mayor offers a rotating board composed from areas and
   templates, persisted across a save, sitting beside hand-authored quests that still
   work untouched.

---

## 1. Findings this phase closes

### 1.1 There is no objective concept anywhere in the codebase

Verified: zero hits for "objective" across `scripts/` and `resources/`.

Completion means the encounter list ran out (`RunController._next_encounter()` calls
`_run_complete()` when the index passes the end). Failure means the party wiped.
"Kill this boss", "investigate an area", "bring back three relics" and "survive five
waves" have nowhere to live, and `QuestResult` has nothing to report progress against.

### 1.2 There is no place concept either

There is one `OverworldField` with one palette, and `LevelDef.display_name` is a
string. A quest to investigate an area needs an area to investigate, and the endless
builder needs the same object so it can stop hardcoding its own naming.

### 1.3 Quests are three files listed in a const in the mayor's office

`mayor_office.gd` hardcodes `QUEST_ORDER` as easy / medium / hard and loads
`res://resources/quests/<id>.tres` by string. The reward is one flat authored integer,
`QuestDef.gold_reward`. There is no generator, and nothing that would persist a
generated quest across a save.

### 1.4 A class's identity in the core loop is one ternary

`SlotIcon.innate_for()` returns a heal icon for the mage and a damage icon for
everyone else. Since the combat loop redesign the board is the party's **only** source
of actions, so that ternary is the entire mechanical difference between classes.

`SlotMachine._swinging_hero()` returns the first living hero in formation order, and
its own comment says: *"When the mage and ranger return, per-hero icon ownership
decides the swinger here instead."* That comment is the Phase 1 ticket.

### 1.5 Item icons ignore whether their wearer is alive

`SlotMachine._rebuild_bag()` filters **innate** icons through `_living_hero_classes()`,
but adds base and modifier icons for every equipped item with no alive check. A dead
mage's staff keeps putting its icons in the bag. Harmless while no icon has an owner;
it becomes a rule the moment Executor gives icons owners. See Step 2.

### 1.6 The pieces a generator needs already exist and work

- `GameState._build_endless_level()` is a real procedural level builder, with
  level-band interpolation shared with the quest builder via `_interpolated_level()`.
- `forge_stock` / `forge_stock_generated` is a working, tested pattern for "generate
  once, cache on the profile, reroll only on an explicit refresh, save it". A quest
  board is that pattern pointed at quests. Note especially why
  `forge_stock_generated` exists separately from `forge_stock.is_empty()` — buying out
  the stock must not read as "never generated". A quest board has the identical trap.

---

## 2. Decision D1 — Executor

**Resolved.** Three shapes were considered for what a class means on the slot board.

| Shape | What a class is | Outcome |
|---|---|---|
| Contribution | Its innate icon plus the item types it can wear | Rejected. Classes converge back into one bag. |
| **Executor** | **The owner of icon kinds. Each kind is resolved by the class that owns it.** | **Chosen.** Cheapest route to three classes that visibly differ, on the loop as it stands. |
| Board rule | A class rewrites how the board resolves | Parked. See `Sir Fish - Class Idea - Board Rules.md`. |

### 2.1 The executor ceiling — plan for it now

There are four executable icon kinds (`DAMAGE`, `BLOCK`, `DAMAGE_ALL`, `HEAL`); `MULT`
is summed before resolution and has no actor. Three classes fit comfortably. A fourth
can take a kind from a class that owns two. **A fifth class has nothing left to own**,
and D3 anticipates more classes.

This is not a reason to revisit D1 now. It is the recorded revisit trigger: when a new
class has no unowned kind, either add an icon kind or reopen board rules. The side note
covers both routes.

---

## 3. Scope — three steps, in order

### Step 1 — QuestObjective and the reward model

#### 1a. Objectives

Ship objectives first as a **pure refactor with no visible change**: the three authored
quests each get a single `ClearEncountersObjective` and behave exactly as they do today.
`test_quest_flow.gd` and `test_quest_gen.gd` pin that. Only then add a second kind.

```gdscript
class_name QuestObjective extends Resource
@export var description: String = ""          # "Slay the Bone Warden"
func on_event(evt: StringName, payload: Dictionary) -> void: pass
func progress() -> Vector2i: return Vector2i(0, 1)   # current, target
func is_complete() -> bool: return false
```

Concrete subclasses, in the order they are worth building:

| Subclass | Asks for | Reads |
|---|---|---|
| `ClearEncountersObjective` | reach the end of the list | `encounter_resolved` |
| `SlayObjective(id_or_tag, count)` | kill N of something | `combatant_died` |
| `CollectObjective(slot, rarity, count)` | bring back N items | `item_added` |
| `ExploreObjective(area, depth)` | reach a depth in an area | `encounter_resolved` |
| `SurviveObjective(waves)` | last N waves | `encounter_resolved` |

`QuestDef` gains `@export var objectives: Array[QuestObjective]`.

**Event plumbing.** `EventBus` already carries `combatant_died`, `encounter_resolved`
and `item_added`, which covers every subclass above with **no new signals**. Add a
small `QuestRuntime` node under `RunController` that subscribes once, fans events out
to the active objectives, and emits a single `quest_progress(objective, current,
target)` for the HUD.

**Completion moves.** `RunController._next_encounter()` stops meaning "the quest is
won". Won means *every objective reports complete*. That is also what unlocks quests
that end early, which `SlayObjective` needs.

**Objectives are per-expedition state, not authored state.** A `QuestDef` on disk is
shared and cached, exactly like `CombatantStats`. `start_expedition()` must
`duplicate(true)` the objective list into runtime instances, or two runs of the same
quest share a progress counter. This is the same trap `Combatant.level` documents.

#### 1b. Rewards (D2)

**Decision:** a quest reward always contains gold, and may contain other things later.
Scrap and experience are the named candidates.

Encode "always gold" in the shape of the data rather than in a convention:

```gdscript
# QuestDef — gold_reward stays exactly as it is today.
@export var gold_reward: int = 0                         # always paid, always > 0
@export var reward_extras: Array[QuestRewardExtra] = []  # empty in Phase 1

class_name QuestRewardExtra extends Resource
func grant() -> void: pass
func describe() -> String: return ""
# later: ScrapRewardExtra, XpRewardExtra, and the recruitment outline's RecruitRewardExtra
```

**Why gold keeps its own field** rather than becoming one entry among many extras: the
decision is that gold is *required*. A field that always exists says so. A list that
happens to contain gold says so only by convention, and a generator can forget a
convention. It is also purely additive — every current reader of `gold_reward`
(`run_controller.gd`, `mayor_office.gd`, `quest_result.gd`, `debug.gd`, and the three
quest resources) needs no change.

**Phase 1 ships the structure and no extras.** Requirements:

- Phase 0's content lint already asserts `gold_reward > 0` on every authored quest. The
  generator (Step 3) asserts the same on every quest it emits.
- `mayor_office.gd` and `quest_result.gd` render extras through `describe()`.
  `QuestResult` currently writes gold into a single named `QuestReward` row, so extras
  need rows of their own.
- Extras are paid **on victory only**, at the same point gold is, in
  `RunController._run_complete()`. `_game_over()` pays neither.
- Generated quests serialise `reward_extras` along with everything else (§3.2).

**Two traps for when the first extras land**, recorded now so they are not
rediscovered:

- **Experience ordering.** `_run_complete()` calls `GameState.apply_expedition_xp()`
  *before* it pays the quest reward. An `XpRewardExtra` banked into `expedition_xp`
  after that call is never applied, and the next `start_expedition()` zeroes it —
  silently lost. Bank experience extras before the apply call, or grant them through
  `_apply_xp_to_hero()` directly.
- **Scrap has one faucet by design.** The town spec and `quest_def.gd`'s own comment
  define combat pickups as scrap's only source (*"No scrap reward - scrap comes only
  from the combat pickups"*). A `ScrapRewardExtra` is a deliberate amendment to that
  rule, and the comment and the town spec should change in the same commit.

### Step 2 — ClassDef, the executor rule, and the ranger and mage

```gdscript
class_name ClassDef extends Resource
@export var id: StringName = &""
@export var roster_order: int = 0                      # D3 — moved from CombatantStats
@export var innate_icon: StringName = &""              # was SlotIcon.innate_for()
@export var executes: Array[SlotIcon.Kind] = []        # the executor rule (D1)
@export var glyph: Texture2D                           # was ClassIconGlyph._draw()
@export var bar_color: Color = Color.WHITE             # was HeroBars.CLASS_BAR_COLORS
@export var item_types: Array[StringName] = []         # was Itemizer.ITEM_TYPES.classes
```

`CombatantStats` gains `@export var class_def: ClassDef` for heroes.

#### 2a. The executor rule

`SlotMachine._swinging_hero()` becomes `_executor_for(kind) -> Combatant`: the first
living party member, in roster order, whose class executes `kind`.

Suggested starting assignment, grounded in each class's **existing special** so the
board and the character agree about who does what. Authored in the three class
resources, tunable without code.

| Kind | Executor | Echoes |
|---|---|---|
| `DAMAGE` | warrior | the front-line swing it already makes |
| `BLOCK` | warrior | Defend |
| `DAMAGE_ALL` | ranger | the bomb arrow's splash |
| `HEAL` | mage | the heal special and the existing innate heal |
| `MULT` | — | summed before resolution; no actor |

**Orphaned icons fall back to the first living hero.** Finding §1.5 means a dead
class's gear keeps its icons in the bag, and a party may also hold icons no living
member executes — a solo warrior rolling `slot_mend` today, for instance. When a kind's
executor is dead or absent, resolve it through the first living hero in roster order.

This matches the existing rule in `Combatant.slot_attack()` that the party's turn is
never simply lost, and it is what keeps a **solo warrior's play identical** to today.
The alternative — letting orphaned icons fizzle — makes a death compound into a damage
loss the board never shows. Pin the rule with a test.

**Attribution stays as it is.** Chain and mend resolve with `source = null` today, on
purpose, so slot damage never feeds `hero_damage_dealt` (see the comment in
`Combatant.take_damage()`). An executor that *animates* a chain bolt should still pass
`null` as the damage source unless that is revisited deliberately. `hero_damage_dealt`
has no consumer today, so the risk is low, but it should stay a choice.

#### 2b. Invert the item table

`Itemizer.ITEM_TYPES` hardcodes `classes: [&"warrior"]` on every armor and trinket row,
with a comment saying the mage and ranger get their own rows when they return. Rather
than adding two names to nine rows, let `ClassDef.item_types` be the source and have
`weapon_types_for()` read it. One class, one asset, one list.

#### 2c. Re-enable the ranger and mage

- `GameState.active_party` grows past one. **This is the first real exercise of Phase 0
  Step 5** — if any index coupling survived, it surfaces here.
- `Itemizer.droppable_classes()` and the drop-coverage weighting in
  `GameState.next_drop_class()` already handle a multi-class party and were written
  for it. They have been dormant, not absent. Confirm the boss-drop tie-break decision
  from Phase 0 Step 5 now that it is observable.
- `GameState.night_inn_cost()` and `meal_cost()` already multiply by party size, so
  the nightly bill triples. `test_economy.gd` must be re-reasoned, not re-baselined.
- `_maybe_auto_equip()` already gates on `active_party`.

### Step 3 — AreaDef, QuestTemplate, and the generated board

Last, because it consumes every structure above: pools for rosters, tags for
coherence, objectives for goals, the reward shape for payouts, and the forge-stock
pattern for persistence.

```gdscript
class_name AreaDef extends Resource
@export var display_name: String = ""
@export var pool: EnemyPool                    # from Phase 0 Step 4
@export var boss_pool: EnemyPool
@export var level_band: Vector2i
@export var field_profile: StringName          # parallax / palette hook
@export var name_fragments: PackedStringArray  # "the Shallow", "Wood", "Hollow"

class_name QuestTemplate extends Resource
@export var objective_proto: QuestObjective    # duplicated per roll
@export var rhythm: Array[int]                 # encounter type pattern
@export var length_range: Vector2i
@export var difficulty_mult: float = 1.0
@export var gold_formula_mult: float = 1.0     # D2: gold is always computed, never optional
@export var blurb_templates: PackedStringArray
```

```gdscript
# QuestBoard — mirrors the forge stock pattern exactly.
func offers() -> Array[QuestDef]:
    if not GameState.quest_board_generated:
        GameState.quest_board = _generate(3)
        GameState.quest_board_generated = true
    return GameState.quest_board
```

#### 3.1 Why QuestDef stays the runtime contract

`_build_quest_level()`, `mayor_office.gd`, `QuestResult` and the save file all already
speak `QuestDef`. A generator that **emits a plain QuestDef** needs changes to none of
them, the three authored quests keep working beside generated ones, and hand-authored
story quests stay possible forever. Generating `LevelDef` directly throws all of that
away. Do not.

#### 3.2 The one genuinely new persistence problem

A generated quest must survive a quit. The player sees three offers, closes the app,
and expects the same three back.

`Item.to_dict()` / `from_dict()` is the established answer, and the comment on
`to_dict()` explains why it beats saving the resource: a `.tres` embeds the script
path, so moving the file later silently invalidates every player's save. `QuestDef`,
`QuestObjective` and `QuestRewardExtra` all need the same treatment **before any
generator ships**, along with a `SaveGame.VERSION` bump — which Phase 0 Step 5 made
survivable.

#### 3.3 The endless builder folds in

`_build_endless_level()`'s hardcoded pools and `"The Endless Wood — Depth %d"` naming
both become an `AreaDef` lookup. Endless mode stops being a separate content path and
becomes "an area with no objective and no end", which is what it always was.

---

## 4. Out of scope for Phase 1

- New art of any kind. Both phases are code and scene assets only.
- New areas beyond the one that exists. `AreaDef` is the structure; filling it is a
  content pass with an art dependency.
- **Board rules.** Parked by D1. See `Sir Fish - Class Idea - Board Rules.md`.
- **Any reward extra.** D2's list ships empty. Scrap and experience extras are future
  work, and §3 Step 1b records the two traps they will hit.
- Recruiting party members. See
  `Sir Fish - Recruitment Quest Acceptance Test Outline.md` in this folder — the
  proposed acceptance test for both phases, deliberately not scheduled.

---

## 5. Exit criteria

1. `QuestDef.objectives` drives completion, and `RunController` no longer treats "the
   encounter list ran out" as victory.
2. At least two objective kinds ship, one of which can end a quest early.
3. **Every quest pays gold.** Authored quests pass the lint's `gold_reward > 0` check,
   and the generator cannot emit a quest without it.
4. `QuestDef.reward_extras` exists, is rendered by the mayor's office and the result
   screen, serialises with generated quests, and is empty on every shipped quest.
5. `SlotIcon.innate_for()` is gone, replaced by `ClassDef.innate_icon`.
6. `SlotMachine._swinging_hero()` is `_executor_for(kind)`, orphaned icons fall back to
   the first living hero, and a test pins both. **A solo warrior plays identically.**
7. The ranger and mage are playable and mechanically distinct from the warrior and from
   each other.
8. `Itemizer.ITEM_TYPES` carries no `classes` arrays; class eligibility is read from
   `ClassDef`. `roster_order` lives on `ClassDef`.
9. The mayor's office offers a generated board that survives a quit, alongside the
   three authored quests, and `QUEST_ORDER` is gone.
10. `_build_endless_level()` reads an `AreaDef` and contains no enemy ids.
11. **Adding a fourth class is: one stats `.tres`, one class `.tres`, one rig profile,
    one scene — and no code change anywhere.** If it has no unowned icon kind, the
    board rules note says what to do next.
