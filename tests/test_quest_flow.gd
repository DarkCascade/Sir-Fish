extends Node
## The spec 8.5 economy: what a lost quest keeps and drops, and the free
## "sleep in the street" half-heal. These are the numbers that stop a failed
## hard quest from being pure profit (spec 8.5 / 1.9), so they get a permanent
## guard even though spec 13.1 only names test_quest_gen for step 8.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_quest_flow.tscn

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()
	t.guard_user_file(SaveGame.PATH)

	var q: QuestDef = load("res://resources/quests/easy.tres")

	# --- discard_expedition_loot: keep town gear + equipped, drop loose loot ---
	GameState.new_profile()
	var town_item := Itemizer.generate_item()          # carried from town (index 0)
	GameState.inventory.append(town_item)
	GameState.start_expedition(q)
	t.check(GameState._expedition_inventory_mark == 1, "mark snapshots inventory size at start")
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

	# --- street_sleep_recover: ceil(half missing), once per expedition ---------
	GameState.new_profile()
	GameState.start_expedition(q)
	GameState.hero_runtime[0]["current_hp"] = 10
	var maxhp: int = int(GameState.hero_runtime[0]["max_hp"])
	GameState.street_sleep_recover()
	var want: int = 10 + ceili(float(maxhp - 10) * Tuning.INN_STREET_HEAL_FRACTION)
	t.check(int(GameState.hero_runtime[0]["current_hp"]) == want,
		"street sleep heals ceil(half missing) (got %d, want %d)"
			% [int(GameState.hero_runtime[0]["current_hp"]), want])
	t.check(GameState.street_sleep_used, "street sleep sets the once-per-expedition flag")
	GameState.start_expedition(q)
	t.check(not GameState.street_sleep_used, "start_expedition clears street_sleep_used")

	# --- a dead hero is revived by the free heal ------------------------------
	GameState.hero_runtime[0]["current_hp"] = 0
	GameState.hero_runtime[0]["alive"] = false
	GameState.street_sleep_recover()
	t.check(int(GameState.hero_runtime[0]["current_hp"]) > 0 and GameState.hero_runtime[0]["alive"],
		"street sleep revives a downed hero")

	GameState.quest = null
	GameState.completed_quest = null
	t.finish(get_tree(), "test_quest_flow")
