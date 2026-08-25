extends Control
class_name ReelGrid
## [ui-project-longshot] The gold lattice over the reel window: two verticals
## dividing it into the concept board's three reel columns.
##
## The old cabinet separated its reels with 20 px of cabinet-coloured GAP
## between three free-floating windows, which reads as three narrow slots side
## by side. The board's reel window is one continuous pane of dark glass with
## thin gold cames laid over it, like a leaded window - the columns are defined
## by the lines, not by the space between them. That is a different object, and
## it is most of why the board's cabinet reads as a made thing rather than as
## three rectangles.
##
## This used to also draw two horizontal dividers marking the middle (payline)
## row, but those have moved to result_frame.gd, which reuses them as the top
## and bottom rule of the win-result banner instead of a row divider that was
## visible even when nothing had won (spec 16.4 result framing).
##
## Drawn over the reel windows and under the payline (see slot_machine.tscn's
## child order), so a spinning symbol passes BEHIND the lattice.

## Divider weight. Deliberately hairline - these are inlaid cames catching the
## light, not structural bars; at more than about 3 px they start competing
## with the payline, which has to stay the brightest line in the cabinet.
@export var line_width: float = 2.0
## The lattice fades out toward the top and bottom edges of the window, so the
## verticals do not end in two hard stubs against the cabinet's inner bevel.
@export var fade_edges: bool = true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	for i: int in range(1, 3):
		var x := size.x * float(i) / 3.0
		if fade_edges:
			_faded_line(Vector2(x, 0.0), Vector2(x, size.y))
		else:
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), Tuning.C_GOLD_DARK, line_width)

## One vertical came drawn as a short stack of segments whose alpha rises to
## the middle - draw_line takes a single colour, so a gradient along a line has
## to be segmented. Six segments is enough that the steps are invisible at this
## width and cheap enough not to matter.
func _faded_line(from: Vector2, to: Vector2) -> void:
	var steps := 6
	for i: int in range(steps):
		var a := from.lerp(to, float(i) / float(steps))
		var b := from.lerp(to, float(i + 1) / float(steps))
		var mid := (float(i) + 0.5) / float(steps)
		var alpha := sin(mid * PI)          # 0 at both ends, 1 in the middle
		draw_line(a, b, Color(Tuning.C_GOLD_DARK, alpha), line_width)
