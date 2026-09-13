extends Node
## [inn & recovery] The rules that replaced the day/night cycle:
##   - GameState.rest_at_inn(): a flat Tuning.INN_NIGHT_COST any time, full
##     heal, downed revived, mayor's board refreshed.
##   - GameState.buy_meal(): one per quest - refused while a meal is unspent.
##   - GameState.recover_after_expedition(): a wipe brings every hero up to at
##     least RECOVERY_HP_FRACTION of max HP; a win is a free night at the inn
##     (full heal, no charge). Both spend the meal and refresh the board.
##   - SaveGame v4 -> v5: the day keys are dropped, a night-owed save recovered.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_inn_recovery.tscn

const TestSupport := preload("res://tests/test_support.gd")

var _q: QuestDef

func _ready() -> void:
	var t := TestSupport.new()
	t.guard_user_file(SaveGame.PATH)
	_q = load("res://resources/quests/easy.tres")

	_check_rest(t)
	_check_meal(t)
	_check_wipe_recovery(t)
	_check_victory_recovery(t)
	_check_save(t)

	GameState.quest = null
	GameState.completed_quest = null
	t.finish(get_tree(), "test_inn_recovery")

# --- helpers ----------------------------------------------------------------

func _hp(i: int = 0) -> int:
	return int(GameState.hero_runtime[i]["current_hp"])

func _max(i: int = 0) -> int:
	return int(GameState.hero_runtime[i]["max_hp"])

func _half(i: int = 0) -> int:
	return ceili(float(_max(i)) * Tuning.RECOVERY_HP_FRACTION)

func _set_hp(hp: int, i: int = 0) -> void:
	GameState.hero_runtime[i]["current_hp"] = hp
	GameState.hero_runtime[i]["alive"] = hp > 0

# --- the bed ----------------------------------------------------------------

func _check_rest(t: TestSupport) -> void:
	GameState.new_profile()
	GameState.quest_board_offers()
	GameState.gold = 500
	_set_hp(0)
	t.check(GameState.rest_at_inn(), "rest_at_inn() succeeds with gold on hand")
	t.check(GameState.gold == 500 - Tuning.INN_NIGHT_COST,
		"a night costs INN_NIGHT_COST (spent %d)" % [500 - GameState.gold])
	t.check(_hp() == _max() and bool(GameState.hero_runtime[0]["alive"]),
		"a night fully heals and revives a downed hero")
	t.check(not GameState.quest_board_generated, "a night refreshes the mayor's board")

	# Flat, not per hero.
	GameState.active_party = [&"warrior", &"ranger", &"mage"] as Array[StringName]
	GameState.heal_party()
	GameState.gold = 500
	GameState.rest_at_inn()
	t.check(GameState.gold == 500 - Tuning.INN_NIGHT_COST,
		"a three-hero party pays the same flat price (spent %d)" % [500 - GameState.gold])

	# Unaffordable: nothing changes.
	GameState.new_profile()
	GameState.quest_board_offers()
	GameState.gold = Tuning.INN_NIGHT_COST - 1
	_set_hp(5)
	t.check(not GameState.rest_at_inn(), "rest_at_inn() refuses when the party cannot pay")
	t.check(GameState.gold == Tuning.INN_NIGHT_COST - 1 and _hp() == 5
			and GameState.quest_board_generated,
		"an unaffordable night charges nothing, heals nothing and keeps the board")

	# Any time - there is no phase to wait on.
	GameState.gold = Tuning.INN_NIGHT_COST * 2
	t.check(GameState.rest_at_inn() and GameState.rest_at_inn(),
		"the inn can be used twice in a row")

# --- the meal ---------------------------------------------------------------

func _check_meal(t: TestSupport) -> void:
	GameState.new_profile()
	GameState.gold = 500
	var cost := GameState.meal_cost()
	t.check(GameState.meal_pct == 0, "a fresh profile is unfed")
	t.check(GameState.buy_meal(), "buy_meal() succeeds when unfed")
	t.check(GameState.gold == 500 - cost and GameState.meal_pct == Tuning.MEAL_DAMAGE_PCT,
		"a meal spends meal_cost() and sets meal_pct")
	t.check(not GameState.buy_meal() and GameState.gold == 500 - cost,
		"a second meal before the quest is refused and spends nothing")
	GameState.start_expedition(_q)
	t.check(GameState.meal_pct == Tuning.MEAL_DAMAGE_PCT, "the meal rides into the expedition")
	GameState.recover_after_expedition(true)
	t.check(GameState.meal_pct == 0, "finishing the quest spends the meal")
	t.check(GameState.buy_meal(), "a new meal can be bought for the next quest")

	GameState.meal_pct = 0
	GameState.gold = cost - 1
	t.check(not GameState.buy_meal() and GameState.meal_pct == 0,
		"an unaffordable meal sets nothing")

