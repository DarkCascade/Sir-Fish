extends Node
## Content Phase 1, Step 3: AreaDef, QuestTemplate, QuestGenerator, the
## mayor's generated board, and its persistence.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_quest_generator.tscn

const TestSupport := preload("res://tests/test_support.gd")
const MayorOfficeScript := preload("res://scripts/town/mayor_office.gd")

func _ready() -> void:
	var t := TestSupport.new()
	t.guard_user_file(SaveGame.PATH)

	_check_content_lint(t)
	_check_area_def(t)
	_check_generator(t)
	_check_board_caching(t)
	_check_persistence(t)
	_check_authored_quest_order(t)
	_check_endless_uses_area(t)

	GameState.quest = null
	t.finish(get_tree(), "test_quest_generator")

func _check_content_lint(t: TestSupport) -> void:
	var dir := DirAccess.open("res://resources/quest_templates/")
	t.check(dir != null, "can open res://resources/quest_templates/")
	if dir == null:
		return
	var any := false
	for file_name: String in dir.get_files():
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		any = true
		var res := load("res://resources/quest_templates/" + clean)
		t.check(res is QuestTemplate, "%s loads as a QuestTemplate" % clean)
		if res is QuestTemplate:
			var qt := res as QuestTemplate
			t.check(qt.length_range.x >= 1 and qt.length_range.y >= qt.length_range.x,
				"%s: length_range is a valid non-empty inclusive range" % clean)
	t.check(any, "at least one QuestTemplate found on disk")

func _check_area_def(t: TestSupport) -> void:
	var area := GameState.ENDLESS_WOOD_AREA
	t.check(area != null, "ENDLESS_WOOD_AREA loads")
	t.check(area.pool != null and area.boss_pool != null,
		"ENDLESS_WOOD_AREA carries a regular pool and a boss pool")
	t.check(not area.name_fragments.is_empty(),
		"ENDLESS_WOOD_AREA carries name fragments for the generator")

func _check_generator(t: TestSupport) -> void:
	var area := GameState.ENDLESS_WOOD_AREA
	var ok_gold := true
	var ok_boss_last := true
	var ok_ids_resolve := true
	var ok_objectives := true
	var ok_level_range := true
	const N := 40
	for i: int in range(N):
		var anchor: int = 1 + i % area.level_band.y
		var q := QuestGenerator.generate_board(1, area, anchor)[0]
		var r := q.level_range
		if r.y - r.x + 1 != Tuning.QUEST_LEVEL_SPAN or r.x < area.level_band.x \
				or r.y > area.level_band.y or r != QuestGenerator.level_range_for(area, anchor):
			ok_level_range = false
		if q.gold_reward <= 0:
			ok_gold = false
		if q.encounter_types.is_empty() or q.encounter_types[-1] != EncounterDef.Type.COMBAT:
			ok_boss_last = false
		for eid: StringName in q.enemy_pool:
			if GameState.get_stats(eid) == null:
				ok_ids_resolve = false
		for eid: StringName in q.boss_pool:
			if GameState.get_stats(eid) == null:
				ok_ids_resolve = false
		if q.objectives.is_empty():
			ok_objectives = false
	t.check(ok_gold, "every generated quest has gold_reward > 0 (D2)")
	t.check(ok_boss_last, "every generated quest's last encounter type is COMBAT (the boss slot)")
	t.check(ok_ids_resolve, "every generated quest's enemy_pool/boss_pool ids resolve to real stats")
	t.check(ok_objectives, "every generated quest carries at least one objective")
	t.check(ok_level_range,
		"every generated quest's level_range is QUEST_LEVEL_SPAN wide and inside the area band")

	# [content phase 1] Q10: the range starts at the anchor (the party's level)
	# and slides, clamped so it never leaves the area's band.
	var band := area.level_band
	var span := Tuning.QUEST_LEVEL_SPAN
	var cases := [
		[band.x, Vector2i(band.x, band.x + span - 1)],
		[band.x + 1, Vector2i(band.x + 1, band.x + span)],
		[band.x - 5, Vector2i(band.x, band.x + span - 1)],
		[band.y - span + 1, Vector2i(band.y - span + 1, band.y)],
		[band.y, Vector2i(band.y - span + 1, band.y)],
		[band.y + 20, Vector2i(band.y - span + 1, band.y)],
	]
	for c: Array in cases:
		var got_range := QuestGenerator.level_range_for(area, int(c[0]))
		t.check(got_range == c[1], "level_range_for(anchor %d) -> %s (got %s)" % [c[0], c[1], got_range])

	# The live board anchors on GameState.hero_level().
	GameState.new_profile()
	GameState.hero_levels[&"warrior"] = 7
	var anchored := true
	for bq: QuestDef in GameState.quest_board_offers():
		if bq.level_range != QuestGenerator.level_range_for(area, 7):
			anchored = false
	t.check(anchored, "a level-7 party's board offers level %s quests" % [QuestGenerator.level_range_for(area, 7)])

	# The generated LevelDef actually builds and honours the objectives/gold -
	# a generated QuestDef is a plain QuestDef, so GameState.build_level()
	# needs no special case for one (spec §3.1).
	GameState.new_profile()
	var q := QuestGenerator.generate_board(1, area, GameState.hero_level())[0]
	GameState.start_expedition(q)
	t.check(GameState.level != null and GameState.level.encounters.size() == q.encounter_types.size(),
		"a generated quest builds a LevelDef with the right encounter count")
	t.check(GameState.quest_objectives.size() == q.objectives.size(),
		"start_expedition() duplicates a generated quest's objectives same as an authored one")

