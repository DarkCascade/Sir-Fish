extends Node
## Slot odds verification (spec 16.2).
##
## Run headless from the project root:
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_slot_odds.tscn
##
## Asserts the observed win rate over 1,000,000 simulated spins is inside
## [0.490, 0.510] and that each symbol's 3-of-a-kind rate is inside
## [0.014, 0.021]. Also enumerates all 27^3 = 19,683 outcomes exactly, so the
## strip can be re-verified after any edit.

const TestSupport := preload("res://tests/test_support.gd")

const TuningScript := preload("res://scripts/autoload/tuning.gd")

const SPINS := 1_000_000
const WIN_RATE_MIN := 0.490
const WIN_RATE_MAX := 0.510
const THREE_RATE_MIN := 0.014
const THREE_RATE_MAX := 0.021

func _ready() -> void:
	var t := TestSupport.new()
	var strip: Array = TuningScript.SLOT_STRIP
	var stops: int = TuningScript.SLOT_REEL_STOPS
	var blank: int = TuningScript.Sym.BLANK

	t.check(strip.size() == stops, "SLOT_STRIP has exactly %d entries" % stops)

	_check_composition(t, strip)
	_enumerate(t, strip, stops, blank)
	_simulate(t, strip, stops, blank)
	t.finish(get_tree(), "test_slot_odds")

## Exhaustive: every one of the 19,683 outcomes, no estimation.
func _enumerate(t: RefCounted, strip: Array, stops: int, blank: int) -> void:
	var total := 0
	var wins := 0
	var three_of := {}
	for a: int in range(stops):
		for b: int in range(stops):
			for c: int in range(stops):
				total += 1
				var result := _evaluate([strip[a], strip[b], strip[c]], blank)
				if int(result["count"]) >= 2:
					wins += 1
				if int(result["count"]) == 3:
					var sym := int(result["symbol"])
					three_of[sym] = int(three_of.get(sym, 0)) + 1
	print("--- exhaustive enumeration ---")
	print("outcomes: %d, wins: %d, P(win) = %.6f" % [total, wins, float(wins) / float(total)])
	for sym: Variant in three_of.keys():
		print("  3x symbol %d: %d (%.5f)" % [
			int(sym), int(three_of[sym]), float(three_of[sym]) / float(total)])
	t.check(total == 19683, "exhaustive enumeration covers 27^3 = 19,683 outcomes")
	t.check(wins == 9849, "exhaustive enumeration counts exactly 9,849 winning outcomes")

func _simulate(t: RefCounted, strip: Array, stops: int, blank: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var wins := 0
	var three_of := {}
	for i: int in range(SPINS):
		var symbols: Array = [
			strip[rng.randi_range(0, stops - 1)],
			strip[rng.randi_range(0, stops - 1)],
			strip[rng.randi_range(0, stops - 1)],
		]
		var result := _evaluate(symbols, blank)
		if int(result["count"]) >= 2:
			wins += 1
		if int(result["count"]) == 3:
			var sym := int(result["symbol"])
			three_of[sym] = int(three_of.get(sym, 0)) + 1

	var win_rate := float(wins) / float(SPINS)
	print("--- %d simulated spins ---" % SPINS)
	print("observed win rate: %.5f (allowed %.3f - %.3f)" % [
		win_rate, WIN_RATE_MIN, WIN_RATE_MAX])
	t.check_between(win_rate, WIN_RATE_MIN, WIN_RATE_MAX,
		"observed win rate over %d spins" % SPINS)

	for sym: Variant in three_of.keys():
		var rate := float(three_of[sym]) / float(SPINS)
		print("  3x symbol %d: %.5f (allowed %.3f - %.3f)" % [
			int(sym), rate, THREE_RATE_MIN, THREE_RATE_MAX])
		t.check_between(rate, THREE_RATE_MIN, THREE_RATE_MAX,
			"3-of-a-kind rate for symbol %d" % int(sym))

## Mirrors SlotMachine.evaluate() exactly - the real reel logic.
static func _evaluate(symbols: Array, blank: int) -> Dictionary:
	var counts := {}
	for s: int in symbols:
		if s == blank:
			continue
		counts[s] = int(counts.get(s, 0)) + 1
	for s: Variant in counts.keys():
		if int(counts[s]) >= 2:
			return { "symbol": int(s), "count": int(counts[s]) }
	return { "symbol": -1, "count": 0 }

## LIGHTNING 7, GOLD 7, PLUS 7, BLANK 6 (spec 16.2). Do not change a single stop.
func _check_composition(t: RefCounted, strip: Array) -> void:
	print("--- strip composition ---")
	var composition := {}
	for s: int in strip:
		composition[s] = int(composition.get(s, 0)) + 1
	print(composition)
	t.check(int(composition.get(TuningScript.Sym.LIGHTNING, 0)) == 7, "strip has 7 LIGHTNING")
	t.check(int(composition.get(TuningScript.Sym.GOLD, 0)) == 7, "strip has 7 GOLD")
	t.check(int(composition.get(TuningScript.Sym.PLUS, 0)) == 7, "strip has 7 PLUS")
	t.check(int(composition.get(TuningScript.Sym.BLANK, 0)) == 6, "strip has 6 BLANK")
