extends ExpeditionPresentation
## [expedition phase II] The RUNE_FLOOR expedition's presentation (PRD §5.1,
## §6.1): the 3D world fills the whole 1080 x 1920 canvas, a thin top bar
## carries the quest's name under the Hud's own bag, party and minimap row, and
## the plate dock sits over the bottom band. No console.
##
## The real SlotMachine runs hidden in HiddenCabinet, never drawn: RuneFloor
## mirrors its board onto the ground, so the board never owns a rule and the
## combat sims stay honest (§5.2). RunController, the last child, drives the
## whole expedition through the ExpeditionPresentation half below; nothing
## about encounters, loot or results lives here.

## The hidden cabinet's height. The slot lays its reels out against it, and
## nothing of it is ever seen.
const CABINET_HEIGHT := 600.0

@onready var quest_name: Label = $TopBar/QuestName

func _ready() -> void:
	_refresh_quest_name()

## [perf] Stops the world re-rendering behind the shop's opaque scrim, as
## main_layout.gd does for CLASSIC. ShopModal calls it on its owner.
func set_world_rendering(enabled: bool) -> void:
	($BattleView/BattleViewport as SubViewport).render_target_update_mode = \
		SubViewport.UPDATE_WHEN_VISIBLE if enabled else SubViewport.UPDATE_DISABLED

## The quest's name, or an endless run's current level.
func _refresh_quest_name() -> void:
	var label := $TopBar/QuestName as Label
	if GameState.quest != null:
		label.text = GameState.quest.display_name
	elif GameState.level != null:
		label.text = GameState.level.display_name
	else:
		label.text = ""

## What the track shows for encounter `index` of the current level: its type, a
## boss as its own kind, NONE past a quest's end. An endless run builds its next
## level only when it gets there, so past the end of this one it can only say
## "a fight".
static func island_kind(index: int) -> RuneFloorIsland.Kind:
	var level: LevelDef = GameState.level
	if level == null or index >= level.encounters.size():
		return RuneFloorIsland.Kind.NONE if GameState.quest != null or not GameState.endless_mode \
			else RuneFloorIsland.Kind.COMBAT
	var def: EncounterDef = level.encounters[index]
	match def.type:
		EncounterDef.Type.LOOT: return RuneFloorIsland.Kind.LOOT
		EncounterDef.Type.SHOP: return RuneFloorIsland.Kind.SHOP
	return RuneFloorIsland.Kind.BOSS if def.is_boss else RuneFloorIsland.Kind.COMBAT

# --- ExpeditionPresentation (RUNE_FLOOR) -------------------------------------
# Paths, not @onready vars: RunController is a child, so it calls in here
# before this node's own _ready() has run.

func get_world() -> Node3D:
	return $BattleView/BattleViewport/RuneFloorWorld

func get_overlay() -> Control:
	return $BattleOverlay

func get_shop_modal() -> Control:
	return $ModalLayer/ShopModal

func bind_director(director: BattleDirector) -> void:
	var slot = $HiddenCabinet/SlotMachine
	slot.apply_height(CABINET_HEIGHT)
	slot.director = director
	for plate: HeroPlate in $Dock/Plates.get_children():
		plate.director = director
	(get_world().rune_floor as RuneFloor).bind(slot, director)

## The dock's and board's black glass arrive with milestone 3 (#213); until
## then a boss fight looks like any other.
func boss_theme(_on: bool) -> void:
	pass

func board_visible(on: bool) -> void:
	(get_world().rune_floor as RuneFloor).show_board(on, true)

## The board folds away (instantly on the first crossing, which happens under
## the fade in) and the track slides one island over. The crossing lasts the
## travel window plus the ease to a stop, as CLASSIC's scroll does, so the
## enemy preload and the boss nameplate keep their timing.
func begin_travel(def: EncounterDef) -> void:
	var world = get_world()
	(world.rune_floor as RuneFloor).show_board(false, false)
	_refresh_quest_name()
	var here := GameState.current_encounter_index
	var kinds: Array = [island_kind(here), island_kind(here + 1), island_kind(here + 2)]
	var duration: float = def.travel_duration + Tuning.TRAVEL_DECEL_TIME
	(world.track as RuneFloorTrack).begin_crossing(kinds, duration)

func end_travel() -> void:
	await (get_world().track as RuneFloorTrack).end_crossing()

func reset_track() -> void:
	$HiddenCabinet/SlotMachine.reset_to_attract()
	var world = get_world()
	(world.rune_floor as RuneFloor).show_board(false, false)
	(world.track as RuneFloorTrack).reset()

## Nothing here is hidden for framing: the shop always has a hand to close it.
func ui_hidden() -> bool:
	return false