func _check_board_caching(t: TestSupport) -> void:
	GameState.new_profile()
	t.check(not GameState.quest_board_generated, "new_profile() clears quest_board_generated")
	var first := GameState.quest_board_offers()
	t.check(GameState.quest_board_generated, "quest_board_offers() sets quest_board_generated")
	t.check(first.size() == Tuning.QUEST_BOARD_SIZE,
		"quest_board_offers() generates QUEST_BOARD_SIZE quests (%d vs %d)"
			% [first.size(), Tuning.QUEST_BOARD_SIZE])
	var second := GameState.quest_board_offers()
	t.check(second == first, "a second quest_board_offers() call returns the SAME cached array, not a reroll")

	# [content phase 1] The board rerolls once per day (questions doc Q7):
	# resolve_night() drops it and the next visit generates a fresh one. A night
	# that does not resolve (an unaffordable inn) must leave it alone.
	var first_ids: Array[StringName] = []
	for q: QuestDef in first:
		first_ids.append(q.id)
	GameState.day_phase = GameState.DayPhase.NIGHT_PENDING
	GameState.gold = 0
	t.check(GameState.resolve_night(GameState.NightChoice.INN).is_empty(),
		"an unaffordable inn night does not resolve")
	t.check(GameState.quest_board_generated and GameState.quest_board_offers() == first,
		"a night that does not resolve leaves the board alone")
	t.check(not GameState.resolve_night(GameState.NightChoice.STREET).is_empty(),
		"a street night resolves")
	t.check(not GameState.quest_board_generated and GameState.quest_board.is_empty(),
		"resolve_night() drops the board so the new day regenerates it")
	var next_day := GameState.quest_board_offers()
	var overlap := false
	for q: QuestDef in next_day:
		if q.id in first_ids:
			overlap = true
	t.check(next_day.size() == Tuning.QUEST_BOARD_SIZE and not overlap,
		"the next day's board is a fresh roll, not yesterday's quests")

func _check_persistence(t: TestSupport) -> void:
	GameState.new_profile()
	var board := GameState.quest_board_offers()
	var want: Array = []
	for q: QuestDef in board:
		want.append([q.id, q.display_name, q.gold_reward, q.encounter_types.duplicate(),
			q.objectives.size(), q.objectives[0].kind() if not q.objectives.is_empty() else &""])
	SaveGame.save_profile()

	GameState.quest_board = []
	GameState.quest_board_generated = false
	t.check(SaveGame.load_profile(), "the round-trip save loads back")
	t.check(GameState.quest_board_generated, "quest_board_generated round-trips (true)")
	var round_trip_ok := GameState.quest_board.size() == want.size()
	for i: int in range(mini(want.size(), GameState.quest_board.size())):
		var q: QuestDef = GameState.quest_board[i]
		var got: Array = [q.id, q.display_name, q.gold_reward, q.encounter_types.duplicate(),
			q.objectives.size(), q.objectives[0].kind() if not q.objectives.is_empty() else &""]
		if got != want[i]:
			round_trip_ok = false
	t.check(round_trip_ok, "quest_board round-trips field-for-field, objectives included")

	# A save with no quest_board key (pre-Phase-1) loads as never-generated.
	var f := FileAccess.open(SaveGame.PATH, FileAccess.READ)
	var d: Dictionary = str_to_var(f.get_as_text())
	f.close()
	d.erase("quest_board")
	d.erase("quest_board_generated")
	var w := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
	w.store_string(var_to_str(d))
	w.close()
	GameState.quest_board_generated = true
	SaveGame.load_profile()
	t.check(not GameState.quest_board_generated and GameState.quest_board.is_empty(),
		"a legacy save with no quest_board key loads as never-generated")

func _check_authored_quest_order(t: TestSupport) -> void:
	var m := MayorOfficeScript.new()
	var authored: Array[QuestDef] = m._load_authored_quests()
	t.check(authored.size() == 3, "3 hand-authored quests load from disk (got %d)" % authored.size())
	var ids: Array[StringName] = []
	for q: QuestDef in authored:
		ids.append(q.id)
	t.check(ids == ([&"easy", &"medium", &"hard"] as Array[StringName]),
		"authored quests sort easy -> medium -> hard by level_range.x, not a hardcoded QUEST_ORDER (got %s)"
			% [ids])
	m.free()

func _check_endless_uses_area(t: TestSupport) -> void:
	GameState.reset_run()
	t.check(GameState.level.display_name.begins_with(GameState.ENDLESS_WOOD_AREA.display_name),
		"the endless level's name comes from AreaDef.display_name, not a hardcoded string (got '%s')"
			% GameState.level.display_name)
