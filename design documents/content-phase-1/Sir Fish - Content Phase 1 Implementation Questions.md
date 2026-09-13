# Sir Fish — Content Phase 1 Implementation Questions

Each entry below records a decision made during implementation that the spec left open,
plus the reasoning, so it can be revisited rather than rediscovered. **Nothing here
blocked implementation** — no critical issue came up; every fork was resolvable with a
documented, reasonable default. See Q6 for the one item worth a look before the first real
reward extra ships, and Q4b for the one real bug this pass found and fixed along the way.

## Status: implementation complete, exit criteria verified

All three steps (objectives & rewards, ClassDef/executor, the generated quest board) are
implemented and green across the full existing test suite plus five new test files
(`test_quest_objectives`, `test_executor`, `test_quest_generator`, and the two touched
by the new content). Spot-verified live in the running game via `play_scene` /
`Debug.command`, not just in headless tests: a 3-hero party (mage/ranger/warrior) fighting
with distinct board icons and party-bar colours, the mayor's office listing the three
authored quests alongside three freshly generated ones with real blurbs/gold/level bands,
and the blacksmith's Forge tab showing a labelled block per hero.

Exit criteria (spec §5), one line each:

1. ✅ `QuestDef.objectives` drives completion; `RunController` checks `quest_objectives_complete()`, not "encounters ran out."
2. ✅ Two objective kinds ship (`ClearEncountersObjective`, `SlayObjective`); the latter can end a quest early (Q1).
3. ✅ Every quest pays gold; content lint enforces it on authored quests, `QuestGenerator` enforces it on generated ones.
4. ✅ `reward_extras` exists, renders in `quest_result.gd`/`mayor_office.gd`, serialises, ships empty everywhere (Q6).
5. ✅ `SlotIcon.innate_for()` deleted; `ClassDef.innate_icon` is the only source.
6. ✅ `SlotMachine._executor_for(kind)` replaces `_swinging_hero()`; orphan fallback and solo-warrior parity both pinned by `test_executor.gd`.
7. ✅ Ranger and mage playable and mechanically distinct (executor ownership); verified live. Since Q4's revert a new profile fields the warrior alone, so they are exercised through tests and a hand-set `active_party`, not normal play.
8. ✅ `ITEM_TYPES` carries no `classes` arrays; `roster_order` lives on `ClassDef`.
9. ✅ Mayor's office offers a generated board (persisted, rerolled each day - Q7) beside the three authored quests; `QUEST_ORDER` deleted.
10. ✅ `_build_endless_level()` reads `AreaDef`; no enemy ids or area strings remain in `game_state.gd`.
11. ✅ A fourth class needs one stats `.tres` + one class `.tres` + one rig profile + one scene, no code change (both registries are directory scans).

---

## Q1 — Where the "won" check runs for an early-completing objective

The spec says completion moves from "the encounter list ran out" to "every objective
reports complete," and that this is what lets a quest end early. It does not say how often
that check runs.

**Decision:** checked once per encounter-resolution boundary, inside
`RunController._next_encounter()`, not continuously mid-fight. A `SlayObjective` that hits
its count mid-combat is not noticed until that encounter's fight actually ends.

**Why:** interrupting a fight in progress to end the run the instant a kill count is hit
would need new combat-abort plumbing (BattleDirector has no "stop, we won" path today,
only "party wiped" / "all enemies dead"). Checking at the existing encounter-resolution
checkpoint reuses everything RunController already does to end a quest cleanly, and it
still satisfies "ends early" — the quest ends after the encounter that completes it,
without walking the remaining ones.

