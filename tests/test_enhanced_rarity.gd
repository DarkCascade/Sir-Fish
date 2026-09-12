extends Node
## The ENHANCED rarity: weight-0, generator-unreachable, forge-only.
##
## [item power model] UNCOMMON was removed, so Item.Rarity is
## { COMMON, MAGIC, RARE, ENHANCED } and every rarity-indexed array is 4 long.
## This test pins that ENHANCED is the last index of each array, is present but
## unreachable by any generator, and that each forge rung still adds exactly
## one modifier (RARITY_MOD_COUNT = [0, 1, 2, 3]). Itemizer.forge() itself is
## covered by test_forge.gd.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_enhanced_rarity.tscn

const TestSupport := preload("res://tests/test_support.gd")

const SAMPLE := 4000

func _ready() -> void:
	var t := TestSupport.new()

	# --- the enum ---------------------------------------------------------------
	t.check(Item.Rarity.ENHANCED == 3, "Item.Rarity.ENHANCED is index 3 (got %d)" % Item.Rarity.ENHANCED)
	t.check(Item.Rarity.RARE == 2, "RARE is index 2 - UNCOMMON was removed, so MAGIC/RARE/ENHANCED shifted down")

	# --- the four index-addressed arrays grow in lockstep (spec 10.1) ---------
	t.check(Tuning.RARITY_COLORS.size() == 4, "Tuning.RARITY_COLORS has 4 entries")
	t.check(Itemizer.RARITY_WEIGHTS.size() == 4, "Itemizer.RARITY_WEIGHTS has 4 entries")
	t.check(Itemizer.RARITY_MOD_COUNT.size() == 4, "Itemizer.RARITY_MOD_COUNT has 4 entries")
	t.check(Itemizer.RARITY_VALUE_MULT.size() == 4, "Itemizer.RARITY_VALUE_MULT has 4 entries")

	var probe := Item.new()
	probe.rarity = Item.Rarity.ENHANCED
	t.check(probe.rarity_name() == "Enhanced",
		"rarity_name() covers ENHANCED (got '%s')" % probe.rarity_name())
	t.check(probe.rarity_color() == Tuning.RARITY_COLORS[Item.Rarity.ENHANCED],
		"rarity_color() returns the ENHANCED colour")
	var colour_clash := false
	for r: int in range(Item.Rarity.RARE + 1):
		if Tuning.RARITY_COLORS[r] == Tuning.RARITY_COLORS[Item.Rarity.ENHANCED]:
			colour_clash = true
	t.check(not colour_clash, "the ENHANCED colour is distinct from the four rolled rarities")

	# --- weight 0 keeps ENHANCED unreachable (spec 10.1) ----------------------
	t.check(int(Itemizer.RARITY_WEIGHTS[Item.Rarity.ENHANCED]) == 0,
		"RARITY_WEIGHTS[ENHANCED] is 0")
	t.check(int(Itemizer.RARITY_MOD_COUNT[Item.Rarity.ENHANCED]) == 3,
		"RARITY_MOD_COUNT[ENHANCED] is 3 (the three-step ladder's endpoint)")

	# --- the three-step ladder's whole justification (spec 0.4, 10.2) --------
	# "A forged item and a found item of the same rarity carry the same number
	# of modifiers, so the rarity name never lies about power." Each forge rung
	# raises rarity by one and adds exactly one modifier, so that claim holds iff
	# every adjacent pair of this array differs by exactly one.
	#
	# That is a pure property of the ARRAY, so it is testable now - six steps
	# before forge() exists. Which is the point: spec 0.4 recorded the three-step
	# ladder being rejected for breaking this invariant, and if the replacement
	# does not hold either, the fix today is a one-line array edit rather than a
	# redesign discovered at step 9.
	var ladder_ok := true
	for r: int in range(Item.Rarity.ENHANCED):
		if int(Itemizer.RARITY_MOD_COUNT[r + 1]) != int(Itemizer.RARITY_MOD_COUNT[r]) + 1:
			ladder_ok = false
	t.check(ladder_ok,
		"every rarity rung adds exactly one modifier (RARITY_MOD_COUNT = %s)"
			% [Itemizer.RARITY_MOD_COUNT])

	# The mechanism the weight-0 guarantee rests on: weighted_index() over
	# weights ending in 0 never returns that last index. Asserted directly so a
	# future rewrite of weighted_index() that breaks it fails HERE, loudly,
	# rather than by leaking ENHANCED gear into a chest.
	var last_index_hits := 0
	for i: int in range(20000):
		if RNG.weighted_index([60, 30, 10, 0]) == 3:
			last_index_hits += 1
	t.check(last_index_hits == 0,
		"weighted_index() never returns a trailing zero-weight index (%d/20000)" % last_index_hits)

	# --- no generator ever produces an ENHANCED item -------------------------
	var enhanced_seen := 0
	var mod_count_wrong := 0
	for i: int in range(SAMPLE):
		var it := Itemizer.generate_item()
		if it.rarity == Item.Rarity.ENHANCED:
			enhanced_seen += 1
		# The step-4 invariant (test_item_distribution.gd:68) must already hold
		# for the widened array: a generated item's mod count still matches its
		# rarity, and RARITY_MOD_COUNT[ENHANCED] never gets indexed here.
		if it.modifiers.size() != int(Itemizer.RARITY_MOD_COUNT[it.rarity]):
			mod_count_wrong += 1
	t.check(enhanced_seen == 0, "generate_item() never rolls ENHANCED (%d/%d)" % [enhanced_seen, SAMPLE])
	t.check(mod_count_wrong == 0,
		"generate_item() mod count still matches rarity with the widened array (%d wrong)" % mod_count_wrong)

	# generate_item_with_rarity() clamps its input to RARE, so asking for
	# ENHANCED (or garbage) yields a RARE item, not an ENHANCED one.
	var forced_enhanced := Itemizer.generate_item_with_rarity(Item.Rarity.ENHANCED)
	t.check(forced_enhanced.rarity == Item.Rarity.RARE,
		"generate_item_with_rarity(ENHANCED) clamps to RARE (got %s)" % forced_enhanced.rarity_name())
	var forced_garbage := Itemizer.generate_item_with_rarity(999)
	t.check(forced_garbage.rarity == Item.Rarity.RARE,
		"generate_item_with_rarity(999) clamps to RARE (got %s)" % forced_garbage.rarity_name())

	# generate_drop()'s rarity_floor is clamped the same way.
	var drop_enhanced_seen := 0
	for i: int in range(500):
		if Itemizer.generate_drop(&"warrior", 99).rarity == Item.Rarity.ENHANCED:
			drop_enhanced_seen += 1
	t.check(drop_enhanced_seen == 0,
		"generate_drop(c, 99) clamps the floor below ENHANCED (%d/500)" % drop_enhanced_seen)

	t.finish(get_tree(), "test_enhanced_rarity")