# --- coming home ------------------------------------------------------------

func _check_wipe_recovery(t: TestSupport) -> void:
	GameState.new_profile()
	GameState.start_expedition(_q)
	GameState.quest_board_offers()
	GameState.meal_pct = Tuning.MEAL_DAMAGE_PCT
	_set_hp(0)
	GameState.recover_after_expedition(false)
	t.check(_hp() == _half() and bool(GameState.hero_runtime[0]["alive"]),
		"a wipe revives a downed hero at half HP (got %d, want %d)" % [_hp(), _half()])
	t.check(GameState.meal_pct == 0, "a wipe spends the meal")
	t.check(not GameState.quest_board_generated, "a wipe refreshes the mayor's board")

	_set_hp(1)
	GameState.recover_after_expedition(false)
	t.check(_hp() == _half(),
		"a wipe brings a badly wounded hero up to half HP (got %d, want %d)" % [_hp(), _half()])

	var high: int = _max() - 1
	_set_hp(high)
	GameState.recover_after_expedition(false)
	t.check(_hp() == high,
		"a wipe leaves a hero already above half alone (got %d, want %d)" % [_hp(), high])

func _check_victory_recovery(t: TestSupport) -> void:
	GameState.new_profile()
	GameState.start_expedition(_q)
	GameState.quest_board_offers()
	var gold_before: int = GameState.gold
	_set_hp(0)
	GameState.recover_after_expedition(true)
	t.check(_hp() == _max() and bool(GameState.hero_runtime[0]["alive"]),
		"a win's free night revives a downed hero at full HP (got %d, want %d)" % [_hp(), _max()])
	t.check(GameState.gold == gold_before, "a win's night at the inn costs nothing")
	t.check(not GameState.quest_board_generated, "a win refreshes the mayor's board")

	_set_hp(3)
	GameState.recover_after_expedition(true)
	t.check(_hp() == _max(), "a win's free night fully heals a wounded hero (got %d)" % _hp())

# --- the save ---------------------------------------------------------------

func _check_save(t: TestSupport) -> void:
	GameState.new_profile()
	GameState.gold = 500
	GameState.buy_meal()
	SaveGame.save_profile()
	var f := FileAccess.open(SaveGame.PATH, FileAccess.READ)
	var d: Dictionary = str_to_var(f.get_as_text())
	f.close()
	t.check(int(d.get("version", 0)) == SaveGame.VERSION, "the save is written at SaveGame.VERSION")
	t.check(not d.has("day_phase") and not d.has("day_number") and not d.has("meal_eaten_today"),
		"the save writes no day/night key")
	GameState.meal_pct = 0
	t.check(SaveGame.load_profile() and GameState.meal_pct == Tuning.MEAL_DAMAGE_PCT,
		"an unspent meal round-trips")

	# A v4 save written with a night still owed: a downed hero and an old board.
	var legacy := {
		"version": 4, "gold": 100, "scrap": 10, "active_party": [&"warrior"],
		"day_phase": 2, "day_number": 3, "meal_pct": 0, "meal_eaten_today": true,
		"heroes": [{"stats_id": &"warrior", "current_hp": 0, "max_hp": 120, "alive": false}],
		"inventory": [], "quest_board": [], "quest_board_generated": true,
	}
	var w := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
	w.store_string(var_to_str(legacy))
	w.close()
	t.check(SaveGame.load_profile(), "a v4 save with a night owed migrates and loads")
	var hero: Dictionary = GameState.hero_runtime[0]
	t.check(int(hero["current_hp"]) == ceili(120.0 * Tuning.RECOVERY_HP_FRACTION)
			and bool(hero["alive"]),
		"the migration revives that save's downed hero at half HP (got %d)" % int(hero["current_hp"]))
	t.check(not GameState.quest_board_generated, "the migration refreshes that save's board")

	# A v4 save written in town: HP and board untouched, day keys dropped.
	var town_save: Dictionary = SaveGame._migrate_4_to_5({
		"version": 4, "day_phase": 0, "day_number": 7, "meal_eaten_today": false,
		"quest_board_generated": true,
		"heroes": [{"stats_id": &"warrior", "current_hp": 5, "max_hp": 120, "alive": true}],
	})
	t.check(not town_save.has("day_phase") and not town_save.has("day_number")
			and not town_save.has("meal_eaten_today"),
		"the v4 -> v5 migration drops every day/night key")
	var town_hero: Dictionary = (town_save["heroes"] as Array)[0]
	t.check(int(town_hero["current_hp"]) == 5 and bool(town_save["quest_board_generated"]),
		"a v4 save written in town keeps its HP and its board")
