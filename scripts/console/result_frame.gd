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

## [black-glass] Set by SlotMachine.apply_boss_theme()/clear_boss_theme().
@export var boss_active: bool = false:
	set(v):
		boss_active = v
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# [rootwood-canopy] Rootwood brown, matching the cabinet face - not the reel
	# windows' canopy green, which would fight the win text sitting on top of it.
	# [black-glass] Obsidian instead, matching the cabinet's own boss-fight face.
	# Read directly (not a script-level const) - a Tuning colour is not a
	# constant expression to the compiler, only reachable from a function body.
	var fill: Color = Tuning.C_OBSIDIAN if boss_active else Tuning.C_ROOTWOOD
	var line_col: Color = Tuning.C_SEAM if boss_active else Tuning.C_GOLD_DARK
	draw_rect(Rect2(Vector2.ZERO, size), fill)
	draw_line(Vector2(0.0, 0.0), Vector2(size.x, 0.0), line_col, LINE_WIDTH)
	draw_line(Vector2(0.0, size.y), Vector2(size.x, size.y), line_col, LINE_WIDTH)
