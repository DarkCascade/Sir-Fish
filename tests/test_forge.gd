extends Node
## Itemizer.forge() - the rarity ladder, its costs, and the §10.5 arbitrage gate
## (spec 10.2 / 10.3 / 10.5, build-order step 9).
##
## Every assertion here needs REAL scrap and gold spending to mean anything,
## which is why this lands with forge() itself rather than at step 3 with
## test_enhanced_rarity.gd (spec 10.2, step-3 Q1).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_forge.tscn

const TestSupport := preload("res://tests/test_support.gd")

const RICH_GOLD := 1_000_000
const RICH_SCRAP := 1_000_000

var _t: TestSupport

func _ready() -> void:
	_t = TestSupport.new()
	var saved_gold := GameState.gold
	var saved_scrap := GameState.scrap
	var saved_forged := int(GameState.run_stats["items_forged"])

	_test_ladder()
	_test_no_duplicate_ids()
	_test_enhanced_rejects()
	_test_insufficient_currency()
	_test_enhanced_marker_and_rolls()
	_test_arbitrage_gate()

	GameState.gold = saved_gold
	GameState.scrap = saved_scrap
	GameState.run_stats["items_forged"] = saved_forged
	_t.finish(get_tree(), "test_forge")

func _fresh_common() -> Item:
	return Itemizer.generate_item_with_rarity(Item.Rarity.COMMON)

func _be_rich() -> void:
	GameState.gold = RICH_GOLD
	GameState.scrap = RICH_SCRAP

# --- the ladder --------------------------------------------------------------

func _test_ladder() -> void:
	_be_rich()
	var item := _fresh_common()
	_t.check(item.rarity == Item.Rarity.COMMON and item.modifiers.is_empty(),
		"a fresh Common starts at rarity 0 with 0 modifiers")

	var forged_before := int(GameState.run_stats["items_forged"])
	for step: int in range(4):
		var ok := Itemizer.forge(item)
		_t.check(ok, "forge step %d succeeds" % (step + 1))
		_t.check(int(item.rarity) == step + 1,
			"step %d lands rarity %d (got %d)" % [step + 1, step + 1, item.rarity])
		_t.check(item.modifiers.size() == int(Itemizer.RARITY_MOD_COUNT[item.rarity]),
			"step %d: %d modifiers matches RARITY_MOD_COUNT[%s]"
				% [step + 1, item.modifiers.size(), item.rarity_name()])
		_t.check(item.forge_count == step + 1,
			"step %d: forge_count is %d" % [step + 1, item.forge_count])

	_t.check(item.rarity == Item.Rarity.ENHANCED,
		"four steps from COMMON reach ENHANCED, and no more")
	_t.check(int(GameState.run_stats["items_forged"]) == forged_before + 4,
		"run_stats.items_forged counted all four forges")

	var gold_at_cap := GameState.gold
	var scrap_at_cap := GameState.scrap
	_t.check(not Itemizer.forge(item), "forge() on an ENHANCED item returns false")
	_t.check(GameState.gold == gold_at_cap and GameState.scrap == scrap_at_cap,
		"the refused fifth forge spent nothing")

func _test_no_duplicate_ids() -> void:
	_be_rich()
	var dupes := 0
	for i: int in range(1000):
		var item := _fresh_common()
		for _s: int in range(4):
			Itemizer.forge(item)
		var seen := {}
		for m: Dictionary in item.modifiers:
			if seen.has(m["id"]):
				dupes += 1
			seen[m["id"]] = true
	_t.check(dupes == 0,
		"no item carries the same modifier id twice after a full forge (%d/1000)" % dupes)

# --- rejection paths -------------------------------------------------------

func _test_enhanced_rejects() -> void:
	_be_rich()
	var item := _fresh_common()
	for _s: int in range(4):
		Itemizer.forge(item)
	var rarity := item.rarity
	var mods := item.modifiers.size()
	var value := item.value
	var fc := item.forge_count
	var gold := GameState.gold
	var scrap := GameState.scrap

	var ok := Itemizer.forge(item)
	_t.check(not ok, "forge(ENHANCED) -> false")
	_t.check(item.rarity == rarity and item.modifiers.size() == mods
			and item.value == value and item.forge_count == fc,
		"forge(ENHANCED) mutates nothing on the item")
	_t.check(GameState.gold == gold and GameState.scrap == scrap,
		"forge(ENHANCED) spends neither currency")

