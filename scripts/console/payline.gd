extends Control
class_name Payline
## [ui-project-longshot] The winning line across the reel window: a glowing
## gold rule with four-point sparkles punctuating it.
##
## Replaces a 4 px ColorRect and two rotated-square "arrow" ColorRects. That
## version could only ever be a flat bar - it had no glow, and its end markers
## were squares standing on a corner, which read as diamonds rather than as
## light. On the concept board this is the single brightest element in the
## whole console and the thing that says WHERE the payout happens; a flat bar
## cannot carry that job while a bevelled gold frame surrounds it.
##
## Sparkles sit at both ends AND on the two cell boundaries, so the line is
## visibly tied to the lattice underneath it (reel_grid.gd) rather than laid
## across it at an unrelated rhythm.

## The line's colour. Named rather than reusing ColorRect's `color`, because
## this is a Control and the two would silently mean different things to
## whoever next reads slot_machine.gd's tweens.
@export var glow_color: Color = Tuning.C_GOLD_BRIGHT:
	set(value):
		glow_color = value
		queue_redraw()

@export var line_width: float = 4.0
@export var sparkle_size: float = 22.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 0.0:
		return
	var y := size.y * 0.5
	var a := Vector2(0.0, y)
	var b := Vector2(size.x, y)

	# Three passes: a wide dim halo, a mid glow, then the hot core. Stacking
	# translucent lines is how every other glyph in this console fakes a bloom
	# (see slot_symbol.gd's _draw_gem) - one blur shader for one line would be
	# the only material in the file.
	draw_line(a, b, Color(glow_color, 0.12), line_width * 5.0)
	draw_line(a, b, Color(glow_color, 0.28), line_width * 2.4)
	draw_line(a, b, glow_color, line_width)

	# Ends, plus the two cell boundaries the lattice already marks.
	for i: int in range(4):
		_sparkle(Vector2(size.x * float(i) / 3.0, y))

## A four-point star: two crossed slivers plus a bright core. Drawn as
## polygons rather than lines so the points actually taper - a star made of
## strokes has blunt ends and reads as a plus sign.
func _sparkle(at: Vector2) -> void:
	var r := sparkle_size * 0.5
	var w := sparkle_size * 0.11
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0, -r), at + Vector2(w, 0), at + Vector2(0, r), at + Vector2(-w, 0),
	]), glow_color)
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(-r, 0), at + Vector2(0, -w), at + Vector2(r, 0), at + Vector2(0, w),
	]), glow_color)
	draw_circle(at, w * 1.5, Color(1.0, 1.0, 1.0, 0.9))
