extends Node
## Enemy drops verification (Sir Fish - Enemy Drops Implementation Spec §10).
##
## Needs the GameState, Itemizer, Tuning and RNG autoloads, so it runs as a
## scene rather than as a --script SceneTree:
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_drops.tscn

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()

	# --- D1: every generate_drop(c) item is usable by c, over 1000/class ----
	var d1_wrong := 0
	for hero_class: StringName in GameState.PARTY_ORDER:
		for i: int in range(1000):
			if not Itemizer.generate_drop(hero_class).usable_by().has(hero_class):
				d1_wrong += 1
	t.check(d1_wrong == 0,
		"every generate_drop(c) item is usable by c, 1000 samples/class (%d wrong)" % d1_wrong)

	# --- D2: droppable_classes() == active_party, no hero unreachable ------
	# [town] spec 4.5 flipped the party solo; droppable_classes() follows
	# active_party now, not PARTY_ORDER.
	t.check(Itemizer.droppable_classes() == GameState.active_party,
		"droppable_classes() equals active_party (got %s)" % [Itemizer.droppable_classes()])

	# --- D2b: add_item() never auto-equips an item onto a class that is not
	# on the run. Generation is party-gated so this is Debug-only in practice,
	# but the guard keeps a forced non-party item sellable and out of the pool.
	var d2b_party := GameState.active_party
	var d2b_inv := GameState.inventory
	GameState.active_party = [&"warrior"] as Array[StringName]
	GameState.inventory = []
	var outsider := Itemizer.generate_drop(&"mage")
	GameState.add_item(outsider)
	t.check(outsider.equipped_by == &"",
		"add_item() leaves a non-party (mage) item unequipped (got %s)" % [outsider.equipped_by])
	var warrior_item := Itemizer.generate_drop(&"warrior")
	GameState.add_item(warrior_item)
	t.check(warrior_item.equipped_by == &"warrior",
		"add_item() still auto-equips a party item into its empty slot (got %s)" % [warrior_item.equipped_by])
	GameState.inventory = d2b_inv
	GameState.active_party = d2b_party

	# --- D3: no generated item (drop, chest, shop) has an empty usable_by() -
	var d3_empty := 0
	for hero_class: StringName in GameState.PARTY_ORDER:
		for i: int in range(200):
			if Itemizer.generate_drop(hero_class).usable_by().is_empty():
				d3_empty += 1
	for i: int in range(600):
		if Itemizer.generate_item().usable_by().is_empty():
			d3_empty += 1
	for i: int in range(200):
		for item: Item in Itemizer.generate_shop_stock():
			if item.usable_by().is_empty():
				d3_empty += 1
	t.check(d3_empty == 0,
		"no drop/chest/shop item has an empty usable_by() (%d empty)" % d3_empty)

	# --- D4: live-counter coverage is 33.3% +/- 2pp over 3000 drops ---------
	# [town] active_party is solo now (spec 4.5), which would make this
	# tautological ("the one droppable class got 100%"). DROP_CATCHUP's catch-up
	# weighting is written for a multi-class party and spec 15 keeps it alive for
	# the party's return, so override active_party to the full roster for this
	# block - keeping the algorithm under a real three-class test - then restore.
	# Same save/override/restore idiom D8 and _report_party_bonuses() already use
	# for endless_level_number / inventory (step-4 Q11).
	var d4_saved_party := GameState.active_party
	GameState.active_party = GameState.PARTY_ORDER.duplicate()
	GameState.drops_by_class.clear()
	const D4_N := 3000
	for i: int in range(D4_N):
		GameState.record_drop(GameState.next_drop_class())
	for hero_class: StringName in Itemizer.droppable_classes():
		var share := 100.0 * float(GameState.drop_count(hero_class)) / float(D4_N)
		t.check_between(share, 31.3, 35.3,
			"%s's live-counter drop share is 33.3%% +/- 2pp over %d drops (got %.1f%%)"
				% [hero_class, D4_N, share])
	GameState.drops_by_class.clear()
	GameState.active_party = d4_saved_party

	# --- D5: generate_drop(c, 1) never returns a Common, 500 samples/class --
	var d5_commons := 0
	for hero_class: StringName in GameState.PARTY_ORDER:
		for i: int in range(500):
			if Itemizer.generate_drop(hero_class, 1).rarity == Item.Rarity.COMMON:
				d5_commons += 1
	t.check(d5_commons == 0,
		"generate_drop(c, 1) never returns a Common, 500 samples/class (%d found)" % d5_commons)

	# --- D6: generate_drop(c, 0) rarity split within +/- 4pp of 50/30/15/5 --
	var d6_by_rarity: Array[int] = [0, 0, 0, 0]
	for hero_class: StringName in GameState.PARTY_ORDER:
		for i: int in range(1000):
			d6_by_rarity[Itemizer.generate_drop(hero_class, 0).rarity] += 1
	var d6_total := d6_by_rarity[0] + d6_by_rarity[1] + d6_by_rarity[2] + d6_by_rarity[3]
	var d6_expected := [50.0, 30.0, 15.0, 5.0]
	var d6_names := ["Common", "Uncommon", "Magic", "Rare"]
	for i: int in range(4):
		var pct := 100.0 * float(d6_by_rarity[i]) / float(d6_total)
		t.check_between(pct, d6_expected[i] - 4.0, d6_expected[i] + 4.0,
			"generate_drop(c, 0) %s share is %.1f%% +/- 4pp (got %.1f%%)"
				% [d6_names[i], d6_expected[i], pct])

	# --- D7: slot-first generation (spec 4.4, re-derived per step-4 Q2) -----
	# The old per-type "every weapon type ~20%" band cannot survive slot-first
	# generation with a solo warrior: axe/sword land ~16.7% each, the six
	# armor/trinket types ~11.1% each, and bow/dagger/staff exactly 0. D7 keeps
	# its spirit - generation is evenly spread, no slot starved or flooded -
	# pointed at what §4.4 actually produces, over 6000 samples:
	#   * slot share: each of WEAPON/ARMOR/TRINKET is 33.3% +/- 3pp;
	#   * per-type: a wieldable type's share is (33.3% / types-in-its-slot) +/- 3pp
	#     (the within-slot-uniform check, folded together with the slot share);
	#   * the §1.6 guarantee, asserted directly: a type no active-party member
	#     can wield generates EXACTLY zero times. This is the regression guard
	#     D7 was always meant to be, now aimed at what slot-first generation is
	#     for. It survives the mage's return in meaning (only the literal list of
	#     zero-count types would then change).
	const D7_N := 6000
	var d7_by_slot: Array[int] = [0, 0, 0]
	var d7_by_type: Dictionary = {}
	for wtype: StringName in Itemizer.ITEM_TYPES.keys():
		d7_by_type[wtype] = 0
	for i: int in range(D7_N):
		var it := Itemizer.generate_item()
		d7_by_slot[int(it.slot())] += 1
		d7_by_type[it.weapon_type] = int(d7_by_type[it.weapon_type]) + 1
	var d7_slot_names := ["Weapon", "Armor", "Trinket"]
	for s: int in range(3):
		var slot_share := 100.0 * float(d7_by_slot[s]) / float(D7_N)
		t.check_between(slot_share, 30.3, 36.3,
			"generate_item() fills the %s slot 33.3%% +/- 3pp (got %.1f%%)"
				% [d7_slot_names[s], slot_share])
	for wtype: StringName in Itemizer.ITEM_TYPES.keys():
		var wieldable := false
		for c: StringName in GameState.active_party:
			if (Itemizer.ITEM_TYPES[wtype]["classes"] as Array).has(c):
				wieldable = true
		var pct := 100.0 * float(d7_by_type[wtype]) / float(D7_N)
		if not wieldable:
			t.check(int(d7_by_type[wtype]) == 0,
				"generate_item() never rolls %s - no active-party member can wield it (got %d)"
					% [wtype, int(d7_by_type[wtype])])
		else:
			var entry_slot: int = int(Itemizer.ITEM_TYPES[wtype]["slot"])
			var n_in_slot := Itemizer.types_for_slot(entry_slot as Item.Slot, GameState.active_party).size()
			var want := (100.0 / 3.0) / float(n_in_slot)
			t.check_between(pct, want - 3.0, want + 3.0,
				"generate_item()'s %s share is %.1f%% +/- 3pp (got %.1f%%)" % [wtype, want, pct])

	# --- D8: mean expected drops per level is 3.0 - 4.5 ---------------------
	const D8_LEVELS := 500
	var saved_level_number := GameState.endless_level_number
	var d8_total := 0.0
	for n: int in range(1, D8_LEVELS + 1):
		GameState.endless_level_number = n
		d8_total += _expected_drops(GameState.build_level())
	var d8_mean := d8_total / float(D8_LEVELS)
	print("D8: mean expected drops/level over %d levels: %.2f" % [D8_LEVELS, d8_mean])
	t.check_between(d8_mean, 3.0, 4.5, "mean drops per level is 3.0-4.5 (got %.2f)" % d8_mean)

	# --- D9: coverage - >=95%% of >=3-drop levels cover all three classes ---
	# [town] Same active_party override as D4 (step-4 Q11): next_drop_class()
	# reads droppable_classes(), which follows active_party now, so a solo party
	# would make this pass by pigeonhole and assert nothing about the weighting.
	var d9_saved_party := GameState.active_party
	GameState.active_party = GameState.PARTY_ORDER.duplicate()
	const D9_LEVELS := 500
	var d9_with_3plus := 0
	var d9_covered := 0
	for n: int in range(1, D9_LEVELS + 1):
		GameState.endless_level_number = n
		var lvl := GameState.build_level()
		GameState.drops_by_class.clear()
		var level_drops := 0
		for enc: EncounterDef in lvl.encounters:
			if enc.type != EncounterDef.Type.COMBAT:
				continue
			for i: int in range(enc.enemy_stat_ids.size()):
				var chance := _effective_drop_chance(enc, i)
				if chance <= 0.0 or RNG.randf() > chance:
					continue
				var hero_class: StringName = GameState.next_drop_class(
					enc.is_boss and Tuning.DROP_BOSS_TARGETS_HUNGRIEST)
				if hero_class == &"":
					continue
				GameState.record_drop(hero_class)
				level_drops += 1
		if level_drops >= 3:
			d9_with_3plus += 1
			var all_covered := true
			for hero_class: StringName in Itemizer.droppable_classes():
				if GameState.drop_count(hero_class) <= 0:
					all_covered = false
					break
			if all_covered:
				d9_covered += 1
	GameState.drops_by_class.clear()
	var d9_rate := 100.0 * float(d9_covered) / float(maxi(d9_with_3plus, 1))
	print("D9: %d/%d simulated levels produced >= 3 drops; %.1f%% of those covered all three classes"
		% [d9_with_3plus, D9_LEVELS, d9_rate])
	t.check(d9_with_3plus > 0, "at least one simulated level produced >= 3 drops")
	t.check(d9_rate >= 95.0,
		">= 95%% of >= 3-drop levels covered all three classes (got %.1f%%)" % d9_rate)

	GameState.endless_level_number = saved_level_number
	GameState.active_party = d9_saved_party

	# --- informational: party_bonuses()["dmg_flat"] after a 3-level run -----
	_report_party_bonuses()

	t.finish(get_tree(), "test_drops")