func _test_insufficient_currency() -> void:
	# Insufficient scrap: plenty of gold, no scrap.
	var item := _fresh_common()
	GameState.gold = RICH_GOLD
	GameState.scrap = int(Tuning.FORGE_COSTS[Item.Rarity.COMMON][0]) - 1
	var g0 := GameState.gold
	var s0 := GameState.scrap
	_t.check(not Itemizer.forge(item), "forge() with too little scrap -> false")
	_t.check(GameState.gold == g0 and GameState.scrap == s0,
		"too little scrap: neither total moved (%d gold, %d scrap)" % [GameState.gold, GameState.scrap])
	_t.check(item.rarity == Item.Rarity.COMMON and item.modifiers.is_empty(),
		"too little scrap: the item is untouched")

	# Insufficient gold: plenty of scrap, no gold. This is the observable the
	# §10.2 refund path also guarantees - a rejected forge leaves scrap intact.
	item = _fresh_common()
	GameState.scrap = RICH_SCRAP
	GameState.gold = int(Tuning.FORGE_COSTS[Item.Rarity.COMMON][1]) - 1
	g0 = GameState.gold
	s0 = GameState.scrap
	_t.check(not Itemizer.forge(item), "forge() with too little gold -> false")
	_t.check(GameState.gold == g0 and GameState.scrap == s0,
		"too little gold: neither total moved, scrap refunded intact (%d gold, %d scrap)"
			% [GameState.gold, GameState.scrap])
	_t.check(item.rarity == Item.Rarity.COMMON and item.modifiers.is_empty(),
		"too little gold: the item is untouched")

# --- the enhanced marker (spec 10.3) --------------------------------------

func _test_enhanced_marker_and_rolls() -> void:
	_be_rich()
	var mods_by_id := {}
	for def: Dictionary in Itemizer.MODIFIERS:
		mods_by_id[def["id"]] = def

	var early_enhanced := 0
	var final_plain := 0
	var out_of_range := 0
	for i: int in range(300):
		var item := _fresh_common()
		for step: int in range(4):
			Itemizer.forge(item)
			var last: Dictionary = item.modifiers[item.modifiers.size() - 1]
			var is_final := step == 3
			if not is_final and last.get("enhanced", false):
				early_enhanced += 1
			if is_final and not last.get("enhanced", false):
				final_plain += 1
			if is_final:
				var def: Dictionary = mods_by_id[last["id"]]
				var lo := int(def["roll"][0]) * Tuning.FORGE_ENHANCED_MULT
				var hi := int(def["roll"][1]) * Tuning.FORGE_ENHANCED_MULT
				if int(last["roll"]) < lo or int(last["roll"]) > hi:
					out_of_range += 1

	_t.check(early_enhanced == 0,
		"steps 1-3 never produce an enhanced modifier (%d/900)" % early_enhanced)
	_t.check(final_plain == 0,
		"step 4 always produces an enhanced modifier (%d/300 missed)" % final_plain)
	_t.check(out_of_range == 0,
		"every enhanced roll falls in [min x2, max x2] of its definition (%d/300 out)" % out_of_range)

# --- the arbitrage gate (spec 10.5) -------------------------------------------

func _test_arbitrage_gate() -> void:
	_be_rich()
	var profitable := 0
	var worst_ratio := 0.0
	for i: int in range(1000):
		var item := _fresh_common()
		var gold_spent := item.buy_price()
		for r: int in range(4):
			gold_spent += int(Tuning.FORGE_COSTS[item.rarity][1])
			Itemizer.forge(item)
		var recovered := item.sell_price()
		if recovered > gold_spent:
			profitable += 1
		worst_ratio = maxf(worst_ratio, float(recovered) / float(maxi(gold_spent, 1)))
	_t.check(profitable == 0,
		"buy -> forge to ENHANCED -> sell never returns more gold than spent (%d/1000, worst recovered %.2fx spent)"
			% [profitable, worst_ratio])
