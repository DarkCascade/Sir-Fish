extends Node
## The upgrade system (spec 17.6 / 19.3).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_upgrades.tscn
##
## Asserts the cost curve against spec 17.6's table exactly, is_maxed at the
## ceiling, the payout maths at every level combination, and that reset() clears
## everything. Also asserts the thing upgrades must NEVER do: touch the strip.
##
## [ui-project-longshot] The tables below are per-level and UPGRADE_MAX_LEVEL
## moved from 3 to 4, so they grew a column. The loop already read the constant
## while the tables did not, which meant raising it walked off the end of the
## array and took the whole test down after three passing lines - so the sizes
## are now asserted up front, and a future change to the ceiling fails as a
## readable check rather than as an index crash.

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()
	Upgrades.reset()

	# --- cost curve: spec 17.6's table, to the gold ---
	var expected := {
		&"quick_reels": [60, 114, 217, 412],
		&"overcharge": [70, 133, 253, 480],
		&"fat_purse": [50, 95, 181, 343],
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

	# Maxing everything costs 2,408 gold (was 1,173 over three levels).
	var total := 0
	for id: StringName in expected.keys():
		for c: int in (expected[id] as Array):
			total += c
	t.check(total == 2408, "maxing all three upgrades costs 2,408 gold (got %d)" % total)

	# --- payout multipliers at every level, level 0 through the ceiling ---
	var quick_expected := [1.00, 0.86, 0.7396, 0.636056, 0.54700816]
	var over_expected := [1.00, 1.25, 1.50, 1.75, 2.00]
	var purse_expected := [1.00, 1.40, 1.80, 2.20, 2.60]
	t.check(quick_expected.size() == Tuning.UPGRADE_MAX_LEVEL + 1,
		"the multiplier tables cover level 0 through %d" % Tuning.UPGRADE_MAX_LEVEL)
	for level: int in range(Tuning.UPGRADE_MAX_LEVEL + 1):
		Upgrades.levels[&"quick_reels"] = level
		Upgrades.levels[&"overcharge"] = level
		Upgrades.levels[&"fat_purse"] = level
		t.check_near(Upgrades.quick_reels_mult(), quick_expected[level], 0.0005,
			"quick_reels multiplier at level %d" % level)
		t.check_near(Upgrades.overcharge_mult(), over_expected[level], 0.0005,
			"overcharge multiplier at level %d" % level)
		t.check_near(Upgrades.fat_purse_mult(), purse_expected[level], 0.0005,
			"fat_purse multiplier at level %d" % level)

	# The base cycle is 1.10 + 0.28 + 0.28 + 0.85 = 2.51 s; at Quick Reels 3 the
	# whole cycle compresses to 1.60 s (spec 16.3).
	var base_cycle := Tuning.SLOT_SPIN_DURATION + Tuning.SLOT_REEL_STAGGER * 2.0 \
		+ Tuning.SLOT_RESULT_HOLD
	t.check_near(base_cycle, 2.51, 0.001, "base spin cycle is 2.51 s")
	Upgrades.levels[&"quick_reels"] = 3
	t.check_near(base_cycle * Upgrades.quick_reels_mult(), 1.60, 0.01,
		"spin cycle at Quick Reels 3 is 1.60 s")

	# --- gold payout scaling (spec 16.5) ---
	Upgrades.reset()
	t.check(int(round(float(Tuning.SLOT_PAY_2_GOLD) * Upgrades.fat_purse_mult())) == 35,
		"a 2x gold win pays 35 at Fat Purse 0")
	Upgrades.levels[&"fat_purse"] = 3
	t.check(int(round(float(Tuning.SLOT_PAY_3_GOLD) * Upgrades.fat_purse_mult())) == 198,
		"a 3x gold win pays 198 at Fat Purse 3 (90 x 2.20)")

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

	# The ceiling, not a literal 3 - at UPGRADE_MAX_LEVEL 4 a level-3 upgrade is
	# still buyable, so this would have passed only because the gold above was
	# already spent, testing nothing.
	Upgrades.levels[&"overcharge"] = Tuning.UPGRADE_MAX_LEVEL
	GameState.gold = 9999
	t.check(not Upgrades.buy(&"overcharge"), "buy() refuses a maxed upgrade")

	# --- reset() clears everything (spec 17.6: upgrades are run-scoped) ---
	Upgrades.levels[&"quick_reels"] = 2
	Upgrades.levels[&"overcharge"] = 3
	Upgrades.levels[&"fat_purse"] = 1
	Upgrades.reset()
	var all_zero := true
	for id: StringName in Upgrades.DEFS.keys():
		if Upgrades.level(id) != 0:
			all_zero = false
	t.check(all_zero, "reset() puts every level back to 0")

	# --- what upgrades must NEVER do (spec 17.6) ---
	t.check(Tuning.SLOT_STRIP.size() == 27, "the strip is still 27 stops after all of that")
	var counts := {}
	for sym: int in Tuning.SLOT_STRIP:
		counts[sym] = int(counts.get(sym, 0)) + 1
	t.check(int(counts[Tuning.Sym.LIGHTNING]) == 7 and int(counts[Tuning.Sym.GOLD]) == 7
		and int(counts[Tuning.Sym.PLUS]) == 7 and int(counts[Tuning.Sym.BLANK]) == 6,
		"the strip is still 7/7/7/6 - upgrades never touch the odds")

	t.finish(get_tree(), "test_upgrades")
