extends Node
## The gold curve and shop affordability (spec 5.4 / 13.6 / 19.3).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_economy.tscn
##
## NOTE ON THE GOLD ASSERTION [v3, V10 - ratified, stated literally in spec
## 19.3 rather than as an implementer deviation from v2]. A naive reading of
## "14 pre-shop spins puts gold on hand in [150, 260]" as a single-sample
## assertion is a defect: the EXPECTED value is exactly what spec 5.4 predicts
## - 75 + 14 x 6.80 = 170 - but a single 14-spin sample has enormous variance.
## Gold lands on only ~16.7% of spins, so a run with no gold wins at all is
## entirely ordinary and finishes on 75, well below the floor. A literal
## single-sample implementation fails the gate at random, which teaches the
## next author to ignore red - worse than not having the test.
##
## The general rule spec 19.3 establishes: an assertion on a random quantity
## states the statistic AND the sample size. This test asserts the MEAN over
## 1,000 simulated runs, and separately reports the single-run distribution
## (min / p25 / median / p75 / max) as informational output so the spread
## stays visible and nobody re-derives the same wrong conclusion from the mean
## alone.

const TestSupport := preload("res://tests/test_support.gd")

const RUNS := 1000
const PRE_SHOP_SPINS := 14
const SHOP_TRIALS := 1000

func _ready() -> void:
	var t := TestSupport.new()
	Upgrades.reset()

	# --- expected gold per spin (spec 5.4's arithmetic) ---
	var p_two := 3.0 * 7.0 * 7.0 * 20.0 / 19683.0     # exactly 2 of a given symbol
	var p_three := 7.0 * 7.0 * 7.0 / 19683.0          # exactly 3
	t.check_near(p_two, 0.14937, 0.0001, "P(exactly 2 of a given symbol) = 0.14937")
	t.check_near(p_three, 0.01743, 0.0001, "P(exactly 3 of a given symbol) = 0.01743")
	var per_spin := p_two * float(Tuning.SLOT_PAY_2_GOLD) + p_three * float(Tuning.SLOT_PAY_3_GOLD)
	t.check_near(per_spin, 6.80, 0.02, "expected gold per spin at the v2 payouts")

	t.check(Tuning.STARTING_GOLD == 75, "STARTING_GOLD is 75")
	t.check(Tuning.SLOT_PAY_2_GOLD == 35, "SLOT_PAY_2_GOLD is 35")
	t.check(Tuning.SLOT_PAY_3_GOLD == 90, "SLOT_PAY_3_GOLD is 90")

	# --- simulated pre-shop gold ---
	var totals: Array[int] = []
	var sum := 0
	for _r: int in range(RUNS):
		var gold := Tuning.STARTING_GOLD
		for _s: int in range(PRE_SHOP_SPINS):
			gold += _simulate_spin_gold()
		totals.append(gold)
		sum += gold
	totals.sort()
	var mean := float(sum) / float(RUNS)
	# Explicit percentile report (spec 19.3): the mean alone hides how wide the
	# single-run spread actually is.
	@warning_ignore("integer_division")
	var p25 := totals[RUNS / 4]
	@warning_ignore("integer_division")
	var p75 := totals[RUNS * 3 / 4]
	print(("gold on hand after %d spins over %d runs: " +
		"min %d, p25 %d, median %d, p75 %d, mean %.1f, max %d")
		% [PRE_SHOP_SPINS, RUNS, totals[0], p25, totals[RUNS / 2], p75, mean, totals[RUNS - 1]])
	t.check_between(mean, 150.0, 260.0,
		"mean gold on hand at the encounter-3 shop over %d runs" % RUNS)

	# Across a full six-encounter run the slot pays roughly 300 gold (spec 5.4).
	t.check_between(per_spin * 44.0, 250.0, 350.0,
		"a full run's ~44 spins pay roughly 300 gold")

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
	# [refinement-pass-3] Scrapping at the blacksmith reclaims a quarter of the
	# gold sell price as scrap - a 100 G item becomes 25 scrap.
	t.check(probe.scrap_value() == int(round(float(probe.sell_price()) * 0.25)),
		"scrap value is sell price x 0.25")

	t.finish(get_tree(), "test_economy")

## One spin's gold contribution, using the real strip and the real win rule.
func _simulate_spin_gold() -> int:
	var symbols: Array[int] = []
	for _i: int in range(3):
		symbols.append(Tuning.SLOT_STRIP[RNG.randi_range(0, Tuning.SLOT_REEL_STOPS - 1)])
	var counts := {}
	for s: int in symbols:
		if s == Tuning.Sym.BLANK:
			continue
		counts[s] = int(counts.get(s, 0)) + 1
	if int(counts.get(Tuning.Sym.GOLD, 0)) >= 3:
		return int(round(float(Tuning.SLOT_PAY_3_GOLD) * Upgrades.fat_purse_mult()))
	if int(counts.get(Tuning.Sym.GOLD, 0)) >= 2:
		return int(round(float(Tuning.SLOT_PAY_2_GOLD) * Upgrades.fat_purse_mult()))
	return 0