## The level's expected drop count under the assumption every enemy dies -
## the literal "sum drop_chance over each COMBAT's enemy_stat_ids" §10 D8 asks
## for, not a full combat simulation.
func _expected_drops(lvl: LevelDef) -> float:
	var sum := 0.0
	for enc: EncounterDef in lvl.encounters:
		if enc.type != EncounterDef.Type.COMBAT:
			continue
		for i: int in range(enc.enemy_stat_ids.size()):
			sum += _effective_drop_chance(enc, i)
	return sum

## battle_director.start_combat() overrides drop_chance/drop_rarity_floor to
## 1.0/>=1 on whichever combatant fills the boss slot (index 0 of a boss
## encounter) - mirrored here so the simulation matches what actually happens
## at runtime rather than reading the unscaled .tres values.
func _effective_drop_chance(enc: EncounterDef, index: int) -> float:
	if enc.is_boss and index == 0:
		return 1.0
	var stats := GameState.get_stats(enc.enemy_stat_ids[index])
	return stats.drop_chance if stats != null else 0.0

func _effective_drop_rarity_floor(enc: EncounterDef, index: int) -> int:
	if enc.is_boss and index == 0:
		var stats := GameState.get_stats(enc.enemy_stat_ids[index])
		return maxi(1, stats.drop_rarity_floor if stats != null else 0)
	var stats := GameState.get_stats(enc.enemy_stat_ids[index])
	return stats.drop_rarity_floor if stats != null else 0

