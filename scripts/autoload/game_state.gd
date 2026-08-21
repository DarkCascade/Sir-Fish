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
	"upgrades_bought": 0,     # [v2]
	"run_time": 0.0,
}

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
	EventBus.item_added.emit(item)
	EventBus.party_bonuses_changed.emit(party_bonuses())

func remove_item(item: Item) -> void:
	var index := inventory.find(item)
	if index < 0:
		return
	inventory.remove_at(index)
	EventBus.item_removed.emit(item)
	EventBus.party_bonuses_changed.emit(party_bonuses())

func sellable_items() -> Array[Item]:
	# The filter is real even though nothing is ever equipped in the demo -
	# it is the seam for future equipment (spec 13.6 / 21-A6).
	var out: Array[Item] = []
	for i: Item in inventory:
		if not i.equipped:
			out.append(i)
	return out

# --- party bonuses (spec 13.5) ---------------------------------------------

## Every item in the inventory contributes its modifiers to a party-wide pool.
## Items are never equipped in the demo (spec 21-A6); carrying loot makes the
## party stronger and selling it makes them poorer, which is the loop.
##
## Recomputed on demand and re-emitted on every inventory change. The aggregate
## is a straight sum, which is correct at the demo's <=5-item inventory; a build
## with a large inventory needs diminishing returns (spec 22).
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

## The single function a future level generator replaces (spec 12.1 / 22).
func build_level() -> LevelDef:
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
	e2.enemy_stat_ids = [&"shadow_monster", &"shadow_monster", &"orc_barbarian"]
	e2.travel_duration = 3.0

	var e3 := EncounterDef.new()
	e3.type = EncounterDef.Type.SHOP
	e3.shop_item_count = Tuning.SHOP_ITEMS_FOR_SALE
	e3.travel_duration = 3.0

	var e4 := EncounterDef.new()
	e4.type = EncounterDef.Type.COMBAT
	e4.enemy_stat_ids = [&"orc_barbarian", &"orc_barbarian", &"shadow_monster"]
	e4.travel_duration = 3.0

	# Warlord listed first so it lands at the leftmost enemy slot (x = 1.6) and
	# its 1.70x body stays inside the frame (spec 7.3).
	var e5 := EncounterDef.new()
	e5.type = EncounterDef.Type.COMBAT
	e5.is_boss = true
	e5.enemy_stat_ids = [&"orc_warlord", &"shadow_monster"]
	e5.travel_duration = 4.0

	lvl.encounters = [e0, e1, e2, e3, e4, e5]
	return lvl

func reset_run() -> void:
	gold = Tuning.STARTING_GOLD
	inventory.clear()
	current_encounter_index = -1
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

	for key: String in run_stats.keys():
		if key == "run_time":
			run_stats[key] = 0.0
		else:
			run_stats[key] = 0
	EventBus.gold_changed.emit(gold, 0)
	EventBus.party_bonuses_changed.emit(party_bonuses())
