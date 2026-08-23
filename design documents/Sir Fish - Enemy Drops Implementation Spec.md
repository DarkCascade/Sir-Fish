# Sir Fish — Enemy Drops Implementation Spec

Target: a first pass at combat drops in which **every hero class has a real
chance of seeing an item it could wield**, built as the seam the equipment
feature reads later.

Written against the `overworld-prototype` branch. Section numbers in the form
§13.5 refer to *Sir Fish — Demo v5 Implementation Spec*; bare §4.2 refers to
this document.

---

## 0. Scope

### 0.1 What this builds

1. Weapon types gain a **class affinity** (`axe` → warrior, `staff` → priest, …).
2. A drop generator that picks **the class first and the weapon second**, so
   the number of weapon types a class happens to have stops skewing who gets
   served.
3. A per-run **coverage weighting** so a class that is behind on drops is
   favoured by the next roll, plus a **boss guarantee** that hands the boss's
   drop to the hungriest class outright.
4. A per-enemy `drop_chance`, rolled at death, banked, and awarded on victory.
5. Presentation reusing the chest-loot label path, and a Debug verb.
6. A headless test scene that gates coverage and drop rate with numbers.

### 0.2 What this does NOT build — do not drift into these

- **No equipping.** `Item.equipped` stays unused and every item still feeds the
  party-wide pool in `GameState.party_bonuses()` (§13.5). "Usable by the
  warrior" is *recorded and displayed* in this pass, not enforced. This is
  deliberate: §22 says build the seam, not the feature, and the equip screen
  wants a home that does not exist yet.
- **No new UI screens.** Drops present through `overlay.spawn_world_label()`,
  the same call `_run_loot()` already makes.
- **No changes to the slot machine, `SLOT_STRIP`, or the win rule.**
- **No new art.** Drops are labels, not world props. A dropped-item mesh is a
  fine follow-up and is out of scope here.

### 0.3 What must keep working byte-for-byte

`Itemizer.generate_item()`, `generate_item_with_rarity()` and
`generate_shop_stock()` must produce the **same distributions they do today**.
Shop stock and chest loot keep rolling weapon types uniformly. Only the new
drop path picks a class first. `test_item_distribution.gd` and
`test_economy.gd` must pass unchanged, with no edits to either file.

Routing chest loot through the class-aware generator later is a one-line change
in `_run_loot()`; it is not part of this pass, because it moves numbers two
existing tests assert.

---

## 1. The problem

`Itemizer.generate_item_with_rarity()` draws `weapon_type` uniformly from five
types. The party is priest / ranger / warrior. The natural affinity mapping is:

| class | weapon types |
|---|---|
| warrior | axe, sword |
| ranger | bow, dagger |
| priest | staff |

Under a uniform type roll that is **40% warrior, 40% ranger, 20% priest** — the
priest sees a usable item less than half as often as the other two, and the
skew is an artefact of how many nouns each class happens to have, not a design
choice. Adding a sixth weapon type would silently change it again.

Rolling the class first makes the split 33/33/33 by construction and immune to
the weapon table growing. The coverage weighting in §4 then turns "a chance"
into "reliably, within a level".

---

## 2. Data model

### 2.1 `scripts/autoload/itemizer.gd` — class affinity on the weapon table

Add a `classes` key to every `WEAPON_TYPES` entry. Values are hero `stats.id`
values, matching `GameState.PARTY_ORDER`.

```gdscript
const WEAPON_TYPES := {
	&"axe":    { "base_value": 20, "classes": [&"warrior"], "nouns": ["Axe", "Hatchet", "Cleaver", "Chopper"] },
	&"sword":  { "base_value": 22, "classes": [&"warrior"], "nouns": ["Sword", "Blade", "Saber", "Longsword"] },
	&"bow":    { "base_value": 20, "classes": [&"ranger"],  "nouns": ["Bow", "Longbow", "Shortbow", "Recurve"] },
	&"dagger": { "base_value": 18, "classes": [&"ranger"],  "nouns": ["Dagger", "Knife", "Dirk", "Shiv"] },
	&"staff":  { "base_value": 25, "classes": [&"priest"],  "nouns": ["Staff", "Rod", "Cane", "Scepter"] },
}
```

`classes` is an array, not a single id, so a shared type (a dagger both the
ranger and the priest can hold) needs no schema change later.