**Why it's safe:** every COMBAT encounter must be fully cleared to advance (there is no
skip/flee), so by the time any encounter resolves, everything that was going to die this
encounter already has. A quest can therefore never be left permanently un-completable: at
worst, a `SlayObjective` whose target isn't reached until the very last (boss) encounter
completes at the same moment `ClearEncountersObjective` would have anyway - the encounter-
count fallback in `RunController._next_encounter()` covers exactly this case. See §3's
`hunt.tres` template for the one place this matters in practice: its `SlayObjective`
targets `&"undead"`, count 2. Only ONE undead kill is deterministically guaranteed (every
`boss_pool` entry is undead-tagged, and the boss always leads the last encounter); a second
undead kill from an earlier regular encounter is near-certain but not mathematically
guaranteed (each regular encounter draws its enemies uniformly from a 2-id pool, only one
of which is undead). In the vanishingly rare roll where it doesn't, the quest still
completes normally at the last encounter via the fallback above - it just doesn't read as
"early" that one time. A tighter guarantee would need a `QuestTemplate`-authored enemy
pool restricted to `require_tags: [&"undead"]` for regular encounters specifically, which
Phase 1 does not build (see §3's own notes for why the simpler shared-pool approach was
judged sufficient here).

## Q2 — Executor ownership only changes the DAMAGE swing's actor

D1's table assigns `BLOCK` to warrior and `DAMAGE_ALL`/`HEAL` to ranger/mage "by echo," but
the only board resolution that currently picks a single acting hero is the aggregated
`DAMAGE` swing (`_hero_swing`). `BLOCK` grants temp armor to the whole living party;
`DAMAGE_ALL` hits every enemy with `source = null`; `HEAL` mends the lowest-HP hero. None
of the three ever asked "which hero did this."

**Decision:** `_executor_for(kind)` is wired into the one place that needed it —
`_hero_swing()`, called with `Kind.DAMAGE`. `BLOCK`/`DAMAGE_ALL`/`HEAL` keep their current
party-wide / all-enemies / lowest-HP resolution untouched. The executor table's other rows
are the reasoning for *why* D1 assigned those kinds to those classes (their kit already
does something similar), not a request to narrow those kinds' resolution scope to one hero.

**Why:** the exit criteria only name `_executor_for(kind)` replacing `_swinging_hero()`,
the orphan-fallback rule, and "a solo warrior plays identically" — all three are satisfied
without touching BLOCK/DAMAGE_ALL/HEAL's resolution. Narrowing them to a single actor would
be a real balance/feel change (e.g. only the mage's living-or-dead status would gate every
mend) that the spec never asks for and Phase 1's "no new art, code and data only" framing
doesn't cover re-balancing.

**Revisit if:** a future pass wants the mage's death to actually silence healing, or wants
per-class VFX/animation on these three kinds - `_executor_for(kind)` is already general
enough to support it.

## Q3 — Armor/trinket types split one-per-class, not shared