## Simulates three levels' worth of real drops (Bernoulli per enemy, same
## §4/§5 mechanism D9 exercises) into a scratch inventory, so
## party_bonuses()["dmg_flat"] can be read and reported - not gated, per §10's
## "a human needs to read it" note on §11's first open question.
func _report_party_bonuses() -> void:
	var saved_inventory := GameState.inventory
	var saved_drops := GameState.drops_by_class.duplicate()
	var saved_level_number := GameState.endless_level_number

	GameState.drops_by_class.clear()
	GameState.inventory = []

	# [equip] Routed through GameState.add_item(), not appended directly - that
	# is what applies auto-equip (§ equip request 2), and party_bonuses() now
	# only sums equipped items, so skipping add_item() would silently report 0
	# regardless of how much actually dropped.
	for n: int in range(saved_level_number, saved_level_number + 3):
		GameState.endless_level_number = n
		var lvl := GameState.build_level()
		for enc: EncounterDef in lvl.encounters:
			if enc.type != EncounterDef.Type.COMBAT:
				continue
			for i: int in range(enc.enemy_stat_ids.size()):
				var chance := _effective_drop_chance(enc, i)
				if chance <= 0.0 or RNG.randf() > chance:
					continue
				var hero_class: StringName = GameState.next_drop_class(
					enc.is_boss and Tuning.DROP_BOSS_TARGETS_HUNGRIEST)
				if hero_class == &"":
					continue
				GameState.record_drop(hero_class)
				GameState.add_item(
					Itemizer.generate_drop(hero_class, _effective_drop_rarity_floor(enc, i)))

	var bonuses := GameState.party_bonuses()
	print("party_bonuses()[\"dmg_flat\"] after a simulated 3-level run's drops (%d items, equipped-only): %d"
		% [GameState.inventory.size(), int(bonuses["dmg_flat"])])

	GameState.inventory = saved_inventory
	GameState.drops_by_class = saved_drops
	GameState.endless_level_number = saved_level_number
