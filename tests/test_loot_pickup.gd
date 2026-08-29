extends Node
## LootPickup - the value split and the headless award path (spec 9.3 / 9.4,
## build-order step 9).
##
## The ballistic arc is a tween and needs a running battle to see; what reduces
## to a headless invariant is the arithmetic: the instalments a kill pays sum to
## the value rolled, the count is capped at LOOT_PICKUP_MAX_OBJECTS, and every
## pickup credits BOTH the profile total and the expedition bank the result
## modal reads (spec 8.4).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_loot_pickup.tscn

const TestSupport := preload("res://tests/test_support.gd")
const LootPickupScript := preload("res://scripts/battle/loot_pickup.gd")

func _ready() -> void:
	var t := TestSupport.new()

	# --- _split: whole shares that sum back to value (spec 9.3) --------------
	var split_bad := 0
	var count_bad := 0
	for value: int in [1, 2, 3, 4, 5, 6, 7, 9, 18, 27, 50, 100]:
		var count: int = mini(value, Tuning.LOOT_PICKUP_MAX_OBJECTS)
		var shares: Array = LootPickupScript._split(value, count)
		var sum := 0
		for s: int in shares:
			sum += s
		if sum != value:
			split_bad += 1
		if shares.size() != count:
			count_bad += 1
	t.check(split_bad == 0, "_split() shares always sum back to the value (%d bad)" % split_bad)
	t.check(count_bad == 0,
		"_split() object count is mini(value, LOOT_PICKUP_MAX_OBJECTS) (%d bad)" % count_bad)
	t.check((LootPickupScript._split(7, 5) as Array) == [2, 2, 1, 1, 1],
		"_split(7, 5) is [2,2,1,1,1] - the remainder rides the first shares")

	# --- headless award path: both totals and both banks move (spec 8.4/9.4) --
	GameState.gold = 0
	GameState.scrap = 0
	GameState.expedition_gold = 0
	GameState.expedition_scrap = 0

	var gold_lo: int = Tuning.ENEMY_GOLD_DROP.x
	var gold_hi: int = Tuning.ENEMY_GOLD_DROP.y
	var scrap_lo: int = Tuning.ENEMY_SCRAP_DROP.x
	var scrap_hi: int = Tuning.ENEMY_SCRAP_DROP.y

	var out_of_band := 0
	for i: int in range(400):
		var g0 := GameState.gold
		var s0 := GameState.scrap
		var eg0 := GameState.expedition_gold
		var es0 := GameState.expedition_scrap
		LootPickupScript.spawn_for(Vector3.ZERO, false)
		var dg := GameState.gold - g0
		var ds := GameState.scrap - s0
		# The profile total and the expedition bank move by the same amount.
		if GameState.expedition_gold - eg0 != dg or GameState.expedition_scrap - es0 != ds:
			out_of_band += 1
		if dg < gold_lo or dg > gold_hi or ds < scrap_lo or ds > scrap_hi:
			out_of_band += 1
	t.check(out_of_band == 0,
		"a grunt kill pays gold in %s and scrap in %s, into both the profile and the expedition bank (%d off)"
			% [Tuning.ENEMY_GOLD_DROP, Tuning.ENEMY_SCRAP_DROP, out_of_band])

	# --- the boss unit triples both rolls (spec 11.1) -----------------------
	var boss_bad := 0
	for i: int in range(400):
		var g0 := GameState.gold
		var s0 := GameState.scrap
		LootPickupScript.spawn_for(Vector3.ZERO, true)
		var dg := GameState.gold - g0
		var ds := GameState.scrap - s0
		if dg < gold_lo * Tuning.BOSS_LOOT_MULT or dg > gold_hi * Tuning.BOSS_LOOT_MULT:
			boss_bad += 1
		if ds < scrap_lo * Tuning.BOSS_LOOT_MULT or ds > scrap_hi * Tuning.BOSS_LOOT_MULT:
			boss_bad += 1
	t.check(boss_bad == 0,
		"a boss-unit kill pays BOSS_LOOT_MULT x the grunt ranges (%d off)" % boss_bad)

	t.finish(get_tree(), "test_loot_pickup")
