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

	# --- D2: droppable_classes() == PARTY_ORDER, no hero unreachable --------
	t.check(Itemizer.droppable_classes() == GameState.PARTY_ORDER,
		"droppable_classes() equals PARTY_ORDER (got %s)" % [Itemizer.droppable_classes()])

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
	GameState.drops_by_class.clear()
	const D4_N := 3000
	for i: int in range(D4_N):
		GameState.record_drop(GameState.next_drop_class())
	for hero_class: StringName in GameState.PARTY_ORDER:
		var share := 100.0 * float(GameState.drop_count(hero_class)) / float(D4_N)
		t.check_between(share, 31.3, 35.3,
			"%s's live-counter drop share is 33.3%% +/- 2pp over %d drops (got %.1f%%)"
				% [hero_class, D4_N, share])
	GameState.drops_by_class.clear()

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

	# --- D7: regression guard - generate_item() weapon types stay ~20% -----
	const D7_N := 3000
	var d7_by_type: Dictionary = {}
	for wtype: StringName in Itemizer.WEAPON_TYPES.keys():
		d7_by_type[wtype] = 0
	for i: int in range(D7_N):
		var wtype: StringName = Itemizer.generate_item().weapon_type
		d7_by_type[wtype] = int(d7_by_type[wtype]) + 1
	for wtype: StringName in Itemizer.WEAPON_TYPES.keys():
		var pct := 100.0 * float(d7_by_type[wtype]) / float(D7_N)
		t.check_between(pct, 16.0, 24.0,
			"generate_item()'s %s share is 20%% +/- 3pp (got %.1f%%)" % [wtype, pct])

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
			for hero_class: StringName in GameState.PARTY_ORDER:
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
