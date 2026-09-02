extends Node
## The profile/expedition split (spec 2.1-2.3). Pins the ONE thing the split
## exists to guarantee - that start_expedition() leaves profile state alone -
## plus the wounded-hero branch of _reset_hero_runtime(), which nothing else
## reaches while reset_run() is still the only caller of either half.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_profile_expedition.tscn

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()

	# --- P1: new_profile() starts everything a player owns ------------------
	# Spec 14 step 2 replaced new_profile()'s step-1 placeholders: gold/scrap now
	# come from spec 11's PROFILE_STARTING_* constants, not STARTING_GOLD (75).
	GameState.new_profile()
	t.check(GameState.gold == Tuning.PROFILE_STARTING_GOLD,
		"new_profile() sets gold to PROFILE_STARTING_GOLD (got %d)" % GameState.gold)
	t.check(GameState.scrap == Tuning.PROFILE_STARTING_SCRAP, "new_profile() sets scrap to PROFILE_STARTING_SCRAP")
	t.check(GameState.inventory.is_empty(), "new_profile() empties the inventory")
	t.check(GameState.day_phase == GameState.DayPhase.DAY, "new_profile() starts in DAY")
	t.check(GameState.hero_runtime.size() == GameState.active_party.size(),
		"new_profile() builds one hero_runtime entry per active_party member")
	var all_full := true
	for entry: Dictionary in GameState.hero_runtime:
		if int(entry["current_hp"]) != int(entry["max_hp"]) or not entry["alive"]:
			all_full = false
	t.check(all_full, "new_profile() leaves every hero at full hp and alive")

	# --- P2: start_expedition() alone does NOT touch profile state ----------
	# Spec 2.3: "Note what is absent: gold, scrap and inventory. That absence
	# is the whole point of this function existing separately from
	# new_profile(), and is the one thing a future edit here must not undo."
	# This is the assertion that fails if someone ever "tidies" that absence.
	GameState.gold = 512
	GameState.scrap = 37
	var kept := Itemizer.generate_item()
	GameState.inventory.append(kept)

	GameState.start_expedition()

	t.check(GameState.gold == 512,
		"start_expedition() does not touch gold (got %d, want 512)" % GameState.gold)
	t.check(GameState.scrap == 37,
		"start_expedition() does not touch scrap (got %d, want 37)" % GameState.scrap)
	t.check(GameState.inventory.size() == 1 and GameState.inventory[0] == kept,
		"start_expedition() does not touch the inventory")

	# --- P3: start_expedition() DOES reset everything an expedition owns ----
	t.check(GameState.current_encounter_index == -1,
		"start_expedition() rewinds current_encounter_index")
	t.check(GameState.endless_level_number == 1,
		"start_expedition() starts at depth 1 (got %d)" % GameState.endless_level_number)
	t.check(GameState.level != null, "start_expedition() builds a level")
	t.check(GameState.expedition_gold == 0 and GameState.expedition_scrap == 0,
		"start_expedition() zeroes the expedition banks")
	t.check(GameState.drops_by_class.is_empty(), "start_expedition() clears drops_by_class")
	t.check(GameState._expedition_inventory_mark == 1,
		"start_expedition() marks the inventory size it started at (got %d, want 1)"
			% GameState._expedition_inventory_mark)

	# --- P4: the wounded-hero branch (_reset_hero_runtime(false)) -----------
	# The inn is the heal (spec 2.1) - damage must survive a new expedition.
	# Unreachable while reset_run() is the only caller, which is exactly why
	# it is asserted here rather than left for the first real caller to find.
	if GameState.hero_runtime.is_empty():
		t.check(false, "hero_runtime is populated (cannot test the wounded branch)")
	else:
		var wounded_id: StringName = GameState.hero_runtime[0]["stats_id"]
		var wounded_max: int = int(GameState.hero_runtime[0]["max_hp"])
		GameState.hero_runtime[0]["current_hp"] = 3
		GameState.hero_runtime[0]["alive"] = true
		# A second hero killed outright, to prove `alive` is derived, not assumed.
		var had_corpse := GameState.hero_runtime.size() > 1
		if had_corpse:
			GameState.hero_runtime[1]["current_hp"] = 0
			GameState.hero_runtime[1]["alive"] = false

		GameState.start_expedition()

		var after: Dictionary = GameState.hero_runtime[0]
		t.check(after["stats_id"] == wounded_id,
			"start_expedition() keeps hero order stable")
		t.check(int(after["current_hp"]) == 3,
			"start_expedition() carries a wounded hero's hp home (got %d, want 3)"
				% int(after["current_hp"]))
		t.check(int(after["max_hp"]) == wounded_max,
			"start_expedition() re-reads max_hp from the stats resource")
		t.check(after["alive"], "a hero at 3 hp is still alive")
		if had_corpse:
			t.check(int(GameState.hero_runtime[1]["current_hp"]) == 0,
				"start_expedition() does not resurrect a dead hero")
			t.check(not GameState.hero_runtime[1]["alive"],
				"alive is derived from hp, not assumed true")

		# ...and new_profile() is the thing that DOES heal.
		GameState.new_profile()
		t.check(int(GameState.hero_runtime[0]["current_hp"]) == wounded_max,
			"new_profile() full-heals the wounded hero")

	# --- P5: reset_run() is still both halves, in order ---------------------
	# Spec 13.3 keeps this function alive for the whole pass; this is its
	# contract, and it is what test_endless_level_gen.gd leans on.
	GameState.gold = 999
	GameState.scrap = 99
	GameState.inventory.append(Itemizer.generate_item())
	GameState.endless_level_number = 7

	GameState.reset_run()

	t.check(GameState.gold == Tuning.PROFILE_STARTING_GOLD,
		"reset_run() still resets gold (got %d)" % GameState.gold)
	t.check(GameState.scrap == Tuning.PROFILE_STARTING_SCRAP, "reset_run() still resets scrap")
	t.check(GameState.inventory.is_empty(), "reset_run() still empties the inventory")
	t.check(GameState.endless_level_number == 1, "reset_run() still rewinds to depth 1")
	t.check(GameState.current_encounter_index == -1,
		"reset_run() still rewinds current_encounter_index")

	# --- P6: active_party is the solo warrior; PARTY_ORDER is intact -------
	# Spec 4.5 flips active_party's VALUE to [&"warrior"]; PARTY_ORDER stays the
	# canonical 3-hero roster (spec 0.2 "PARTY_ORDER is not deleted"). P6 runs
	# after reset_run() at P5, i.e. post-new_profile(), so [&"warrior"] is the
	# expected value. The second check trips if a future tidy-up trims the
	# roster to match. The `as Array[StringName]` cast is required: an untyped
	# [&"x"] literal will not compare == to a typed Array[StringName] in GDScript.
	t.check(GameState.active_party == ([&"warrior"] as Array[StringName]),
		"active_party is the solo warrior (got %s)" % [GameState.active_party])
	t.check(GameState.PARTY_ORDER.size() == 3,
		"PARTY_ORDER is untouched - the 3-hero roster still exists (spec 4.5)")

	t.finish(get_tree(), "test_profile_expedition")