### 2.2 `scripts/data/item.gd` — derived, not stored

```gdscript
## Which hero classes can wield this item. DERIVED from the weapon type rather
## than stored on the resource, for the reason CombatantStats.required_anims()
## gives: a second copy of the mapping is a second thing to drift. Empty for a
## kind with no weapon type, so potions and relics answer sensibly the day they
## exist.
##
## Built by iteration rather than returned straight from the table because
## WEAPON_TYPES' inline arrays are untyped Array, which GDScript will not
## assign to an Array[StringName] return.
func usable_by() -> Array[StringName]:
	var out: Array[StringName] = []
	if kind != Kind.WEAPON or weapon_type == &"":
		return out
	var entry: Dictionary = Itemizer.WEAPON_TYPES.get(weapon_type, {})
	for c: StringName in entry.get("classes", []):
		out.append(c)
	return out

## "Warrior", or "Warrior / Ranger" for a shared type. "Anyone" when nothing
## restricts the item - which is what an unrestricted kind should read as, not
## an empty string that renders as a gap in the shop card.
func class_label() -> String:
	var classes := usable_by()
	if classes.is_empty():
		return "Anyone"
	var names: PackedStringArray = []
	for c: StringName in classes:
		names.append(String(c).capitalize())
	return " / ".join(names)
```

Reaching `Itemizer` from `Item` follows the existing precedent — `rarity_color()`
and `buy_price()` already read the `Tuning` autoload from this resource.

Extend `subtitle()` so class affinity surfaces in every existing item UI for
free (`shop_buy_card.gd:21`, `shop_sell_row.gd:19` both call it):

```gdscript
func subtitle() -> String:
	# "Magic Sword - Warrior". The class half is what makes an item legible as
	# "this one is for someone" while equipping does not exist to enforce it.
	return "%s %s - %s" % [rarity_name(), type_name(), class_label()]
```

**Check the shop card after this change.** The subtitle label is rarity-coloured
and sits inside a fixed-width card; "Uncommon Longsword - Warrior" is
materially longer than "Uncommon Longsword". If it clips, put the class on its
own line in the card scene rather than shortening the string — the string is
also what the Debug log prints.

### 2.3 `scripts/data/combatant_stats.gd` — two authored knobs

```gdscript
## [drops] Probability this combatant leaves an item when it dies. Rolled once,
## at death, and banked until the fight is won (§5) - a party that wipes carries
## nothing home. Heroes leave it at 0.0. The field lives on the shared stats
## resource rather than an enemies-only one because there is only one stats
## resource, and an is_hero guard at the roll site is cheaper than a second
## class.
@export_range(0.0, 1.0, 0.01) var drop_chance: float = 0.0

## [drops] Lowest rarity this combatant's drop may roll, as an Item.Rarity
## index. The normal weighted roll (§13.2) is taken first and then RAISED to
## this floor, so a floor of 1 does not flatten the curve above it - it only
## removes Commons. Only the boss sets it.
@export_range(0, 3, 1) var drop_rarity_floor: int = 0
```

### 2.4 `scripts/autoload/tuning.gd` — the numbers

Add after the economy block (§5.4), keeping the single-source-of-truth rule:

```gdscript
# --- enemy drops --------------------------------------------------------------
## How strongly a class that is behind on drops is favoured by the next roll:
##   weight = 1 + DROP_CATCHUP * (leader_count - this_count)
## 0.0 makes drops uniform across classes and coverage a pure coin flip; higher
## converges coverage faster at the cost of feeling scripted. 1.5 means a class
## two drops behind is 4x as likely as the leader.
const DROP_CATCHUP := 1.5

## A boss drop skips the weighted roll and goes to the hungriest class outright
## (§4.2). This is what turns §10's coverage gate from "usually" into "almost
## always". Set false to make bosses roll like anything else.
const DROP_BOSS_TARGETS_HUNGRIEST := true

## Seconds between drop labels when several land at once. Matches the chest
## cadence in _run_loot() so a drop reads as the same event as chest loot.
const DROP_LABEL_STAGGER := 0.25
## Height above the recorded corpse position that a drop label pops at.
const DROP_LABEL_LIFT := 1.2
## Smaller than spawn_world_label()'s 40 default: a drop label carries the item
## name AND the class, so it is roughly twice as wide as a chest label.
const DROP_LABEL_FONT_SIZE := 34
```

