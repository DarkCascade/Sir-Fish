class_name SlotSymbol
extends Control
## One reel cell, drawn entirely in _draw() - no image files (spec 16.7).
## Cell is 240 x 160; the glyph is drawn inside a centred 140 x 140 box.

const BOX := 140.0

# PackedVector2Array literals are not constant expressions in GDScript, so the
# glyph outlines are static vars. They are still shared, never mutated.
static var BOLT := PackedVector2Array([
	Vector2(0.55, 0.05), Vector2(0.22, 0.55), Vector2(0.45, 0.55),
	Vector2(0.30, 0.95), Vector2(0.78, 0.42), Vector2(0.52, 0.42),
	Vector2(0.72, 0.05),
])

static var PLUS := PackedVector2Array([
	Vector2(0.37, 0.10), Vector2(0.63, 0.10), Vector2(0.63, 0.37),
	Vector2(0.90, 0.37), Vector2(0.90, 0.63), Vector2(0.63, 0.63),
	Vector2(0.63, 0.90), Vector2(0.37, 0.90), Vector2(0.37, 0.63),
	Vector2(0.10, 0.63), Vector2(0.10, 0.37), Vector2(0.37, 0.37),
])

static var STAR := PackedVector2Array([
	Vector2(0.50, 0.30), Vector2(0.56, 0.44), Vector2(0.71, 0.45),
	Vector2(0.59, 0.54), Vector2(0.64, 0.69), Vector2(0.50, 0.60),
	Vector2(0.36, 0.69), Vector2(0.41, 0.54), Vector2(0.29, 0.45),
	Vector2(0.44, 0.44),
])

@export var symbol: int = Tuning.Sym.BLANK

func set_symbol(value: int) -> void:
	if symbol == value:
		return
	symbol = value
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	match symbol:
		Tuning.Sym.LIGHTNING:
			# A blue stylised bolt with a gold outline (source doc).
			draw_colored_polygon(_map(BOLT, c), Tuning.C_LIGHTNING)
			draw_polyline(_closed(_map(BOLT, c)), Tuning.C_GOLD, 7.0, true)
		Tuning.Sym.GOLD:
			draw_circle(c, 0.42 * BOX, Tuning.C_GOLD)
			draw_arc(c, 0.42 * BOX, 0.0, TAU, 48, Tuning.C_INK, 6.0)
			draw_circle(c, 0.30 * BOX, Color("FFDD66"))
			draw_arc(c, 0.30 * BOX, 0.0, TAU, 48, Color("B8860B"), 4.0)
			draw_colored_polygon(_map(STAR, c), Color("B8860B"))
		Tuning.Sym.PLUS:
			# A green plus sign with a black outline (source doc).
			draw_colored_polygon(_map(PLUS, c), Tuning.C_HEAL)
			draw_polyline(_closed(_map(PLUS, c)), Color.BLACK, 6.0, true)
		_:
			pass    # BLANK: an empty space; the recessed reel window shows through

static func _map(points: PackedVector2Array, center: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(center + (p - Vector2(0.5, 0.5)) * BOX)
	return out

static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(points)
	if out.size() > 0:
		out.append(out[0])
	return out

static func label_for(sym: int) -> String:
	match sym:
		Tuning.Sym.LIGHTNING: return "LIGHTNING"
		Tuning.Sym.GOLD: return "GOLD"
		Tuning.Sym.PLUS: return "HEAL"
		_: return "BLANK"
