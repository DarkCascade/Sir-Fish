extends Node
## Expedition Phase II milestone 1 (#211): the expedition style, the Place.QUEST
## lookup by style, and RunController driven through the ExpeditionPresentation
## interface (PRD §6.1, §6.4).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_expedition_style.tscn

const TestSupport := preload("res://tests/test_support.gd")

const BATTLE_WORLD_SCENE := preload("res://scenes/battle/battle_world.tscn")
const OVERLAY_SCENE := preload("res://scenes/overlay/battle_overlay.tscn")
const RUN_CONTROLLER := preload("res://scripts/run/run_controller.gd")

const STYLE := AreaDef.ExpeditionStyle

## A shop that closes itself on the next frame, so the encounter chain moves on.
class StubShop extends Control:
	signal closed()
	var opened: int = 0

	func open(_def: EncounterDef) -> void:
		opened += 1
		closed.emit.call_deferred()

## Records every interface call, in order. Real world and overlay, since the
## director, props and glyphs are RunController's and need somewhere to live;
## everything a style owns is a log line.
class StubPresentation extends ExpeditionPresentation:
	var calls: Array[String] = []
	var world: Node3D
	var overlay: Control
	var shop: StubShop

	func get_world() -> Node3D:
		return world

	func get_overlay() -> Control:
		return overlay

	func get_shop_modal() -> Control:
		return shop

	func bind_director(_director: BattleDirector) -> void:
		calls.append("bind_director")

	func boss_theme(on: bool) -> void:
		calls.append("boss_theme(%s)" % on)

	func board_visible(on: bool) -> void:
		calls.append("board_visible(%s)" % on)

	func begin_travel(_def: EncounterDef) -> void:
		calls.append("begin_travel")

	func end_travel() -> void:
		calls.append("end_travel")
		await get_tree().process_frame

	func reset_track() -> void:
		calls.append("reset_track")

	func ui_hidden() -> bool:
		return false

var _t := TestSupport.new()

func _ready() -> void:
	_t.guard_user_file(SaveGame.PATH)
	GameState.new_profile()

	_check_resolution()
	_check_routing()
	_check_shipped_content_routes()
	_check_save_round_trip()
	await _check_run_controller()

	GameState.quest = null
	GameState.endless_mode = true
	SceneRouter.place = SceneRouter.Place.TOWN
	_t.finish(get_tree(), "test_expedition_style")

# --- style resolution -------------------------------------------------------

func _check_resolution() -> void:
	print("--- resolution ---")
	GameState.quest = null
	_t.check(GameState.expedition_style() == GameState.expedition_area().expedition_style,
		"with no quest, the style is the area's")
	_t.check(GameState.expedition_style() == STYLE.CLASSIC,
		"the Endless Wood is CLASSIC until milestone 7 (#217) flips it")
	_t.check(AreaDef.new().expedition_style == STYLE.RUNE_FLOOR,
		"a new area defaults to RUNE_FLOOR (decision 10.2)")

	var q := QuestDef.new()
	GameState.quest = q
	_t.check(q.expedition_style == QuestDef.STYLE_FROM_AREA
			and GameState.expedition_style() == STYLE.CLASSIC,
		"a quest with no override takes its area's style")
	q.expedition_style = STYLE.RUNE_FLOOR
	_t.check(GameState.expedition_style() == STYLE.RUNE_FLOOR,
		"a quest's RUNE_FLOOR override wins over a CLASSIC area")
	q.expedition_style = STYLE.CLASSIC
	_t.check(GameState.expedition_style() == STYLE.CLASSIC,
		"a quest's CLASSIC override resolves to CLASSIC")
	GameState.quest = null

# --- routing ----------------------------------------------------------------

func _check_routing() -> void:
	print("--- routing ---")
	var by_style: Dictionary = SceneRouter.PATHS[SceneRouter.Place.QUEST]
	var every_style := true
	for s: int in STYLE.values():
		if not by_style.has(s):
			every_style = false
	_t.check(every_style and by_style.size() == STYLE.size(),
		"PATHS[Place.QUEST] has one scene per ExpeditionStyle")

	GameState.quest = null
	_t.check(SceneRouter.path_for(SceneRouter.Place.QUEST) == "res://scenes/main.tscn",
		"a CLASSIC expedition routes to main.tscn")
	var q := QuestDef.new()
	q.expedition_style = STYLE.RUNE_FLOOR
	GameState.quest = q
	_t.check(SceneRouter.path_for(SceneRouter.Place.QUEST) == by_style[STYLE.RUNE_FLOOR],
		"a RUNE_FLOOR expedition routes to the Rune Floor scene")
	GameState.quest = null
	_t.check(SceneRouter.path_for(SceneRouter.Place.TOWN) == SceneRouter.PATHS[SceneRouter.Place.TOWN],
		"a place with one scene still routes straight to it")

