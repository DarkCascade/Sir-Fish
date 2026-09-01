# Sir Fish — Day & Night Rest Cycle Implementation Spec

Target: make **rest a decision with a price** instead of a button in a room the
player can press whenever they like. Party HP already survives an expedition
(*Town, Inventory, Quests & Forging* §2.1 — "hero HP is profile-scoped, the inn
is the heal"). This pass turns that fact into a **loop**:

> one day = any amount of town business + exactly one quest
> → one night = the inn (paid, full) or the street (free, half of what's missing)
> → the next day.

and gives the inn a new reason to exist once the bed moves out of it: **a meal**,
bought by the day, worth +10% damage on the expedition it precedes (§9).

Written against the `web-performance` branch, on top of *Sir Fish — Town,
Inventory, Quests & Forging Implementation Spec*. Section numbers in the form
**(town §8.5)** refer to that document; bare **§4.2** refers to **this** one.

---

## 0. Scope

### 0.1 What this builds

1. **A day/night state machine** on `GameState` — a three-value `DayPhase`
   that makes "you must quest between two nights" a *provable* property of the
   enum rather than a flag somebody has to remember to clear (§2).
2. **A night after every quest, won or lost.** Today only a *failed* quest
   offers recovery (town §8.5); a won quest hands the player a "Retire for the
   evening" button that heals nothing. Both endings now converge on the same
   choice (§4).
3. **Two new modals** in the Hud modal layer, presented back to back around a
   scene change (§5):
   - **NightChoice** — party health, and the two options.
   - **NightResult** — the same party health *as it was*, then the bars filling
     to their new values.
4. **The meal** — the inn's replacement trade. Once per day, pay per hero, and
   every hero deals `MEAL_DAMAGE_PCT` more damage for the expedition that
   follows (§9). This is the first thing in the game to write
   `Combatant.damage_multiplier` from outside combat, and the seam it uses is
   one `combatant.gd` has been carrying a comment about since v2 (§9.5).
5. **A detached mode for `hero_bars.tscn`**, so the party's bars can be drawn
   in town from `hero_runtime` dictionaries with no `Combatant` and no 3D rig
   alive behind them (§5.4).
6. **A 1.5-second fade** that *is* the route home, replacing today's
   route-then-present ordering on the quest-end path (§4.2, §6).
7. **Resume-safe night state** — quitting between the quest and the night
   choice returns to the choice on next launch, not to a free town day (§8.2).
8. Tests: a new `test_day_night.gd`, plus the two edits §11.2 names.

**The street-sleep heal is unchanged.** `GameState.street_sleep_recover()` and
`Tuning.INN_STREET_HEAL_FRACTION` keep their formula, their name and their
meaning: **half of a hero's missing HP, rounded up** (§3.2). What changes around
them is *when* that function may be called and what guards it — see §1.3.

### 0.2 What this does NOT build — do not drift into these

- **No calendar, no scheduling, no timed town events.** `day_number` is an
  integer that goes up and gets printed on a modal. Nothing reads it as a
  condition. Quests do not expire, stock does not rotate on a day boundary, and
  the blacksmith does not care what day it is. The **one** exception is
  `meal_eaten_today`, which is a boolean cleared by the same call that
  increments `day_number` — not a scheduler (§9.4).
- **No consumables, no inventory food, no second buff.** The meal is a purchase
  with an immediate effect on a `GameState` field. It is not an `Item`, it does
  not occupy a slot, it does not enter `inventory`, and it does not go through
  `Itemizer`. If a second buff type is ever wanted, *that* is the pass that
  generalises this into a table; this pass hardcodes one number (§9.8).
- **No night art.** The town screen is the same town screen. A darkened
  night-time palette for `town.tscn` is a separate, purely cosmetic pass and
  must not be smuggled in here — the fade to black is the whole of this pass's
  "time passed" language.
- **No sleep anywhere but the post-quest modal.** No camping in the forest, no
  bedroll item, no mid-quest rest. The night has exactly one trigger point
  (§2.2), and that is what makes the "one quest per day" rule enforceable.
- **No changes to combat, damage formulas, drops, the forge or the slot
  machine.** The meal multiplies an existing multiplier at an existing call
  site; it does not touch `Combatant.compute_damage()`'s shape (§9.5).
- **No party beyond the warrior.** `active_party` stays `[&"warrior"]` (town
  §4.5). Everything here is written per-hero and loops the array, so a
  three-hero party is a data change; but nothing in this pass grows the party.
- **No mid-quest save/resume.** Unchanged from town §2.4. §8.2's resume covers
  the gap between quest end and night resolution only.
- **No new currency.** Both the bed and the meal are gold sinks. Scrap is not
  involved.

### 0.3 What must keep working with no test edits

| test | what pins it |
|---|---|
| `test_scene_router.gd` | `Place` totality still holds — this pass adds **no** `Place`. Its `boot.gd` code check requires `boot.gd` to keep exactly **one** `new_profile()` and exactly **one** `save_profile()`; §8.2's resume hook must therefore be a *signal emit*, not a save (§7.1). |
| `test_profile_save.gd` | the save round-trip. New keys are additive and load through `d.get(key, default)`, so `VERSION` stays **2** (town §2.4's policy: bump on a meaning change, never merely to add a key) (§8.1). |
| `test_quest_flow.gd` — **its street-sleep formula block** | `street_sleep_recover()` keeps `ceil(half missing)` and `INN_STREET_HEAL_FRACTION` keeps its meaning, so lines ~36–45 and the revival check at ~50–55 pass **untouched**. Only the two `street_sleep_used` assertions move (§11.2). |
| `test_economy.gd` | `Tuning.INN_REST_COST_PER_HERO` keeps its name **and** its value of 50. `MEAL_COST_PER_HERO` is a new constant, not a change to an existing one (§6). |
| `test_slot_odds.gd`, `test_upgrades.gd`, `test_item_distribution.gd`, `test_forge*.gd`, `test_drops.gd`, `test_quest_gen.gd`, `test_endless_level_gen.gd` | nothing in this pass reaches them. In particular `party_bonuses()` gains a key but changes no existing key's value (§9.5). |
| `test_autoload_safety.gd` | no new autoload. The two modals are Hud children, like `QuestResult` (town §3.2). |

`test_profile_expedition.gd:22` asserts `new_profile()` clears
`street_sleep_used`, a field this pass deletes. That is an edit, listed in
§11.2, not a "keep working" entry.

### 0.4 Decisions taken

1. **The night is mandatory and unskippable.** There is no "carry on wounded"
   third button. A party at 3/120 that cannot afford the inn sleeps in the
   street; the street is free precisely so the loop can never soft-lock on
   poverty (§10.1).
2. **The heal is applied at the button press, not at the animation.** The
   NightResult modal is a *replay* of a mutation that has already happened and
   already been saved. Animating a pending mutation would mean a quit during
   the fade loses a paid inn stay (§4.3).
3. **The 1.5s fade doubles as the route home.** The stats screen and the night
   choice are presented over the quest scene (the victory/defeat tableau the
   game already holds on — town §18.1); the fade to black is when
   `main.tscn` is finally freed. This removes a route rather than adding one,
   and matches the brief's wording literally (§4.2).
4. **`Mode.RETRY` is untouched.** The endless / fixed dev path has no quest and
   therefore no day, no night and no meal. `completed_quest == null` still means
   "no night" (§10.4).
5. **The inn keeps its room; the bed becomes a price board and the meal becomes
   the trade.** The paid rest is unreachable under §2.2 and has to go, but the
   building does not: it becomes the place you go *before* a quest rather than
   after one (§9).
6. **The meal is bought by the day and spent by the expedition.** Set in town,
   cleared at quest end (T2) — not at quest start, which would spend it on the
   loading screen (§9.4).

---

## 1. The problems this pass solves

**1.1 Healing is currently free in wall-clock terms.** `inn.gd`'s rest is
gated on gold and nothing else. A player with 200 gold can rest, walk out, walk
back in, and rest again. The cost is real but the *rhythm* is not — there is no
unit of time that a rest consumes.

**1.2 Winning a quest heals nothing, and that reads as a bug.** Today: victory
routes to the mayor's office and offers "Retire for the evening", which
dismisses. Defeat routes to the inn and offers two recovery buttons. So the
*losing* path is the one that restores HP. A player who wins three quests in a
row arrives at the fourth on fumes with no prompt to do anything about it.

**1.3 `street_sleep_used` is a flag defending against a formula.** Its comment
says it plainly: "half of half repeated converges on a full heal (§1.9)". The
formula is right — half of what is missing is exactly the shape a free option
should have, generous when the party is desperate and near-worthless when they
are barely scratched, which is what stops it competing with the bed. What is
wrong is the *guard*: a boolean that four call sites have to keep honest.

Under §2's state machine the **fiction** does the guarding. You cannot sleep
twice without a quest in between, because there is no transition that lets you.
The flag is deleted and the formula it was protecting is not touched.

**1.4 The inn has one button that will stop working and one that never did.**
"Rest for the night" becomes unreachable the moment the night moves to the
post-quest modal (§2.2), and "Sit by the fire" is documented flavour that
deliberately does nothing (town §7.2). Left alone, the room becomes a dead end
the player still has to walk into to find that out. It needs a real trade, and
the natural one is the other thing an inn sells (§9).

**1.5 Nothing in town helps you before a quest, only after one.** The forge
and shop change what you *carry*; nothing changes how the next expedition
*goes*. The meal is a small, one-day, non-permanent lever — the first purchase
in the game whose value depends on which quest you are about to take.

**1.6 There is no clock the player can feel.** "Day 7" on a modal, arriving in
a fixed rhythm, is the cheapest possible way to make a session feel like a
campaign rather than a queue of quests.

---

## 2. The day/night state machine

### 2.1 `GameState` — new state

```gdscript
## [day-night] Where the party is in the day/night loop (§2.2). This enum is
## the whole enforcement mechanism for "one quest per day, one night per
## quest": resolve_night() is reachable ONLY from NIGHT_PENDING, and
## NIGHT_PENDING is reachable ONLY from QUEST, so two nights in a row is not a
## rule anybody has to check - it is a transition that does not exist.
##
## Replaces street_sleep_used, which was a flag guarding the same property by
## hand (§1.3). The HEAL that flag was guarding is unchanged.
enum DayPhase {
	DAY,            # in town. Shop, forge, eat, talk to the mayor. No quest run yet today.
	QUEST,          # an expedition is in flight. GameState.quest is non-null.
	NIGHT_PENDING,  # the quest ended; the night has not been chosen yet.
}

## Profile-scoped, saved (§8.1). A loaded profile that predates this field
## defaults to DAY, which is correct - a save written before this pass could
## only ever have been written in town.
var day_phase: DayPhase = DayPhase.DAY

## [day-night] Days elapsed, 1-based, incremented by resolve_night(). Display
## only: printed on both night modals so the run reads as a campaign (§1.6).
## NOTHING may branch on this value - see §0.2.
var day_number: int = 1

## [day-night] What the last night restored, captured by resolve_night() BEFORE
## it heals, so NightResult can draw the bars as they were and then fill them
## (§4.3). One entry per hero, in hero_runtime order:
##   {stats_id, before_hp, after_hp, max_hp, was_dead}
## Not saved: it is presentation state with a lifetime of one modal.
var last_night_report: Array = []

## [day-night] The meal buff (§9). Percent added to every hero's damage for the
## current or next expedition; 0 when the party is unfed. Profile-scoped and
## SAVED, because a meal bought before a quit must still be there after it.
var meal_pct: int = 0

## [day-night] Whether today's meal has been eaten. Cleared by resolve_night(),
## the same call that advances day_number - so the rhythm is one bed, one meal,
## one quest, and the buff cannot be stacked five times before leaving town
## (§9.4).
var meal_eaten_today: bool = false
```

Deleted: `var street_sleep_used: bool` and every reference to it
(`new_profile()`, `start_expedition()`, `street_sleep_recover()`'s trailing
assignment, `save_game.gd` both directions, `quest_result.gd`,
`test_quest_flow.gd`, `test_profile_expedition.gd`).

**Kept, untouched**: `street_sleep_recover()`'s body and
`Tuning.INN_STREET_HEAL_FRACTION`. The function loses exactly its last line
(`street_sleep_used = true`) and gains a caller (§3.6).

### 2.2 The transitions — the complete set

There are exactly three, and no others may be added without revisiting this
section:

| # | from | to | trigger | who calls it | also does |
|---|---|---|---|---|---|
| T1 | `DAY` | `QUEST` | quest accepted | `GameState.start_expedition(q)` — alongside the existing `quest = q`, and **only when `q != null`** | — |
| T2 | `QUEST` | `NIGHT_PENDING` | quest resolved, win **or** loss | `RunController._run_complete()` / `._game_over()`, in the block that already nulls `quest` and saves | `meal_pct = 0` (§9.4) |
| T3 | `NIGHT_PENDING` | `DAY` | night chosen | `GameState.resolve_night(choice)` | `day_number += 1`, `meal_eaten_today = false` |

**T1 must be guarded on `q != null`, and this is not cosmetic.**
`start_expedition()` takes an optional argument and is called with **none** by
`reset_run()` (the endless path) and by `debug.gd`'s `route quest`
(`debug.gd:361`). Those calls run an expedition with `quest == null` — and
`RunController`'s quest-end blocks, where T2 lives, are both inside
`if GameState.quest != null`. An unguarded T1 would therefore push the endless
path into `QUEST` and **strand it there forever**: no T2, no T3, and the
mayor's §2.3 guard locks the player out of quests permanently on the next real
profile load. One line:

```gdscript
# game_state.gd, start_expedition():
if q != null:
	day_phase = DayPhase.QUEST
```

This is the whole of §10.4's "the dev loop is untouched", made structural.

Read the rules off the table:

- **"The party must undertake a quest after a night is triggered"** — T3 lands
  in `DAY`, and the only edge out of `DAY` is T1. There is no `DAY → *` edge
  that reaches `NIGHT_PENDING`.
- **"Cannot trigger multiple nights in a row"** — `resolve_night()` is the only
  writer of the heal, and it early-returns unless `day_phase == NIGHT_PENDING`.
  A second call in the same phase is a no-op, not a second heal. This is what
  replaces `street_sleep_used` (§1.3).
- **"A day consists of any town activity and one quest"** — town activity is
  unbounded in `DAY`; T1 fires once, and the phase leaves `DAY` when it does.
  The meal is the one piece of town activity that is *not* unbounded, and it is
  rationed by its own per-day flag rather than by the phase (§9.4).

### 2.3 Guards on the existing entry points

Three cheap assertions make the machine self-defending rather than merely
well-behaved. None is reachable through the UI today; all three cover a corrupt
save, a debug command, and the next person to wire a button.

```gdscript
# mayor_office.gd, _accept():
if GameState.day_phase != GameState.DayPhase.DAY:
	return          # already spent today's quest, or a night is owed

# game_state.gd, resolve_night():
if day_phase != DayPhase.NIGHT_PENDING:
	return []       # no night is owed - nothing to heal, nothing to charge

# game_state.gd, buy_meal():
if day_phase != DayPhase.DAY or meal_eaten_today:
	return false    # one meal, one day, and not on the road
```

The mayor's quest buttons and the inn's meal button are additionally
**disabled** rather than silently inert whenever their guard would fire, on the
same affordability pattern `upgrade_button.gd` and `inn.gd` already use (grey
`Color(0.68, 0.65, 0.6, 1)` plus `disabled = true`).

---

## 3. The heal maths

### 3.1 The inn — full

```
after = max_hp
```

Unchanged in effect from `GameState.heal_party()` (town §7.2): every hero in
`active_party` to full, the dead among them revived. `resolve_night()` calls
`heal_party()` for this branch rather than reimplementing it.

**Cost**: `Tuning.INN_REST_COST_PER_HERO * max(active_party.size(), 1)`
= **50 G** with today's solo warrior, 150 G with the full three-hero roster.
Identical to the existing `_inn_cost()` helpers in `inn.gd` and
`quest_result.gd`; this pass moves that helper onto `GameState` as
`night_inn_cost()` so the call sites stop each owning a copy.

### 3.2 The street — half of what is missing, rounded up

**Unchanged from the code in the tree today.** `GameState.street_sleep_recover()`
stays exactly as written, minus its final `street_sleep_used = true`:

```gdscript
for entry: Dictionary in hero_runtime:
	var missing: int = int(entry["max_hp"]) - int(entry["current_hp"])
	if missing > 0:
		entry["current_hp"] = int(entry["current_hp"]) \
			+ ceili(float(missing) * Tuning.INN_STREET_HEAL_FRACTION)
	entry["alive"] = int(entry["current_hp"]) > 0
```

`Tuning.INN_STREET_HEAL_FRACTION := 0.5` keeps its name, its value **and its
comment's claim that it is a fraction of MISSING hp**. Its comment's second
sentence — "once per expedition (`street_sleep_used`), because half of half
repeated converges on a full heal" — is the part that needs rewriting, to point
at §2.2 instead of at a deleted flag.

### 3.3 Worked cases (these are the test table in §11.1)

Warrior, `max_hp = 120`:

| before | missing | + ceil(missing × 0.5) | `after` | dead? |
|---|---|---|---|---|
| 10 / 120 | 110 | +55 | **65** | — |
| 0 / 120 | 120 | +60 | **60** | revived |
| 70 / 120 | 50 | +25 | **95** | — |
| 119 / 120 | 1 | +1 | **120** | — |
| 120 / 120 | 0 | +0 | **120** | — |

**No clamp is needed and none is present.** `ceil(missing / 2) ≤ missing` for
every `missing ≥ 0`, so the result can reach `max_hp` and can never pass it.
Do not add a `mini()` "for safety" — it would be dead code implying a risk that
the formula does not carry.

The last two rows are the reason a second street sleep is worth guarding
against (§1.3): repeated application converges on full, just slowly.

### 3.4 `alive` is always derived

Every write of `current_hp` is followed by
`entry["alive"] = entry["current_hp"] > 0`, never by an assumed `true`. This is
the existing rule in `_reset_hero_runtime()` and `street_sleep_recover()` and it
is what lets a downed hero come back from either option without a special case.

### 3.5 `resolve_night()`

```gdscript
## [day-night] The one and only heal in the game outside combat (§2.2 T3).
## Charges for the inn, applies the chosen recovery, advances the day, and
## returns the report NightResult replays (§4.3).
##
## Returns [] - and mutates NOTHING - if no night is owed, or if the inn was
## chosen and cannot be paid for. The caller checks for the empty array and
## leaves its buttons live; there is no partial application to unwind.
enum NightChoice { INN, STREET }

func resolve_night(choice: NightChoice) -> Array:
	if day_phase != DayPhase.NIGHT_PENDING:
		return []

	# Snapshot BEFORE any mutation - this is what the bars start at (§4.3).
	var report: Array = []
	for entry: Dictionary in hero_runtime:
		report.append({
			"stats_id": entry["stats_id"],
			"before_hp": int(entry["current_hp"]),
			"after_hp": int(entry["current_hp"]),   # rewritten below
			"max_hp": int(entry["max_hp"]),
			"was_dead": int(entry["current_hp"]) <= 0,
		})

	if choice == NightChoice.INN:
		if not spend_gold(night_inn_cost()):
			return []                      # unaffordable: no charge, no heal
		heal_party()                       # town §7.2, unchanged
	else:
		street_sleep_recover()             # §3.2, unchanged

	for i: int in range(report.size()):
		report[i]["after_hp"] = int(hero_runtime[i]["current_hp"])

	day_phase = DayPhase.DAY
	day_number += 1
	meal_eaten_today = false               # a new day, a new meal (§9.4)
	last_night_report = report
	return report
```

Three notes for whoever types this in:

- `heal_party()` calls `_reset_hero_runtime(true)`, which **rebuilds** the
  array. The `report` snapshot is taken first and indexed positionally
  afterwards; that is safe because `_reset_hero_runtime()` iterates
  `active_party` in the same order both times. If `active_party` ever becomes
  mutable mid-day, re-key the report by `stats_id` instead of index.
- `spend_gold()` is checked **before** `heal_party()`, and returns early on
  failure with nothing mutated. `test_day_night.gd` assertion 13 is the guard
  against someone reordering those two lines.
- `meal_pct` is **not** touched here. It is cleared at T2, one step earlier
  (§9.4) — by the time the night is resolved it is already zero, and clearing
  it again here would hide a T2 that had gone missing.

---

## 4. The flow, end to end

### 4.1 Sequence

```
                          ┌── RunController ───────────┐
 quest resolves ─────────►│ bank reward / discard loot │
   (win or lose)          │ completed_quest = quest    │
                          │ quest = null               │
                          │ meal_pct = 0               │  T2
                          │ day_phase = NIGHT_PENDING  │
                          │ SaveGame.save_profile()    │
                          │ EventBus.quest_finished(v) │
                          └────────────┬───────────────┘
                                       │      (still on main.tscn — the
                                       ▼       victory/defeat tableau)
                       ╔═══════════════════════════════╗
                       ║  QuestResult  (existing)      ║   stats screen
                       ║  "QUEST COMPLETE" / "DEFEATED"║
                       ║  [ Make camp ]                ║
                       ╚═══════════════┬═══════════════╝
                                       │ dismissed
                                       ▼
                       ╔═══════════════════════════════╗
                       ║  NightChoice  (new, §5.1)     ║
                       ║  Day 4 · party health         ║
                       ║  [ Stay at the Inn — 50 G ]   ║
                       ║  [ Sleep in the street — free]║
                       ╚═══════════════┬═══════════════╝
                                       │ GameState.resolve_night(choice)   T3
                                       │ SaveGame.save_profile()
                                       ▼
                          fade to black ......... 1.5 s
                          change_scene_to_file(town.tscn)
                          fade in ............... 0.75 s
                                       │
                                       ▼
                       ╔═══════════════════════════════╗
                       ║  NightResult  (new, §5.2)     ║
                       ║  bars start at before_hp,     ║
                       ║  fill to after_hp             ║
                       ║  [ Good morning ]             ║
                       ╚═══════════════┬═══════════════╝
                                       ▼
                             town.tscn, DayPhase.DAY
                          (unfed: the inn is open again)
```

### 4.2 Who drives it

`QuestResult` already owns the route-and-present coroutine for exactly the
reason this pass needs: `SceneRouter.go()` frees `main.tscn`, so anything that
awaits it from `RunController` resumes on a freed node (town §8.5). The same
argument applies to the whole chain, so **the chain is driven from the Hud
children**, which outlive the swap:

```gdscript
# quest_result.gd — replaces _on_quest_finished()
func _on_quest_finished(victory: bool) -> void:
	present(victory)                 # over main.tscn — NO route first
```

and the night hand-off, in `night_modal.gd` (the script that owns both new
modals — §5.3):

```gdscript
func _ready() -> void:
	Hud.quest_result.dismissed.connect(_on_result_dismissed)

func _on_result_dismissed() -> void:
	if GameState.day_phase != GameState.DayPhase.NIGHT_PENDING:
		return                       # RETRY / dev path - no night (§10.4)
	choice_panel.show()
```

**What this changes about the existing code**: the two `SceneRouter.go(MAYOR |
INN)` calls in `_on_quest_finished()` are deleted. The victory path's
`_dismiss_route = SceneRouter.Place.INN` and the whole `Mode.FAILURE` button
branch in `_configure_buttons()` are deleted with them — both endings now show
one button, `"Make camp"`, and dismiss into the night (§7.2).

`main.tscn` therefore stays alive for two modals longer than it does today.
That is a live concern on the `web-performance` branch, and it is bounded:
`_run_complete()`/`_game_over()` have already called `director.stop_combat()`
and `world.set_scroll_speed(0.0)`, so the scene behind the scrim is an idle
tableau, not a running battle. Do not add work to it; do not add a "restart the
parallax" flourish behind the modals.

### 4.3 Ordering: mutate, save, *then* animate

The night is applied **at the button press**, before the fade. The NightResult
modal is a replay of `last_night_report`, not a driver of it.

The alternative — hold the mutation until the bars finish filling — was
rejected: a quit or a crash during a 1.5-second fade would then charge nothing
and heal nothing after the player has already committed, or worse, charge and
not heal depending on where the save landed. Applying first makes the sequence
atomic with respect to the save file, and makes NightResult a pure view that can
be re-presented, skipped, or unit-tested without touching state.

The consequence to keep in mind: **`hero_runtime` is already at `after_hp` when
NightResult opens.** The bars must be seeded from `before_hp` explicitly and
must not read live state (§5.2).

---

## 5. The screens

### 5.1 NightChoice

`scenes/modals/night_modal.tscn`'s `ChoicePanel` (§5.3), instanced under
`Hud/ModalLayer`, sibling to `QuestResult` and `InventoryModal`. Authored in the
editor per CLAUDE.md's "prefer inspector properties over code" — the script
writes text, numbers and enabled-state, never positions.

Contents, top to bottom:

- **Scrim** — `ColorRect`, fades `0 → 1` over 0.5 s, matching `QuestResult`'s.
- **Title** — `"NIGHTFALL"`, `Tuning.C_GOLD`.
- **Day line** — `"Day %d" % GameState.day_number`, small caps under the title.
- **Party rows** — one detached `hero_bars.tscn` per entry in
  `GameState.hero_runtime` (§5.4), **static**: seeded with
  `set_health_fraction()`, no tween. This is the "show party health" the brief
  asks for, and it is the *before* picture in both modals.
- **PrimaryButton** — `"Stay at the Inn  —  %d G" % GameState.night_inn_cost()`.
  Disabled and greyed to `Color(0.68, 0.65, 0.6, 1)` when
  `GameState.gold < cost`, re-evaluated on `EventBus.gold_changed` exactly as
  `inn.gd._refresh_rest_button()` does today.
- **SecondaryButton** — `"Sleep in the street  —  free"`. Always enabled
  (§10.1).

`ui_cancel` is **swallowed**, not routed. There is no way out of this modal but
through one of the two buttons (§0.4.1).

### 5.2 NightResult

The same scene's `ResultPanel`, same authoring rules.

- **Title** — `"MORNING"` on the inn branch, `"A COLD MORNING"` on the street
  branch. Subtitle carries the flavour: the inn reuses `inn.gd`'s existing line
  *"You wake with the dawn, every wound closed."*; the street gets a new one.
- **Party rows** — one detached `hero_bars.tscn` per `last_night_report` entry,
  seeded at `before_hp / max_hp` **and held there for `NIGHT_BAR_HOLD` (0.35 s)**
  so the player reads the damage before it goes away. Then, staggered by
  `NIGHT_BAR_STAGGER` (0.12 s) per hero:

  ```gdscript
  row.show_hp(e["before_hp"], e["max_hp"])          # static seed
  await ... hold ...
  row.tween_hp(e["after_hp"], e["max_hp"], Tuning.NIGHT_BAR_FILL)
  ```

  `tween_health_fraction(fraction, heal_flash = true)` on `CombatantBarsBase`
  already does the fill and the green heal flash; the row wrapper only needs to
  drive the `hp_text` number in step with it (§5.4).
- **A revived hero** (`was_dead == true`) drops its `set_dead()` grey
  (`modulate = Color(0.45,0.45,0.52)`) back to `Color.WHITE` over the same
  window, so the revival is legible as an event rather than a colour that was
  always there.
- **PrimaryButton** — `"Good morning"`. Dismiss hides the modal; nothing routes,
  because the town scene is already up behind it.

The bars must be **seeded from the report**, never from `hero_runtime` — see
§4.3.

### 5.3 One script, two panels

Both modals live in one scene and one script,
`scripts/modals/night_modal.gd`, with two sibling panels under a shared root:

```
NightModal (Control, full-rect, MOUSE_FILTER_IGNORE when hidden)
├── Scrim         (ColorRect)
├── ChoicePanel   (PanelContainer)  → §5.1
└── ResultPanel   (PanelContainer)  → §5.2
```

They are two halves of one interaction separated by a scene change; splitting
them into two scenes would mean two `Hud` children, two `_ready()` bindings and
a signal between them to carry `last_night_report` across a swap it does not
need to cross (it is on `GameState`). One script, one `Mode { CHOICE, RESULT }`,
same shape as `QuestResult`'s existing three-mode switch.

### 5.4 Detached mode for `hero_bars.gd`

`hero_bars.setup()` takes a `Combatant`, and `refresh()` early-returns on a null
one. In town there are no `Combatant`s and spawning three 3D rigs behind a modal
to draw three 2D bars is not acceptable on the web build.

Add **~15 lines** and change nothing on the battle path:

```gdscript
## [day-night] Draw this card from profile data instead of a live Combatant,
## for the night modals in town (§5.4). `combatant` stays null, so refresh()
## keeps early-returning and NOTHING on the battle path changes: poll_health is
## false, no _process reads it, and party_bars.gd never sees one of these.
func setup_detached(stats: CombatantStats) -> void:
	combatant = null
	base_fill_color = CLASS_BAR_COLORS.get(stats.id, stats.accent_color)
	chip.color = base_fill_color
	health_fill.color = base_fill_color
	var has_glyph: bool = stats.id in KNOWN_ICON_CLASSES
	chip_glyph.set_kind(stats.id if has_glyph else &"")
	chip_label.text = stats.display_name.substr(0, 1).to_upper()
	chip_label.visible = not has_glyph
	buff_shield.visible = false

## Snap. Used to seed the "before" picture in both night modals.
func show_hp(current: int, maximum: int) -> void:
	_last_hp_shown = current
	hp_text.text = "DEAD" if current <= 0 else "%d" % current
	set_health_fraction(float(current) / float(maxi(maximum, 1)))
	modulate = Color(0.45, 0.45, 0.52) if current <= 0 else Color.WHITE

## Fill. `hp_text` counts up in step with the bar rather than snapping at the
## end - the number and the fill are one statement (hero_bars.gd's own rule).
func tween_hp(target: int, maximum: int, duration: float) -> void:
	var from: int = _last_hp_shown
	_last_hp_shown = target
	_dead = false
	tween_health_fraction(float(target) / float(maxi(maximum, 1)), true, duration)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: int) -> void: hp_text.text = "%d" % v,
		from, target, duration)
	tw.tween_property(self, "modulate", Color.WHITE, duration)
```

`CombatantStats` comes from `GameState.get_stats(entry["stats_id"])`, which is
already loaded for every id in `res://resources/stats/`.

`tween_health_fraction()` hardcodes **0.25 s** (`combatant_bars_base.gd:98`),
which is a combat-paced tween and far too quick to read as a night's rest. Give
it the duration as a third parameter defaulted to the current value, so every
existing call site is unchanged:

```gdscript
func tween_health_fraction(fraction: float, heal_flash: bool = true,
		duration: float = 0.25) -> void:
```

The green heal-flash pair below it (0.15 + 0.15) stays as-is — it is a
punctuation mark, not a fill, and stretching it to 0.9 s would read as a
different effect.

---

## 6. Timings and Tuning

### 6.1 New constants

```gdscript
# --- [day-night] The night (§3, §6) -----------------------------------------
## The night's fade-to-black - the "time passed" beat, and the scene change
## home (§4.2). Long on purpose: it is the only place in the game where the
## screen is deliberately empty, and it is what stops the loop reading as
## "quest, quest, quest".
const NIGHT_FADE_OUT := 1.5
## Coming back is not the same beat as leaving, and 1.5 s of waiting to see a
## town you have already seen is dead time. Half, and no more.
const NIGHT_FADE_IN := 0.75

## NightResult's bar choreography (§5.2). Hold, then fill, staggered per hero -
## the same cadence as QuestResult's stat rows (0.08 s apart), slowed slightly
## because there are three of these, not fifteen.
const NIGHT_BAR_HOLD := 0.35
const NIGHT_BAR_FILL := 0.9
const NIGHT_BAR_STAGGER := 0.12

# --- [day-night] The meal (§9) ----------------------------------------------
## Percent added to every hero's damage for one expedition. A round number on
## purpose: the player is told "+10% damage" and that is exactly what the
## multiplier does - no hidden diminishing curve, no per-class variation.
const MEAL_DAMAGE_PCT := 10
## Per hero, like the bed. 30 against the bed's 50: a night and a meal together
## are 80 G of the easy quest's 200 G reward, so a fed, rested run of the
## cheapest quest still profits - but not by much, and not on a loss (§9.2).
const MEAL_COST_PER_HERO := 30
```

One more constant, `C_MEAL`, belongs to the palette block rather than here and
is specified with the icon that uses it (§9.7.5).

### 6.2 Constants kept, unchanged

- `INN_REST_COST_PER_HERO := 50` — name, value and meaning (the price per hero
  of a full-heal night). Its only caller moves; the constant does not.
- `INN_STREET_HEAL_FRACTION := 0.5` — name, value and meaning (a fraction of
  **missing** hp, §3.2). Only its doc-comment's second sentence changes, to
  point at §2.2's state machine instead of the deleted `street_sleep_used`.

Nothing in `tuning.gd` is deleted by this pass.

### 6.3 The fade

`SceneRouter.FADE_TIME` (0.18) stays the default for every ordinary route.
`go()` gains optional parameters rather than a second function:

```gdscript
func go(to: Place, fade_out: float = FADE_TIME, fade_in: float = FADE_TIME,
		force: bool = false) -> void:
```

The night calls
`SceneRouter.go(Place.TOWN, Tuning.NIGHT_FADE_OUT, Tuning.NIGHT_FADE_IN, true)`.
Every existing call site is unchanged and behaviour-identical, including the
`.bind(Place.TOWN)` connections in `town.gd`, `inn.gd`, `blacksmith.gd` and
`mayor_office.gd`, which bind only the first argument.

`force` skips `go()`'s existing `if to == place: return` early-out. Without it
the night's fade is silently dropped whenever the player is already routed to
`TOWN` — which is exactly what happens on the §8.2 resume path, every time.
One fade implementation with a flag, not two implementations.

---

## 7. Changes to existing files

| file | change | § |
|---|---|---|
| `scripts/autoload/tuning.gd` | +7 constants and `C_MEAL` (§9.7.5), −0; two doc-comments reworded | §6, §9.7.5 |
| `scripts/autoload/game_state.gd` | `DayPhase`, `NightChoice`, `day_phase`, `day_number`, `last_night_report`, `meal_pct`, `meal_eaten_today`, `resolve_night()`, `night_inn_cost()`, `meal_cost()`, `buy_meal()`, `meal_multiplier()`; `party_bonuses()` gains `meal_pct`; delete `street_sleep_used`; T1 in `start_expedition()` | §2, §3.5, §9 |
| `scripts/autoload/save_game.gd` | save/load `day_phase`, `day_number`, `meal_pct`, `meal_eaten_today`; drop `street_sleep_used` | §8.1 |
| `scripts/autoload/scene_router.gd` | `go()` gains `fade_out`, `fade_in`, `force` | §6.3 |
| `scripts/autoload/event_bus.gd` | `signal profile_ready()` | §8.2 |
| `scripts/run/run_controller.gd` | T2 in both `_run_complete()` and `_game_over()` | §2.2 |
| `scripts/battle/combatant.gd` | `apply_party_bonuses()` recomputes `damage_multiplier` from source — **the compounding fix, §9.5** | §9.5 |
| `scripts/modals/quest_result.gd` | no route on `quest_finished`; `Mode.FAILURE` buttons collapse to one `"Make camp"`; delete `_inn_cost()` and the street branch | §4.2, §7.2 |
| `scripts/overlay/hero_bars.gd` | `setup_detached()`, `show_hp()`, `tween_hp()` | §5.4 |
| `scripts/overlay/combatant_bars_base.gd` | optional `duration` on `tween_health_fraction()` | §5.4 |
| `scripts/console/bonus_strip.gd` | `&"meal_pct"` last in `ROWS`, a `_format()` percentage case, a `_draw_glyph()` arm, `TEX_MEAL` preload | §9.6 |
| `scripts/town/mayor_office.gd` | `day_phase` guard, disabled buttons, "fed" line | §2.3, §9.6 |
| `scripts/town/inn.gd` | rest action → price board; meal action added | §9 |
| `scripts/boot.gd` | `EventBus.profile_ready.emit()` after the currency nudges — **no new save** | §8.2, §0.3 |
| `scenes/town/inn.tscn` | `RestButton` → `PriceBoard` label; `MealButton` added | §9 |
| `scenes/hud/hud.tscn` | `NightModal` instanced under `ModalLayer`; `@onready var night_modal` on `hud.gd` | §5.3 |

New: `scenes/modals/night_modal.tscn`, `scripts/modals/night_modal.gd`,
`tests/test_day_night.gd` + `.tscn`, and `assets/icons/bonus_meal.png` +
`.import` — generated and imported per §9.7, **`process/size_limit=256`**.

### 7.2 What `QuestResult` looks like afterwards

`Mode` stays three-valued. What changes is that `VICTORY` and `FAILURE` now
differ **only** in their heading, subtitle and stat rows — never in their
buttons:

```gdscript
Mode.RETRY:
	primary_button.text = "RETRY"
Mode.VICTORY, Mode.FAILURE:
	primary_button.text = "Make camp"
	# _dismiss_route stays -1: NightModal takes it from here (§4.2).
```

`secondary_button` is hidden in all three modes. It stays in the scene — it is
authored chrome and the next modal to want two buttons will want it back.

---

## 8. Persistence

### 8.1 Save format

Four additive keys, no `VERSION` bump (town §2.4's policy — bump on a meaning
change, never merely to add a key):

```gdscript
"day_phase": int(GameState.day_phase),
"day_number": GameState.day_number,
"meal_pct": GameState.meal_pct,
"meal_eaten_today": GameState.meal_eaten_today,
```

and on load:

```gdscript
GameState.day_phase = int(d.get("day_phase", GameState.DayPhase.DAY)) as GameState.DayPhase
GameState.day_number = int(d.get("day_number", 1))
GameState.meal_pct = int(d.get("meal_pct", 0))
GameState.meal_eaten_today = bool(d.get("meal_eaten_today", false))
```

`street_sleep_used` disappears from the written payload. A save file written
before this pass still loads: the key is simply never read, `day_phase` defaults
to `DAY` and the party defaults to unfed — all of which are right, because every
save that could exist was written in town or at a quest boundary.

`last_night_report` is **not** saved. It is presentation state with a lifetime
of one modal; a resume presents the choice again (§8.2), not the result.

### 8.2 Resuming a pending night

`day_phase = NIGHT_PENDING` is written to disk by T2, *before* the stats screen
appears. So a player who force-quits between the quest ending and picking a bed
reloads into town owing a night — and without a guard, walks into the mayor's
office and takes a second quest on the same day at whatever HP they had left.

The hook: `boot.gd` emits `EventBus.profile_ready()` after its existing currency
nudges; `night_modal.gd` listens, and on `NIGHT_PENDING` presents `ChoicePanel`
directly over the town screen. No stats screen — `run_stats` is expedition-scoped
and was never saved, so there is nothing to show.

`boot.gd` gains **one emit and no save**, which is what keeps
`test_scene_router.gd`'s `boot.gd` code check green (§0.3).

---

## 9. The inn: a bed you cannot buy, and a meal you can

### 9.1 What the room is for now

The night moves out of the inn to the post-quest modal (§2.2), which leaves the
building with two buttons that no longer work: a rest that is unreachable and a
fireside that never did anything (§1.4). The room stays — it has art, a `Place`,
and a routing test that asserts its scene exists — and it changes job:

> The inn is where you go **before** a quest, not after one.
> It tells you what tonight will cost, and it sells you the meal.

### 9.2 The price board (replaces `RestButton`)

`RestButton` becomes a non-interactive `Label`, `PriceBoard`:

> *A bed for the night — 50 G, payable at nightfall.*

with the number from `GameState.night_inn_cost()`, so it tracks party size and
`INN_REST_COST_PER_HERO` without a second copy of the arithmetic. `_on_rest()`
and `_refresh_rest_button()` are deleted.

This is not decoration. A player who spends their last 60 G at the forge and
then takes a hard quest needs to have been told, somewhere, that the bed costs
50 — and today nothing tells them until the night modal disables the button.

`FireButton` and its `_flavour` line stay exactly as they are.

### 9.3 The meal (new `MealButton`)

> *Order a meal — 90 G* → **+10% damage for your next expedition.**

(90 G = `MEAL_COST_PER_HERO × 3` at the full roster; **30 G** with today's solo
warrior.)

- Once per day (§9.4).
- Buyable only in `DayPhase.DAY` — you cannot eat on the road, and you cannot
  eat while a night is owed.
- Disabled and greyed when unaffordable, already eaten, or out of phase, on the
  established `inn.gd` affordability pattern; the label states *which* when
  disabled (`"Order a meal — eaten today"`), because a grey button with no
  reason is the failure mode this codebase's `_refresh_rest_button()` was
  written to avoid.
- On success, the existing `_flavour` label carries the confirmation:
  *"A ribeye off the bone, bread to mop the plate, and a second helping. You'll
  fight better for it."*

### 9.4 Bought by the day, spent by the expedition

Two fields, two different lifetimes, and the split is the whole design:

| field | set by | cleared by | why there |
|---|---|---|---|
| `meal_pct` | `buy_meal()` | **T2**, quest end | the buff itself. Cleared when the expedition it paid for is over — win or lose. |
| `meal_eaten_today` | `buy_meal()` | **T3**, `resolve_night()` | the ration. Cleared by the night, so exactly one meal fits in a day. |

Read the consequences off the table:

- **A meal cannot be banked.** Eat, quest, and it is gone at T2 whether the
  quest went well or not. You cannot eat on three consecutive days and take one
  quest at +30%.
- **A meal cannot be stacked.** `meal_eaten_today` blocks the second purchase in
  the same day, and `meal_pct` is assigned (`= MEAL_DAMAGE_PCT`), never
  accumulated (`+=`).
- **A meal survives a quit.** Both fields are saved (§8.1), so buying a meal and
  closing the game does not lose 30 G.
- **Clearing at T2 rather than T1 is load-bearing.** T1 fires when the quest is
  *accepted* — clearing there would spend the meal on the loading screen, and
  the player would arrive at the first encounter unfed having paid for lunch.

```gdscript
## [day-night] The inn's meal (§9.3). One per day, in town only. Returns false
## and spends nothing if the guard or the gold check fails - the caller leaves
## its button live rather than unwinding a partial purchase.
func buy_meal() -> bool:
	if day_phase != DayPhase.DAY or meal_eaten_today:
		return false
	if not spend_gold(meal_cost()):
		return false
	meal_pct = Tuning.MEAL_DAMAGE_PCT      # assigned, never accumulated
	meal_eaten_today = true
	EventBus.party_bonuses_changed.emit(party_bonuses())   # §9.5
	return true

func meal_cost() -> int:
	return Tuning.MEAL_COST_PER_HERO * maxi(active_party.size(), 1)

## The meal as a multiplier, for combatant.gd. 1.0 when unfed.
func meal_multiplier() -> float:
	return 1.0 + float(meal_pct) / 100.0
```

`inn.gd` calls `buy_meal()` then `SaveGame.save_profile()` — the same
spend-then-save shape `_on_rest()` used, and one that town §2.4's "When to save"
list already covers as a town profile mutation.

### 9.5 Wiring the buff into damage — and the compounding trap

`Combatant` has been carrying the seam for this since v2. From `combatant.gd:28`
and `:43`:

```gdscript
var damage_multiplier: float = 1.0        # party damage buff + item dmg_pct
## The dmg_pct share of damage_multiplier, kept apart so the party damage buff
## can be divided back out without wiping the item bonus (spec 17.3 / 21-D13).
var _item_pct_multiplier: float = 1.0
```

A grep confirms **nothing currently writes `damage_multiplier` from outside
`combatant.gd`** — the "party damage buff" the comment names has no source in
the tree today. The meal becomes that source, and it is the reason the field was
split in two.

`party_bonuses()` gains one key, kept **separate** from `dmg_pct` rather than
summed into it, so the strip can show the meal as its own thing and so no
existing consumer's number changes:

```gdscript
var out := {
	"dmg_flat": 0,
	"dmg_pct": 0,
	"meal_pct": meal_pct,      # [day-night] §9.5 - NOT from an item, and not
	                           # summed into dmg_pct: it is a separate
	                           # multiplier and a separate glyph (§9.6).
	...
}
```

> **The trap.** `apply_party_bonuses()` currently reconstructs the external buff
> by dividing it back out of the previous value:
>
> ```gdscript
> var buff: float = damage_multiplier / _item_pct_multiplier
> _item_pct_multiplier = 1.0 + float(b["dmg_pct"]) / 100.0
> damage_multiplier = buff * _item_pct_multiplier
> ```
>
> That round-trip is safe only while `buff` is always 1.0. Feed the meal in and
> it **compounds**: `apply_party_bonuses()` runs on every
> `party_bonuses_changed` emit (`battle_director.gd:66-68`) and again on every
> spawn (`:210`), so a fed party's multiplier walks 1.10 → 1.21 → 1.33 across a
> few equip changes. This is silent, it only shows up as damage numbers that
> are subtly too big, and it is the single most likely bug in this pass.

Recompute from source instead:

```gdscript
func apply_party_bonuses() -> void:
	if not is_hero:
		return
	var b := GameState.party_bonuses()
	bonus_flat_damage = int(b["dmg_flat"])
	_item_pct_multiplier = 1.0 + float(b["dmg_pct"]) / 100.0
	# [day-night] §9.5: recomputed from GameState every time, NEVER from the
	# previous value of damage_multiplier. The old `damage_multiplier /
	# _item_pct_multiplier` round-trip compounded the meal on every
	# party_bonuses_changed emit (battle_director.gd:66).
	damage_multiplier = GameState.meal_multiplier() * _item_pct_multiplier
```

`_item_pct_multiplier` stays — it is still the item share, still separate, and
`projectile.gd:45` still reads `source.damage_multiplier` unchanged. The damage
formula at `combatant.gd:331` is untouched.

### 9.6 Showing it

Three places, cheapest first:

1. **`bonus_strip.gd`** — add `&"meal_pct"` to `ROWS`. The strip already omits
   any entry whose value is zero, so an unfed party sees nothing new, and it
   already refreshes on `party_bonuses_changed`, which `buy_meal()` emits. This
   gets the buff into **both** the battle overlay and the shop modal for one
   array entry, one `match` arm and one icon.

   Three details, all of which the file's own conventions decide for you:

   - **Position: last among the numerics**, after `&"slot_mend"` and before the
     element chip. `ROWS`' comment says the order is fixed "so the strip does
     not reshuffle as it fills" — inserting the meal mid-list would move the
     five existing glyphs sideways for a player who is mid-run and has learned
     where they sit.
   - **`_format()`**: `meal_pct` joins the percentage branch with `dmg_pct` and
     `slot_mend`, so it renders `+10%`, not `+10`.
   - **`_draw_glyph()`**: a new `"meal_pct"` arm,
     `draw_texture_rect(TEX_MEAL, box, false, Tuning.C_MEAL)`.

2. **`mayor_office.gd`** — one line above the quest list when `meal_pct > 0`:

   > *"The party is well fed. +10% damage."*

   in `Tuning.C_MEAL`, hidden entirely when `meal_pct == 0` (a "not fed" line
   would be nagging, and the strip already covers the absence by omission).
   This is where the player chooses which quest to take, so it is the one place
   the buff changes a decision rather than merely reporting itself — the meal
   is bought before the choice and spent after it, and this line is the only
   thing joining those two moments. It is part of the pass, not a nice-to-have.

3. **`inn.gd`** — the flavour line after purchase (§9.3).

### 9.7 The meal icon — generation and import plan

Per CLAUDE.md rule 2, this is a Meshy case and not a procedural one: it is an
icon with a recognisable silhouette that has to sit beside five existing
Meshy-generated glyphs and not look out of place. A `_draw()` polygon steak would
be the axe-icon mistake again.

**Cost: 9 credits** (one `meshy_text_to_image` run, nano-banana-pro). Budget 18
if the first read fails §9.7.3's check. Confirm before spending, per the Meshy
server's Rule 1.

#### 9.7.1 Subject

**A bone-in ribeye** — the steak seen flat-on, with the rib bone protruding
from one side. The bone is not decoration; it is the requirement.

At `GLYPH = 38 px` the glyph is a silhouette and nothing more, and the strip's
existing five have already claimed the easy shapes: `bonus_purse.png` owns
"round blob", `bonus_sword.png` and `bonus_bolt.png` own "thin diagonal", and
`glyph_heal.png` owns "symmetrical cross". A bowl, a loaf, an apple or a pie are
all round blobs and would collide with the purse; a drumstick is a thin diagonal
with a knob and reads against the sword at a glance.

The ribeye is the one food shape that lands in none of those buckets: a **fat
asymmetric mass with a hard spur off one edge**. Nothing else on the strip has
that outline, and the asymmetry means it stays distinct even at the smallest
size the vertical overlay layout uses.

Fallback if it does not read: **a bowl of stew with a spoon standing in it**,
the spoon handle breaking the circle at an angle so the bowl is not a second
purse. Ranked below the ribeye precisely because it needs that trick to clear
the purse at all, where the ribeye is already unlike everything on the strip.

#### 9.7.2 Style, matched to the existing five

From `bonus_strip.gd`'s own description of the set — "cream-on-near-black",
drawn through a `modulate` colour, which is why every source is a flat two-tone
shape and not painted art:

> Flat 2D game icon of a bone-in ribeye steak, seen straight on, with the rib
> bone clearly protruding from the right side of the meat. Single
> cream-coloured (#F5F1E4) shape on a near-black (#07171B) background. Thick
> dark outline, chunky faceted forms, no bevels, no gradients, no highlights,
> no perspective. Bold blocky silhouette, the bone reading as a distinct spur
> off the edge of the meat. Centred in a square frame with even margin. Simple
> and readable at 40 pixels.

Match the existing set's framing exactly: **1024 × 1024**, centred, generous
margin. Save as `assets/icons/bonus_meal.png`.

The near-black field matters: `_draw_glyph()` tints the whole texture with
`modulate`, so the background is not transparent in the existing icons — it is
dark enough to disappear against `C_CONSOLE_BG` (`#07171B`). Do not ask for a
transparent background; it would make this one icon behave differently from the
other five under tinting.

#### 9.7.3 Acceptance check before importing

Downscale the result to **38 px** and look at it, beside `bonus_purse.png` and
`bonus_sword.png`. The check is whether the bone still reads as a separate spur
rather than melting into the meat and leaving a blob.

If it does not, re-prompt with the bone longer and more clearly separated —
"the bone extending well past the edge of the meat, with a visible notch where
it meets" — rather than accepting it. This is the whole reason the subject was
chosen, and it is invisible at 1024.

#### 9.7.4 Import settings — **ship it at 256, not 1024**

This is the part not to skip. The web-performance acceptance pass (*Web
Performance Acceptance Testing Spec* §E1) found **16.51 MB of 1024 × 1024 UI
icons rendering at ~104 px** — `assets/icons` alone is 11.88 MB across 22 files,
now the single largest remaining category in the build by a wide margin. Every
existing bonus glyph is a ~0.7–1.0 MB lossless 1024². A new one imported the
same way would add ~1 MB to a payload that is already the open item on the
branch this spec is written against.

So `assets/icons/bonus_meal.png.import` ships with **one line different** from
its five siblings:

```ini
process/size_limit=256
```

(everything else identical to `bonus_sword.png.import`, in particular
`compress/mode=0` — lossless. A two-tone shape with a hard dark outline is
exactly where lossy compression fringes, and at 256² the saving is not worth
it.)

**Why `size_limit` rather than exporting a 256 master.** Godot resizes at import
time and ships the imported `.ctex`, not the source PNG — so a 1024 master with
`size_limit = 256` ships at ~15 KB while the full-resolution art stays in the
repo. That keeps this icon consistent with the other 21 on disk, keeps the
decision reversible, and means that when §E1's fleet-wide question ("what target
size?") is answered, the same one-line change applies uniformly to all 22 rather
than this one being a special case that has to be un-done first.

§E1's own recommendation is 256 × 256 lossless for the icon set, so this icon
simply arrives on the far side of a decision the rest of the set is still
waiting on. If that decision later lands somewhere else, change one number here
along with the other 21.

**Verify after import**: the file under `.godot/imported/` for `bonus_meal`
should be tens of kilobytes, not ~1 MB. If it is ~1 MB, `size_limit` did not
take and the icon has silently joined the E1 pile.

#### 9.7.5 The tint colour

`_draw_glyph()` hardcodes a colour per glyph. The five in use are steel
(`C_ORC_IRON`), red (`C_DANGER`), blue (`C_LIGHTNING`), gold (`C_GOLD`) and
green (`C_HEAL`). The gap is warm orange-brown, so add one palette constant:

```gdscript
## [day-night] The meal glyph's tint (§9.7). Warm roast orange - the one gap in
## the bonus strip's five existing glyph colours (steel/red/blue/gold/green).
## Deliberately close to C_FIRE without being it: the fire ELEMENT chip is drawn
## as a filled circle, never a textured glyph, so a warm steak and a warm circle
## are never confusable even when both are on the strip at once.
const C_MEAL := Color("D9793A")
```

Do not reuse `C_FIRE` itself. The two can appear in the same strip — a fed party
carrying a fire modifier shows both — and giving them the same value would make
the strip look like it had drawn one entry twice.

### 9.8 What the meal deliberately is not

One number, one field, one day. It is not a table of buffs, not a `Resource`,
not an `Item`, not a duration in seconds, not a stacking system, and not
per-class. If a second buff is ever wanted — a whetstone for crit, a draught for
HP — *that* pass generalises `meal_pct` into a small dictionary and this one
does not pay for the abstraction in advance.

---

## 10. Edge cases

**10.1 The party cannot afford the inn.** The street is free and always
enabled; the loop cannot deadlock on gold. The inn button is disabled and greyed
(§5.1). No third option, no debt, no "sleep here and owe the innkeeper".

**10.2 The whole party is dead.** A wipe is a quest failure, so
`hero_runtime` is all-zero when NightChoice opens. Both options revive: the inn
to full, the street to `ceil(max_hp / 2)` (§3.3, row 2). The bars in NightChoice
read `DEAD` and grey; NightResult fills them and returns them to white (§5.2).
There is no game-over state and this pass does not add one.

**10.3 The party is at full health.** Both buttons stay live. The street is a
no-op that costs nothing; the inn is a no-op that costs 50 G and the button does
**not** hide, because hiding it would mean the modal's shape changes based on
state the player has to squint at the bars to verify. NightResult's bars simply
do not move.

**10.4 The endless / dev path.** `endless_mode` runs with `quest == null`, so
T1 never fires, `day_phase` never leaves `DAY`, `Mode.RETRY` presents its one
`RETRY` button, and `night_modal._on_result_dismissed()` returns immediately on
the phase check (§4.2). A meal bought in town before a dev run *does* apply —
`meal_pct` is read by `apply_party_bonuses()` regardless of phase — and is never
cleared, because T2 does not fire. That is acceptable for a dev path and worth
one line in `debug.gd`'s status dump (`debug.gd:497` already prints
`party_bonuses()`, so it comes for free).

**10.5 Double-clicking a button.** `resolve_night()` early-returns outside
`NIGHT_PENDING` and `buy_meal()` early-returns on `meal_eaten_today` (§2.3), so
both are idempotent at the state level. Both night panels also set
`mouse_filter = STOP` on their scrim while visible, so the second press of a
double-click hits a hidden control.

**10.6 The two `Debug` entry points behave differently, and both are right.**
`debug.gd`'s `quest <id>` command calls `start_expedition(q)` with a real
`QuestDef`, so it takes T1 and runs the full day/night loop — it stands in for
the mayor's office and should. `debug.gd`'s `route quest` calls
`start_expedition()` with **no** argument (`debug.gd:361`), so under the §2.2
guard it stays in `DAY` and runs the endless path with no night. Both bypass the
mayor's `day_phase` gate; a debug command should be able to force the state.

**10.7 `active_party` grows to three mid-profile.** `_reset_hero_runtime()`
already preserves per-hero HP by `stats_id` and defaults a newly-added hero to
`max_hp`. `resolve_night()`'s positional re-index (§3.5) is the only thing that
assumes a stable array, and it does so *within a single call*, between two
iterations of the same unchanged `active_party`. Safe. Both the bed and the meal
reprice themselves off `active_party.size()` automatically.

**10.8 A meal bought, then a night owed.** Not reachable: `buy_meal()` requires
`DayPhase.DAY`, and T2 has already zeroed `meal_pct` by the time
`NIGHT_PENDING` exists. The guard is there for the corrupt-save case.

---

## 11. Tests

### 11.1 New: `tests/test_day_night.gd` (+ `.tscn`)

Run: `godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_day_night.tscn`

Follows `test_quest_flow.gd`'s shape — `TestSupport`, `t.guard_user_file(SaveGame.PATH)`,
`t.check()` per assertion, `t.finish()`.

**The state machine (the point of the whole pass):**

1. `new_profile()` leaves `day_phase == DAY`, `day_number == 1`, `meal_pct == 0`.
2. `start_expedition(q)` with a real `QuestDef` moves `DAY → QUEST`.
3. `start_expedition()` with **no** argument leaves `day_phase == DAY` — the
   §2.2 endless-path guard, asserted directly. This is the one that prevents the
   permanent lockout.
4. `resolve_night()` called in `QUEST` returns `[]` and mutates nothing — check
   HP and gold are both untouched.
5. From `NIGHT_PENDING`, `resolve_night(STREET)` moves to `DAY` and increments
   `day_number`.
6. **A second `resolve_night(STREET)` immediately after returns `[]` and heals
   nothing.** This is "cannot trigger multiple nights in a row", asserted
   directly — and it is what `street_sleep_used` used to do (§1.3).
7. `start_expedition(q)` → `resolve_night()` succeeds again. This is "must
   undertake a quest after a night", asserted directly.

**The street formula — the §3.3 table:**

8. `120 max`, before `10` → after `65`.
9. before `0`, `alive == false` → after `60`, `alive == true` (revival).
10. before `119` → after `120`, and **never above** `max_hp`.

> Assertions 8–10 duplicate what `test_quest_flow.gd` already pins. That is
> deliberate and cheap: the formula is unchanged by this pass, but
> `resolve_night()` is a **new caller** of it, and these assertions test the
> call site, not the arithmetic.

**The inn:**

11. Full heal from `10 / 120` → `120 / 120`.
12. Charges exactly `Tuning.INN_REST_COST_PER_HERO * active_party.size()`.
13. With `gold = cost - 1`: returns `[]`, gold unchanged, **HP unchanged**, and
    `day_phase` still `NIGHT_PENDING`. (The failure mode this catches is a heal
    that lands before the `spend_gold()` check.)

**The report:**

14. `last_night_report[0]["before_hp"]` is the pre-night value and
    `["after_hp"]` the post-night one — i.e. the snapshot really is taken
    before the mutation (§4.3). A report where both fields match after a real
    heal means the snapshot moved, and NightResult would animate nothing.

**The meal:**

15. `buy_meal()` in `DAY` with enough gold: returns `true`, spends
    `MEAL_COST_PER_HERO × party`, sets `meal_pct == MEAL_DAMAGE_PCT` and
    `meal_eaten_today`.
16. A **second** `buy_meal()` the same day returns `false`, spends nothing, and
    leaves `meal_pct` at `MEAL_DAMAGE_PCT` — not 20.
17. `buy_meal()` with `gold = cost - 1` returns `false` and sets neither field.
18. `buy_meal()` outside `DAY` (set `day_phase = QUEST` by hand) returns `false`.
19. `party_bonuses()["meal_pct"]` reflects the buff, and `["dmg_pct"]` does
    **not** — the two stay separate (§9.5).
20. **The compounding regression (§9.5).** With `meal_pct = 10`, spawn a warrior
    from `res://scenes/battle/heroes/warrior.tscn`, `setup()` it, then call
    `apply_party_bonuses()` **five times** and assert `damage_multiplier` is
    still `1.10` (within `is_equal_approx`) rather than `1.61`.

    *If instantiating a `Combatant` headless proves awkward*, fall back to the
    source-text guard `test_scene_router.gd` already establishes with
    `_code_only()`: assert that `combatant.gd`'s `apply_party_bonuses()` body
    contains no `damage_multiplier /`. Less satisfying, equally permanent, and
    it names the exact regression in the failure message.

21. T2 clears `meal_pct` but **not** `meal_eaten_today`; T3 clears
    `meal_eaten_today` but leaves `meal_pct` at 0 (§9.4's table, asserted).

**Persistence:**

22. `save_profile()` → mutate all four new fields → `load_profile()` restores
    all four.
23. A payload dictionary with **none** of the four keys loads as
    `DAY / 1 / 0 / false` (the legacy-save path, §8.1) — write one by hand as
    `test_profile_save.gd:149` already does.

### 11.2 Edits to existing tests — both are part of this pass

**`tests/test_quest_flow.gd`** — its street-sleep block keeps its formula
assertions and its revival check **untouched** (§0.3). Delete only the two
`street_sleep_used` lines:

```gdscript
t.check(GameState.street_sleep_used, "street sleep sets the once-per-expedition flag")
GameState.start_expedition(q)
t.check(not GameState.street_sleep_used, "start_expedition clears street_sleep_used")
```

The property those two lines were guarding now lives in `test_day_night.gd`
assertion 6, where it is asserted against the state machine rather than a flag.
Leave a one-line comment at the deletion site pointing there, so the next reader
does not conclude the guarantee was dropped.

**`tests/test_profile_expedition.gd:22`** —
`t.check(not GameState.street_sleep_used, "new_profile() clears street_sleep_used")`
becomes
`t.check(GameState.day_phase == GameState.DayPhase.DAY, "new_profile() starts in DAY")`.

### 11.3 Runtime acceptance (not a headless test)

Via `play_scene` + `capture_frames`, per CLAUDE.md's verification note:

- Buy a meal, take the easy quest, and confirm the **damage numbers are ~10%
  higher** against the same enemy than on an unfed run. This is the only check
  that catches the §9.5 wiring being right in the dictionary and wrong in the
  multiplier.
- Confirm the meal glyph appears in the battle overlay's bonus panel and
  disappears on the next expedition — and that at its rendered size it does not
  read as a second purse or a second sword (§9.7.1) — the bone must still be a
  distinct spur. Screenshot the strip with a fed party carrying both gold-find
  and flat-damage gear, so all three glyphs are on screen at once.
- Confirm the mayor's fed line is present before accepting a quest and gone the
  next day (§9.6.2).
- Lose a quest deliberately; confirm the stats screen appears **over the
  battlefield** (not over a town screen) and carries one button.
- Confirm the fade to black measures ~1.5 s and the fade in ~0.75 s.
- Confirm the NightResult bars start visibly short and fill — the single most
  likely bug in the *presentation* half of this pass is bars that are already
  full when the modal opens, which is §4.3's consequence going unhandled.
- Confirm the mayor's quest buttons and the inn's meal button are both live
  again immediately after "Good morning".

---

## 12. Build order

Each step ends green — all tests passing, game bootable.

| step | work | ends when |
|---|---|---|
| 1 | §2.1 state + §6.1 constants + §8.1 save round-trip. Delete `street_sleep_used` (keep `street_sleep_recover()`'s body); §11.2's two test edits land **here**. `quest_result.gd`'s `Mode.FAILURE` branch temporarily calls `heal_party()` / `street_sleep_recover()` directly so the game still works. | `test_profile_save`, `test_profile_expedition`, `test_quest_flow` green |
| 2 | §3.5 `resolve_night()` + `night_inn_cost()`, T1/T2/T3 wired (§2.2), §2.3 guards. Still no new UI — the temporary `quest_result.gd` buttons call `resolve_night()` instead. | `test_day_night.gd` assertions 1–14 green; the night loop is *mechanically* complete and playable |
| 3 | §9.4 `buy_meal()` + §9.5 the `combatant.gd` fix + `party_bonuses()` key. **Assertion 20 before assertion 15** — write the compounding test first, watch it fail against the old round-trip, then fix. | `test_day_night.gd` assertions 15–21 green |
| 4 | §9.7 the icon: confirm the 9 credits, generate, check it at 38 px (§9.7.3), import at `size_limit=256` (§9.7.4), add `C_MEAL`. Then §9.6's three display sites. | the glyph appears in the strip when fed, is distinguishable from the purse, and its imported file is tens of KB |
| 5 | §9.2–9.3 the inn's price board and meal button; `mayor_office.gd`'s disabled state and fed line. | no dead buttons anywhere; the meal is buyable and visibly works |
| 6 | §6.3 `SceneRouter.go()` parameters + the night's fade. `quest_result.gd` stops routing (§4.2, §7.2). | a quest ends → stats over the battlefield → a 1.5 s fade → town |
| 7 | §5.4 `hero_bars.gd` detached mode. Verify standalone through `status_panel_preview.tscn` before wiring it to anything. | three bars draw in town at arbitrary HP with no `Combatant` |
| 8 | §5.1–5.3 the two panels, authored in the editor, script writes text and state only. | the full §4.1 sequence plays |
| 9 | §8.2 resume, §10 edge cases, §11.3 runtime acceptance. | force-quit after a quest returns to the choice |

Steps 1–5 are the pass. Steps 6–9 are the presentation of it, and the game is
playable and correct from the end of step 5 onward — which is the property to
protect if this gets interrupted.

Step 4 is the only step that spends money and the only one that blocks on a
reply from you (§9.7's credit confirmation). It is placed after step 3 so that
if the answer is "not now", steps 5–9 still run: `bonus_strip` omits a zero
entry, so an un-generated glyph costs a missing texture in a `match` arm and
nothing else. Ship the mayor's line and the inn's flavour text either way —
they carry the buff in words, and they are what make it legible without art.

---

## 13. Acceptance checklist

- [ ] Party HP recovers **only** through `resolve_night()`. Grep proves
      `heal_party()` has exactly **one** caller — `resolve_night()` — the two it
      has today (`inn.gd:48`, `quest_result.gd:144`) both having gone, and
      `street_sleep_recover()` likewise has exactly one.
      (`new_profile()` reaches full HP through `_reset_hero_runtime(true)`
      directly, not through `heal_party()`, and stays that way.)
- [ ] Winning a quest and losing a quest both reach the same night choice.
- [ ] Two nights cannot be taken without a quest between them — asserted in
      `test_day_night.gd`, not merely true of the current UI.
- [ ] A quest cannot be accepted while a night is owed, including after a
      force-quit and relaunch.
- [ ] Inn: 50 G × party size, party to full, dead revived.
- [ ] Street: free, `+ ceil(missing / 2)`, dead revived, never above `max_hp`.
      **`INN_STREET_HEAL_FRACTION` and `street_sleep_recover()`'s arithmetic are
      byte-for-byte what they were before this pass.**
- [ ] A party that cannot afford the inn always has a free way forward.
- [ ] Meal: one per day, in town only, `+10%` damage, gone at quest end, and
      **does not compound** across repeated `apply_party_bonuses()` calls.
- [ ] The mayor's office shows the fed line while `meal_pct > 0` and hides it
      at 0 — the buff is legible at the moment it changes a decision (§9.6.2).
- [ ] The meal glyph's bone still reads as a separate spur at 38 px, distinct
      from `bonus_purse` and `bonus_sword` (§9.7.3),
      and `bonus_meal`'s file under `.godot/imported/` is **tens of KB, not
      ~1 MB** — it did not join the §E1 icon pile (§9.7.4).
- [ ] Fade out 1.5 s; town; fade in; bars start at the pre-night value and fill
      to the post-night one.
- [ ] `endless_mode` (`quest == null`) is unaffected: RETRY button, no day, no
      night, `day_phase` never leaves `DAY`.
