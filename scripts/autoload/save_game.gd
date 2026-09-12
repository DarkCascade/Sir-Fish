extends Node
## [town] The profile save (spec 2.4). One file, rewritten whole - the profile
## is a few kilobytes and a partial-write scheme buys nothing at this size.
##
## `var_to_str` rather than JSON because StringName round-trips natively
## (&"warrior" survives as a StringName, not as "warrior"), and item.modifiers
## is an Array[Dictionary] whose ids are StringNames.
##
## Registered AFTER GameState in project.godot (spec 2.4). Reads GameState only
## from save_profile() / load_profile() / _notification(), never from _ready()
## or _init() - test_autoload_safety.gd's invariant.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_profile_save.tscn

const PATH := "user://profile.save"

## Bumped 1 -> 2 at spec 4.5, which changed what `active_party` MEANS: it was
## "the authored three-hero roster", it is now "the solo warrior". That is
## exactly the trigger spec 2.4's VERSION policy names ("bump when the meaning
## of an existing key changes"; adding a key alone never needs one).
##
## Spec 2.4 originally waived this bump, arguing nothing writes a save until
## boot.tscn at step 5. That was wrong - _notification() below writes on window
## close and has been live since step 2, so any dev who played and closed the
## window between steps 2 and 4 has a version-1 save holding the three-hero
## roster and possibly mage/ranger-equipped items. load_profile()'s gate is an
## exact match, so this bump discards those saves and boot.tscn falls back to
## new_profile() - rather than resurrecting a party 4.5 just retired, with
## orphaned gear still feeding party_bonuses().
##
## [levels] Bumped 2 -> 3: adding Item.level itself needs no bump (a new key,
## defaulting to 1 on read per from_dict()) - what triggers this one is that
## EVERY item already on disk would silently load at level 1, near-inert
## against level-scaled enemies and worth a fraction of its intended value.
## That is the same "an existing default now means something materially
## different" trigger the 1 -> 2 bump fired on, not a mere added key.
##
## [item power model] Bumped 3 -> 4: removing the UNCOMMON tier reindexes
## Item.Rarity (MAGIC 2->1, RARE 3->2, ENHANCED 4->3). rarity is stored as a
## raw int, so a v3 item's saved `2` would load as RARE and its `3` as
## ENHANCED - a found item silently becoming a rarity that can never be rolled.
## Same trigger again; the gate discards v3 saves and boot falls back to
## new_profile().
const VERSION := 4

## [content phase 0] Version -> the name of the function that migrates a
## payload FROM that version up to the next one, mutating and returning the
## dict (spec §3 Step 5 / §2.8). Empty today - VERSION has not moved past 4
## in this pass - but the chain is the deliverable: load_profile() walks it
## below instead of discarding every save that isn't an exact match, so the
## next bump needs one migration function and one entry here, not a rejected
## player file. A version with no entry (and no exact match) still falls back
## to new_profile(), same as before.
##
## A migration function does NOT set "version" - migrate() advances it after
## every step. test_profile_save.gd's S7 asserts every entry here names a real
## method, so a typo fails the suite rather than a player's first launch.
const MIGRATIONS := {}

## Walks payload `d` from its own "version" up to `target`, one step per
## version. `steps` maps a version to a Callable taking that version's payload
## and returning the next version's. Returns the migrated payload, or null
## when the save is from the future, a step is missing, or a step returns
## something other than a Dictionary - every one of which load_profile()
## treats as "start a new profile".
##
## The chain owns the version number, not each step. When the loop re-read
## "version" from the step's output instead, a migration that forgot to bump
## it re-ran the same step forever - a hang at boot, not a rejected save.
##
## Takes `steps` rather than reading MIGRATIONS so S7 can drive it with
## stand-in steps while the real table is still empty.
func migrate(d: Dictionary, target: int, steps: Dictionary) -> Variant:
	var version: int = int(d.get("version", 0))
	if version > target:
		return null
	while version < target:
		if not steps.has(version):
			return null
		var out: Variant = (steps[version] as Callable).call(d)
		if not (out is Dictionary):
			return null
		d = out
		version += 1
		d["version"] = version
	return d

## MIGRATIONS' method names, bound to this node - the shape migrate() takes.
func _migration_steps() -> Dictionary:
	var steps := {}
	for v: Variant in MIGRATIONS:
		steps[v] = Callable(self, StringName(MIGRATIONS[v]))
	return steps