Exit criterion 8 ("`Itemizer.ITEM_TYPES` carries no `classes` arrays; class eligibility is
read from `ClassDef`") doesn't say whether armor/trinket types stay warrior-only once the
mapping moves to data, or whether every class can wear them.

**First attempt (reverted): share all six armor/trinket rows across every class.** This
broke `_maybe_auto_equip()`'s determinism, caught by `test_drops.gd`'s D2b check. That
check generates a drop explicitly aimed at one class (`Itemizer.generate_drop(&"mage")`
with only `&"warrior"` in `active_party`) and expects it to land unequipped, since the
mage isn't on the run. With armor/trinket types shared, a "mage" drop can roll e.g. a
helm - which, shared, is *also* wieldable by the warrior - and `_maybe_auto_equip()`
happily equips it onto the warrior instead, silently defeating the point of
`GameState.next_drop_class()`'s coverage weighting: `drops_by_class` records the drop
against the mage, but the gear physically ends up on the warrior. That is a real
bookkeeping lie, not just a test artifact, and the spec's own §3 Step 2b phrasing - "One
class, one asset, one list" - already says the intended shape is one class per item type,
not several.

**Decision:** each of the six armor/trinket rows goes to exactly one class, alongside its
own exclusive weapon type(s):

| Class | Weapons | Armor | Trinket |
|---|---|---|---|
| warrior | axe, sword | mail | idol |
| ranger | bow, dagger | helm | ring |
| mage | staff | shield | amulet |

**Why this exact split:** every class needs at least one type per slot, or
`Itemizer._equippable_slots_for()` permanently excludes that slot for that class's drops.
The names carry no real class flavor (a "Shield" or "Helm" isn't inherently a warrior
item the way a "Staff" is inherently a mage item), so the split is arbitrary by design -
a one-line data edit if a future pass wants different flavor pairings. It also happens to
match `test_level_curves.gd`'s own pre-existing, independently-authored gear model
(`_TYPE_FOR_SLOT`: sword/mail/idol for its solo-warrior simulation), which is an
encouraging sign this is the obvious split rather than an arbitrary one.

**Consequence:** `GameState.new_profile()`'s starter kit generates `&"mail"` now, not
`&"shield"` - the intent ("give the fresh warrior a starter armor piece") is unchanged,
only the concrete type name is, since `&"shield"` moved to the mage.

## Q4 — A new profile's party is the warrior alone (full-roster default reverted)

Step 2c says "`GameState.active_party` grows past one. This is the first real exercise of
Phase 0 Step 5," but recruiting party members is explicitly out of scope for this phase
(§4, and the parked Recruitment Quest Acceptance Test Outline). With no recruit mechanic,
the only way `active_party` grows is if its *default* changes.

**First implementation (reverted 12 Sep 2026):** `new_profile()` set
`active_party = PARTY_ORDER.duplicate()` (mage, ranger, warrior), reading Step 2c as a
request to undo Phase 0's solo flip.

**Decision (owner, 12 Sep 2026):** a new profile's party contains only the warrior. That is
the intended design, not a Phase 0 stopgap. `new_profile()` sets `active_party =
[&"warrior"]` again, and `test_profile_expedition.gd`'s P6 pins it. The ranger and mage stay
fully built (ClassDef, executor, item types, multi-hero town screens) and join only through
a future recruit mechanic.

**What the temporary full-roster default still bought:** it exercised every multi-hero path
for real, and found the index-coupling bug in Q4b, which stays fixed. Step 2c's "grows past
one" is now covered by tests that set `active_party` by hand (`test_executor.gd`,
`test_drops.gd`, and `test_day_night.gd` 12b, which pins the inn bill at party sizes 1-3)
rather than by the default.

**Consequences:**

- The warrior-only starting kit (starter sword + mail) is correct as it stands; there is
  no unarmed ranger or mage on a fresh profile.
- There is no debug command to add a hero to `active_party`, so seeing the ranger or mage
  in the running game means setting it by hand (e.g. `execute_game_script`).
- `test_day_night.gd`'s street/inn assertions (8-11, 14) keep deriving their expected HP
  from `hero_runtime[0]["max_hp"]` rather than the warrior's literal 120. That change was
  made for the full-roster default and is harmless, arguably better, under a solo party.

## Q4b — the index coupling Step 2c predicted: found in two town screens

Step 2c's own text warned "this is the first real exercise of Phase 0 Step 5 - if any
index coupling survived, it surfaces here." It did, in two places neither
`GameState.droppable_classes()` nor `Itemizer` touch: the blacksmith's Forge tab and the
inventory modal's Equipped section both read `GameState.active_party[0]` as *the* hero and
built exactly three slot rows for that one hero only. While `active_party` was the solo
warrior this was invisible - index 0 was the only hero there was. With the roster flip
(Q4), index 0 became the mage, and both screens would have silently shown only the mage's
gear forever, with no way to view (Forge tab) or even see (inventory modal) the ranger's or
warrior's equipment - even though the actual equip/unequip transaction underneath
(`ItemCardActions.equip_hero()`, already multi-class-aware, picks the first *usable*
active-party class per item) worked correctly the whole time. A player could still equip
the ranger from the inventory modal's Carried section; they could just never see what
landed on it, or forge it.

