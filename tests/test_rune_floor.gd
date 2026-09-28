extends Node
## Expedition Phase II milestone 2 (#212): the Rune Floor expedition. What the
## islands ahead show, the treadmill crossing, the board's states, the dock's
## empty "recruit to fill" plates, and one run of the real scene driven by
## RunController (PRD §5.1, §5.2, §5.6, §6.4).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_rune_floor.tscn

const TestSupport := preload("res://tests/test_support.gd")

const WORLD_SCENE := preload("res://scenes/expedition/rune_floor_world.tscn")
const PLATE_SCENE := preload("res://scenes/expedition/hero_plate.tscn")
const EXPEDITION_SCENE := preload("res://scenes/expedition_rune_floor.tscn")
const PRESENTATION := preload("res://scripts/expedition/rune_floor_expedition.gd")

const KIND := RuneFloorIsland.Kind

var _t := TestSupport.new()

func _ready() -> void:
	_t.guard_user_file(SaveGame.PATH)
	GameState.new_profile()

	_check_island_kinds()
	await _check_track()
	await _check_board()
	await _check_plates()
	await _check_expedition()

	GameState.quest = null
	GameState.level = null
	GameState.endless_mode = true
	SceneRouter.place = SceneRouter.Place.TOWN
	_t.finish(get_tree(), "test_rune_floor")

func _encounter(type: EncounterDef.Type, boss: bool = false) -> EncounterDef:
	var def := EncounterDef.new()
	def.type = type
	def.is_boss = boss
	def.travel_duration = 0.1
	def.loot_item_count = 1
	if type == EncounterDef.Type.COMBAT:
		def.enemy_stat_ids = [&"shadow_monster"]
	return def

# --- what the islands ahead show --------------------------------------------

func _check_island_kinds() -> void:
	print("--- island kinds follow the encounter list ---")
	var lvl := LevelDef.new()
	lvl.encounters = [_encounter(EncounterDef.Type.COMBAT), _encounter(EncounterDef.Type.LOOT),
		_encounter(EncounterDef.Type.SHOP), _encounter(EncounterDef.Type.COMBAT, true)]
	GameState.level = lvl
	GameState.quest = QuestDef.new()
	_t.check(PRESENTATION.island_kind(0) == KIND.COMBAT, "a fight is a COMBAT island")
	_t.check(PRESENTATION.island_kind(1) == KIND.LOOT, "a loot encounter is a LOOT island")
	_t.check(PRESENTATION.island_kind(2) == KIND.SHOP, "a shop encounter is a SHOP island")
	_t.check(PRESENTATION.island_kind(3) == KIND.BOSS, "a boss fight is a BOSS island")
	_t.check(PRESENTATION.island_kind(4) == KIND.NONE, "past a quest's last encounter there is no island")
	GameState.quest = null
	GameState.endless_mode = true
	_t.check(PRESENTATION.island_kind(4) == KIND.COMBAT,
		"past the end of an endless level the next level is unknown: a fight")
	GameState.endless_mode = false
	_t.check(PRESENTATION.island_kind(4) == KIND.NONE, "a bounded run ends where its list does")
	GameState.endless_mode = true

# --- the treadmill -----------------------------------------------------------

func _check_track() -> void:
	print("--- the track: a treadmill of islands ---")
	var world = WORLD_SCENE.instantiate()
	add_child(world)
	await get_tree().process_frame
	var track: RuneFloorTrack = world.track

	_t.check(track.docked_island() != null and track.docked_island().kind == KIND.START,
		"the party starts on a bare start island")
	_t.check(_live_islands(track) == 3, "three islands at rest: docked, next, preview")
	var dock_pose: Vector3 = track.docked_island().global_position
	var next_before: RuneFloorIsland = track.next_island()
	var next_pose: Vector3 = next_before.global_position
	_t.check_near(dock_pose.distance_to(next_pose), track.pitch, 0.01,
		"the next island waits one pitch up the run axis")

	track.begin_crossing([KIND.LOOT, KIND.SHOP, KIND.BOSS], 0.3)
	_t.check(track.is_crossing(), "a crossing is under way")
	_t.check(_live_islands(track) == 4, "a crossing briefly holds four islands")
	_t.check(next_before.kind == KIND.LOOT, "the island ahead is corrected to what comes next")
	await get_tree().create_timer(0.15).timeout
	var mid: Vector3 = next_before.global_position
	_t.check(mid.distance_to(dock_pose) < track.pitch - 0.5 and mid.distance_to(next_pose) > 0.5,
		"mid-crossing the next island is sliding toward the dock")
	await track.end_crossing()
	await get_tree().process_frame

	_t.check(track.docked_island() == next_before, "the next island docks")
	_t.check_near(track.docked_island().global_position.distance_to(dock_pose), 0.0, 0.01,
		"exactly where the last one stood")
	_t.check(_live_islands(track) == 3, "the island left behind is freed")
	_t.check(track.next_island().kind == KIND.SHOP, "the shop is next")
	_t.check(track.next_island().get_node_or_null("Bridge") != null,
		"the bridge to the next island is laid")
	var loot: RuneFloorIsland = track.docked_island()
	_t.check(loot._marker != null and not loot._marker.visible,
		"a docked loot island's chest steps aside for the real one")

	track.begin_crossing([KIND.SHOP, KIND.BOSS, KIND.NONE], 0.2)
	_t.check(loot._marker != null and not loot._marker.visible,
		"a spent island's marker stays down as it slides away")
	await track.end_crossing()
	await get_tree().process_frame
	_t.check(track.next_island().kind == KIND.BOSS, "the boss is next")
	_t.check(_live_islands(track) == 2, "past a quest's end no preview island is built")

	track.begin_crossing([KIND.BOSS, KIND.NONE, KIND.NONE], 0.2)
	await track.end_crossing()
	await get_tree().process_frame
	_t.check(track.docked_island().kind == KIND.BOSS and track.next_island() == null,
		"on the last island the track ends")

	track.reset()
	await get_tree().process_frame
	_t.check(track.docked_island().kind == KIND.START and _live_islands(track) == 3,
		"reset puts the party back on a start island")
	world.queue_free()
	await get_tree().process_frame