## Every profile mutation in town saves (spec 2.4's "When to save" list); this
## is also called from GameState.new_profile(), from start_expedition() and the
## result-banking flow (later steps), and from _notification() below.
func save_profile() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveGame: cannot write %s (%d)" % [PATH, FileAccess.get_open_error()])
		return
	f.store_string(var_to_str({
		"version": VERSION,
		"gold": GameState.gold,
		"scrap": GameState.scrap,
		"active_party": GameState.active_party,
		# [day-night] four additive keys, no VERSION bump (town spec §2.4:
		# bump on a meaning change, never merely to add a key). A save written
		# before this pass loads with all four at their defaults, which is right
		# - it could only ever have been written in town, unfed, no night owed.
		"day_phase": int(GameState.day_phase),
		"day_number": GameState.day_number,
		"meal_pct": GameState.meal_pct,
		"meal_eaten_today": GameState.meal_eaten_today,
		"heroes": GameState.hero_runtime,
		"inventory": GameState.inventory.map(func(i: Item) -> Dictionary: return i.to_dict()),
		# [town] spec 7.4: the blacksmith's cached stock. Joins the dict here, at
		# step 10 - no VERSION bump, because a save written before this key existed
		# loads cleanly under load_profile()'s d.get(key, default) (spec 2.4's
		# VERSION policy: bump on a meaning change, never merely to add a key).
		"forge_stock": GameState.forge_stock.map(func(i: Item) -> Dictionary: return i.to_dict()),
		# [town] spec 7.4 / A1: distinct from forge_stock being non-empty, so that
		# buying out the stock does not present as "never generated" on next load.
		# No VERSION bump - same rule as forge_stock above (spec 2.4).
		"forge_stock_generated": GameState.forge_stock_generated,
		# [levels] Additive - no VERSION bump (same rule as forge_stock above).
		# Absent on a pre-existing save means every hero reads as level 1 / 0 xp,
		# which is exactly what that save's heroes actually are.
		"hero_levels": GameState.hero_levels,
		"hero_xp": GameState.hero_xp,
	}))

## Returns false when there is no save, or it is unreadable, or its version is
## from the future - every one of which means "start a new profile", not
## "crash". A corrupt save must never be a launch failure, and must never push
## an error that would fail a headless run. Mutates GameState only once the
## payload has passed the version gate, so a rejected load leaves it untouched.
func load_profile() -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = str_to_var(f.get_as_text())
	if not (data is Dictionary):
		return false
	var d: Dictionary = data

	# [content phase 0] A migration chain, not an exact-match gate (spec §3
	# Step 5 / §2.8) - a save from the future is still refused outright
	# (never guess forward), but anything older walks MIGRATIONS one step at
	# a time until it reaches VERSION or runs out of path, in which case it
	# falls back to new_profile() exactly as an exact-match miss always has.
	var migrated: Variant = migrate(d, VERSION, _migration_steps())
	if migrated == null:
		return false
	d = migrated

	GameState.gold = int(d.get("gold", 0))
	GameState.scrap = int(d.get("scrap", 0))

	var party: Array[StringName] = []
	for c: Variant in d.get("active_party", []):
		party.append(StringName(c))
	if not party.is_empty():
		GameState.active_party = party

	# [day-night] §8.1: all four default to a legacy save's only possible state.
	GameState.day_phase = int(d.get("day_phase", GameState.DayPhase.DAY)) as GameState.DayPhase
	# A QUEST-phase profile on disk is an interrupted expedition: mayor_office
	# ._accept() persists DAY -> QUEST before main.tscn loads (town §2.4), and a
	# quit or crash before RunController reaches T2 (QUEST -> NIGHT_PENDING)
	# leaves that state saved with no run scene to resume into. §8.2's resume
	# only re-presents NIGHT_PENDING, so a QUEST load would strand the player in
	# town behind the mayor's §2.3 guard with every quest locked and no night to
	# pass - the exact soft-lock §10.4 guards the endless path against, reached
	# by a real quest instead. Normalise to DAY and drop the dangling quest: the
	# interrupted day simply did not happen.
	if GameState.day_phase == GameState.DayPhase.QUEST:
		push_warning("load_profile(): QUEST-phase profile (interrupted expedition) - recovering to DAY")
		GameState.day_phase = GameState.DayPhase.DAY
		GameState.quest = null
	GameState.day_number = int(d.get("day_number", 1))
	GameState.meal_pct = int(d.get("meal_pct", 0))
	GameState.meal_eaten_today = bool(d.get("meal_eaten_today", false))

	var heroes: Array = []
	for entry: Variant in d.get("heroes", []):
		heroes.append((entry as Dictionary).duplicate(true))
	GameState.hero_runtime = heroes

	var inv: Array[Item] = []
	for raw: Variant in d.get("inventory", []):
		inv.append(Item.from_dict(raw))
	GameState.inventory = inv

	var stock: Array[Item] = []
	for raw: Variant in d.get("forge_stock", []):
		stock.append(Item.from_dict(raw))
	GameState.forge_stock = stock
	# A1: a save written before this key existed, but holding real stock, must not
	# present as never-generated - derive the default from the stock it carries.
	GameState.forge_stock_generated = bool(d.get("forge_stock_generated",
		not stock.is_empty()))

	# [levels] Rebuilt key-by-key rather than trusted verbatim, same defensive
	# shape as active_party above - a hand-edited or older save's raw dict could
	# carry a plain String key instead of a StringName.
	var raw_levels: Dictionary = d.get("hero_levels", {})
	var levels := {}
	for k: Variant in raw_levels.keys():
		levels[StringName(k)] = int(raw_levels[k])
	GameState.hero_levels = levels
	var raw_xp: Dictionary = d.get("hero_xp", {})
	var xp := {}
	for k: Variant in raw_xp.keys():
		xp[StringName(k)] = int(raw_xp[k])
	GameState.hero_xp = xp

	return true

## The mobile-critical line (spec 2.4). Android backgrounds the app without
## warning and may never return; a save that only happens on a clean quit is a
## save that never happens.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_profile()
