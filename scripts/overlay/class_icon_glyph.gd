class_name ClassIconGlyph
extends Control
## Class glyph drawn over a hero's icon tile in the party bars (reskin to
## match the referenced fantasy UI kit): a cross for the priest, a bow for
## the ranger, a shield for the warrior. Procedurally drawn - no image files,
## same approach as status_icon.gd and slot_symbol.gd.

# PackedVector2Array literals are not constant expressions in GDScript.
static var SHIELD := PackedVector2Array([
	Vector2(0.5, 0.08), Vector2(0.86, 0.24), Vector2(0.86, 0.56),
	Vector2(0.5, 0.92), Vector2(0.14, 0.56), Vector2(0.14, 0.24),
])

@export var kind: StringName = &""

func set_kind(value: StringName) -> void:
	kind = value
	queue_redraw()

## A dark ink stroke around every glyph (matching SlotSymbol's fill + black
## outline) so the cream glyph color still reads against a light background -
## the ranger's tan/gold tile is close enough in value to Tuning.C_TEXT that
## an unstroked bow nearly vanished into it.
const OUTLINE_WIDTH_FRACTION := 0.08

func _draw() -> void:
	match kind:
		&"priest":
			_draw_polygon(SlotSymbol.PLUS, 0.62)
		&"ranger":
			_draw_bow()
		&"warrior":
			_draw_polygon(SHIELD, 0.66)
		_:
			pass

func _draw_polygon(points: PackedVector2Array, box_fraction: float) -> void:
	var box := minf(size.x, size.y)
	var poly := _scaled(points, size * 0.5, box * box_fraction)
	draw_colored_polygon(poly, Tuning.C_TEXT)
	draw_polyline(_closed(poly), Tuning.C_INK, box * OUTLINE_WIDTH_FRACTION, true)

## Bow limb as an arc, string and nocked arrow as lines, arrowhead as a small
## triangle - a filled-polygon glyph can't self-overlap the way a bow does.
## Each stroke is drawn twice, a wider ink pass under a narrower cream one, to
## get the same outlined look as the polygon glyphs.
func _draw_bow() -> void:
	var c := size * 0.5
	var box := minf(size.x, size.y)
	var radius := box * 0.38
	var start := deg_to_rad(110.0)
	var end := deg_to_rad(250.0)
	var top := c + Vector2(cos(start), sin(start)) * radius
	var bottom := c + Vector2(cos(end), sin(end)) * radius
	var tip := c + Vector2(box * 0.42, 0.0)
	var nock := c - Vector2(box * 0.30, 0.0)
	var wide := box * 0.13
	var thin := box * 0.07

	draw_arc(c, radius, start, end, 24, Tuning.C_INK, wide, true)
	draw_line(top, bottom, Tuning.C_INK, wide, true)
	draw_line(nock, tip, Tuning.C_INK, wide, true)
	draw_arc(c, radius, start, end, 24, Tuning.C_TEXT, thin, true)
	draw_line(top, bottom, Tuning.C_TEXT, thin, true)
	draw_line(nock, tip, Tuning.C_TEXT, thin, true)

	var head := PackedVector2Array([
		tip, tip + Vector2(-box * 0.16, -box * 0.12), tip + Vector2(-box * 0.16, box * 0.12),
	])
	draw_colored_polygon(head, Tuning.C_TEXT)
	draw_polyline(_closed(head), Tuning.C_INK, box * OUTLINE_WIDTH_FRACTION, true)

static func _scaled(points: PackedVector2Array, center: Vector2, box: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(center + (p - Vector2(0.5, 0.5)) * box)
	return out

static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(points)
	if out.size() > 0:
		out.append(out[0])
	return out
