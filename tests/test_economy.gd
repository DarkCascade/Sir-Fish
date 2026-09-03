extends Node
## The gold curve and shop affordability (spec 5.4 / 13.6 / 19.3).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_economy.tscn
##
## [slot phase 2] The slot no longer produces gold in ANY form (§5). Gold now
## comes only from enemy drops (Tuning.ENEMY_GOLD_DROP, BOSS_LOOT_MULT), item
## sales, and quest rewards. That removed roughly half the run's income, so
## ENEMY_GOLD_DROP was re-tuned upward and this test's pre-shop model changed
## from "14 slot spins" to "the kills of the two combats before the encounter-3
## shop".
##
## NOTE ON THE GOLD ASSERTION [v3, V10 - ratified]. An assertion on a random
## quantity states the statistic AND the sample size (spec 19.3). This test
## asserts the MEAN over 1,000 simulated runs and separately reports the
## single-run distribution as informational output so the spread stays visible.

const TestSupport := preload("res://tests/test_support.gd")

const RUNS := 1000
const SHOP_TRIALS := 1000

## The endless layout up to the encounter-3 shop: COMBAT, LOOT, COMBAT, SHOP.
## Two combats, each _build_endless_level(1)'s enemy_count = mini(2 + 1/3, 3) = 2
## grunts. The LOOT chest pays items, not gold, so it does not feed this.
const PRE_SHOP_COMBATS := 2
const ENEMIES_PER_COMBAT := 2

func _ready() -> void:
	var t := TestSupport.new()
	Upgrades.reset()

	t.check(Tuning.STARTING_GOLD == 75, "STARTING_GOLD is 75 (the economy baseline)")

	# --- simulated pre-shop gold: two combats of grunt kills ---
	var totals: Array[int] = []
	var sum := 0
	for _r: int in range(RUNS):
		var gold := Tuning.STARTING_GOLD
		for _c: int in range(PRE_SHOP_COMBATS):
			for _e: int in range(ENEMIES_PER_COMBAT):
				gold += _simulate_kill_gold(false)
		totals.append(gold)
		sum += gold
	totals.sort()
	var mean := float(sum) / float(RUNS)
	@warning_ignore("integer_division")
	var p25 := totals[RUNS / 4]
	@warning_ignore("integer_division")
	var p75 := totals[RUNS * 3 / 4]
	print(("gold on hand at the encounter-3 shop over %d runs " +
		"(%d start + %d grunt kills): min %d, p25 %d, median %d, p75 %d, mean %.1f, max %d")
		% [RUNS, Tuning.STARTING_GOLD, PRE_SHOP_COMBATS * ENEMIES_PER_COMBAT,
			totals[0], p25, totals[RUNS / 2], p75, mean, totals[RUNS - 1]])
	t.check_between(mean, 150.0, 260.0,
		"mean gold on hand at the encounter-3 shop over %d runs" % RUNS)

	# A boss kill still pays BOSS_LOOT_MULT x a grunt's range.
	var boss_lo := Tuning.ENEMY_GOLD_DROP.x * Tuning.BOSS_LOOT_MULT
	var boss_hi := Tuning.ENEMY_GOLD_DROP.y * Tuning.BOSS_LOOT_MULT
	var boss_ok := true
	for _i: int in range(2000):
		var g := _simulate_kill_gold(true)
		if g < boss_lo or g > boss_hi:
			boss_ok = false
	t.check(boss_ok, "a boss kill pays inside [%d, %d]" % [boss_lo, boss_hi])

	# --- shop stock always offers something buyable (spec 13.6) ---
	var affordable_runs := 0
	var teaser_runs := 0
	for _i: int in range(SHOP_TRIALS):
		var stock: Array[Item] = Itemizer.generate_shop_stock()
		if stock.size() != Tuning.SHOP_ITEMS_FOR_SALE:
			continue
		var purse := int(mean)
		var any_affordable := false
		var any_teaser := false
		for item: Item in stock:
			if item.buy_price() <= purse:
				any_affordable = true
			if item.rarity >= Item.Rarity.MAGIC:
				any_teaser = true
		if any_affordable:
			affordable_runs += 1
		if any_teaser:
			teaser_runs += 1
	var affordable_rate := float(affordable_runs) / float(SHOP_TRIALS)
	print("at %d gold, %.1f%% of shops offered an affordable card; %.1f%% offered a teaser"
		% [int(mean), affordable_rate * 100.0, 100.0 * float(teaser_runs) / float(SHOP_TRIALS)])
	t.check(affordable_rate >= 0.95,
		"at least one card is affordable in >= 95%% of shops (got %.1f%%)"
			% (affordable_rate * 100.0))
	t.check(teaser_runs == SHOP_TRIALS,
		"every shop carries a Magic-or-better teaser (got %d of %d)"
			% [teaser_runs, SHOP_TRIALS])

	# The forced spread must not change the count.
	var stock_size_ok := true
	for _i: int in range(50):
		if Itemizer.generate_shop_stock().size() != Tuning.SHOP_ITEMS_FOR_SALE:
			stock_size_ok = false
	t.check(stock_size_ok, "generate_shop_stock() always returns SHOP_ITEMS_FOR_SALE items")

	# --- sell/buy prices (spec 5.4) ---
	var probe := Itemizer.generate_item()
	t.check(probe.buy_price() == int(round(float(probe.value) * 1.5)), "buy price is value x 1.5")
	t.check(probe.sell_price() == int(round(float(probe.value) * 0.5)), "sell price is value x 0.5")
	t.check(probe.scrap_value() == int(round(float(probe.sell_price()) * 0.25)),
		"scrap value is sell price x 0.25")

	t.finish(get_tree(), "test_economy")

## One kill's gold contribution, using the real drop range and the real
## boss multiplier (mirrors loot_pickup.gd).
func _simulate_kill_gold(is_boss: bool) -> int:
	var mult := Tuning.BOSS_LOOT_MULT if is_boss else 1
	return RNG.randi_range(Tuning.ENEMY_GOLD_DROP.x, Tuning.ENEMY_GOLD_DROP.y) * mult
