extends Node
## GameState — everything that survives an encounter (spec 4.4).
## Hero HP persists across encounters; there is no between-encounter heal.

const STATS_DIR := "res://resources/stats/"

## Party order is fixed left-to-right: Mage, Ranger, Warrior (spec 7.1).
const PARTY_ORDER: Array[StringName] = [&"mage", &"ranger", &"warrior"]

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

## [drops] Drops received per hero class this run. Cleared by
## start_expedition().
##
## The goal is COVERAGE, not fairness. A run where the mage never sees a
## staff is a run where a third of the party is inert once equipping exists, so
## a class that is behind is weighted up until it catches up. The weighting is
## soft - it changes the odds, it does not rotate a queue - because a guaranteed
## round robin is readable by the player within two levels and stops being a
## drop at all.
var drops_by_class: Dictionary = {}      # StringName -> int

# --- [town] profile vs. expedition (step 1 of the town/quests/forging spec) -
##
## Two lifetimes are being teased apart here. PROFILE survives everything and
## will be saved to disk (a later pass). EXPEDITION is one quest, from the
## mayor's desk to the result modal, and resets every retry exactly as the
## whole run used to.
##
## For now `reset_run()` below still calls both in sequence on every retry, so
## nothing observable changes yet - see reset_run()'s own comment for why that
## is deliberate rather than an oversight.

## [town] Scrap metal - the forge's currency. Inert for now: nothing awards or
## spends it yet (that lands with the forge and the combat pickups). Declared
## here, at 0, so the save format and the profile/expedition split can be
## built around a field that already exists.
var scrap: int = 0

## [town] The heroes that actually take the field. PARTY_ORDER stays the
## canonical roster - it is what the drop-coverage weighting is written
## against, and restoring a three-hero party is one assignment - and this is
## who is currently in it. Profile-scoped.
##
## [town] spec 4.5: the party is solo. This initialiser and new_profile()'s
## matching assignment are the VALUE FLIP that actually makes it so - the three
## reads spec 4.5 lists (droppable_classes(), _reset_hero_runtime(),
## spawn_party() via hero_runtime) only matter once this stops equalling
## PARTY_ORDER. PARTY_ORDER itself is untouched.
var active_party: Array[StringName] = [&"warrior"]

## [town] The quest being run, or null in town / outside a quest. Untyped
## until QuestDef exists (a later pass); GameState.build_level() does not yet
## branch on it.
var quest = null

## [town] Gold and scrap picked up during the CURRENT expedition. Inert until
## the result modal reads them; kept at 0 here since nothing yet adds to
## either mid-run.
var expedition_gold: int = 0
var expedition_scrap: int = 0

## [town] Whether the free half-heal has been used since this expedition
## started. Inert until the inn's recovery flow exists; declared now so
## start_expedition() has something real to clear.
var street_sleep_used: bool = false

## [town] Inventory size at the moment the current expedition started, so a
## failed quest can later tell "brought from town" apart from "found this
## trip" without tagging every Item. Inert until the failure flow reads it.
##
## Underscored because nothing outside GameState should WRITE it; spec 8.5's
## failure flow needs to READ it to pick which unequipped items to discard, so
## the intended access path is a discard helper on GameState rather than a
## reach-in from RunController. Spec 2.2's field listing omits this field
## entirely - it appears only in 8.5's prose - which is why it is called out
## here rather than left to be rediscovered.
var _expedition_inventory_mark: int = 0

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

## [town] The item in `hero_class`'s `slot`, or null (spec 4.3). `equipped_by`
## still records only the hero, not the slot - the slot is recoverable from the
## item's own type (Item.slot()), so one item is never ambiguous about which
## slot it fills, which is why this needs no new field on Item.
func equipped_item(hero_class: StringName, slot: Item.Slot) -> Item:
	for i: Item in inventory:
		if i.equipped_by == hero_class and i.slot() == slot:
			return i
	return null

