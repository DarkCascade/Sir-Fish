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
const VERSION := 2

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
		"street_sleep_used": GameState.street_sleep_used,
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
	if int(d.get("version", 0)) != VERSION:
		return false

	GameState.gold = int(d.get("gold", 0))
	GameState.scrap = int(d.get("scrap", 0))

	var party: Array[StringName] = []
	for c: Variant in d.get("active_party", []):
		party.append(StringName(c))
	if not party.is_empty():
		GameState.active_party = party

	GameState.street_sleep_used = bool(d.get("street_sleep_used", false))

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

	return true

## The mobile-critical line (spec 2.4). Android backgrounds the app without
## warning and may never return; a save that only happens on a clean quit is a
## save that never happens.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_profile()
