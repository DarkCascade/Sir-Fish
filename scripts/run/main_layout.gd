extends Control
## Owns the one number that decides how the screen is divided: how many of the
## 1920 px belong to the battle view, with the console taking the rest.
##
## A dev-only export, like BattleDirector.turn_based_combat - there is no player
## facing control for it. 640 is the shipped 33/66 split; 960 is the 50/50
## experiment. Everything below re-lays itself from this, so trying a third value
## costs nothing.
@export var battle_height: float = 960.0

## How wide a slice of the AUTHORED world the camera shows, before
## Tuning.BATTLEFIELD_SCALE squeezes it. The authored slots span -4.0 to 4.0
## (Tuning.HERO_SLOT_X / ENEMY_X_MAX) plus about 0.4 of character on each end, so
## much under 9.0 clips the outermost fighters at any battlefield scale.
@export var camera_width: float = 9.7875

## Where the height a taller split buys gets spent: 1.0 is all sky, 0.5 splits it
## evenly above and below the authored framing. Below about 0.75 the ground plane
## runs out and the void under it shows.
@export_range(0.5, 1.0, 0.05) var sky_share: float = 0.85

const SCREEN := Vector2(1080, 1920)
const DIVIDER_HEIGHT := 8.0

@onready var battle_view: SubViewportContainer = $BattleView
@onready var overlay = $BattleOverlay
@onready var divider: ColorRect = $ConsoleDivider
@onready var console = $Console

func _ready() -> void:
	apply_split(battle_height)

func apply_split(h: float) -> void:
	battle_height = clampf(h, 320.0, SCREEN.y - 600.0)

	# The container has stretch enabled, so it drives the SubViewport's size -
	# assigning battle_viewport.size directly is refused by the engine.
	battle_view.position = Vector2.ZERO
	battle_view.size = Vector2(SCREEN.x, battle_height)

	# unproject_position() maps into the overlay 1:1 only while the two are the
	# same size at the same position (spec 3.3), so the overlay follows exactly.
	overlay.position = Vector2.ZERO
	overlay.size = Vector2(SCREEN.x, battle_height)

	divider.position = Vector2(0, battle_height)
	divider.size = Vector2(SCREEN.x, DIVIDER_HEIGHT)

	var console_top := battle_height + DIVIDER_HEIGHT
	console.position = Vector2(0, console_top)
	console.apply_height(SCREEN.y - console_top)

	_keep_camera_framing()

## The battle camera is orthographic and keeps its VERTICAL size by default, so a
## taller viewport would silently zoom the world in horizontally and bunch the
## heroes together. Pinning the WIDTH instead means changing the split changes how
## much sky and ground you see, and nothing else - hero spacing, prop scale and the
## parallax framing all stay exactly where they were authored.
##
## The default camera_width, 9.7875, is the horizontal extent the shipped 33/66
## split produced: the authored vertical size 5.8 across a 1080 x 640 viewport.
const CAMERA_BASE_HEIGHT := 5.8      # authored vertical extent at the 33/66 split
const CAMERA_BASE_Y := 2.2           # authored camera height above the ground

func _keep_camera_framing() -> void:
	var world := get_tree().get_first_node_in_group("battle_world")
	if world == null:
		return
	var cam := world.get_node_or_null("BattleCamera") as Camera3D
	if cam == null:
		return
	# Squeezing the field and the camera by the same factor leaves every combatant
	# on the pixel it was already on; only the models, whose size is fixed in world
	# units, grow. That is the whole trick (Tuning.BATTLEFIELD_SCALE).
	var field: float = Tuning.BATTLEFIELD_SCALE
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = camera_width * field

	# An orthographic camera grows symmetrically about its own centre, so a taller
	# view spends half its new room below the ground plane, on the void under it.
	# Lifting the camera moves that share back up into the sky.
	var extent := camera_width * field * (battle_height / SCREEN.x)
	cam.position.y = CAMERA_BASE_Y * field \
		+ (extent - CAMERA_BASE_HEIGHT * field) * (sky_share - 0.5)