## [town] Every item `hero_class` currently wears, in Slot order, gaps omitted
## (spec 4.3). What the forge and the inventory modal's Equipped section list.
func equipped_set(hero_class: StringName) -> Array[Item]:
	var out: Array[Item] = []
	for s: Item.Slot in [Item.Slot.WEAPON, Item.Slot.ARMOR, Item.Slot.TRINKET]:
		var it := equipped_item(hero_class, s)
		if it != null:
			out.append(it)
	return out

## Equips item for hero_class, replacing whatever that hero already had in
## THAT item's slot - "one item per slot" (spec 4.3). Does not require
## hero_class to be in item.usable_by(): the UI only ever offers eligible
## classes, and the Debug harness wants the freedom to force odd states.
func equip_item(item: Item, hero_class: StringName) -> void:
	if item == null or hero_class == &"":
		return
	var previous := equipped_item(hero_class, item.slot())
	if previous != null:
		previous.equipped_by = &""
	item.equipped_by = hero_class
	# [town] spec 3.3: the deliberate-equip hook (step 6). Auto-equip on pickup
	# stays silent - it only fills a slot the player left empty. party_bonuses
	# still fires for both, since both change the pool.
	EventBus.item_equipped.emit(item, hero_class, int(item.slot()))
	EventBus.party_bonuses_changed.emit(party_bonuses())

func unequip_item(item: Item) -> void:
	if item == null or item.equipped_by == &"":
		return
	item.equipped_by = &""
	EventBus.party_bonuses_changed.emit(party_bonuses())

## Fills an EMPTY slot only - never swaps out an existing equip (§ equip
## request 2). Picks the first of the item's eligible classes whose matching
## slot is empty; in practice every generated item has exactly one eligible
## class today, so there is no real ambiguity to resolve.
func _maybe_auto_equip(item: Item) -> void:
	for hero_class: StringName in item.usable_by():
		if equipped_item(hero_class, item.slot()) == null:
			item.equipped_by = hero_class
			return

# --- party bonuses (spec 13.5) ---------------------------------------------

## Only EQUIPPED items contribute - an item sitting unequipped in inventory is
## inert. Carrying loot only makes the party stronger once it is actually worn;
## selling an equipped item empties that slot the moment it leaves the inventory.
##
## [town] Up to THREE items per hero now, one per Item.Slot (spec 4.3) - it was
## one. That is the point of three slots: spec 1.5 records the solo warrior
## carrying a third as much as the old three-hero party into this pool, and the
## slot machine, the core loop, is what reads the result.
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
	&"skeleton_warrior", &"skeleton_mage", &"skeleton_rogue", &"sporecap",
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

## [town] A brand new profile - the thing a missing / unreadable save file
## falls back to (spec 2.4). Resets everything PROFILE-scoped: currencies,
## inventory, the active party, and hero HP to full. Memory only - the caller
## persists the fallback (see "THIS FUNCTION DOES NOT SAVE" below).
##
## Step 2 (spec 14) replaced this function's step-1 placeholders: gold/scrap now
## use spec 11's PROFILE_STARTING_GOLD / PROFILE_STARTING_SCRAP (a 75-gold
## profile shipping forever was the failure mode). STARTING_GOLD (75) is
## untouched and still means "gold the slot economy was balanced against"
## (test_economy.gd:41).
##
## THIS FUNCTION DOES NOT SAVE, and that is deliberate (step-2 Q4). It is a
## memory-only reset; whoever DECIDES a new profile is real - boot.tscn, on
## load_profile() returning false (spec 3.1) - is what persists it.
##
## The reason is that this function is DESTRUCTIVE and reset_run() calls it
## unconditionally, which RunController._start_run() calls on every boot and
## retry. A save call here would mean every single launch overwrites the
## player's file with a fresh 150-gold profile before anything has a chance to
## load it. A new profile is fully deterministic, so re-deriving it after a
## crash costs nothing - there is no state here worth persisting eagerly.
## Spec 2.4's own "When to save" list never names this function.
##
## [town] spec 4.5 flipped active_party here to the solo warrior - this
## assignment plus the field's initialiser are the value flip that makes the
## party solo. PARTY_ORDER stays the canonical roster.
func new_profile() -> void:
	gold = Tuning.PROFILE_STARTING_GOLD
	scrap = Tuning.PROFILE_STARTING_SCRAP
	inventory.clear()
	active_party = [&"warrior"] as Array[StringName]
	street_sleep_used = false
	_reset_hero_runtime(true)     # full heal - a new profile starts whole