**Fix:** both screens now loop over every `active_party` member, adding a named header
(hidden when the party is one hero, so a solo-warrior save looks exactly as it always has)
above each hero's three-slot block. `blacksmith.gd`'s `_forge_rows` dictionary changed key
shape from `Item.Slot` to `"<hero>_<slot>"` to keep one card addressable per (hero, slot)
pair instead of per slot alone. Verified live in the running game (screenshot: Forge tab
showing a "Mage" header and three empty slots, then a "Ranger" header and its three, with
Warrior scrolled below).

**Not touched, on purpose:** `Debug._cmd_forge()`'s "field leader" (`active_party[0]`)
shorthand for the dev-only `forge` console command, and the same fallback inside
`equip_hero()`/`_eligible_class()` for an unrestricted ("Anyone") item - both already
correct uses of "the first party member" as a deliberate default, not a coupling bug.

## Q5 — `QuestObjective.bind()` added beyond the spec's snippet

The spec's `QuestObjective` code block has `on_event`, `progress`, `is_complete`. It has no
hook for an objective to learn its target count from the quest/level it was duplicated
onto (e.g. `ClearEncountersObjective` needs to know the encounter count; a generated
`SlayObjective` needs its `count` set per-roll by the template, not fixed at author time).

**Decision:** added `func bind(quest: QuestDef, level: LevelDef) -> void: pass`, called once
by `GameState.start_expedition()` right after duplicating the objective list and building
the level. Base no-ops; `ClearEncountersObjective` uses it to read `level.encounters.size()`
as its target.

## Q6 — Reward-extra rendering is generic and untested visually

`QuestDef.reward_extras` ships empty on every authored and generated quest in Phase 1 (D2 /
§4 "out of scope: any reward extra"). `quest_result.gd` and `mayor_office.gd` now walk the
list and render `describe()` generically, but with the list always empty in practice this
path has no exercised visual case — only a unit-level check that an extra's `describe()`
string is rendered when one exists synthetically in a test.

**Revisit when the first real extra ships** (scrap or XP, per the spec's own two named
traps): confirm the generic row actually reads well next to the fixed `QuestReward` /
`ExpeditionGold` rows rather than just trusting the code path.

---

## Step 3 — AreaDef, QuestTemplate, and the generated board

Step 3 shipped in the same commit as Steps 1-2, but the entries above only cover those two.
The code already cites a "Q8" that did not exist (`save_game.gd`). These entries record the
Step 3 forks, and one open problem (Q10).

## Q7 — The generated board rerolls once per day

