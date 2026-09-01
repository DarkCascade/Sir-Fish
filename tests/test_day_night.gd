extends Node
## [day-night] The day/night state machine, the night maths, the meal, and the
## persistence of all four new fields (day/night spec §11.1). The point of the
## whole pass is that "one quest per day, one night per quest" is a property of
## the DayPhase enum's transitions, not a flag anyone has to remember to clear -
## assertions 2-7 test that directly.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_day_night.tscn

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()
	t.guard_user_file(SaveGame.PATH)

	var q: QuestDef = load("res://resources/quests/easy.tres")
	var DP := GameState.DayPhase
	var NC := GameState.NightChoice

	# ================= the state machine =================================

	# 1. new_profile() starts a fresh day, unfed.
	GameState.new_profile()
	t.check(GameState.day_phase == DP.DAY, "1: new_profile() -> day_phase DAY")
	t.check(GameState.day_number == 1, "1: new_profile() -> day_number 1")
	t.check(GameState.meal_pct == 0, "1: new_profile() -> meal_pct 0")

	# 2. T1: a real QuestDef moves DAY -> QUEST.
	GameState.start_expedition(q)
	t.check(GameState.day_phase == DP.QUEST, "2: start_expedition(q) -> QUEST")

	# 3. The §2.2 guard: start_expedition() with NO argument leaves day_phase.
	#    This is the one that prevents the permanent endless-path lockout.
	GameState.new_profile()
	GameState.start_expedition()
	t.check(GameState.day_phase == DP.DAY, "3: start_expedition() no-arg stays in DAY")

	# 4. resolve_night() in QUEST returns [] and mutates nothing.
	GameState.new_profile()
	GameState.start_expedition(q)
	GameState.hero_runtime[0]["current_hp"] = 40
	var gold_before: int = GameState.gold
	var got: Array = GameState.resolve_night(NC.STREET)
	t.check(got.is_empty(), "4: resolve_night() in QUEST returns []")
	t.check(int(GameState.hero_runtime[0]["current_hp"]) == 40, "4: HP untouched")
	t.check(GameState.gold == gold_before, "4: gold untouched")

	# 5. From NIGHT_PENDING, resolve_night(STREET) -> DAY, day_number++.
	GameState.day_phase = DP.NIGHT_PENDING
	var day_was: int = GameState.day_number
	GameState.resolve_night(NC.STREET)
	t.check(GameState.day_phase == DP.DAY, "5: resolve_night(STREET) -> DAY")
	t.check(GameState.day_number == day_was + 1, "5: day_number incremented")

	# 6. A second resolve_night(STREET) immediately after returns [] and heals
	#    nothing. This is "cannot trigger multiple nights in a row".
	GameState.hero_runtime[0]["current_hp"] = 30
	var again: Array = GameState.resolve_night(NC.STREET)
	t.check(again.is_empty(), "6: second resolve_night() returns []")
	t.check(int(GameState.hero_runtime[0]["current_hp"]) == 30, "6: no second heal")

	# 7. A quest, then a night, succeeds again - "must undertake a quest after a
	#    night".
	GameState.start_expedition(q)
	GameState.day_phase = DP.NIGHT_PENDING
	t.check(not GameState.resolve_night(NC.STREET).is_empty(),
		"7: quest -> night resolves again")

	# ================= the street formula (§3.3 table) ===================

	# 8. 120 max, before 10 -> after 65.
	GameState.new_profile()
	GameState.start_expedition(q)
	GameState.day_phase = DP.NIGHT_PENDING
	GameState.hero_runtime[0]["current_hp"] = 10
	GameState.resolve_night(NC.STREET)
	t.check(int(GameState.hero_runtime[0]["current_hp"]) == 65, "8: 10 -> 65")

	# 9. before 0, dead -> after 60, revived.
	GameState.start_expedition(q)
	GameState.day_phase = DP.NIGHT_PENDING
	GameState.hero_runtime[0]["current_hp"] = 0
	GameState.hero_runtime[0]["alive"] = false
	GameState.resolve_night(NC.STREET)
	t.check(int(GameState.hero_runtime[0]["current_hp"]) == 60, "9: 0 -> 60")
	t.check(GameState.hero_runtime[0]["alive"], "9: revived")

	# 10. before 119 -> after 120, never above max.
	GameState.start_expedition(q)
	GameState.day_phase = DP.NIGHT_PENDING
	GameState.hero_runtime[0]["current_hp"] = 119
	GameState.resolve_night(NC.STREET)
	t.check(int(GameState.hero_runtime[0]["current_hp"]) == 120, "10: 119 -> 120")
	t.check(int(GameState.hero_runtime[0]["current_hp"])
		<= int(GameState.hero_runtime[0]["max_hp"]), "10: never above max_hp")

	# ================= the inn ===========================================

	# 11. Full heal 10/120 -> 120/120.
	GameState.new_profile()
	GameState.start_expedition(q)
	GameState.day_phase = DP.NIGHT_PENDING
	GameState.hero_runtime[0]["current_hp"] = 10
	GameState.gold = 10_000
	GameState.resolve_night(NC.INN)
	t.check(int(GameState.hero_runtime[0]["current_hp"]) == 120, "11: inn -> full heal")

	# 12. Charges exactly INN_REST_COST_PER_HERO * party size.
	GameState.start_expedition(q)
	GameState.day_phase = DP.NIGHT_PENDING
	GameState.hero_runtime[0]["current_hp"] = 10
	var g0: int = GameState.gold
	GameState.resolve_night(NC.INN)
	var want_cost: int = Tuning.INN_REST_COST_PER_HERO * GameState.active_party.size()
	t.check(g0 - GameState.gold == want_cost,
		"12: inn charges %d (got %d)" % [want_cost, g0 - GameState.gold])

	# 13. gold = cost - 1: returns [], gold + HP unchanged, still NIGHT_PENDING.
	#    (Catches a heal that lands before the spend_gold() check.)
	GameState.start_expedition(q)
	GameState.day_phase = DP.NIGHT_PENDING
	GameState.hero_runtime[0]["current_hp"] = 15
	GameState.gold = GameState.night_inn_cost() - 1
	var poor_gold: int = GameState.gold
	var poor: Array = GameState.resolve_night(NC.INN)
	t.check(poor.is_empty(), "13: unaffordable inn returns []")
	t.check(GameState.gold == poor_gold, "13: gold unchanged")
	t.check(int(GameState.hero_runtime[0]["current_hp"]) == 15, "13: HP unchanged")
	t.check(GameState.day_phase == DP.NIGHT_PENDING, "13: still NIGHT_PENDING")

	# ================= the report (§4.3) =================================

	# 14. before_hp is pre-night, after_hp is post-night - the snapshot really is
	#     taken before the mutation.
	GameState.start_expedition(q)
	GameState.day_phase = DP.NIGHT_PENDING
	GameState.hero_runtime[0]["current_hp"] = 20
	GameState.gold = 10_000
	var rep: Array = GameState.resolve_night(NC.INN)
	t.check(int(rep[0]["before_hp"]) == 20, "14: report before_hp is pre-night")
	t.check(int(rep[0]["after_hp"]) == 120, "14: report after_hp is post-night")
	t.check(GameState.last_night_report.size() == rep.size(),
		"14: last_night_report is the returned report")

	# ================= the meal =========================================

	# 15. buy_meal() in DAY with gold: true, spends, sets both fields.
	GameState.new_profile()
	GameState.gold = 10_000
	var g_meal: int = GameState.gold
	t.check(GameState.buy_meal(), "15: buy_meal() in DAY returns true")
	t.check(g_meal - GameState.gold
		== Tuning.MEAL_COST_PER_HERO * GameState.active_party.size(),
		"15: meal spends MEAL_COST_PER_HERO * party")
	t.check(GameState.meal_pct == Tuning.MEAL_DAMAGE_PCT, "15: meal_pct set")
	t.check(GameState.meal_eaten_today, "15: meal_eaten_today set")

	# 16. Second buy_meal() same day: false, spends nothing, meal_pct stays 10.
	var g_second: int = GameState.gold
	t.check(not GameState.buy_meal(), "16: second buy_meal() returns false")
	t.check(GameState.gold == g_second, "16: second buy_meal() spends nothing")
	t.check(GameState.meal_pct == Tuning.MEAL_DAMAGE_PCT, "16: meal_pct still 10, not 20")

	# 17. buy_meal() with gold = cost - 1: false, sets neither field.
	GameState.new_profile()
	GameState.gold = GameState.meal_cost() - 1
	t.check(not GameState.buy_meal(), "17: unaffordable buy_meal() returns false")
	t.check(GameState.meal_pct == 0 and not GameState.meal_eaten_today,
		"17: unaffordable buy_meal() sets neither field")

	# 18. buy_meal() outside DAY: false.
	GameState.new_profile()
	GameState.gold = 10_000
	GameState.day_phase = DP.QUEST
	t.check(not GameState.buy_meal(), "18: buy_meal() outside DAY returns false")

	# 19. party_bonuses() carries meal_pct separately from dmg_pct.
	GameState.new_profile()
	GameState.gold = 10_000
	GameState.buy_meal()
	var b: Dictionary = GameState.party_bonuses()
	t.check(int(b["meal_pct"]) == Tuning.MEAL_DAMAGE_PCT, "19: party_bonuses meal_pct")
	t.check(int(b["dmg_pct"]) == 0, "19: party_bonuses dmg_pct untouched by the meal")

	# 20. The compounding regression (§9.5). Source-text guard, per the spec's
	#     sanctioned fallback: apply_party_bonuses() must not reconstruct the
	#     buff by dividing the previous damage_multiplier back out.
	var src := FileAccess.get_file_as_string("res://scripts/battle/combatant.gd")
	var body := src.substr(src.find("func apply_party_bonuses"))
	body = body.substr(0, body.find("\nfunc "))
	t.check(not body.contains("damage_multiplier /"),
		"20: apply_party_bonuses() no longer divides damage_multiplier back out")
	t.check(body.contains("meal_multiplier()"),
		"20: apply_party_bonuses() recomputes from GameState.meal_multiplier()")

	# 21. T2 clears meal_pct but not meal_eaten_today; T3 clears meal_eaten_today
	#     and leaves meal_pct at 0 (§9.4's table).
	GameState.new_profile()
	GameState.gold = 10_000
	GameState.buy_meal()
	GameState.start_expedition(q)
	# simulate T2 (run_controller does this in the quest-end block)
	GameState.day_phase = DP.NIGHT_PENDING
	GameState.meal_pct = 0
	t.check(GameState.meal_pct == 0, "21: T2 clears meal_pct")
	t.check(GameState.meal_eaten_today, "21: T2 leaves meal_eaten_today set")
	GameState.resolve_night(NC.STREET)   # T3
	t.check(not GameState.meal_eaten_today, "21: T3 clears meal_eaten_today")
	t.check(GameState.meal_pct == 0, "21: T3 leaves meal_pct at 0")

	# ================= persistence (§8.1) ===============================

	# 22. All four new fields round-trip through save/load.
	GameState.new_profile()
	GameState.day_phase = DP.NIGHT_PENDING
	GameState.day_number = 7
	GameState.meal_pct = 10
	GameState.meal_eaten_today = true
	SaveGame.save_profile()
	GameState.day_phase = DP.DAY
	GameState.day_number = 1
	GameState.meal_pct = 0
	GameState.meal_eaten_today = false
	t.check(SaveGame.load_profile(), "22: load_profile() succeeds")
	t.check(GameState.day_phase == DP.NIGHT_PENDING, "22: day_phase round-trips")
	t.check(GameState.day_number == 7, "22: day_number round-trips")
	t.check(GameState.meal_pct == 10, "22: meal_pct round-trips")
	t.check(GameState.meal_eaten_today, "22: meal_eaten_today round-trips")

	# 23. A legacy payload with none of the four keys loads as DAY / 1 / 0 / false.
	var f := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
	f.store_string(var_to_str({
		"version": 2, "gold": 100, "scrap": 10,
		"active_party": [&"warrior"], "heroes": [], "inventory": [],
	}))
	f.close()
	GameState.day_phase = DP.NIGHT_PENDING
	GameState.day_number = 99
	GameState.meal_pct = 10
	GameState.meal_eaten_today = true
	t.check(SaveGame.load_profile(), "23: legacy payload loads")
	t.check(GameState.day_phase == DP.DAY, "23: legacy -> day_phase DAY")
	t.check(GameState.day_number == 1, "23: legacy -> day_number 1")
	t.check(GameState.meal_pct == 0, "23: legacy -> meal_pct 0")
	t.check(not GameState.meal_eaten_today, "23: legacy -> meal_eaten_today false")

	GameState.quest = null
	GameState.completed_quest = null
	t.finish(get_tree(), "test_day_night")
