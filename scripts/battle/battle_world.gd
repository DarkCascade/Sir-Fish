extends Node3D
## Owns the 3D battlefield: slot geometry, camera shake, and the roots that
## combatants, props and projectiles are parented to.
##
## [overworld prototype] The battlefield is a plane now, not a line. Every
## position below is derived from Tuning.RUN_DIR and Tuning.PARTY_ANCHOR, so
## the whole composition - party formation, enemy rank, entry lane, props -
## rotates as one if RUN_DIR changes. There is no second place to edit.

@onready var camera: Camera3D = $BattleCamera
@onready var field = $OverworldField           # OverworldField (untyped: custom API)
@onready var hero_slots: Node3D = $HeroSlots
@onready var enemy_root: Node3D = $EnemyRoot
@onready var prop_root: Node3D = $PropRoot
@onready var projectile_root: Node3D = $ProjectileRoot
@onready var world_environment: WorldEnvironment = $WorldEnvironment

## RunController still reaches for `world.parallax` on the retry path. The
## field answers the same two calls (reset_tiles / advance_tiles), so the alias
## keeps that path working without a second name for one object.
@onready var parallax = $OverworldField

var _shake_time: float = 0.0
var _shake_duration: float = 0.0
var _shake_amount: float = 0.0

func _process(delta: float) -> void:
	if _shake_time <= 0.0:
		return
	_shake_time = maxf(0.0, _shake_time - delta)
	var decay := _shake_time / maxf(_shake_duration, 0.0001)
	camera.h_offset = RNG.randf_range(-_shake_amount, _shake_amount) * decay
	camera.v_offset = RNG.randf_range(-_shake_amount, _shake_amount) * decay
	if _shake_time <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

## Spec 7.2: shake is used only where an ability explicitly calls for it.
func shake(amount: float, duration: float) -> void:
	_shake_amount = maxf(_shake_amount, amount)
	_shake_duration = duration
	_shake_time = duration

# --- the run axis -------------------------------------------------------------

## The direction the party runs: up and to the right on screen.
func run_dir() -> Vector3:
	return Tuning.RUN_DIR

## RUN_DIR turned 90 degrees about the ground normal - the axis ranks spread
## along. Right-handed, so +perp is the party's right.
func perp_dir() -> Vector3:
	return Tuning.RUN_DIR.cross(Vector3.UP).normalized()

## The facing convention itself lives on Tuning, because Combatant needs it
## during setup() before it would be safe to reach through `director.world`.
func yaw_along(dir: Vector3) -> float:
	return Tuning.yaw_along(dir)

# --- slots --------------------------------------------------------------------

## Two ranks: the warrior alone in front, the mage and the ranger behind him.
## The shape itself is authored in Tuning.PARTY_FORMATION, in RUN_DIR's frame,
## so it rotates with the run axis and this only has to project it out.
func hero_slot_position(index: int) -> Vector3:
	if index < 0 or index >= Tuning.PARTY_FORMATION.size():
		return Tuning.PARTY_ANCHOR
	var slot: Vector2 = Tuning.PARTY_FORMATION[index]
	return Tuning.PARTY_ANCHOR \
		+ perp_dir() * (slot.x * Tuning.PARTY_ROW_SPREAD) \
		- Tuning.RUN_DIR * (slot.y * Tuning.PARTY_ROW_DEPTH)

## The enemy rank forms up-run from the party leader, spread across the
## perpendicular so every enemy is visible rather than hidden behind the one
## in front. Works for any enemy count (spec 7.3).
func enemy_slot_position(index: int, total: int) -> Vector3:
	var centre: Vector3 = Tuning.PARTY_ANCHOR + Tuning.RUN_DIR * Tuning.ENEMY_DISTANCE
	if total <= 1:
		return centre
	var across: float = (float(index) - float(total - 1) * 0.5) * Tuning.ENEMY_SPREAD
	return centre + perp_dir() * across

## Where an enemy starts its run-in: straight up-run from its own slot, well
## past the top-right corner of the frame.
func enemy_entry_position(index: int, total: int) -> Vector3:
	return enemy_slot_position(index, total) \
		+ Tuning.RUN_DIR * Tuning.ENEMY_ENTRY_DISTANCE

## Kept because Debug's `spawn` verb addresses enemy slots by X (spec 19.2).
func enemy_slot_x(index: int, total: int) -> float:
	return enemy_slot_position(index, total).x

## Where a chest or shop building stands: up-run from the party, on the axis,
## roughly where the enemy rank would have been.
func prop_position(distance: float) -> Vector3:
	return Tuning.PARTY_ANCHOR + Tuning.RUN_DIR * distance

## Where a dead hero is carried off to - straight back down the run axis, out
## through the bottom-left corner (spec 12.5 / Q11).
func exit_position() -> Vector3:
	return Tuning.PARTY_ANCHOR - Tuning.RUN_DIR * 16.0

# --- field --------------------------------------------------------------------

func set_scroll_speed(value: float) -> void:
	field.scroll_speed = value

func get_scroll_speed() -> float:
	return field.scroll_speed

## Priest's darkening pass (spec 9.3).
func tween_brightness(to_value: float, duration: float) -> Tween:
	var env := world_environment.environment
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
			env.adjustment_brightness = v,
		env.adjustment_brightness, to_value, duration)
	return tween
