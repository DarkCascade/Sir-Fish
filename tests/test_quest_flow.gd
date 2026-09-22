extends Node
## The spec 8.5 economy: what a lost quest keeps and drops. These are the
## numbers that stop a failed hard quest from being pure profit (spec 8.5 /
## 1.9), so they get a permanent guard even though spec 13.1 only names
## test_quest_gen for step 8. What coming home does to the party's HP, and the
## inn's bed and meal, are test_inn_recovery.gd.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_quest_flow.tscn

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()
	t.guard_user_file(SaveGame.PATH)

	var q: QuestDef = load("res://resources/quests/easy.tres")

	# --- discard_expedition_loot: keep town gear + equipped, drop loose loot ---
	GameState.new_profile()                             # ships a starting weapon at index 0
	var town_item := Itemizer.generate_item()          # carried from town
	GameState.inventory.append(town_item)
	var inv_at_start := GameState.inventory.size()
	GameState.start_expedition(q)
	t.check(GameState._expedition_inventory_mark == inv_at_start,
		"mark snapshots inventory size at start (got %d, want %d)"
			% [GameState._expedition_inventory_mark, inv_at_start])
	t.check(GameState.completed_quest == null, "start_expedition clears completed_quest")

	var found_loose := Itemizer.generate_item_with_rarity(Item.Rarity.COMMON)
	var found_equipped := Itemizer.generate_item_with_rarity(Item.Rarity.RARE)
	GameState.inventory.append(found_loose)
	GameState.inventory.append(found_equipped)
	GameState.equip_item(found_equipped, &"warrior")

	GameState.discard_expedition_loot()
	t.check(GameState.inventory.has(town_item), "town gear survives a failed quest")
	t.check(GameState.inventory.has(found_equipped), "equipped loot survives a failed quest")
	t.check(not GameState.inventory.has(found_loose), "loose expedition loot is discarded")

	# --- issue #116: selling a pre-quest item keeps the mark accurate ---
	# Selling an unequipped pre-quest item at the quest's shop used to leave
	# _expedition_inventory_mark one too high (remove_item() shifted every later
	# index down but never adjusted the mark), so one loose found item dodged
	# the wipe discard.
	GameState.new_profile()                             # ships a starting weapon at index 0
	var town_item_a := Itemizer.generate_item()
	var town_item_b := Itemizer.generate_item()
	GameState.inventory.append(town_item_a)
	GameState.inventory.append(town_item_b)
	GameState.start_expedition(q)
	var mark_at_start: int = GameState._expedition_inventory_mark

	var found_item := Itemizer.generate_item_with_rarity(Item.Rarity.COMMON)
	GameState.inventory.append(found_item)              # found this trip, index >= mark

	GameState.remove_item(town_item_b)                  # sold at the quest's shop
	t.check(GameState._expedition_inventory_mark == mark_at_start - 1,
		"remove_item() before the mark decrements it (got %d, want %d)"
			% [GameState._expedition_inventory_mark, mark_at_start - 1])

	GameState.discard_expedition_loot()
	t.check(not GameState.inventory.has(found_item),
		"found loot is still discarded after a pre-quest item was sold")
	t.check(GameState.inventory.has(town_item_a), "the untouched pre-quest item survives")

	GameState.quest = null
	GameState.completed_quest = null
	t.finish(get_tree(), "test_quest_flow")
