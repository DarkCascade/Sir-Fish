extends Node
## Top-level state machine (spec 12). Drives travel, encounters, the shop and
## the run summary, and owns the BattleDirector.

enum RunState {
	BOOT, TRAVEL, ARRIVE, COMBAT, LOOT, SHOP,
	ENCOUNTER_EXIT, RUN_COMPLETE, GAME_OVER
}

const CHEST_SCENE := preload("res://scenes/battle/props/treasure_chest.tscn")
const SHOP_SCENE := preload("res://scenes/battle/props/shop_building.tscn")

var state: RunState = RunState.BOOT

# These five are deliberately untyped: each exposes a custom script API that a
# static Node/Control annotation would reject at parse time.
var world
var overlay
var console
var shop_modal
var run_summary
var director: BattleDirector

var _prop = null
var _running: bool = false

func _ready() -> void:
	var main := get_parent()
	world = main.get_node("BattleView/BattleViewport/BattleWorld")
	overlay = main.get_node("BattleOverlay")
	console = main.get_node("Console")
	shop_modal = main.get_node("ModalLayer/ShopModal")
	run_summary = main.get_node("ModalLayer/RunSummary")

	director = BattleDirector.new()
	director.name = "BattleDirector"
	director.world = world
	add_child(director)

	EventBus.combat_ended.connect(_on_combat_ended)
	run_summary.retry_pressed.connect(_on_retry)

	console.bind_director(director)
	_start_run()

func _process(delta: float) -> void:
	if _running:
		GameState.run_stats["run_time"] = float(GameState.run_stats["run_time"]) + delta

# --- run lifecycle ----------------------------------------------------------

func _start_run() -> void:
	GameState.reset_run()
	director.spawn_party()
	state = RunState.BOOT
	_running = true
	EventBus.run_started.emit()
	_next_encounter()

func _next_encounter() -> void:
	GameState.current_encounter_index += 1
	if GameState.current_encounter_index >= GameState.level.encounters.size():
		if not GameState.endless_mode:
			_run_complete()
			return
		# Endless (spec: Endless Mode): the party never "completes" a level,
		# it just walks into the next one - generate it and keep going. The
		# run only ends via _game_over() on a wipe.
		GameState.endless_level_number += 1
		GameState.level = GameState.build_level()
		GameState.current_encounter_index = 0
	var def: EncounterDef = GameState.level.encounters[GameState.current_encounter_index]
	_travel(def)

# --- TRAVEL / ARRIVE --------------------------------------------------------

