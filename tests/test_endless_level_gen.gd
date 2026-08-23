extends Node
## GameState's endless level generator (spec: Endless Mode).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_endless_level_gen.tscn

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()

	GameState.reset_run()
	t.check(GameState.endless_mode, "endless_mode defaults to true")
	t.check(GameState.endless_level_number == 1, "reset_run() starts at depth 1")

	_check_level_shape(t, GameState.level, "depth 1")

	# Every enemy id the generator can produce must resolve to real stats -
	# this is the check that would have caught a typo in the enemy pools.
	for id: StringName in GameState.ENDLESS_EARLY_POOL:
		t.check(GameState.get_stats(id) != null, "early pool '%s' resolves to real stats" % id)
	for id: StringName in GameState.ENDLESS_MID_POOL:
		t.check(GameState.get_stats(id) != null, "mid pool '%s' resolves to real stats" % id)
	for id: StringName in GameState.BOSS_POOL:
		t.check(GameState.get_stats(id) != null, "boss pool '%s' resolves to real stats" % id)

	# Depth 1: only the early pool should ever appear in the three REGULAR
	# combat slots (0, 2, 4) - encounter 5 is always a boss fight and is
	# checked separately below, at every depth including 1.
	var depth1 := GameState.level
	var combat1: EncounterDef = depth1.encounters[0]
	t.check(combat1.enemy_stat_ids.size() == 2, "depth 1 combat group size is 2")
	# Checked as "only ever early-pool ids" rather than "never mid/boss pool
	# ids" - BOSS_POOL is all four skeletons now, which overlaps both the
	# early pool (skeleton_minion) and the mid pool (the other three), so the
	# exclusion check would false-positive on a perfectly legal early-pool draw.
	var only_early_at_depth1 := true
	for i: int in range(30):
		GameState.endless_level_number = 1
		var lvl: LevelDef = GameState.build_level()
		for enc_index: int in [0, 2, 4]:
			var enc: EncounterDef = lvl.encounters[enc_index]
			for id: StringName in enc.enemy_stat_ids:
				if id not in GameState.ENDLESS_EARLY_POOL:
					only_early_at_depth1 = false
	t.check(only_early_at_depth1, "depth 1's regular combat slots only ever draw the early pool")
	t.check(depth1.encounters[5].enemy_stat_ids[0] in GameState.BOSS_POOL,
		"depth 1's boss encounter still leads with a boss-pool id")

	# Depth 5: the mid pool has joined, and the group size has scaled up to
	# the cap (2 + 5/3 = 3, integer division).
	GameState.endless_level_number = 5
	var depth5: LevelDef = GameState.build_level()
	_check_level_shape(t, depth5, "depth 5")
	var combat5: EncounterDef = depth5.encounters[0]
	t.check(combat5.enemy_stat_ids.size() == 3, "depth 5 combat group size scales to 3")

	# Every boss slot (encounter 6) leads with a boss-pool id, same
	# convention as the fixed level's boss encounter.
	var boss_enc: EncounterDef = depth5.encounters[5]
	t.check(boss_enc.is_boss, "encounter 6 is flagged as the boss fight")
	t.check(boss_enc.enemy_stat_ids[0] in GameState.BOSS_POOL,
		"boss encounter's first id is from the boss pool")

	t.finish(get_tree(), "test_endless_level_gen")

## Shape every generated level must share: 6 encounters in the established
## COMBAT/LOOT/COMBAT/SHOP/COMBAT/boss-COMBAT rhythm.
func _check_level_shape(t: TestSupport, lvl: LevelDef, label: String) -> void:
	t.check(lvl.encounters.size() == 6, "%s: six encounters" % label)
	if lvl.encounters.size() != 6:
		return
	var expect_types := [
		EncounterDef.Type.COMBAT, EncounterDef.Type.LOOT, EncounterDef.Type.COMBAT,
		EncounterDef.Type.SHOP, EncounterDef.Type.COMBAT, EncounterDef.Type.COMBAT,
	]
	for i: int in range(6):
		var enc: EncounterDef = lvl.encounters[i]
		t.check(enc.type == expect_types[i], "%s: encounter %d has the expected type" % [label, i])
		if enc.type == EncounterDef.Type.COMBAT:
			t.check(enc.enemy_stat_ids.size() > 0, "%s: combat encounter %d has enemies" % [label, i])
			for id: StringName in enc.enemy_stat_ids:
				t.check(GameState.get_stats(id) != null,
					"%s: encounter %d enemy id '%s' is real" % [label, i, id])
