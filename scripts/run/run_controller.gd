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
	# spec 3.2 / step-5 Q8: cover direct-scene launches (F5, MCP play_scene) too,
	# not just the routed path - go() sets this, but a bare main.tscn launch
	# would leave it defaulting to TOWN and drive Hud's InventoryButton rule off
	# a lie.
	SceneRouter.place = SceneRouter.Place.QUEST
	# D1: hand Hud a direct reference so _combat_locked() stops running a
	# recursive whole-tree find_child() every frame. Hud drops it when `place`
	# leaves QUEST and guards it with is_instance_valid() (go() frees this node).
	Hud.register_run_controller(self)

	var main := get_parent()
	world = main.get_node("BattleView/BattleViewport/BattleWorld")
	overlay = main.get_node("BattleOverlay")
	console = main.get_node("Console")
	shop_modal = main.get_node("ModalLayer/ShopModal")
	# spec 3.2 / step-5 Q2: the result modal moved to Hud/ModalLayer and was
	# renamed QuestResult. Step 5 is a reference swap plus a signal rename;
	# spec 8.5 rewires the actual victory/failure flow at step 8.
	run_summary = Hud.quest_result

	# As early as possible, so the shader-variant compiles it forces land
	# before the party is even moving rather than on the first real cast
	# (smoothness pass, suggestion 1). See BattleVfx.warm_up().
	BattleVfx.warm_up(world)

	director = BattleDirector.new()
	director.name = "BattleDirector"
	director.world = world
	add_child(director)

	EventBus.combat_ended.connect(_on_combat_ended)
	run_summary.dismissed.connect(_on_retry)

	console.bind_director(director)
	_start_run()

func _process(delta: float) -> void:
	if _running:
		GameState.run_stats["run_time"] = float(GameState.run_stats["run_time"]) + delta

# --- run lifecycle ----------------------------------------------------------

func _start_run() -> void:
	# spec 3.1 / step-5 Q1: guard, do not drop. Once main.tscn is a routed
	# destination rather than the main scene, an unconditional reset_run() here
	# wipes the profile boot.tscn just loaded. Guarded on `level == null` (not
	# `quest == null`): that is what lets a dev path opt out of the wipe by
	# calling start_expedition() itself - which is exactly what debug `route
	# quest` does at step 5, before the mayor (spec 7.5) exists. Every step-5
	# path into RunController still arrives with `level` null, so today this is
	# byte-for-byte the old behaviour.
	if GameState.level == null:
		GameState.reset_run()
	director.spawn_party()
	state = RunState.BOOT
	_running = true
	EventBus.run_started.emit()
	_next_encounter()

func _next_encounter() -> void:
	GameState.current_encounter_index += 1
	if GameState.current_encounter_index >= GameState.level.encounters.size():
		# [town] spec 8.3: a quest is a BOUNDED expedition - when its encounters
		# run out the party has won, so _run_complete() (previously dead code,
		# reachable only with endless_mode off) fires. Checked ahead of
		# endless_mode, which stays default-true even during a quest.
		if GameState.quest != null:
			_run_complete()
			return
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

	# Warm the fight's enemy scenes now, while the run-in gives the loader
	# several seconds of slack - see battle_director.preload_encounter()
	# (smoothness pass, suggestion 1). Fire-and-forget: the coroutine keeps
	# polling in the background while travel proceeds below.
	if def.type == EncounterDef.Type.COMBAT:
		director.preload_encounter(def.enemy_stat_ids)

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
			director.start_combat(def.enemy_stat_ids, def.is_boss, def.boss_drop_rarity_floor)
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
		director.pending_drops.clear()      # a wipe carries nothing home (§5)
		_game_over()
		return
	director.begin_corpse_cleanup()
	await _award_drops()
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

# --- DROPS (§5) -------------------------------------------------------------

## Mirrors _run_loot()'s presentation deliberately: a drop and a chest item are
## the same item from the same generator, so they should read as the same
## event. Labels pop at the recorded corpse positions rather than at a prop -
## the field is not scrolling yet (travel only restarts in _encounter_exit()),
## so those positions are still where the bodies fell.
##
## No _ui_hidden() branch, unlike _run_shop(): nothing here blocks on a button,
## so with the overlay hidden the items are still added and only the labels go
## unseen, which is the correct degradation.
func _award_drops() -> void:
	for entry: Dictionary in director.pending_drops:
		var item: Item = entry["item"]
		GameState.add_item(item)
		GameState.run_stats["items_found"] = int(GameState.run_stats["items_found"]) + 1
		GameState.run_stats["items_dropped"] = int(GameState.run_stats["items_dropped"]) + 1
		overlay.spawn_world_label(
			(entry["position"] as Vector3) + Vector3(0, Tuning.DROP_LABEL_LIFT, 0),
			"%s (%s)" % [item.display_name, item.class_label()],
			item.rarity_color(), Tuning.DROP_LABEL_FONT_SIZE)
		await get_tree().create_timer(Tuning.DROP_LABEL_STAGGER).timeout
	director.pending_drops.clear()

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

	# [town] spec 8.5 victory. RunController does the synchronous profile work
	# and emits; QuestResult (a persistent Hud child, unlike this scene) does the
	# await SceneRouter.go(MAYOR) -> present(true). It CANNOT be driven from here:
	# go() frees main.tscn, so a coroutine that awaited it would resume on a
	# freed RunController.
	if GameState.quest != null:
		var q := GameState.quest
		GameState.add_gold(q.gold_reward)
		GameState.completed_quest = q
		GameState.quest = null
		# [day-night] T2: QUEST -> NIGHT_PENDING, win or loss (day/night spec
		# §2.2). meal_pct is spent HERE - the expedition it paid for is over.
		GameState.day_phase = GameState.DayPhase.NIGHT_PENDING
		GameState.meal_pct = 0
		SaveGame.save_profile()
		EventBus.quest_finished.emit(true)
		return

	run_summary.present(true)     # endless_mode = false dev path, unchanged

func _game_over() -> void:
	state = RunState.GAME_OVER
	director.stop_combat()
	# Hold on the battlefield so the player sees the wipe (spec 18.1).
	await get_tree().create_timer(1.0).timeout
	_running = false
	EventBus.game_over.emit()

	# [town] spec 8.5 failure: keep banked gold and scrap, drop every unequipped
	# item found this trip, then hand off to QuestResult exactly as victory does
	# (see _run_complete()'s comment for why the route is not driven from here).
	if GameState.quest != null:
		GameState.discard_expedition_loot()
		GameState.completed_quest = GameState.quest
		GameState.quest = null
		# [day-night] T2: QUEST -> NIGHT_PENDING on a loss too (day/night spec
		# §2.2). A lost quest still eats the meal it was bought for.
		GameState.day_phase = GameState.DayPhase.NIGHT_PENDING
		GameState.meal_pct = 0
		SaveGame.save_profile()
		EventBus.quest_finished.emit(false)
		return

	run_summary.present(false)    # endless / fixed dev path, unchanged

# --- retry (spec 18.3) ------------------------------------------------------

func _on_retry() -> void:
	# [day-night] The quest path's QuestResult dismissal is consumed by
	# NightModal (day/night spec §4.2), not by a retry - completed_quest is
	# non-null exactly then. Only the endless / fixed dev path retries here.
	if GameState.completed_quest != null:
		return
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
	# spec 3.1 / step-5 Q1: endless retry wants the full wipe, explicitly. The
	# guard in _start_run() would otherwise skip it - `level` is still non-null
	# from the dead run - and respawn onto stale state.
	GameState.reset_run()
	_start_run()
