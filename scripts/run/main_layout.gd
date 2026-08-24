extends Control
## Owns the one number that decides how the screen is divided: how many of the
## 1920 px belong to the battle view, with the console taking the rest.
##
## A dev-only export, like BattleDirector.turn_based_combat - there is no
## player-facing control for it. 640 was the old 33/66 split and 960 the 50/50
## experiment; 764 is the concept board's own division, measured off it (the
## world occupies almost exactly the top 40% there, not a third).
##
## [overworld prototype] `hide_console` overrides the split entirely and gives
## the battle view the whole 1080 x 1920, so the overhead camera can be framed
## against nothing but the field. Turn it off to get the console back - the
## split maths below is untouched and still runs.
@export var battle_height: float = 764.0

## First-draft framing aids. The slot machine, status panel and upgrade tray
## are the console; the bars, damage numbers and status icons are the overlay.
## Both are hidden while the camera is being framed.
@export var hide_console: bool = true
@export var hide_overlay: bool = true

const SCREEN := Vector2(1080, 1920)
## [ui-project-longshot] Was an 8 px solid gold bar. On the concept board there
## is no rule between the world and the console at all - the carved frame's own
## top edge IS the boundary, with the world sitting behind it. This is now just
## a thin dark gutter, so the console reads as being in FRONT of the forest
## rather than stacked below it.
const DIVIDER_HEIGHT := 5.0

@onready var battle_view: SubViewportContainer = $BattleView
@onready var overlay = $BattleOverlay
@onready var divider: ColorRect = $ConsoleDivider
@onready var console = $Console

func _ready() -> void:
	apply_split(SCREEN.y if hide_console else battle_height)

func apply_split(h: float) -> void:
	var full: bool = hide_console
	battle_height = SCREEN.y if full else clampf(h, 320.0, SCREEN.y - 600.0)

	# The container has stretch enabled, so it drives the SubViewport's size -
	# assigning battle_viewport.size directly is refused by the engine.
	battle_view.position = Vector2.ZERO
	battle_view.size = Vector2(SCREEN.x, battle_height)

	# unproject_position() maps into the overlay 1:1 only while the two are the
	# same size at the same position (spec 3.3), so the overlay follows exactly
	# even when it is hidden - a hidden overlay that is later switched back on
	# must already be aligned.
	overlay.position = Vector2.ZERO
	overlay.size = Vector2(SCREEN.x, battle_height)
	overlay.visible = not hide_overlay

	divider.visible = not full
	console.visible = not full
	if full:
		_keep_camera_framing()
		return

	divider.position = Vector2(0, battle_height)
	divider.size = Vector2(SCREEN.x, DIVIDER_HEIGHT)

	var console_top := battle_height + DIVIDER_HEIGHT
	console.position = Vector2(0, console_top)
	console.apply_height(SCREEN.y - console_top)

	_keep_camera_framing()

## The overhead camera is perspective and pinned to KEEP_WIDTH, so its
## horizontal coverage is fixed no matter how tall the viewport is: changing
## the split changes how much field you see up and down the run axis, and
## nothing else. That is the whole reason the side-on view's ortho-size /
## BATTLEFIELD_SCALE juggling is gone - with KEEP_WIDTH there is nothing left
## to recompute, only to enforce.
func _keep_camera_framing() -> void:
	var world := get_tree().get_first_node_in_group("battle_world")
	if world == null:
		return
	var cam := world.get_node_or_null("BattleCamera") as Camera3D
	if cam == null:
		return
	cam.keep_aspect = Camera3D.KEEP_WIDTH