---

## 3. Class-first generation

### 3.1 Refactor, without changing behaviour

Split the body of `generate_item_with_rarity()` so the weapon type becomes a
parameter. `generate_item_with_rarity()` keeps picking uniformly and delegating,
so its distribution is untouched — this is the part §0.3 protects.

```gdscript
func generate_item_with_rarity(rarity_index: int) -> Item:
	rarity_index = clampi(rarity_index, 0, 3)
	var types: Array = WEAPON_TYPES.keys()
	var wtype: StringName = types[RNG.randi_range(0, types.size() - 1)]
	return _generate_typed(wtype, rarity_index)

## The whole of the old generate_item_with_rarity() body from `item.weapon_type`
## onward, with the type handed in. Nothing else moves.
func _generate_typed(wtype: StringName, rarity_index: int) -> Item:
	...
```

### 3.2 The class-aware helpers

```gdscript
## Every weapon type `hero_class` can wield.
func weapon_types_for(hero_class: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for wtype: StringName in WEAPON_TYPES:
		if (WEAPON_TYPES[wtype]["classes"] as Array).has(hero_class):
			out.append(wtype)
	return out

## The classes a drop can be aimed at, in PARTY_ORDER. Derived from the weapon
## table rather than listed, so a class with no wieldable type is excluded
## automatically instead of silently receiving items it cannot use.
func droppable_classes() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in GameState.PARTY_ORDER:
		if not weapon_types_for(id).is_empty():
			out.append(id)
	return out

## One item aimed at `hero_class`. Rarity is the normal §13.2 weighted roll
## raised to `rarity_floor`; the weapon type is drawn only from that class's
## types. THE ONLY generator that picks a class first - see §0.3.
func generate_drop(hero_class: StringName, rarity_floor: int = 0) -> Item:
	var rarity: int = maxi(RNG.weighted_index(RARITY_WEIGHTS), clampi(rarity_floor, 0, 3))
	var types := weapon_types_for(hero_class)
	if types.is_empty():
		# Unreachable while droppable_classes() gates the caller, but a drop is
		# better than a crash if a future class joins PARTY_ORDER before it has
		# a weapon.
		return generate_item_with_rarity(rarity)
	return _generate_typed(types[RNG.randi_range(0, types.size() - 1)], rarity)
```

---

## 4. Coverage — `scripts/autoload/game_state.gd`

The counters are per-run state, so they live with the rest of it.

### 4.1 Counters and the weighted pick

```gdscript
## [drops] Drops received per hero class this run. Cleared by reset_run().
##
## The goal is COVERAGE, not fairness. A run where the priest never sees a
## staff is a run where a third of the party is inert once equipping exists, so
## a class that is behind is weighted up until it catches up. The weighting is
## soft - it changes the odds, it does not rotate a queue - because a guaranteed
## round robin is readable by the player within two levels and stops being a
## drop at all.
var drops_by_class: Dictionary = {}      # StringName -> int

func drop_count(hero_class: StringName) -> int:
	return int(drops_by_class.get(hero_class, 0))

func record_drop(hero_class: StringName) -> void:
	drops_by_class[hero_class] = drop_count(hero_class) + 1

## The class the next drop is aimed at, or &"" when there are none to aim at.
## `force_hungriest` skips the roll entirely - the §4.2 boss guarantee.
func next_drop_class(force_hungriest: bool = false) -> StringName:
	var classes: Array[StringName] = Itemizer.droppable_classes()
	if classes.is_empty():
		return &""
	if force_hungriest:
		# Ties break in PARTY_ORDER rather than by dictionary iteration order:
		# the boss drop is the one drop a player will remember, so which class
		# it favours must not depend on insertion order.
		var best: StringName = classes[0]
		for c: StringName in classes:
			if drop_count(c) < drop_count(best):
				best = c
		return best
	var leader: int = 0
	for c: StringName in classes:
		leader = maxi(leader, drop_count(c))
	var weights: Array[int] = []
	for c: StringName in classes:
		# x100 because weighted_index takes integers and DROP_CATCHUP is
		# fractional. Only the ratios matter, not the scale.
		weights.append(int(round(100.0 * (1.0 + Tuning.DROP_CATCHUP
			* float(leader - drop_count(c))))))
	return classes[RNG.weighted_index(weights)]
```

