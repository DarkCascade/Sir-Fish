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
const VERSION := 1

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

	return true

## The mobile-critical line (spec 2.4). Android backgrounds the app without
## warning and may never return; a save that only happens on a clean quit is a
## save that never happens.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_profile()