func _travel(def: EncounterDef) -> void:
	state = RunState.TRAVEL
	for hero: Combatant in director.living_heroes():
		hero.set_running(true)
	EventBus.travel_started.emit()

	var accel := create_tween()
	accel.tween_method(Callable(world, "set_scroll_speed"),
		world.get_scroll_speed(), Tuning.TRAVEL_SPEED, Tuning.TRAVEL_ACCEL_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(def.travel_duration).timeout
	_arrive(def)

func _arrive(def: EncounterDef) -> void:
	state = RunState.ARRIVE
	var decel := create_tween()
	decel.tween_method(Callable(world, "set_scroll_speed"),
		world.get_scroll_speed(), 0.0, Tuning.TRAVEL_DECEL_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await decel.finished

	for hero: Combatant in director.living_heroes():
		hero.set_running(false)
	EventBus.travel_finished.emit()
	EventBus.encounter_started.emit(GameState.current_encounter_index, def)

	match def.type:
		EncounterDef.Type.COMBAT:
			state = RunState.COMBAT
			director.start_combat(def.enemy_stat_ids, def.is_boss)
		EncounterDef.Type.LOOT:
			state = RunState.LOOT
			_run_loot(def)
		EncounterDef.Type.SHOP:
			state = RunState.SHOP
			_run_shop(def)

# --- COMBAT -----------------------------------------------------------------

func _on_combat_ended(victory: bool) -> void:
	if state != RunState.COMBAT:
		return
	if not victory:
		_game_over()
		return
	director.begin_corpse_cleanup()
	_encounter_resolved()

# --- LOOT (spec 14.2) -------------------------------------------------------

func _run_loot(def: EncounterDef) -> void:
	var chest = CHEST_SCENE.instantiate()
	world.prop_root.add_child(chest)
	chest.position = world.prop_position(3.2)
	_prop = chest
	chest.pop_in()

	await get_tree().create_timer(0.5 + 0.45).timeout
	chest.open()
	await get_tree().create_timer(0.35).timeout

	for item: Item in Itemizer.generate_items(def.loot_item_count):
		GameState.add_item(item)
		GameState.run_stats["items_found"] = int(GameState.run_stats["items_found"]) + 1
		overlay.spawn_world_label(chest.global_position + Vector3(0, 1.2, 0),
			item.display_name, item.rarity_color())
		await get_tree().create_timer(0.25).timeout

	_encounter_resolved()

# --- SHOP (spec 14.3) -------------------------------------------------------

func _run_shop(def: EncounterDef) -> void:
	var building = SHOP_SCENE.instantiate()
	world.prop_root.add_child(building)
	building.position = world.prop_position(3.4)
	_prop = building
	building.pop_in()

	await get_tree().create_timer(0.4 + 0.45).timeout

	# [overworld prototype] The shop modal is a UI element AND a blocking one:
	# the encounter resolves only when its close button is pressed. With the
	# console hidden for camera framing there is nobody to press it, so the
	# encounter chain would stall here forever and the "ongoing action" the
	# overworld is meant to show would stop at the first shop. Hold on the
	# building for a beat instead and move on.
	if _ui_hidden():
		await get_tree().create_timer(Tuning.SHOP_SKIP_HOLD).timeout
		_encounter_resolved()
		return

	shop_modal.open(def)
	# The encounter resolves only when the modal's close button is pressed.
	await shop_modal.closed
	_encounter_resolved()

## Whether the run is being played with the UI hidden (main_layout.hide_console).
func _ui_hidden() -> bool:
	var main := get_parent()
	return main != null and bool(main.get("hide_console"))

# --- resolution / exit ------------------------------------------------------

func _encounter_resolved() -> void:
	var def: EncounterDef = GameState.level.encounters[GameState.current_encounter_index]
	GameState.run_stats["encounters_cleared"] = \
		int(GameState.run_stats["encounters_cleared"]) + 1
	EventBus.encounter_resolved.emit(GameState.current_encounter_index, def)

	if _prop != null and is_instance_valid(_prop):
		_prop.fade_out()
		_prop = null

	await get_tree().create_timer(Tuning.ENCOUNTER_RESOLVE_PAUSE).timeout
	await director.await_corpse_cleanup()
	_encounter_exit()

## Spec 12.5 / Q11. "Removed from the battlefield" means visually removed, not
## freed: the node stays alive and stays in director.heroes, because the status
## panel's three rows are index-addressed and freeing the node would shift them.
## A dead hero is freed only on Retry (spec 18.3). Conceptually the party leaves
## them behind; visually, because the camera is fixed and the world scrolls, the
## corpse slides off-screen behind the party, which is the correct read.
##
## [overworld prototype] "Off-screen behind the party" is back down the run
## axis now rather than along -X, so the corpse leaves through the bottom-left
## corner - the direction the field is scrolling anyway.
func _encounter_exit() -> void:
	state = RunState.ENCOUNTER_EXIT
	var dead: Array = director.dead_heroes()
	for hero: Combatant in dead:
		if hero.visible:
			var tw := create_tween()
			tw.tween_property(hero, "global_position", world.exit_position(),
				Tuning.DEAD_HERO_EXIT_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw.tween_callback(func() -> void:
				if is_instance_valid(hero):
					hero.visible = false)
	# [v3.5 D5] Do not wait for that tween. Travel begins on the same frame,
	# so the world scrolls past the departing corpse instead of the corpse
	# crawling away under its own power across a static background.
	_next_encounter()

# --- endings ----------------------------------------------------------------

func _run_complete() -> void:
	state = RunState.RUN_COMPLETE
	for hero: Combatant in director.living_heroes():
		hero.set_running(true)
	var tw := create_tween()
	tw.tween_method(Callable(world, "set_scroll_speed"),
		0.0, Tuning.TRAVEL_SPEED, 0.4)
	await get_tree().create_timer(2.0).timeout
	world.set_scroll_speed(0.0)
	for hero: Combatant in director.living_heroes():
		hero.set_running(false)
	_running = false
	EventBus.run_completed.emit()
	run_summary.present(true)

func _game_over() -> void:
	state = RunState.GAME_OVER
	director.stop_combat()
	# Hold on the battlefield so the player sees the wipe (spec 18.1).
	await get_tree().create_timer(1.0).timeout
	_running = false
	EventBus.game_over.emit()
	run_summary.present(false)

# --- retry (spec 18.3) ------------------------------------------------------

func _on_retry() -> void:
	director.stop_combat()
	director.clear_enemies()
	director.clear_party()
	for root: Node3D in [world.projectile_root, world.prop_root]:
		for child: Node in root.get_children():
			child.queue_free()
	_prop = null
	overlay.clear_all()
	console.slot_machine.reset_to_attract()
	world.set_scroll_speed(0.0)
	world.parallax.reset_tiles()
	await get_tree().process_frame
	_start_run()
