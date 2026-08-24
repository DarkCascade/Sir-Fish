extends Node
## GameState — everything that survives an encounter (spec 4.4).
## Hero HP persists across encounters; there is no between-encounter heal.

const STATS_DIR := "res://resources/stats/"

## Party order is fixed left-to-right: Priest, Ranger, Warrior (spec 7.1).
const PARTY_ORDER: Array[StringName] = [&"priest", &"ranger", &"warrior"]

var gold: int = 0
var inventory: Array[Item] = []
var hero_runtime: Array = []       # [{stats_id, current_hp, max_hp, alive}]
var current_encounter_index: int = -1
var level: LevelDef

## Endless is the default mode (spec: Endless Mode) - a run keeps generating
## six-encounter levels back to back instead of ending after one fixed level,
## and only stops on a party wipe (run_controller._next_encounter() is what
## actually loops back into build_level() when a level runs out). Flipping
## this to false restores the original single fixed level (Whispering Wood).
var endless_mode: bool = true
var endless_level_number: int = 1

var run_stats := {
	"encounters_cleared": 0,
	"gold_earned": 0,
	"gold_spent": 0,          # [v2] upgrades + shop, for the summary
	"damage_dealt": 0,
	"damage_taken": 0,
	"slot_spins": 0,
	"slot_wins": 0,
	"items_found": 0,
	"items_sold": 0,
	"items_dropped": 0,       # [drops] drop-only subset of items_found, for the summary
	"upgrades_bought": 0,     # [v2]
	"run_time": 0.0,
}

## [drops] Drops received per hero class this run. Cleared by reset_run().
##
## The goal is COVERAGE, not fairness. A run where the priest never sees a
## staff is a run where a third of the party is inert once equipping exists, so
## a class that is behind is weighted up until it catches up. The weighting is
## soft - it changes the odds, it does not rotate a queue - because a guaranteed
## round robin is readable by the player within two levels and stops being a
## drop at all.
var drops_by_class: Dictionary = {}      # StringName -> int

var _stats_cache: Dictionary = {}   # StringName -> CombatantStats

func _ready() -> void:
	_load_all_stats()

# --- stats registry ---------------------------------------------------------

func _load_all_stats() -> void:
	_stats_cache.clear()
	var dir := DirAccess.open(STATS_DIR)
	if dir == null:
		push_error("GameState: cannot open %s" % STATS_DIR)
		return
	for file_name: String in dir.get_files():
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var res := load(STATS_DIR + clean)
		if res is CombatantStats:
			_stats_cache[(res as CombatantStats).id] = res

func get_stats(id: StringName) -> CombatantStats:
	if not _stats_cache.has(id):
		push_error("GameState: unknown combatant stats id '%s'" % id)
		return null
	return _stats_cache[id]

# --- gold -------------------------------------------------------------------

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	run_stats["gold_earned"] = int(run_stats["gold_earned"]) + amount
	EventBus.gold_changed.emit(gold, amount)

func spend_gold(amount: int) -> bool:
	if amount <= 0 or gold < amount:
		return false
	gold -= amount
	run_stats["gold_spent"] = int(run_stats["gold_spent"]) + amount
	EventBus.gold_changed.emit(gold, -amount)
	return true

# --- inventory --------------------------------------------------------------

func add_item(item: Item) -> void:
	if item == null:
		return
	inventory.append(item)
	_maybe_auto_equip(item)
	EventBus.item_added.emit(item)
	EventBus.party_bonuses_changed.emit(party_bonuses())

func remove_item(item: Item) -> void:
	var index := inventory.find(item)
	if index < 0:
		return
	inventory.remove_at(index)
	EventBus.item_removed.emit(item)
	EventBus.party_bonuses_changed.emit(party_bonuses())

# --- equipping ----------------------------------------------------------

## The item a hero currently has equipped, or null. One item per hero
## (equip_item() enforces it), so the first match in inventory is the only one.
func equipped_item(hero_class: StringName) -> Item:
	for i: Item in inventory:
		if i.equipped_by == hero_class:
			return i
	return null

