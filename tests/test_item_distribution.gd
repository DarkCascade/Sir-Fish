extends Node
## Itemizer distribution verification (spec 20, M5 gate).
##
## Needs the Itemizer and RNG autoloads, so it runs as a scene rather than as a
## --script SceneTree like test_slot_odds.gd:
##     godot --headless --path <project> res://tests/test_item_distribution.tscn
##
## Reports the rarity split over SAMPLE items (expected roughly 50/30/15/5) and
## the min / median / max value.

const TestSupport := preload("res://tests/test_support.gd")

const SAMPLE := 200

func _ready() -> void:
	var t := TestSupport.new()
	var items: Array[Item] = Itemizer.generate_items(SAMPLE)

	# [town] Five entries, indexed by Item.Rarity (spec 10.1 added ENHANCED).
	# ENHANCED's weight is 0 so by_rarity[4] is never incremented here, but a
	# four-wide array indexed by a five-value enum is an out-of-bounds waiting
	# for the day that weight changes - widen it now (spec 13.2, step-3 Q6).
	var by_rarity := [0, 0, 0, 0, 0]
	var values: Array[int] = []
	for item: Item in items:
		by_rarity[item.rarity] += 1
		values.append(item.value)
	values.sort()

	print("--- %d generated items ---" % SAMPLE)
	var names := ["Common", "Uncommon", "Magic", "Rare", "Enhanced"]
	var expected := [50.0, 30.0, 15.0, 5.0, 0.0]
	for i: int in range(5):
		print("  %-9s %3d  (%5.1f%%, expected %4.1f%%)" % [
			names[i], by_rarity[i], 100.0 * float(by_rarity[i]) / float(SAMPLE),
			expected[i]])

	@warning_ignore("integer_division")
	var mid: int = int(values.size() / 2.0)
	var median: int = values[mid]
	print("value  min %d  median %d  max %d" % [values[0], median, values[-1]])

	# Buy prices are what the shop actually shows (spec 13.3).
	print("buy    min %d  median %d  max %d" % [
		int(round(float(values[0]) * Tuning.SHOP_BUY_MARKUP)),
		int(round(float(median) * Tuning.SHOP_BUY_MARKUP)),
		int(round(float(values[-1]) * Tuning.SHOP_BUY_MARKUP))])

	# Q13: modifiers are drawn without replacement, so no item may carry the same
	# modifier id twice. "+4 Damage" and "+7 Damage" on one sword is a display bug
	# waiting to happen.
	var dupes := 0
	var missing_roll := 0
	for item: Item in items:
		var seen := {}
		for mod: Dictionary in item.modifiers:
			var id: StringName = mod["id"]
			if seen.has(id):
				dupes += 1
			seen[id] = true
			# The raw roll is mandatory in v2 - modifiers now have effects (13.5).
			if not mod.has("roll"):
				missing_roll += 1
	t.check(dupes == 0, "no item carries a duplicate modifier id (%d found)" % dupes)
	t.check(missing_roll == 0, "every modifier stores its raw roll (%d missing)" % missing_roll)

	# The pool is 8 entries in v2, so a Rare's three draws are comfortably distinct.
	t.check(Itemizer.MODIFIERS.size() == 8, "the modifier pool has 8 entries")

	var wrong_count := 0
	for item: Item in items:
		if item.modifiers.size() != Itemizer.RARITY_MOD_COUNT[item.rarity]:
			wrong_count += 1
	t.check(wrong_count == 0,
		"every item's modifier count matches its rarity (0/1/2/3) (%d wrong)" % wrong_count)

	# [v3, V9] Element ties resolve fire -> ice -> lightning, via
	# GameState.party_bonuses()'s dictionary insertion order (spec 17.6). Hand-
	# build a tied inventory and confirm the winner is fire; restore the real
	# inventory after so this test cannot leak state into anything else.
	#
	# [equip] party_bonuses() only sums EQUIPPED items, so both probe items must
	# carry a non-empty equipped_by to contribute at all.
	#
	# [town] They sit on two different heroes for history: before spec 4.3 a hero
	# held ONE item, so a fire/ice tie was only expressible across two of them.
	# Three slots make a same-hero tie possible now (a fire axe and an ice helm),
	# but the probe is left on two heroes deliberately - party_bonuses() sums
	# every equipped item regardless of slot or active_party membership, so the
	# two-hero form still exercises exactly the insertion-order tiebreak this
	# block is about, and spec 13.2 gives this file one step-4 edit (the rarity
	# array widening above), not a rewrite.
	var saved_inventory := GameState.inventory
	var fire_item := Item.new()
	fire_item.equipped_by = &"warrior"
	fire_item.modifiers = [
		{ "id": &"elem_fire", "label": "+5 Fire Damage", "roll": 5, "value_mult": 0.5 },
	]
	var ice_item := Item.new()
	ice_item.equipped_by = &"ranger"
	ice_item.modifiers = [
		{ "id": &"elem_ice", "label": "+5 Ice Damage", "roll": 5, "value_mult": 0.5 },
	]
	GameState.inventory = [fire_item, ice_item]
	var tied_element: StringName = GameState.party_bonuses()["element"]
	GameState.inventory = saved_inventory
	t.check(tied_element == &"fire",
		"a fire/ice tie resolves to fire (got '%s')" % tied_element)

	t.finish(get_tree(), "test_item_distribution")