### 4.2 The boss guarantee

A boss kill passes `force_hungriest = true` (gated on
`Tuning.DROP_BOSS_TARGETS_HUNGRIEST`). Every endless level ends on a boss
(`_build_endless_level()`), so this is one deterministic top-up per level aimed
exactly where the run is thinnest. It is what carries the §10 coverage gate:
three weighted drops leave a class uncovered often enough to notice, and the
boss closes that hole without the weighted rolls having to be heavy-handed.

### 4.3 Reset and stats

- `reset_run()`: add `drops_by_class.clear()`.
- `run_stats`: add `"items_dropped": 0`. Keep incrementing the existing
  `items_found` for drops too — it means "items the party acquired by finding",
  and a drop is that. `items_dropped` is the drop-only subset for the summary.

---

## 5. Runtime flow

Rolled **at death** so the chance is the dying enemy's own and the corpse
position is still valid. Awarded **on victory** so a wipe carries nothing home,
and so several kills present as one sequence instead of interrupting the fight.

### 5.1 `scripts/battle/battle_director.gd`

```gdscript
## [drops] Items banked from enemies killed in the current fight, as
## {item: Item, position: Vector3}. See §5's note on why the roll and the award
## happen at different times.
var pending_drops: Array[Dictionary] = []

## [drops] Whether the fight in progress is the level's boss (§4.2). Set by
## start_combat() from the encounter def rather than inferred from the enemy's
## stats, for the same reason special_targets_opponent is a data flag: the
## warlord is the boss because the ENCOUNTER says so, and a future level that
## fields two warlords mid-level must not hand out two boss drops.
var _boss_fight: bool = false
```

- `start_combat(enemy_stat_ids: Array, is_boss: bool = false)` — set
  `_boss_fight = is_boss` and `pending_drops.clear()` at the top, alongside the
  existing `clear_enemies()`. The default keeps Debug's `spawn` verb working.
- `_on_combatant_died(c)` — call `_roll_drop(c)` inside the existing
  `if _active and c is Combatant and enemies.has(c):` branch, before the current
  body.

```gdscript
func _roll_drop(c: Combatant) -> void:
	var stats := c.stats
	if stats == null or stats.is_hero or stats.drop_chance <= 0.0:
		return
	if RNG.randf() > stats.drop_chance:
		return
	var hero_class: StringName = GameState.next_drop_class(
		_boss_fight and Tuning.DROP_BOSS_TARGETS_HUNGRIEST)
	if hero_class == &"":
		return
	var item := Itemizer.generate_drop(hero_class, stats.drop_rarity_floor)
	GameState.record_drop(hero_class)
	# The position is captured now: begin_corpse_cleanup() starts the moment the
	# fight ends, and the award pass runs after it.
	pending_drops.append({ "item": item, "position": c.hit_world_position() })
```

Also clear `pending_drops` in `clear_enemies()` — the retry path
(`_on_retry()` → `director.clear_enemies()`) must not carry a dead run's
bankings into the next one.

### 5.2 `scripts/run/run_controller.gd`

Pass the boss flag through at the one call site in `_arrive()`:

```gdscript
		EncounterDef.Type.COMBAT:
			state = RunState.COMBAT
			director.start_combat(def.enemy_stat_ids, def.is_boss)
```

Award in `_on_combat_ended()`:

```gdscript
func _on_combat_ended(victory: bool) -> void:
	if state != RunState.COMBAT:
		return
	if not victory:
		director.pending_drops.clear()      # a wipe carries nothing home (§5)
		_game_over()
		return
	director.begin_corpse_cleanup()
	await _award_drops()
	_encounter_resolved()
```

```gdscript
# --- DROPS (§5) -------------------------------------------------------------

## Mirrors _run_loot()'s presentation deliberately: a drop and a chest item are
## the same item from the same generator, so they should read as the same
## event. Labels pop at the recorded corpse positions rather than at a prop -
## the field is not scrolling yet (travel only restarts in _encounter_exit()),
## so those positions are still where the bodies fell.
##
## No _ui_hidden() branch, unlike _run_shop(): nothing here blocks on a button,
## so with the overlay hidden the items are still added and only the labels go
## unseen, which is the correct degradation.
func _award_drops() -> void:
	for entry: Dictionary in director.pending_drops:
		var item: Item = entry["item"]
		GameState.add_item(item)
		GameState.run_stats["items_found"] = int(GameState.run_stats["items_found"]) + 1
		GameState.run_stats["items_dropped"] = int(GameState.run_stats["items_dropped"]) + 1
		overlay.spawn_world_label(
			(entry["position"] as Vector3) + Vector3(0, Tuning.DROP_LABEL_LIFT, 0),
			"%s (%s)" % [item.display_name, item.class_label()],
			item.rarity_color(), Tuning.DROP_LABEL_FONT_SIZE)
		await get_tree().create_timer(Tuning.DROP_LABEL_STAGGER).timeout
	director.pending_drops.clear()
```