## Equips item for hero_class, replacing whatever that hero already had
## equipped - "one item per hero" (§ equip request 1). Does not require
## hero_class to be in item.usable_by(): the UI only ever offers eligible
## classes, and the Debug harness wants the freedom to force odd states.
func equip_item(item: Item, hero_class: StringName) -> void:
	if item == null or hero_class == &"":
		return
	var previous := equipped_item(hero_class)
	if previous != null:
		previous.equipped_by = &""
	item.equipped_by = hero_class
	EventBus.party_bonuses_changed.emit(party_bonuses())

func unequip_item(item: Item) -> void:
	if item == null or item.equipped_by == &"":
		return
	item.equipped_by = &""
	EventBus.party_bonuses_changed.emit(party_bonuses())

## Fills an EMPTY slot only - never swaps out an existing equip (§ equip
## request 2). Picks the first of the item's eligible classes with nothing
## equipped; in practice every generated weapon has exactly one eligible
## class today, so there is no real ambiguity to resolve.
func _maybe_auto_equip(item: Item) -> void:
	for hero_class: StringName in item.usable_by():
		if equipped_item(hero_class) == null:
			item.equipped_by = hero_class
			return

# --- party bonuses (spec 13.5) ---------------------------------------------

## Only EQUIPPED items contribute (one per hero, GameState.equip_item()) - an
## item sitting unequipped in inventory is inert. Carrying loot only makes the
## party stronger once it is actually worn; selling an equipped item empties
## that hero's slot the moment it leaves the inventory.
##
## Recomputed on demand and re-emitted on every inventory/equip change.
func party_bonuses() -> Dictionary:
	var out := {
		"dmg_flat": 0,
		"dmg_pct": 0,
		"element": &"",
		"slot_bolt": 0,
		"slot_purse": 0,
		"slot_mend": 0,
	}
	# Elemental totals are kept apart rather than summed into one number, because
	# resistances are the obvious next step (spec 22).
	var elements := { &"fire": 0, &"ice": 0, &"light": 0 }
	for item: Item in inventory:
		if item.equipped_by == &"":
			continue
		for mod: Dictionary in item.modifiers:
			var id: StringName = mod["id"]
			var roll: int = int(mod.get("roll", 0))
			match id:
				&"dmg_flat":
					out["dmg_flat"] = int(out["dmg_flat"]) + roll
				&"dmg_pct":
					out["dmg_pct"] = int(out["dmg_pct"]) + roll
				&"elem_fire":
					out["dmg_flat"] = int(out["dmg_flat"]) + roll
					elements[&"fire"] = int(elements[&"fire"]) + roll
				&"elem_ice":
					out["dmg_flat"] = int(out["dmg_flat"]) + roll
					elements[&"ice"] = int(elements[&"ice"]) + roll
				&"elem_light":
					out["dmg_flat"] = int(out["dmg_flat"]) + roll
					elements[&"light"] = int(elements[&"light"]) + roll
				&"slot_bolt":
					out["slot_bolt"] = int(out["slot_bolt"]) + roll
				&"slot_purse":
					out["slot_purse"] = int(out["slot_purse"]) + roll
				&"slot_mend":
					out["slot_mend"] = int(out["slot_mend"]) + roll
	var best: StringName = &""
	var best_total: int = 0
	for key: StringName in elements.keys():
		if int(elements[key]) > best_total:
			best_total = int(elements[key])
			best = key
	out["element"] = best
	return out

## The damage-number colour for the party's dominant element (spec 11.4).
## Plain danger red when the party carries no elemental modifier.
func element_color() -> Color:
	match party_bonuses()["element"]:
		&"fire": return Tuning.C_FIRE
		&"ice": return Tuning.C_ICE
		&"light": return Tuning.C_LIGHTNING
	return Tuning.C_DANGER

# --- enemy drops (§4) --------------------------------------------------------

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

