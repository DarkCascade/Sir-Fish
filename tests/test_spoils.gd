extends Node
## [party-wipe-consequences] The four-reel spoils roll: what each outcome does to
## the run's four banks, and how the verdict rating adds up. These are the
## numbers that decide whether a wipe is a loss or a payday, so they get the
## same permanent guard test_quest_flow.gd gives the old spec 8.5 economy.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_spoils.tscn

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()
	t.guard_user_file(SaveGame.PATH)

	_test_tables(t)
	_test_pools(t)
	_test_verdict_range(t)
	_test_gold_and_scrap(t)
	_test_xp(t)
	_test_items(t)

	GameState.quest = null
	GameState.completed_quest = null
	t.finish(get_tree(), "test_spoils")

## The multiplier and point tables the whole feature rests on. KEEP and
## KEEP_HALF must both be worth nothing, or a neutral run starts drifting green.
func _test_tables(t) -> void:
	t.check(Spoils.multiplier(Spoils.Outcome.LOSE) == 0.0, "LOSE keeps nothing")
	t.check(Spoils.multiplier(Spoils.Outcome.KEEP) == 1.0, "KEEP keeps all")
	t.check(Spoils.multiplier(Spoils.Outcome.KEEP_HALF) == 0.5, "KEEP_HALF keeps half")
	t.check(Spoils.multiplier(Spoils.Outcome.DOUBLE) == 2.0, "DOUBLE keeps double")

	t.check(Spoils.points(Spoils.Outcome.LOSE) == -1, "LOSE rates -1")
	t.check(Spoils.points(Spoils.Outcome.KEEP) == 0, "KEEP rates neutral")
	t.check(Spoils.points(Spoils.Outcome.KEEP_HALF) == 0, "KEEP_HALF rates neutral")
	t.check(Spoils.points(Spoils.Outcome.DOUBLE) == 1, "DOUBLE rates +1")

## A wipe can only ever take and a win can only ever give. Rolled rather than
## just table-checked, because roll() drawing from the wrong pool is the way
## this actually breaks.
func _test_pools(t) -> void:
	t.check(not Spoils.pool_for(false).has(Spoils.Outcome.DOUBLE),
		"a wipe cannot roll DOUBLE")
	t.check(not Spoils.pool_for(true).has(Spoils.Outcome.LOSE),
		"a win cannot roll LOSE")
	t.check(Spoils.pool_for(false).has(Spoils.Outcome.LOSE), "a wipe can roll LOSE")
	t.check(Spoils.pool_for(true).has(Spoils.Outcome.DOUBLE), "a win can roll DOUBLE")

	var defeat_ok := true
	var victory_ok := true
	for i: int in range(400):
		if Spoils.multiplier(Spoils.roll(false)) > 1.0:
			defeat_ok = false
		if Spoils.multiplier(Spoils.roll(true)) < 0.5:
			victory_ok = false
	t.check(defeat_ok, "400 defeat rolls never pay out above 1x")
	t.check(victory_ok, "400 victory rolls never come home empty")

## quest_result.gd rates a run on the reels ALONE, so the pools are the only
## thing deciding which verdict tiers a run can reach. A wipe has to be able to
## climb to yellow (it held on to everything) and a win has to be able to fall
## short of green (it doubled nothing), or the three word banks collapse back
## into two and the tier that goes unreachable becomes dead content.
func _test_verdict_range(t) -> void:
	var defeat := _points_range(Spoils.pool_for(false))
	var victory := _points_range(Spoils.pool_for(true))
	t.check(defeat.y == 0,
		"a wipe tops out at yellow, never green (got %d)" % defeat.y)
	t.check(defeat.x < 0, "a wipe can still reach red (got %d)" % defeat.x)
	t.check(victory.x == 0,
		"a win bottoms out at yellow, never red (got %d)" % victory.x)
	t.check(victory.y > 0, "a win can still reach green (got %d)" % victory.y)

## Worst and best rating a full set of reels drawing from `pool` can total.
func _points_range(pool: Array[int]) -> Vector2i:
	var lo: int = Spoils.points(pool[0] as Spoils.Outcome)
	var hi: int = lo
	for outcome: int in pool:
		lo = mini(lo, Spoils.points(outcome as Spoils.Outcome))
		hi = maxi(hi, Spoils.points(outcome as Spoils.Outcome))
	var reels: int = Spoils.CATEGORY_ORDER.size()
	return Vector2i(lo * reels, hi * reels)