`damage_number.tscn`'s Label is single-line — if "Gleaming Longsword (Warrior)"
clips at 1080 wide, drop `DROP_LABEL_FONT_SIZE` before you reach for a second
label or a shortened string.

---

## 6. Authored drop chances

Set these on the `.tres` files through the inspector / `edit_resource`, not in
script (CLAUDE.md, *Prefer inspector properties over code*).

| resource | `drop_chance` | `drop_rarity_floor` | why |
|---|---|---|---|
| `shadow_monster.tres` | 0.30 | 0 | swarm filler |
| `skeleton_minion.tres` | 0.30 | 0 | swarm filler |
| `skeleton_warrior.tres` | 0.40 | 0 | mid pool |
| `skeleton_rogue.tres` | 0.40 | 0 | mid pool |
| `skeleton_mage.tres` | 0.40 | 0 | mid pool |
| `orc_barbarian.tres` | 0.45 | 0 | toughest regular |
| `orc_warlord.tres` | 1.00 | 1 | boss: always drops, never Common |
| `priest` / `ranger` / `warrior` | 0.00 | 0 | heroes leave nothing |

These are a **starting point sized to hit §10's D8 gate**, not tuned values.
Run the test, read the measured mean, and adjust this table rather than the gate.

---

## 7. Debug harness — `scripts/autoload/debug.gd`

Add a `drops` verb to the `match verb:` table (§19.2's one-`[DEBUG]`-line-per-
command contract applies):

```gdscript
func _cmd_drops(args: Array) -> void:
	if not args.is_empty() and String(args[0]) == "clear":
		GameState.drops_by_class.clear()
		_log("drops -> cleared")
		return
	var bits: PackedStringArray = []
	for c: StringName in Itemizer.droppable_classes():
		bits.append("%s %d" % [String(c), GameState.drop_count(c)])
	var d = _director()
	_log("drops -> %s | banked %d | next %s" % [
		", ".join(bits),
		d.pending_drops.size() if d != null else 0,
		String(GameState.next_drop_class())])
```

Extend `additem` with an optional class token so a specific class's drop can be
forced: `additem magic ranger` → `Itemizer.generate_drop(&"ranger", 2)`. Keep
the existing no-arg and rarity-only forms working.

Add the per-class counts to `_cmd_state()`'s summary line if it fits without
wrapping.

---

## 8. Files touched

- [ ] `scripts/autoload/tuning.gd` — §2.4 constants
- [ ] `scripts/autoload/itemizer.gd` — §2.1 `classes`, §3.1 refactor, §3.2 helpers
- [ ] `scripts/data/item.gd` — §2.2 `usable_by()`, `class_label()`, `subtitle()`
- [ ] `scripts/data/combatant_stats.gd` — §2.3 exports
- [ ] `scripts/autoload/game_state.gd` — §4.1 counters, §4.3 reset + run_stats
- [ ] `scripts/battle/battle_director.gd` — §5.1 roll and bank
- [ ] `scripts/run/run_controller.gd` — §5.2 boss flag, award pass
- [ ] `scripts/autoload/debug.gd` — §7 verbs
- [ ] `resources/stats/*.tres` — §6 table (10 resources)
- [ ] `scenes/modals/shop_buy_card.tscn` — only if §2.2's subtitle clips
- [ ] `tests/test_drops.gd` + `tests/test_drops.tscn` — §10

---

## 9. Order of work

1. §2 data model. `validate_script` each file as you go — `Item` reaching
   `Itemizer` is the one new cross-autoload edge and it fails loudly if wrong.
2. §3 refactor. **Run `test_item_distribution.tscn` and `test_economy.tscn`
   here, before anything else is added.** If either moves, the refactor was not
   behaviour-preserving and nothing downstream is trustworthy.
