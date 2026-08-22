extends Node3D
## Owns the 3D battlefield: slot geometry, camera shake, and the roots that
## combatants, props and projectiles are parented to.

@onready var camera: Camera3D = $BattleCamera
@onready var parallax = $ParallaxBackground   # ParallaxBackground (untyped: custom API)
@onready var hero_slots: Node3D = $HeroSlots
@onready var enemy_root: Node3D = $EnemyRoot
@onready var prop_root: Node3D = $PropRoot
@onready var projectile_root: Node3D = $ProjectileRoot
@onready var world_environment: WorldEnvironment = $WorldEnvironment

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

## The authored slots, squeezed by Tuning.BATTLEFIELD_SCALE. Every world-space x
## in the battle goes through here or through world_x(), so the squeeze has
## exactly one definition.
func hero_slot_position(index: int) -> Vector3:
	return Vector3(world_x(float(Tuning.HERO_SLOT_X[index])), 0.0, 0.0)

## Works for any enemy count (spec 7.3).
func enemy_slot_x(index: int, total: int) -> float:
	if total <= 1:
		return world_x((Tuning.ENEMY_X_MIN + Tuning.ENEMY_X_MAX) * 0.5)
	return world_x(Tuning.ENEMY_X_MIN \
		+ (Tuning.ENEMY_X_MAX - Tuning.ENEMY_X_MIN) * (float(index) / float(total - 1)))

## An authored battlefield x, placed in the squeezed world.
func world_x(authored: float) -> float:
	return authored * Tuning.BATTLEFIELD_SCALE

func set_scroll_speed(value: float) -> void:
	parallax.scroll_speed = value

func get_scroll_speed() -> float:
	return parallax.scroll_speed

## Priest's darkening pass (spec 9.3).
func tween_brightness(to_value: float, duration: float) -> Tween:
	var env := world_environment.environment
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
			env.adjustment_brightness = v,
		env.adjustment_brightness, to_value, duration)
	return tween