# --- heroes -----------------------------------------------------------------

func hero_entry(stats_id: StringName) -> Dictionary:
	for entry: Dictionary in hero_runtime:
		if entry["stats_id"] == stats_id:
			return entry
	return {}

func living_hero_count() -> int:
	var n := 0
	for entry: Dictionary in hero_runtime:
		if entry["alive"]:
			n += 1
	return n

# --- run lifecycle ----------------------------------------------------------

## Dispatches on endless_mode (spec: Endless Mode). This is the seam spec
## 12.1 / 22 called out for a future level generator - _build_endless_level()
## is that generator; _build_whispering_wood_level() is the original fixed
## level, kept for endless_mode = false.
func build_level() -> LevelDef:
	if endless_mode:
		return _build_endless_level(endless_level_number)
	return _build_whispering_wood_level()

# --- endless mode (spec: Endless Mode) --------------------------------------

## Regular enemies available from the first level. skeleton_minion is the
## other "weak" combatant alongside shadow_monster - a swarm of either reads
## as an easy opener.
const ENDLESS_EARLY_POOL: Array[StringName] = [&"shadow_monster", &"skeleton_minion"]
## Join the pool once the party has cleared at least one level, so depth 1
## stays as gentle as the old fixed level's opening fight.
##
## The orc barbarian is out of the rotation: it is the last in-house model,
## built from separate primitive blocks (O_Head, O_ArmL, O_Torso...), and
## next to the KayKit skeletons it reads as a stick figure. The stats, scene
## and rig branches all stay - nothing spawns it, so nothing renders it.
const ENDLESS_MID_POOL: Array[StringName] = [
	&"skeleton_warrior", &"skeleton_mage", &"skeleton_rogue",
]
## [UI pass] Was just the orc warlord. Any of the four KayKit skeletons can
## anchor encounter 6 now - battle_director.start_combat() scales whichever
## one gets picked up 150% for the boss slot (a runtime-duplicated
## CombatantStats, never the shared cached one, so the regular-sized version
## other encounters spawn from ENDLESS_MID_POOL is untouched).
const BOSS_POOL: Array[StringName] = [
	&"skeleton_warrior", &"skeleton_mage", &"skeleton_rogue", &"skeleton_minion",
]

## Six encounters, same COMBAT/LOOT/COMBAT/SHOP/COMBAT/boss-COMBAT rhythm as
## the fixed level (that pacing was already tuned - only which enemies fill
## the combat slots is generated). Called again every time the party walks
## off the end of a level (run_controller._next_encounter()), with
## endless_level_number already incremented, so difficulty is entirely from
## a wider enemy pool and slightly bigger groups at higher depths - no
## stat-scaling multiplier, to avoid a second source of truth for combatant
## power alongside CombatantStats.
func _build_endless_level(level_number: int) -> LevelDef:
	var lvl := LevelDef.new()
	lvl.display_name = "The Endless Wood — Depth %d" % level_number

	var pool: Array[StringName] = ENDLESS_EARLY_POOL.duplicate()
	if level_number >= 2:
		pool.append_array(ENDLESS_MID_POOL)
	@warning_ignore("integer_division")
	var enemy_count := mini(2 + level_number / 3, 3)

	var e0 := EncounterDef.new()
	e0.type = EncounterDef.Type.COMBAT
	e0.enemy_stat_ids = _random_enemies(pool, enemy_count)
	e0.travel_duration = 2.0

	var e1 := EncounterDef.new()
	e1.type = EncounterDef.Type.LOOT
	e1.loot_item_count = Tuning.LOOT_ITEMS_PER_CHEST
	e1.travel_duration = 3.0

	var e2 := EncounterDef.new()
	e2.type = EncounterDef.Type.COMBAT
	e2.enemy_stat_ids = _random_enemies(pool, enemy_count)
	e2.travel_duration = 3.0

	var e3 := EncounterDef.new()
	e3.type = EncounterDef.Type.SHOP
	e3.shop_item_count = Tuning.SHOP_ITEMS_FOR_SALE
	e3.travel_duration = 3.0

	var e4 := EncounterDef.new()
	e4.type = EncounterDef.Type.COMBAT
	e4.enemy_stat_ids = _random_enemies(pool, enemy_count)
	e4.travel_duration = 3.0

	# Boss listed first so it lands at the leftmost enemy slot (spec 7.3),
	# same convention as the fixed level's boss encounter.
	var boss_id: StringName = RNG.pick(BOSS_POOL)
	var e5_ids: Array[StringName] = [boss_id]
	e5_ids.append_array(_random_enemies(pool, mini(enemy_count, 2)))
	var e5 := EncounterDef.new()
	e5.type = EncounterDef.Type.COMBAT
	e5.is_boss = true
	e5.enemy_stat_ids = e5_ids
	e5.travel_duration = 4.0

	lvl.encounters = [e0, e1, e2, e3, e4, e5]
	return lvl

