extends Control
## Health + cooldown pair for one combatant (spec 11). Lives in the 2D overlay,
## never in 3D, so it can be positioned pixel-exactly over the character.

const FILL_WIDTH := 136.0

var combatant: Combatant = null

@onready var cooldown_fill: ColorRect = $CooldownFill
@onready var health_fill: ColorRect = $HealthFill
@onready var health_bg: ColorRect = $HealthBg

func pop_in() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.6, 0.6)
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, Tuning.BARS_POP_IN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, Tuning.BARS_POP_IN_TIME)

func refresh() -> void:
	if combatant == null or not is_instance_valid(combatant):
		return
	cooldown_fill.size.x = FILL_WIDTH * combatant.cooldown_fraction()

## Snaps the health fill; the detached chunk carries the motion (spec 11.2).
func set_health_fraction(fraction: float) -> void:
	health_fill.size.x = FILL_WIDTH * clampf(fraction, 0.0, 1.0)

## Healing tweens up instead, and flashes green (spec 11.2).
func tween_health_fraction(fraction: float) -> void:
	var tw := create_tween()
	tw.tween_property(health_fill, "size:x", FILL_WIDTH * clampf(fraction, 0.0, 1.0), 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var flash := create_tween()
	flash.tween_property(health_fill, "color", Tuning.C_HEAL, 0.15)
	flash.tween_property(health_fill, "color", Tuning.C_DANGER, 0.15)

func flash_background() -> void:
	var tw := create_tween()
	tw.tween_property(health_bg, "color", Color.WHITE, 0.05)
	tw.tween_property(health_bg, "color", Tuning.C_CONSOLE_BG, 0.05)

## World-space rect of the segment that was just lost, in global 2D coords.
func lost_segment_rect(f_prev: float, f_new: float) -> Rect2:
	var x0 := FILL_WIDTH * clampf(f_new, 0.0, 1.0)
	var x1 := FILL_WIDTH * clampf(f_prev, 0.0, 1.0)
	var origin := health_fill.global_position + Vector2(x0, 0.0)
	return Rect2(origin, Vector2(maxf(x1 - x0, 1.0), health_fill.size.y))

func fade_and_free() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