func _live_islands(track: RuneFloorTrack) -> int:
	var n := 0
	for child: Node in track.get_children():
		if child is RuneFloorIsland and not child.is_queued_for_deletion():
			n += 1
	return n

# --- the board ------------------------------------------------------------------

func _check_board() -> void:
	print("--- the board folds and unfolds ---")
	var world = WORLD_SCENE.instantiate()
	add_child(world)
	await get_tree().process_frame
	var board: RuneFloor = world.rune_floor
	_t.check(board.visible and board.is_shown(), "the board starts out (the demo never folds it)")
	board.show_board(false, false)
	_t.check(not board.visible and not board.is_shown(), "folded instantly: hidden")
	board.show_board(true, true)
	_t.check(board.visible and board.is_shown(), "unfolding shows it at once")
	await get_tree().create_timer(board.unfold_time + 0.1).timeout
	_t.check_near(board.scale.x, 1.0, 0.01, "unfolded to full size")
	board.show_board(false, true)
	await get_tree().create_timer(board.fold_time + 0.1).timeout
	_t.check(not board.visible, "folded away and hidden once the fold ends")
	world.queue_free()
	await get_tree().process_frame

# --- the dock ---------------------------------------------------------------------

func _check_plates() -> void:
	print("--- the dock keeps an empty plate for a missing hero ---")
	GameState.active_party = [&"warrior"]
	var plate: HeroPlate = PLATE_SCENE.instantiate()
	plate.hero_class = &"ranger"
	plate.special_name = "Bomb Arrow"
	add_child(plate)
	await get_tree().process_frame
	var name_label: Label = plate.get_node("Column/NamePill/Name")
	_t.check(plate.visible, "the plate stays in the dock")
	_t.check(plate.disabled, "an empty plate has nothing to press")
	_t.check(name_label.text == plate.empty_text, "its pill says '%s'" % plate.empty_text)
	_t.check(plate.get_node("Column/HpBar").modulate.a == 0.0, "no health bar")
	_t.check((plate.get_node("Column/Ring") as PlateChargeRing).silhouette,
		"the portrait draws as a silhouette")

	GameState.active_party = [&"warrior", &"ranger"]
	await get_tree().process_frame
	_t.check(not plate.disabled and name_label.text == "Bomb Arrow",
		"a recruit fills the plate with their special")
	_t.check(plate.get_node("Column/HpBar").modulate.a == 1.0, "and their health")
	plate.queue_free()
	GameState.active_party = [&"warrior"]
	await get_tree().process_frame

# --- the real scene --------------------------------------------------------------

## The real expedition scene, driven by RunController: a loot island, then a boss
## fight. The fight is ended by hand once it starts, as in test_expedition_style.
func _check_expedition() -> void:
	print("--- the Rune Floor expedition, end to end ---")
	GameState.quest = null
	GameState.endless_mode = false
	GameState.current_encounter_index = -1
	var lvl := LevelDef.new()
	lvl.encounters = [_encounter(EncounterDef.Type.LOOT), _encounter(EncounterDef.Type.COMBAT, true)]
	GameState.level = lvl

	var stage = EXPEDITION_SCENE.instantiate()
	_t.check(stage is ExpeditionPresentation, "the scene's root is an ExpeditionPresentation")
	add_child(stage)
	var rc = stage.get_node("RunController")
	var world = stage.get_world()
	var board: RuneFloor = world.rune_floor
	var track: RuneFloorTrack = world.track

	await get_tree().process_frame
	_t.check(not board.visible, "the board is dark while the party travels")
	_t.check(track.is_crossing(), "the expedition opens with the first crossing")

	var guard := 0
	while rc.state != rc.RunState.COMBAT and guard < 1200:
		await get_tree().process_frame
		guard += 1
	_t.check(rc.state == rc.RunState.COMBAT, "the run reached the boss fight")
	_t.check(track.docked_island().kind == KIND.BOSS, "the party stands on the boss island")
	_t.check(board.visible, "the board unfolds for the fight")
	_t.check(track.next_island() == null, "the boss island is the end of the track")

	await get_tree().process_frame
	rc.director.stop_combat()
	rc.director.clear_enemies()
	EventBus.combat_ended.emit(true)
	await get_tree().create_timer(board.fold_time + 0.1).timeout
	_t.check(not board.visible, "a won fight folds the board away")

	guard = 0
	while rc.state != rc.RunState.RUN_COMPLETE and guard < 1200:
		await get_tree().process_frame
		guard += 1
	_t.check(rc.state == rc.RunState.RUN_COMPLETE, "the run completed")

	Hud.quest_result.visible = false
	stage.queue_free()
	await get_tree().process_frame