func _random_enemies(pool: Array[StringName], count: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i: int in range(count):
		var id: StringName = RNG.pick(pool)
		out.append(id)
	return out

# --- fixed level (endless_mode = false) --------------------------------------

func _build_whispering_wood_level() -> LevelDef:
	var lvl := LevelDef.new()
	lvl.display_name = "The Whispering Wood"

	var e0 := EncounterDef.new()
	e0.type = EncounterDef.Type.COMBAT
	e0.enemy_stat_ids = [&"shadow_monster", &"shadow_monster"]
	e0.travel_duration = 2.0

	var e1 := EncounterDef.new()
	e1.type = EncounterDef.Type.LOOT
	e1.loot_item_count = Tuning.LOOT_ITEMS_PER_CHEST
	e1.travel_duration = 3.0

	var e2 := EncounterDef.new()
	e2.type = EncounterDef.Type.COMBAT
	# skeleton_warrior fills the heavy slot the orc barbarian used to hold
	# (see ENDLESS_MID_POOL) - closest melee bruiser in the roster.
	e2.enemy_stat_ids = [&"shadow_monster", &"shadow_monster", &"skeleton_warrior"]
	e2.travel_duration = 3.0

	var e3 := EncounterDef.new()
	e3.type = EncounterDef.Type.SHOP
	e3.shop_item_count = Tuning.SHOP_ITEMS_FOR_SALE
	e3.travel_duration = 3.0

	var e4 := EncounterDef.new()
	e4.type = EncounterDef.Type.COMBAT
	e4.enemy_stat_ids = [&"skeleton_warrior", &"skeleton_warrior", &"shadow_monster"]
	e4.travel_duration = 3.0

	# Boss listed first so it lands at the leftmost enemy slot (x = 1.6) and
	# its scaled-up body stays inside the frame (spec 7.3).
	var e5 := EncounterDef.new()
	e5.type = EncounterDef.Type.COMBAT
	e5.is_boss = true
	e5.enemy_stat_ids = [RNG.pick(BOSS_POOL), &"shadow_monster"]
	e5.travel_duration = 4.0

	lvl.encounters = [e0, e1, e2, e3, e4, e5]
	return lvl

func reset_run() -> void:
	gold = Tuning.STARTING_GOLD
	inventory.clear()
	current_encounter_index = -1
	endless_level_number = 1
	level = build_level()

	hero_runtime.clear()
	for id: StringName in PARTY_ORDER:
		var s := get_stats(id)
		if s == null:
			continue
		hero_runtime.append({
			"stats_id": id,
			"current_hp": s.max_hp,
			"max_hp": s.max_hp,
			"alive": true,
		})

	Upgrades.reset()

	drops_by_class.clear()

	for key: String in run_stats.keys():
		if key == "run_time":
			run_stats[key] = 0.0
		else:
			run_stats[key] = 0
	EventBus.gold_changed.emit(gold, 0)
	EventBus.party_bonuses_changed.emit(party_bonuses())