Spec §1.6 and §3 Step 3 point the board at the forge-stock pattern: generate once, cache,
reroll "only on an explicit refresh". It names no refresh for quests. The first
implementation rerolled only on `new_profile()`, so each profile saw the same three generated
quests forever. That is the exact problem Phase 1 §0 set out to fix ("stops offering the same
three quests forever").

**Decision (owner, 12 Sep 2026):** `GameState.resolve_night()` drops the board
(`quest_board = []`, `quest_board_generated = false`) when it starts a new day. The next
mayor visit regenerates it lazily through `quest_board_offers()`. `night_modal.gd` saves
straight after `resolve_night()`, so the new day's board survives a quit like any other.

**Why the day boundary:** the day/night rhythm allows one quest per day, so a fresh board
each morning means every chance to take a quest sees a fresh roll. For the same reason,
taking or finishing a generated quest does not remove it: the player cannot take another
that day anyway. A night that does not resolve (an unaffordable inn) leaves the board alone.
Unlike the forge, there is no paid refresh button. The endless path never touches the board.

Pinned in `test_quest_generator.gd`'s board-caching block.

## Q8 — No `SaveGame.VERSION` bump for the board

§3.2 says generated quests need `to_dict()`/`from_dict()` "along with a `SaveGame.VERSION`
bump". The serialisation shipped (`QuestDef`, `QuestObjective`, `QuestRewardExtra`); the bump
did not. `VERSION` stays 4.

**Why:** the save file's own versioning policy, recorded on every earlier additive key
(`forge_stock`, `hero_levels`), is to bump on a *meaning change*, never merely to add a key.
`quest_board` and `quest_board_generated` are new keys read with `d.get(key, default)`, and
a save without them loads as "never generated", which is literally true of it.
`test_quest_generator.gd` pins that legacy load. The migration chain from Phase 0 Step 5 is
still there for the first real meaning change, e.g. a change to `QuestDef.to_dict()`'s shape.

## Q9 — AreaDef fields that differ from the spec's snippet

- **`mid_pool` added.** `_build_endless_level()` added a second pool from depth 2. The
  spec's single `pool` could not express that without changing endless difficulty.
  Generated quests read `pool` only.
- **`field_profile` authored, not consumed.** There is one `OverworldField` palette; wiring
  it in is art-dependent (§4).
- **`level_band` is read by the generator only.** Endless mode keeps scaling its band off
  depth (`Tuning.ENDLESS_LEVELS_PER_DEPTH`), since a run with no depth limit cannot use a
  fixed band.

## Q10 — A generated quest spans three levels, starting at the party's level

**The problem:** `QuestGenerator.generate()` originally set `q.level_range =
area.level_band`, which is `(1, 30)` for The Endless Wood, so every generated quest copied
the full band. `_build_quest_level()` interpolates across it, so a five-encounter hunt ran at
levels 1, 8, 16, 23, 30, with the boss bonus on top. The mayor's office showed "Lv. 1–30",
and the underlevelled warning never fired.

**Decision (owner, 12 Sep 2026): the range is 3 levels wide** — 1-3, 2-4, and so on
(`Tuning.QUEST_LEVEL_SPAN`).

**Implementation choice for where the range starts:** at the party's level
(`GameState.hero_level()`, the highest level in `active_party`), passed into
`generate_board()` by `quest_board_offers()`. `QuestGenerator.level_range_for()` clamps it to
sit wholly inside `AreaDef.level_band`, so a level-30 party gets 28-30. The board rerolls each
morning (Q7), so it follows a levelling party without any extra rule. Every quest on one
board shares the same range; the templates differ in length, difficulty and objective, not
level.

**Consequence:** the mayor's underlevelled warning cannot fire on a generated quest while the
anchor is the party's own level. It still applies to the authored quests. If generated quests
should sometimes sit above the party, or should spread across the board, change the start in
`level_range_for()` / `generate_board()` (e.g. offset by slot or by the template's
`difficulty_mult`). The width stays one Tuning constant.

Pinned in `test_quest_generator.gd`: width and band containment for every roll, the sliding
and clamping cases, and a level-7 party's board offering 7-9.

## Q11 — Generator tuning that lives in code, not data

Every item below is a starting value in `quest_generator.gd`, easy to move into
`QuestTemplate`/`AreaDef` when a content pass wants it there:

- `_NAME_ADJECTIVES` ("Deep", "Forgotten", ...). The name fragments are per-area data; the
  adjectives are shared across areas in code.
- Gold: `_GOLD_PER_ENCOUNTER` (50) × encounter count × `gold_formula_mult`, floored at 1
  (D2). Generated quests never pay 0.
- Enemy count: `Vector2i(2, clamp(round(3 × difficulty_mult), 2, MAX_ENEMIES))`.
- `boss_drop_rarity_floor` fixed at 1.
- Templates are picked uniformly *with* replacement, so one board can hold two hunts.

## Q12 — Where the board lives

The spec sketches a `QuestBoard` with an `offers()` method. It shipped as
`GameState.quest_board_offers()` plus a stateless `QuestGenerator` (`RefCounted`, static
functions, not an autoload). This is the same split `Itemizer` (generator) and `GameState`
(persisted stock) already use for the blacksmith, so there is no new autoload and no second
home for profile state.

The hunt template's "can this actually end early" guarantee is covered by Q1.

---

*Nothing above blocked implementation. Q6 is still the thing to check when the first reward
extra ships.*
