extends Node
## The upgrade system (spec 17.6 / 19.3).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_upgrades.tscn
##
## Asserts the cost curve against spec 17.6's table exactly, is_maxed at the
## ceiling, the derived multipliers at every level, and that reset() clears
## everything.
##
## [slot phase 2] `fat_purse` ("Gold pays +X%") retired with slot gold and was
## replaced by `polish` ("Remove X blanks from the reel"). Its base and growth
## were kept at fat_purse's exact numbers, so the cost table and the
## "maxing all three costs 2,408 G" total are unchanged; only the effect the
## third upgrade delivers is different, and the old gold-payout / strip
## assertions are gone.

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()
	Upgrades.reset()

	# --- the three upgrades are quick_reels / overcharge / polish ---
	t.check(Upgrades.ORDER == ([&"quick_reels", &"overcharge", &"polish"] as Array[StringName]),
		"the tray's three upgrades are quick_reels, overcharge, polish")
	t.check(not Upgrades.DEFS.has(&"fat_purse"), "fat_purse is gone")

	# --- cost curve: spec 17.6's table, to the gold ---
	var expected := {
		&"quick_reels": [60, 114, 217, 412],
		&"overcharge": [70, 133, 253, 480],
		&"polish": [50, 95, 181, 343],
	}
	for id: StringName in expected.keys():
		var costs: Array = expected[id]
		t.check(costs.size() == Tuning.UPGRADE_MAX_LEVEL,
			"%s's cost table covers all %d levels (has %d)"
				% [id, Tuning.UPGRADE_MAX_LEVEL, costs.size()])
		Upgrades.levels[id] = 0
		for level: int in range(Tuning.UPGRADE_MAX_LEVEL):
			Upgrades.levels[id] = level
			t.check(Upgrades.cost(id) == int(costs[level]),
				"%s level %d costs %d (got %d)" % [id, level + 1, costs[level],
					Upgrades.cost(id)])
		Upgrades.levels[id] = Tuning.UPGRADE_MAX_LEVEL
		t.check(Upgrades.is_maxed(id), "%s is maxed at level %d" % [id, Tuning.UPGRADE_MAX_LEVEL])
		t.check(Upgrades.cost(id) == -1, "%s costs -1 once maxed" % id)
	Upgrades.reset()

	# Maxing everything still costs 2,408 gold (polish kept fat_purse's numbers).
	var total := 0
	for id: StringName in expected.keys():
		for c: int in (expected[id] as Array):
			total += c
	t.check(total == 2408, "maxing all three upgrades costs 2,408 gold (got %d)" % total)

	# --- derived effects at every level, level 0 through the ceiling ---
	var quick_expected := [1.00, 0.86, 0.7396, 0.636056, 0.54700816]
	var over_expected := [1.00, 1.25, 1.50, 1.75, 2.00]
	var polish_expected := [0, 2, 4, 6, 8]
	t.check(quick_expected.size() == Tuning.UPGRADE_MAX_LEVEL + 1,
		"the effect tables cover level 0 through %d" % Tuning.UPGRADE_MAX_LEVEL)
	for level: int in range(Tuning.UPGRADE_MAX_LEVEL + 1):
		Upgrades.levels[&"quick_reels"] = level
		Upgrades.levels[&"overcharge"] = level
		Upgrades.levels[&"polish"] = level
		t.check_near(Upgrades.quick_reels_mult(), quick_expected[level], 0.0005,
			"quick_reels multiplier at level %d" % level)
		t.check_near(Upgrades.overcharge_mult(), over_expected[level], 0.0005,
			"overcharge multiplier at level %d (now lifts every damage icon)" % level)
		t.check(Upgrades.polish_blanks_removed() == int(polish_expected[level]),
			"polish removes %d blanks at level %d" % [polish_expected[level], level])

	# The base cycle is 1.10 + 0.28 + 0.28 + 0.85 = 2.51 s; at Quick Reels 3 the
	# whole cycle compresses to 1.60 s (spec 16.3).
	var base_cycle := Tuning.SLOT_SPIN_DURATION + Tuning.SLOT_REEL_STAGGER * 2.0 \
		+ Tuning.SLOT_RESULT_HOLD
	t.check_near(base_cycle, 2.51, 0.001, "base spin cycle is 2.51 s")
	Upgrades.levels[&"quick_reels"] = 3
	t.check_near(base_cycle * Upgrades.quick_reels_mult(), 1.60, 0.01,
		"spin cycle at Quick Reels 3 is 1.60 s")

	# --- polish drives the bag's blank pad toward, but never past, the floor ---
	Upgrades.reset()
	for level: int in range(Tuning.UPGRADE_MAX_LEVEL + 1):
		Upgrades.levels[&"polish"] = level
		var pad := maxi(Tuning.SLOT_BLANK_PAD_START - Upgrades.polish_blanks_removed(),
			Tuning.SLOT_BLANK_PAD_FLOOR)
		t.check(pad >= Tuning.SLOT_BLANK_PAD_FLOOR,
			"blank pad at polish %d (%d) is at or above the floor %d"
				% [level, pad, Tuning.SLOT_BLANK_PAD_FLOOR])
	Upgrades.levels[&"polish"] = Tuning.UPGRADE_MAX_LEVEL
	t.check(maxi(Tuning.SLOT_BLANK_PAD_START - Upgrades.polish_blanks_removed(),
		Tuning.SLOT_BLANK_PAD_FLOOR) == Tuning.SLOT_BLANK_PAD_FLOOR,
		"maxed polish lands the blank pad exactly on the floor")

	# --- buy() spends gold and refuses when broke ---
	Upgrades.reset()
	GameState.gold = 0
	t.check(not Upgrades.buy(&"quick_reels"), "buy() refuses with no gold")
	t.check(Upgrades.level(&"quick_reels") == 0, "a refused buy does not raise the level")
	GameState.gold = 60
	t.check(Upgrades.buy(&"quick_reels"), "buy() succeeds at exactly the cost")
	t.check(Upgrades.level(&"quick_reels") == 1, "the level advanced to 1")
	t.check(GameState.gold == 0, "the gold was spent")
	t.check(int(GameState.run_stats["gold_spent"]) >= 60, "gold_spent tracked the purchase")
	t.check(int(GameState.run_stats["upgrades_bought"]) == 1, "upgrades_bought incremented")

	Upgrades.levels[&"overcharge"] = Tuning.UPGRADE_MAX_LEVEL
	GameState.gold = 9999
	t.check(not Upgrades.buy(&"overcharge"), "buy() refuses a maxed upgrade")

	# --- reset() clears everything (spec 17.6: upgrades are run-scoped) ---
	Upgrades.levels[&"quick_reels"] = 2
	Upgrades.levels[&"overcharge"] = 3
	Upgrades.levels[&"polish"] = 1
	Upgrades.reset()
	var all_zero := true
	for id: StringName in Upgrades.DEFS.keys():
		if Upgrades.level(id) != 0:
			all_zero = false
	t.check(all_zero, "reset() puts every level back to 0")

	t.finish(get_tree(), "test_upgrades")
