class_name CombatantBarsBase
extends Control
## Shared plumbing for the two bar layouts: the compact enemy pair
## (combatant_bars.gd/.tscn) and the hero card (hero_bars.gd/.tscn). Each
## scene nests its CooldownFill/HealthBg/HealthFill/etc wherever its own
## layout wants - the six rects below are plain vars, not @onready $Path
## lookups, precisely so a scene is free to restructure without the other
## one's paths going stale. Each subclass resolves them against its own
## hierarchy in _ready(), before calling super._ready(). Rounding, tweening
## and the damage-chunk math stay identical either way.

const ROUNDED_SHADER := preload("res://assets/shaders/rounded_rect.gdshader")

## A radius past half the shorter side just reads as a full pill - see
## rounded_rect.gdshader - so this one constant covers every bar rect
## regardless of its width.
const PILL_RADIUS := 999.0

var combatant: Combatant = null

## [ui-project-longshot] What colour this bar's fill returns to. Was implicit
## (every bar was C_DANGER red, so the heal flash could hardcode its way back),
## and that stopped being true the moment the party bars took a colour per
## hero: a healed mage flashed green and then settled to red. Subclasses that
## want a coloured bar set this in setup() alongside health_fill.color; the
## default keeps every existing red bar exactly as it was.
var base_fill_color: Color = Tuning.C_DANGER

## Set by each subclass's setup() to its own fixed layout width - there is no
## runtime layout math left to derive it from. Both are read only by
## subclasses, which the analyzer can't see from here.
@warning_ignore("unused_private_class_variable")
var _fill_width: float = 0.0
@warning_ignore("unused_private_class_variable")
var _cd_width: float = 0.0

## Overlay bars are pushed their health by BattleOverlay's damage handlers, which
## also spawn the detaching chunk (spec 11.2). The console's party bars have no
## such handler and no chunk to detach, so they pull the fraction on every frame
## instead and tween the difference.
var poll_health: bool = false
@warning_ignore("unused_private_class_variable")
var _polled_fraction: float = -1.0

## Resolved by each subclass's _ready() against its own scene - see the class
## comment above for why these aren't @onready $Path lookups here.
var cooldown_border: ColorRect
var cooldown_bg: ColorRect
var cooldown_fill: ColorRect
var health_border: ColorRect
var health_bg: ColorRect
var health_fill: ColorRect

func _ready() -> void:
	_round(cooldown_border, PILL_RADIUS)
	_round(cooldown_bg, PILL_RADIUS)
	_round(cooldown_fill, PILL_RADIUS)
	_round(health_border, PILL_RADIUS)
	_round(health_bg, PILL_RADIUS)
	_round(health_fill, PILL_RADIUS)

## Rounds one bar rect's corners via a shader instead of swapping ColorRect
## for a StyleBox-backed control, so every existing .color assignment and
## .size:x tween (health/cooldown fills, flash_background) keeps working
## untouched. Idempotent: calling it again (e.g. a hero retry re-running
## setup()) just updates the existing material instead of stacking new
## signal connections.
func _round(rect: ColorRect, radius: float) -> void:
	if rect == null:      # hero_bars.gd has no cooldown row - see its _ready()
		return
	var mat := rect.material as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = ROUNDED_SHADER
		rect.material = mat
		rect.resized.connect(func() -> void:
			(rect.material as ShaderMaterial).set_shader_parameter("box_size", rect.size))
	mat.set_shader_parameter("corner_radius", radius)
	mat.set_shader_parameter("box_size", rect.size)

func pop_in() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.6, 0.6)
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, Tuning.BARS_POP_IN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, Tuning.BARS_POP_IN_TIME)

## Snaps the health fill; the detached chunk carries the motion (spec 11.2).
func set_health_fraction(fraction: float) -> void:
	health_fill.size.x = _fill_width * clampf(fraction, 0.0, 1.0)

## Healing tweens up instead, and flashes green (spec 11.2). A polled party bar
## losing health tweens the same way but must not flash green about it.
func tween_health_fraction(fraction: float, heal_flash: bool = true) -> void:
	var tw := create_tween()
	tw.tween_property(health_fill, "size:x", _fill_width * clampf(fraction, 0.0, 1.0), 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if not heal_flash:
		return
	var flash := create_tween()
	flash.tween_property(health_fill, "color", Tuning.C_HEAL, 0.15)
	flash.tween_property(health_fill, "color", base_fill_color, 0.15)

func flash_background() -> void:
	var tw := create_tween()
	tw.tween_property(health_bg, "color", Color.WHITE, 0.05)
	tw.tween_property(health_bg, "color", Tuning.C_CONSOLE_BG, 0.05)

## World-space rect of the segment that was just lost, in global 2D coords.
func lost_segment_rect(f_prev: float, f_new: float) -> Rect2:
	var x0 := _fill_width * clampf(f_new, 0.0, 1.0)
	var x1 := _fill_width * clampf(f_prev, 0.0, 1.0)
	var origin := health_fill.global_position + Vector2(x0, 0.0)
	return Rect2(origin, Vector2(maxf(x1 - x0, 1.0), health_fill.size.y))

func fade_and_free() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