## Gold and scrap are already in the profile when the roll lands, so the roll has
## to settle them as a delta - the failure mode being a double credit.
func _test_gold_and_scrap(t) -> void:
	GameState.new_profile()
	GameState.start_expedition(load("res://resources/quests/easy.tres") as QuestDef)
	var carried := GameState.gold
	GameState.add_expedition_gold(100)
	GameState.add_expedition_scrap(40)
	t.check(GameState.gold == carried + 100, "pickups credit the profile on the spot")

	GameState.apply_spoils({Spoils.Category.GOLD: Spoils.Outcome.KEEP})
	t.check(GameState.gold == carried + 100, "KEEP leaves banked gold alone")
	t.check(GameState.expedition_gold == 100, "KEEP leaves the brought-home row alone")

	GameState.apply_spoils({Spoils.Category.GOLD: Spoils.Outcome.KEEP_HALF})
	t.check(GameState.gold == carried + 50, "KEEP_HALF claws back half the banked gold")
	t.check(GameState.expedition_gold == 50, "KEEP_HALF rewrites the brought-home row")

	GameState.apply_spoils({Spoils.Category.GOLD: Spoils.Outcome.DOUBLE})
	t.check(GameState.gold == carried + 100, "DOUBLE pays the banked gold a second time")

	GameState.apply_spoils({Spoils.Category.GOLD: Spoils.Outcome.LOSE})
	t.check(GameState.gold == carried, "LOSE takes back exactly what the run banked")
	t.check(GameState.expedition_gold == 0, "LOSE zeroes the brought-home row")

	# [backlog P5, issue #153] The result screen settles one bank per reel as it
	# lands (apply_spoils_category). Settling gold must leave scrap alone, so a
	# row only changes when its own reel lands.
	GameState.add_expedition_gold(100)
	var scrap_before := GameState.scrap
	var exp_scrap_before := GameState.expedition_scrap
	GameState.apply_spoils_category(Spoils.Category.GOLD, Spoils.Outcome.DOUBLE)
	t.check(GameState.expedition_gold == 200, "one reel: the gold bank settles on its own")
	t.check(GameState.scrap == scrap_before and GameState.expedition_scrap == exp_scrap_before,
		"one reel: the other banks are untouched until their reels land")
	GameState.apply_spoils_category(Spoils.Category.GOLD, Spoils.Outcome.LOSE)

	GameState.apply_spoils({Spoils.Category.SCRAP: Spoils.Outcome.LOSE})
	t.check(GameState.expedition_scrap == 0, "the scrap reel settles scrap, not gold")

	# An omitted category must mean KEEP - victory settles with an empty roll.
	GameState.add_expedition_gold(30)
	var before := GameState.gold
	GameState.apply_spoils({})
	t.check(GameState.gold == before, "an empty roll keeps everything")

## XP is the one bank still unspent when the roll lands, so it is scaled
## directly. A win must still bank every point.
func _test_xp(t) -> void:
	GameState.new_profile()
	GameState.start_expedition(load("res://resources/quests/easy.tres") as QuestDef)
	GameState.expedition_xp = 80
	GameState.apply_spoils({Spoils.Category.XP: Spoils.Outcome.KEEP_HALF})
	t.check(GameState.expedition_xp == 0, "the roll applies the banked XP, it does not leave it")
	var half_xp := _party_xp_total()

	GameState.new_profile()
	GameState.start_expedition(load("res://resources/quests/easy.tres") as QuestDef)
	GameState.expedition_xp = 80
	GameState.apply_spoils({})
	t.check(_party_xp_total() > half_xp,
		"a full roll banks more XP than a halved one (got %d, half was %d)"
			% [_party_xp_total(), half_xp])

	GameState.new_profile()
	GameState.start_expedition(load("res://resources/quests/easy.tres") as QuestDef)
	GameState.expedition_xp = 80
	GameState.apply_spoils({Spoils.Category.XP: Spoils.Outcome.LOSE})
	t.check(_party_xp_total() == 0, "LOSE banks no XP at all")

## Total XP across the party, levels included - a level-up zeroes hero_xp, so
## reading that alone would make a big award look like a small one.
func _party_xp_total() -> int:
	var total := 0
	for id: StringName in GameState.active_party:
		total += int(GameState.hero_xp.get(id, 0))
		total += (int(GameState.hero_levels.get(id, 1)) - 1) * Tuning.XP_CURVE_BASE
	return total

## The items reel, against the same equipped/town-gear exemptions
## discard_expedition_loot() has always honoured.
func _test_items(t) -> void:
	# LOSE drops the loose haul and nothing else.
	var kept := _expedition_with_items(4)
	GameState.apply_spoils({Spoils.Category.ITEMS: Spoils.Outcome.LOSE})
	t.check(GameState.inventory.size() == kept, "LOSE drops the whole loose haul")

	# KEEP_HALF rounds the KEPT count up, so a lone find never reads as a LOSE.
	kept = _expedition_with_items(4)
	GameState.apply_spoils({Spoils.Category.ITEMS: Spoils.Outcome.KEEP_HALF})
	t.check(GameState.inventory.size() == kept + 2,
		"KEEP_HALF keeps half of four (got %d loose)" % [GameState.inventory.size() - kept])

	kept = _expedition_with_items(1)
	GameState.apply_spoils({Spoils.Category.ITEMS: Spoils.Outcome.KEEP_HALF})
	t.check(GameState.inventory.size() == kept + 1, "KEEP_HALF of a single find keeps it")

	# DOUBLE rolls a second haul the same size rather than cloning the first.
	kept = _expedition_with_items(3)
	GameState.apply_spoils({Spoils.Category.ITEMS: Spoils.Outcome.DOUBLE})
	t.check(GameState.inventory.size() == kept + 6, "DOUBLE brings home twice the haul")

	# Equipped loot is never on the table, whatever the reel says.
	_expedition_with_items(2)
	var worn := Itemizer.generate_item_with_rarity(Item.Rarity.RARE)
	GameState.inventory.append(worn)
	GameState.equip_item(worn, &"warrior")
	GameState.apply_spoils({Spoils.Category.ITEMS: Spoils.Outcome.LOSE})
	t.check(GameState.inventory.has(worn), "equipped loot survives a LOSE")

## A fresh profile mid-expedition carrying `count` loose finds. Returns the
## inventory size the roll must never drop below (town gear plus the mark).
func _expedition_with_items(count: int) -> int:
	GameState.new_profile()
	GameState.start_expedition(load("res://resources/quests/easy.tres") as QuestDef)
	var floor_size := GameState.inventory.size()
	for item: Item in Itemizer.generate_items(count):
		GameState.inventory.append(item)
	return floor_size