## The guard that keeps RUNE_FLOOR the field default safe before its scene
## exists: nothing that ships may resolve to a style with no scene, or accepting
## that quest would soft-fail in go()'s missing-path bail.
func _check_shipped_content_routes() -> void:
	print("--- shipped content routes to a scene that exists ---")
	var by_style: Dictionary = SceneRouter.PATHS[SceneRouter.Place.QUEST]
	var quests: Array[QuestDef] = []
	for f: String in DirAccess.get_files_at("res://resources/quests"):
		if f.ends_with(".tres") or f.ends_with(".tres.remap"):
			quests.append(load("res://resources/quests/" + f.trim_suffix(".remap")) as QuestDef)
	# A generated quest carries no override, so it routes as its area does.
	quests.append(QuestDef.new())
	for q: QuestDef in quests:
		GameState.quest = q
		var path := SceneRouter.path_for(SceneRouter.Place.QUEST)
		_t.check(ResourceLoader.exists(path),
			"quest '%s' routes to a scene that exists (%s)" % [q.id, path])
	GameState.quest = null
	for f: String in DirAccess.get_files_at("res://resources/areas"):
		if not (f.ends_with(".tres") or f.ends_with(".tres.remap")):
			continue
		var area := load("res://resources/areas/" + f.trim_suffix(".remap")) as AreaDef
		_t.check(ResourceLoader.exists(String(by_style.get(area.expedition_style, ""))),
			"area '%s' has a scene for its style" % area.display_name)

func _check_save_round_trip() -> void:
	print("--- save round trip ---")
	var q := QuestDef.new()
	q.expedition_style = STYLE.RUNE_FLOOR
	_t.check(QuestDef.from_dict(q.to_dict()).expedition_style == STYLE.RUNE_FLOOR,
		"a generated quest's style override survives the saved board")
	var old := q.to_dict()
	old.erase("expedition_style")
	_t.check(QuestDef.from_dict(old).expedition_style == QuestDef.STYLE_FROM_AREA,
		"a board saved before the field reads back as 'from area'")

# --- RunController through the interface ------------------------------------

## A LOOT, a SHOP and a boss COMBAT through a stub presentation. The fight is
## ended by hand once it starts - heroes only act off the slot, which the stub
## does not have - so this checks the interface's call order, not combat.
func _check_run_controller() -> void:
	print("--- RunController drives the presentation interface ---")
	var stage := StubPresentation.new()
	stage.world = BATTLE_WORLD_SCENE.instantiate()
	stage.overlay = OVERLAY_SCENE.instantiate()
	stage.shop = StubShop.new()
	stage.add_child(stage.world)
	stage.add_child(stage.overlay)
	stage.add_child(stage.shop)

	GameState.quest = null
	GameState.endless_mode = false
	GameState.current_encounter_index = -1
	var lvl := LevelDef.new()
	var loot := EncounterDef.new()
	loot.type = EncounterDef.Type.LOOT
	loot.loot_item_count = 1
	loot.travel_duration = 0.1
	var shop := EncounterDef.new()
	shop.type = EncounterDef.Type.SHOP
	shop.travel_duration = 0.1
	var boss := EncounterDef.new()
	boss.type = EncounterDef.Type.COMBAT
	boss.is_boss = true
	boss.enemy_stat_ids = [&"shadow_monster"]
	# The boss keeps the default travel_duration: the nameplate is tuned to land
	# its impact inside it, and that timing is part of what is checked.
	lvl.encounters = [loot, shop, boss]
	GameState.level = lvl

	var rc = RUN_CONTROLLER.new()
	rc.name = "RunController"
	stage.add_child(rc)
	add_child(stage)

	var guard := 0
	while rc.state != rc.RunState.COMBAT and guard < 1200:
		await get_tree().process_frame
		guard += 1
	_t.check(rc.state == rc.RunState.COMBAT, "the run reached the boss fight")
	await get_tree().process_frame
	rc.director.stop_combat()
	rc.director.clear_enemies()
	EventBus.combat_ended.emit(true)
	guard = 0
	while rc.state != rc.RunState.RUN_COMPLETE and guard < 1200:
		await get_tree().process_frame
		guard += 1
	_t.check(rc.state == rc.RunState.RUN_COMPLETE, "the run completed")

	print("calls: %s" % [stage.calls])
	_t.check(stage.calls.front() == "bind_director", "the director is bound first")
	_t.check(stage.calls.count("begin_travel") == 3 and stage.calls.count("end_travel") == 3,
		"one begin/end_travel pair per encounter")
	_t.check(stage.shop.opened == 1, "the shop encounter opened the presentation's shop modal")
	var boss_on := stage.calls.find("boss_theme(true)")
	var board_on := stage.calls.find("board_visible(true)")
	var boss_off := stage.calls.find("boss_theme(false)")
	var board_off := stage.calls.find("board_visible(false)")
	_t.check(board_on > stage.calls.rfind("end_travel"),
		"the board comes on after the party arrives at the fight")
	_t.check(boss_on >= 0 and boss_on < board_on,
		"the boss theme lands during the crossing, before the fight")
	_t.check(boss_off > board_on and board_off > boss_off,
		"a won fight clears the boss theme, then puts the board away")
	_t.check(not stage.calls.has("reset_track"), "no reset without a retry")

	Hud.quest_result.visible = false
	stage.queue_free()
	await get_tree().process_frame
