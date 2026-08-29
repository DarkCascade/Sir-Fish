extends Node
## The profile save round-trip (spec 2.4, 13.1). This is the test that matters
## most in the town pass, because a save bug is the only bug in that document
## that destroys player data.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_profile_save.tscn

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()
	var path: String = SaveGame.PATH

	# A real dev save at this path is snapshotted and restored by finish()
	# (step-2 Q8) - running the suite must never be a way to lose town progress.
	t.guard_user_file(path)

	# Start from a clean slate - a stale file from a previous run must not make
	# the missing-file case pass by accident.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# --- S0: new_profile() is memory-only and does NOT write to disk --------
	# Step-2 Q4. It is destructive and reset_run() calls it unconditionally on
	# every boot, so a save call inside it would overwrite the player's file
	# before boot.tscn ever got to load it. This is the assertion that fires if
	# anyone re-adds one.
	GameState.new_profile()
	t.check(not FileAccess.file_exists(path),
		"new_profile() does not write a save file (boot.tscn persists the fallback)")

	# --- S1: a missing file returns false and leaves GameState untouched ----
	var gold_before: int = GameState.gold
	var scrap_before: int = GameState.scrap
	var inv_before: int = GameState.inventory.size()
	t.check(not SaveGame.load_profile(), "load_profile() returns false when there is no file")
	t.check(GameState.gold == gold_before and GameState.scrap == scrap_before
		and GameState.inventory.size() == inv_before,
		"a missing file leaves GameState untouched")

	# --- S2: full round-trip ----------------------------------------------------
	GameState.new_profile()
	GameState.gold = 843
	GameState.scrap = 271

	# Three "equipped" items of different types and rarities, one forged twice,
	# plus one loose item. (Slots arrive in spec 4; distinct weapon_type stands
	# in for distinct slot here.)
	GameState.inventory.clear()
	var a := Itemizer.generate_item_with_rarity(Item.Rarity.MAGIC)
	a.weapon_type = &"axe"
	a.equipped_by = &"warrior"
	a.forge_count = 2
	var b := Itemizer.generate_item_with_rarity(Item.Rarity.RARE)
	b.weapon_type = &"bow"
	b.equipped_by = &"ranger"
	var c := Itemizer.generate_item_with_rarity(Item.Rarity.UNCOMMON)
	c.weapon_type = &"staff"
	c.equipped_by = &"mage"
	var loose := Itemizer.generate_item_with_rarity(Item.Rarity.COMMON)
	loose.equipped_by = &""
	GameState.inventory = [a, b, c, loose]

	# A wounded hero, and one killed outright.
	if GameState.hero_runtime.size() >= 2:
		GameState.hero_runtime[0]["current_hp"] = 4
		GameState.hero_runtime[0]["alive"] = true
		GameState.hero_runtime[1]["current_hp"] = 0
		GameState.hero_runtime[1]["alive"] = false

	var want_gold := GameState.gold
	var want_scrap := GameState.scrap
	var want_party := GameState.active_party.duplicate()
	var want_heroes := GameState.hero_runtime.duplicate(true)
	var want_items: Array[Dictionary] = []
	for it: Item in GameState.inventory:
		want_items.append(it.to_dict())

	SaveGame.save_profile()

	# Wipe live state, then load it back.
	GameState.gold = 0
	GameState.scrap = 0
	GameState.inventory = []
	GameState.hero_runtime = []
	GameState.active_party = [] as Array[StringName]

	t.check(SaveGame.load_profile(), "load_profile() returns true for a valid save")
	t.check(GameState.gold == want_gold, "gold round-trips (got %d, want %d)" % [GameState.gold, want_gold])
	t.check(GameState.scrap == want_scrap, "scrap round-trips (got %d, want %d)" % [GameState.scrap, want_scrap])
	t.check(GameState.active_party == want_party,
		"active_party round-trips as StringNames (got %s)" % [GameState.active_party])

	t.check(GameState.hero_runtime.size() == want_heroes.size(), "hero count round-trips")
	var heroes_ok := true
	for i: int in range(mini(GameState.hero_runtime.size(), want_heroes.size())):
		var got: Dictionary = GameState.hero_runtime[i]
		var exp: Dictionary = want_heroes[i]
		if got["stats_id"] != exp["stats_id"] or int(got["current_hp"]) != int(exp["current_hp"]) \
			or int(got["max_hp"]) != int(exp["max_hp"]) or bool(got["alive"]) != bool(exp["alive"]):
			heroes_ok = false
		if not (got["stats_id"] is StringName):
			heroes_ok = false
	t.check(heroes_ok, "every hero_runtime field round-trips, stats_id stays a StringName")

	t.check(GameState.inventory.size() == want_items.size(),
		"inventory count round-trips (got %d, want %d)" % [GameState.inventory.size(), want_items.size()])
	var items_ok := true
	for i: int in range(mini(GameState.inventory.size(), want_items.size())):
		var it: Item = GameState.inventory[i]
		var exp: Dictionary = want_items[i]
		if it.display_name != exp["display_name"] or int(it.rarity) != int(exp["rarity"]) \
			or it.weapon_type != exp["weapon_type"] or it.value != int(exp["value"]) \
			or it.equipped_by != exp["equipped_by"] or it.forge_count != int(exp["forge_count"]):
			items_ok = false
		if it.modifiers.size() != (exp["modifiers"] as Array).size():
			items_ok = false
		else:
			for k: int in range(it.modifiers.size()):
				var gm: Dictionary = it.modifiers[k]
				var em: Dictionary = exp["modifiers"][k]
				if gm["id"] != em["id"] or int(gm.get("roll", 0)) != int(em.get("roll", 0)) \
					or not is_equal_approx(float(gm.get("value_mult", 0.0)), float(em.get("value_mult", 0.0))) \
					or bool(gm.get("enhanced", false)) != bool(em.get("enhanced", false)):
					items_ok = false
	t.check(items_ok, "every item field and every modifier (id, roll, value_mult, enhanced) round-trips")

	t.check(GameState.inventory[0].forge_count == 2, "a forged item keeps its forge_count")

	# --- S3: a loaded item's modifiers do not alias Itemizer.MODIFIERS ---------
	# Find a loaded modifier whose id is in the constant table, mutate it, and
	# assert the constant is unchanged.
	var aliased := false
	for it: Item in GameState.inventory:
		for m: Dictionary in it.modifiers:
			for src: Dictionary in Itemizer.MODIFIERS:
				if src["id"] == m["id"]:
					var original_label: String = src["label"]
					m["label"] = "MUTATED"
					if src["label"] != original_label:
						aliased = true
					m["label"] = original_label
	t.check(not aliased, "mutating a loaded item's modifier does not touch Itemizer.MODIFIERS")

	# --- S4: a version from the future is rejected ----------------------------
	_write_raw(path, var_to_str({"version": 999, "gold": 1, "scrap": 1,
		"active_party": [&"warrior"], "street_sleep_used": false,
		"heroes": [], "inventory": []}))
	var g := GameState.gold
	t.check(not SaveGame.load_profile(), "load_profile() rejects a version from the future")
	t.check(GameState.gold == g, "a rejected version leaves GameState untouched")

	# --- S5: corrupt bytes are rejected without a fatal error -----------------
	_write_raw(path, "{ this is not a var_to_str payload ][")
	t.check(not SaveGame.load_profile(), "load_profile() rejects garbage bytes")
	_write_raw(path, var_to_str({"version": 1, "gold": 5}).substr(0, 12))   # truncated
	t.check(not SaveGame.load_profile(), "load_profile() rejects a truncated payload")

	# Clean up so the next headless run starts fresh.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	t.finish(get_tree(), "test_profile_save")

func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