3. §4 coverage + §10 checks D1–D7. Pure data, testable headless with no game
   running.
4. §6 `.tres` values, then gate D8 and tune the table against it.
5. §5 runtime wiring. Verify in-game with `play_scene` plus the §7 verbs.
6. §7 Debug verbs — can move earlier if useful for step 5.

---

## 10. Gate — `tests/test_drops.gd`

Runs as a scene, not `--script`, because it needs the `GameState`, `Itemizer`,
`Tuning` and `RNG` autoloads:

```
godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_drops.tscn
```

Use `TestSupport` for PASS/FAIL bookkeeping, matching
`test_item_distribution.gd`. Required checks:

| id | check |
|---|---|
| **D1** | Over 1000 `generate_drop(c)` per class, **every** item's `usable_by()` contains `c`. |
| **D2** | `Itemizer.droppable_classes()` equals `GameState.PARTY_ORDER` — no hero is unreachable. |
| **D3** | No generated item anywhere (drop, chest, or shop stock) has an empty `usable_by()`. |
| **D4** | With live counters over 3000 drops, each class's share is **33.3% ± 2pp**. |
| **D5** | `generate_drop(c, 1)` never returns a Common, over 500 samples per class. |
| **D6** | `generate_drop(c, 0)` rarity split is within ±4pp of 50/30/15/5. |
| **D7** | Regression guard on §3.1: over 3000 `generate_item()` calls, each of the five weapon types is within ±3pp of 20%. |
| **D8** | Mean drops per level is **3.0–4.5**. Build real levels with `GameState.build_level()`, walk the encounters, and sum `drop_chance` over each COMBAT's `enemy_stat_ids`. Print the measured mean. |
| **D9** | Coverage: simulate 500 levels using D8's per-level drop counts and the §4 weighting, with counters resetting per run. Of the levels that produced **≥3 drops**, **≥95%** gave all three classes at least one. |

D9 is the gate the whole feature exists for. If it fails, raise
`Tuning.DROP_CATCHUP` before touching anything structural.

Also **print, without gating**: `GameState.party_bonuses()["dmg_flat"]` after a
simulated three-level run's worth of drops. That number is the input to §11's
first open question and a human needs to read it.

Re-run the full existing suite before calling this done — at minimum
`test_item_distribution.tscn`, `test_economy.tscn`, `test_endless_level_gen.tscn`
and `test_autoload_safety.tscn`.

---

## 11. Consequences to raise, not to silently absorb

These are real effects of this change. Report the measured numbers; do not
"fix" them inside this pass.

1. **Inventory grows past what §13.5 was designed for.** `party_bonuses()` is a
   straight sum and its own comment says that is "correct at the demo's ≤5-item
   inventory". At ~3.5 drops per level the party holds well over five items
   inside two levels, and party damage climbs faster than anything was tuned
   for. §22 already lists diminishing returns as deferred; this pass is what
   makes it urgent. **Measure it (§10) and report it.** Do not add a curve or an
   inventory cap here.
2. **The party gets richer.** Drops are sellable at `SHOP_SELL_RATE`. Roughly
   3.5 extra items per level at a median value near 50 is ~85 gold per level on
   top of the ~300 per run the slot pays. `test_economy.gd` does not simulate
   selling drops so it will not fail, but shop pricing is now looser than §5.4
   assumed. Record the new figure; retune when equipping lands and items start
   getting kept instead of sold.
3. **"Usable by" is displayed, not enforced.** Until equipping exists, a staff
   dropping "for the priest" makes the whole party stronger exactly as an axe
   would. That is the honest state of this pass, and it is why §2.2 puts the
   class into `subtitle()` — so the player is being taught the vocabulary the
   equip screen will later depend on.

---

## 12. Deferred

- Routing chest loot through `generate_drop()` (§0.3).
- A dropped-item world prop instead of a floating label.
- Per-enemy weighting toward *thematic* drops (the skeleton mage favouring
  staves). The seam is `generate_drop()`'s `hero_class` argument — a
  `preferred_class` field on `CombatantStats` would compete with §4's coverage
  weighting and needs a design decision about which wins.
- Drop chance scaling with `GameState.endless_level_number`.
- Potions and relics (§22): `usable_by()` already returns empty for them.