## [town] Everything an EXPEDITION owns, and nothing a profile owns. Will be
## called from the mayor's office on quest accept (a later pass), which is
## also when `q` starts being a real QuestDef instead of always null. For now
## the only caller is reset_run() below, always with no argument.
##
## Deliberately does NOT touch gold, scrap or inventory - see reset_run()'s
## comment for why that absence matters once this stops being called back to
## back with new_profile() on every retry.
func start_expedition(q = null) -> void:
	quest = q
	current_encounter_index = -1
	# Must precede build_level() - _build_endless_level() reads it. Spec 2.3's
	# listing omits this line; without it a retry regenerates at the depth the
	# party died on, and test_endless_level_gen.gd:13 is what catches that.
	endless_level_number = 1
	expedition_gold = 0
	expedition_scrap = 0
	street_sleep_used = false
	_expedition_inventory_mark = inventory.size()
	drops_by_class.clear()
	Upgrades.reset()
	level = build_level()
	_reset_hero_runtime(false)    # keep current HP - the inn is the heal

	for key: String in run_stats.keys():
		if key == "run_time":
			run_stats[key] = 0.0
		else:
			run_stats[key] = 0
	EventBus.gold_changed.emit(gold, 0)
	EventBus.party_bonuses_changed.emit(party_bonuses())

## [town] Rebuilds hero_runtime from active_party, exactly as spec 2.3 words
## it ("rebuilds hero_runtime from active_party, not PARTY_ORDER").
##
## Reading active_party here is a provable no-op today - the field is
## initialised to PARTY_ORDER.duplicate() and nothing writes it - so it costs
## no behaviour change and takes one site off spec 4.5's list of three. The
## coupling 4.5 worries about (drops targeting a hero who is not on the field)
## is created by active_party's VALUE changing, not by which name each site
## reads, so moving this one read early decouples nothing.
##
## `full_heal` false preserves an existing entry's current_hp instead of
## resetting it to max. That is what lets damage carry home once new_profile()
## and start_expedition() stop being called back to back (spec 2.1: hero HP is
## profile-scoped, the inn is the heal). `alive` is derived from the resulting
## hp, never assumed true, so a hero who died stays dead until something heals
## them - which is what spec 8.5's two recovery buttons are for.
func _reset_hero_runtime(full_heal: bool) -> void:
	var previous: Array = hero_runtime
	hero_runtime = []
	for id: StringName in active_party:
		var s := get_stats(id)
		if s == null:
			continue
		var hp: int = s.max_hp
		if not full_heal:
			for entry: Dictionary in previous:
				if entry["stats_id"] == id:
					hp = int(entry["current_hp"])
					break
		hero_runtime.append({
			"stats_id": id,
			"current_hp": hp,
			"max_hp": s.max_hp,
			"alive": hp > 0,
		})

## The endless-mode entry point: the one caller that wants BOTH halves.
## RunController on boot and on retry, and test_endless_level_gen.gd directly,
## all mean "reset absolutely everything, right now" - which is exactly the
## two halves in sequence, so nothing observable changed at step 1. Gold,
## scrap and inventory still reset on every retry, same as before the split.
##
## This is NOT a temporary shim, despite spec 2.3's "reset_run() is deleted".
## Spec 13.3 requires test_endless_level_gen.gd to keep passing with NO edits
## for the whole of this pass, and that test calls reset_run() directly; 13.3
## also states endless mode survives intact, "only bypassed when quest !=
## null". Deleting this function would force the test edit 13.3 forbids, so it
## stays, permanently, as endless mode's way in.
##
## What DOES change later is that quest accept calls start_expedition() ALONE
## (spec 8, via the mayor's office). That is the path on which gold, scrap and
## inventory finally survive a retry, and it is the whole reason the two halves
## are separate functions. Nothing on this line reaches that path.
func reset_run() -> void:
	new_profile()
	start_expedition()
