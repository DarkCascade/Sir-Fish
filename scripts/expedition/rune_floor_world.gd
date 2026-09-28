extends "res://scripts/battle/battle_world.gd"
## [rune floor demo] The battle world for the Rune Floor concept: a floating
## moss island in a black void, seen from a high tactical camera behind the
## party, with the slot board carved into the ground between the two sides.
##
## Everything BattleDirector, the abilities and BattleVfx reach for is the real
## BattleWorld API, inherited: the slot positions still derive from
## Tuning.PARTY_ANCHOR / RUN_DIR / ENEMY_DISTANCE, each side pushed back from the
## board by party_setback / enemy_setback. Combat rules are an expedition's; only
## the camera, the spacing and the scenery differ. OverworldField
## is an empty stand-in here - the demo never travels, so nothing scrolls it.

## The camera looks at a point this far up-run from the party anchor, from this
## far away, pitched this many degrees below the horizon. Solved against the
## full 1080 x 1920 portrait view with the invoker dock over the bottom band:
## low enough that the next islands (loot, shop, boss) hang in the top of the
## frame, as on the concept board. At this angle the far row's icons stand in
## front of the middle row's tiles - the billboards read through it.
@export var focus_along: float = 3.6
@export var camera_distance: float = 19.5
@export_range(20.0, 85.0, 0.5) var pitch_deg: float = 36.0
## Horizontal field of view (the camera keeps width, as the shipped one does).
@export_range(10.0, 90.0, 0.5) var fov_deg: float = 31.0

## Where the board sits between the party's front rank (0) and the enemy line
## (1). A little past halfway, so the warrior's model clears its near edge.
@export_range(0.3, 0.7, 0.01) var board_fraction: float = 0.55

## Both sides stand further from the board than an expedition's slots put them,
## so the board has the ground between them to itself: the party this far back
## down-run, the enemy line this far further up-run. Demo-only - Tuning's slot
## geometry, which the expedition camera is solved against, is untouched.
@export var party_setback: float = 1.5
@export var enemy_setback: float = 1.2

@export var fog_begin: float = 22.0
@export var fog_end: float = 70.0

func _ready() -> void:
	frame_camera()
	super._ready()
	var env := world_environment.environment
	env.fog_depth_begin = fog_begin
	env.fog_depth_end = fog_end

func hero_slot_position(index: int) -> Vector3:
	return super(index) - Tuning.RUN_DIR * party_setback

## enemy_entry_position() is built from this, so the run-in lane moves with it.
func enemy_slot_position(index: int, total: int) -> Vector3:
	return super(index, total) + Tuning.RUN_DIR * enemy_setback

## The board's centre, board_fraction of the way from the party's front rank to
## the enemy line.
func grid_centre() -> Vector3:
	return Tuning.PARTY_ANCHOR + Tuning.RUN_DIR * (Tuning.ENEMY_DISTANCE * board_fraction)

## The field's own frame: +x is the party's right, +z points back toward the
## party (down the screen), so board row 0 is the far row, nearest the enemies.
func field_basis() -> Basis:
	return Basis(perp_dir(), Vector3.UP, -Tuning.RUN_DIR)

func frame_camera() -> void:
	var focus: Vector3 = Tuning.PARTY_ANCHOR + Tuning.RUN_DIR * focus_along
	var pitch := deg_to_rad(pitch_deg)
	var eye: Vector3 = focus - Tuning.RUN_DIR * (cos(pitch) * camera_distance) \
		+ Vector3.UP * (sin(pitch) * camera_distance)
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = fov_deg
	camera.look_at_from_position(eye, focus, Vector3.UP)
