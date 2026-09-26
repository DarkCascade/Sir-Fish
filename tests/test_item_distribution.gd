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

	# [item power model] Four entries, indexed by Item.Rarity
	# { COMMON, MAGIC, RARE, ENHANCED }. ENHANCED's weight is 0 so by_rarity[3]
	# is never incremented here, but the array is sized to the full enum so an
	# index can never go stale.
	var by_rarity := [0, 0, 0, 0]
	var values: Array[int] = []
	for item: Item in items:
		by_rarity[item.rarity] += 1
		values.append(item.value)
	values.sort()

	print("--- %d generated items ---" % SAMPLE)
	var names := ["Common", "Magic", "Rare", "Enhanced"]
	var expected := [60.0, 30.0, 10.0, 0.0]
	for i: int in range(4):
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

	# [icons phase 2] 11 entries: 4 warrior weapon + 1 ranger weapon + 1 mage
	# weapon + 1 armor + 4 trinket. [backlog P7] slot_mend (the second armor
	# modifier) is retired with the slot's heal. Each has a `slots` field;
	# _modifiers_for_type filters on it (and `types`, where present).
	# [backlog P3, issue #75] Plus decision 3.11's twelve stats, 23 in all. They
	# carry `types: []` until #73 wires the sets, so no type can roll one yet.
	t.check(Itemizer.MODIFIERS.size() == 23, "the modifier pool has 23 entries")
	var unwired := 0
	for wtype: StringName in Itemizer.ITEM_TYPES:
		for def: Dictionary in Itemizer._modifiers_for_type(wtype):
			if StringName(def["id"]) in SlotIcon.STAT_MODIFIER_IDS 					and not (StringName(def["id"]) in [&"bleed", &"crit"]):
				unwired += 1
	t.check(unwired == 0, "no type rolls a decision-3.11 stat before #73 (%d found)" % unwired)
	for def: Dictionary in Itemizer.MODIFIERS:
		t.check(def.has("slots") and not (def["slots"] as Array).is_empty(),
			"modifier '%s' declares which slots may roll it" % def["id"])
	var has_purse := false
	for def: Dictionary in Itemizer.MODIFIERS:
		if def["id"] == &"slot_purse":
			has_purse = true
	t.check(not has_purse, "slot_purse is no longer in the modifier pool")

	# A rarity sets how many modifiers an item carries, capped by how many its type
	# can roll: the generator never repeats a modifier, so a type with a one-id pool
	# (armor, since slot_mend went - [backlog P7]) carries one however rare it is.
	var wrong_count := 0
	for item: Item in items:
		var want: int = mini(int(Itemizer.RARITY_MOD_COUNT[item.rarity]),
			Itemizer._modifiers_for_type(item.weapon_type).size())
		if item.modifiers.size() != want:
			wrong_count += 1
	t.check(wrong_count == 0,
		"every item's modifier count is its rarity's (0/1/2/3), capped by its type's pool (%d wrong)" % wrong_count)

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
