extends Control
## [party-wipe-consequences] The scrolling strip behind one spoils reel. Owns
## the motion; spoils_reel.gd around it owns the caption, the result word and
## the choreography.
##
## Unlike the cabinet's SlotReel this is a ONE-cell window - only the landed
## outcome matters, so there are no scoring rows above and below to show. The
## strip is drawn straight onto this Control (clip_contents keeps the partial
## cells inside the window) rather than as child nodes, because a cell here
## carries nothing an inspector would want to reach.
##
## Not @tool, unlike SlotSymbol: every cell's colour comes from Tuning and every
## strip from RNG, and neither autoload is a @tool script, so an editor-time
## _draw() would be reaching for singletons the editor has not instantiated.

## Stops on the strip the window scrolls over. Long enough to spin for a beat
## before the landed outcome comes into view.
const STRIP_LEN := 18
const SPIN_SPEED := 11.0      # stops per second while free-spinning

@export var tile_style: StyleBox:
	set(value):
		tile_style = value
		queue_redraw()

## The glyph's size as a fraction of the cell's shorter side.
@export_range(0.1, 1.0, 0.01) var glyph_fraction: float = 0.46:
	set(value):
		glyph_fraction = value
		queue_redraw()

## Fractional strip position - integer part is the stop in the window, fraction
## is how far it has scrolled toward the next one.
var position_stops: float = 0.0

var _strip: Array[int] = []
var _target_stop: int = 0
var _spinning: bool = false
var _stopping: bool = false
var _stop_tween: Tween = null

func _ready() -> void:
	_build_strip(Spoils.Outcome.KEEP)
	set_process(false)

func _process(delta: float) -> void:
	if _spinning:
		position_stops -= SPIN_SPEED * delta
		queue_redraw()
	elif _stopping:
		queue_redraw()
	else:
		set_process(false)

func start_spin() -> void:
	if _stop_tween != null and _stop_tween.is_valid():
		_stop_tween.kill()
	_stopping = false
	_spinning = true
	set_process(true)

## Decelerates onto `outcome` with the same overshoot-and-snap the cabinet's
## reels use, so both machines read as the same hardware.
func stop_on(outcome: Spoils.Outcome, duration: float = 0.42) -> Tween:
	_build_strip(outcome)
	_spinning = false
	_stopping = true
	set_process(true)

	# Always approach from below, so the reel never reverses to reach its stop.
	var target := float(_target_stop)
	while target < position_stops + 2.0:
		target += float(_strip.size())

	_stop_tween = create_tween()
	_stop_tween.tween_property(self, "position_stops", target, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_stop_tween.tween_callback(func() -> void:
		position_stops = fposmod(position_stops, float(_strip.size()))
		_stopping = false
		queue_redraw())
	return _stop_tween

## Fills the strip with a random ring of outcomes and plants `landed` on a fresh
## stop, far enough from the edges that the partial cells either side of the
## window always have something to show.
func _build_strip(landed: Spoils.Outcome) -> void:
	_strip.clear()
	for i: int in range(STRIP_LEN):
		_strip.append(Spoils.roll())
	_target_stop = RNG.randi_range(2, STRIP_LEN - 3)
	_strip[_target_stop] = landed

func _draw() -> void:
	if _strip.is_empty():
		return
	var cell_h := size.y
	var base := int(floor(position_stops))
	var frac := position_stops - float(base)
	# One cell either side of the window, so a partial scroll is never a gap.
	for k: int in range(-1, 2):
		var outcome := _strip[posmod(base + k, _strip.size())] as Spoils.Outcome
		var y := float(k) * cell_h - frac * cell_h
		_draw_cell(outcome, Rect2(0.0, y, size.x, cell_h))

func _draw_cell(outcome: Spoils.Outcome, rect: Rect2) -> void:
	if tile_style != null:
		# Inset so consecutive tiles keep a seam between them as they scroll,
		# rather than reading as one unbroken column.
		draw_style_box(tile_style, rect.grow(-4.0))
	var box := minf(rect.size.x, rect.size.y) * glyph_fraction
	var at := rect.position + rect.size * 0.5 - Vector2.ONE * box * 0.5
	_draw_glyph(outcome, at, box)

## Deliberately procedural, not generated art (CLAUDE.md best practice 2): these
## are a handful of strokes each AND they recolour per outcome, which baked
## pixels would not.
func _draw_glyph(outcome: Spoils.Outcome, at: Vector2, box: float) -> void:
	var c := Spoils.color(outcome)
	var w := box * 0.15
	match outcome:
		Spoils.Outcome.LOSE:
			_stroke(at, box, [Vector2(0.16, 0.16), Vector2(0.84, 0.84)], c, w)
			_stroke(at, box, [Vector2(0.84, 0.16), Vector2(0.16, 0.84)], c, w)
		Spoils.Outcome.KEEP:
			_stroke(at, box, [
				Vector2(0.12, 0.52), Vector2(0.40, 0.80), Vector2(0.88, 0.22),
			], c, w)
		Spoils.Outcome.KEEP_HALF:
			var centre := at + Vector2.ONE * box * 0.5
			var r := box * 0.40
			draw_colored_polygon(_half_disc(centre, r), c)
			draw_arc(centre, r, 0.0, TAU, 32, c, w * 0.7, true)
		Spoils.Outcome.DOUBLE:
			_stroke(at, box, [
				Vector2(0.14, 0.50), Vector2(0.50, 0.14), Vector2(0.86, 0.50),
			], c, w)
			_stroke(at, box, [
				Vector2(0.14, 0.86), Vector2(0.50, 0.50), Vector2(0.86, 0.86),
			], c, w)

func _stroke(at: Vector2, box: float, points: Array, c: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for p: Vector2 in points:
		pts.append(at + p * box)
	draw_polyline(pts, c, width, true)

## The bottom half of a disc - "you keep some of it", filling from the floor up.
func _half_disc(centre: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(17):
		var a := PI * float(i) / 16.0
		pts.append(centre + Vector2(cos(a), sin(a)) * r)
	return pts
