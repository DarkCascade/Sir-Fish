extends Control
class_name ResultFrame
## [ui-project-longshot] Frames the win-result banner ("Heal One", "Lightning",
## etc.) between two thin gold rules and blacks out the band between them, so
## the result reads as a dedicated ticker rather than text floating over the
## spinning reels.
##
## The two rules are the middle row's dividers that reel_grid.gd used to draw
## unconditionally (see that file). Moving them here means they only appear
## while there is a result to frame - slot_machine.gd sizes and positions this
## control to match that row exactly, then fades it in and out alongside the
## Banner label in _celebrate() (spec 16.4).

const LINE_WIDTH := 2.0
const FILL := Color(Tuning.C_CONSOLE_INSET)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), FILL)
	draw_line(Vector2(0.0, 0.0), Vector2(size.x, 0.0), Tuning.C_GOLD_DARK, LINE_WIDTH)
	draw_line(Vector2(0.0, size.y), Vector2(size.x, size.y), Tuning.C_GOLD_DARK, LINE_WIDTH)
