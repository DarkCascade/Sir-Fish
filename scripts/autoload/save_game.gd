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
##
## [inn & recovery] Bumped 4 -> 5: the day/night cycle is gone. Its three keys
## would merely be ignored, but a v4 save written with a night still owed
## (day_phase NIGHT_PENDING) holds a party that never got its post-quest
## recovery - downed heroes at 0 HP beside an old quest board - and nothing
## would ever apply it now. _migrate_4_to_5() does, the first real migration.
const VERSION := 5

## [content phase 0] Version -> the name of the function that migrates a
## payload FROM that version up to the next one, mutating and returning the
## dict (spec §3 Step 5 / §2.8). load_profile() walks it below instead of
## discarding every save that isn't an exact match, so a bump needs one
## migration function and one entry here, not a rejected player file. A
## version with no entry (and no exact match) still falls back to
## new_profile(), same as before - which is what v1-v3 saves still do.
##
## A migration function does NOT set "version" - migrate() advances it after
## every step. test_profile_save.gd's S7 asserts every entry here names a real
## method, so a typo fails the suite rather than a player's first launch.
const MIGRATIONS := {
	4: "_migrate_4_to_5",
}

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
## stand-in steps as well as the real table.
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

## [inn & recovery] v4 -> v5 (see VERSION). Drops day_phase, day_number and
## meal_eaten_today. A save written with a night still owed also gets the
## recovery it never received: every hero up to at least RECOVERY_HP_FRACTION of
## max HP - the wipe rule, which is never worse for the player than the victory
## one, and the save does not record which ending it was - and a fresh board.
## A save written mid-quest (the old QUEST phase) needs nothing: the quest
## itself was never saved, so it already loads as a party standing in town.
func _migrate_4_to_5(d: Dictionary) -> Dictionary:
	const NIGHT_PENDING := 2   # the retired GameState.DayPhase value
	if int(d.get("day_phase", 0)) == NIGHT_PENDING:
		for entry: Variant in d.get("heroes", []):
			var e := entry as Dictionary
			var floor_hp: int = ceili(float(int(e.get("max_hp", 0))) * Tuning.RECOVERY_HP_FRACTION)
			e["current_hp"] = maxi(int(e.get("current_hp", 0)), floor_hp)
			e["alive"] = int(e["current_hp"]) > 0
		d["quest_board"] = []
		d["quest_board_generated"] = false
	d.erase("day_phase")
	d.erase("day_number")
	d.erase("meal_eaten_today")
	return d

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
		# [inn & recovery] An unspent meal survives a quit (GameState.meal_pct).
		"meal_pct": GameState.meal_pct,
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
		# [content phase 1] The mayor's generated board (spec §3 Step 3.2).
		# Additive, same as forge_stock above - no VERSION bump (content-phase-1
		# questions doc Q8 explains the divergence from the spec's literal "bump
		# it" instruction).
		"quest_board": GameState.quest_board.map(func(q: QuestDef) -> Dictionary: return q.to_dict()),
		"quest_board_generated": GameState.quest_board_generated,
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

	GameState.meal_pct = int(d.get("meal_pct", 0))

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

	# [content phase 1] The mayor's generated board (spec §3 Step 3.2). Absent
	# on a pre-existing save reads as "never generated" (both defaults below),
	# which is exactly true of a save written before this key existed.
	var board: Array[QuestDef] = []
	for raw: Variant in d.get("quest_board", []):
		board.append(QuestDef.from_dict(raw))
	GameState.quest_board = board
	GameState.quest_board_generated = bool(d.get("quest_board_generated", false))

	return true

## The mobile-critical line (spec 2.4). Android backgrounds the app without
## warning and may never return; a save that only happens on a clean quit is a
## save that never happens.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_profile()
