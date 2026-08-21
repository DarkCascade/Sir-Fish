extends Control
## 44x44 buff indicator on a hero status row (spec 17.2): a blue shield while
## the warrior is defending, a gold arrow-up while the party damage buff runs.

# PackedVector2Array literals are not constant expressions in GDScript.
static var SHIELD := PackedVector2Array([
	Vector2(0.5, 0.10), Vector2(0.84, 0.26), Vector2(0.84, 0.56),
	Vector2(0.5, 0.90), Vector2(0.16, 0.56), Vector2(0.16, 0.26),
])

static var ARROW_UP := PackedVector2Array([
	Vector2(0.5, 0.10), Vector2(0.86, 0.48), Vector2(0.64, 0.48),
	Vector2(0.64, 0.90), Vector2(0.36, 0.90), Vector2(0.36, 0.48),
	Vector2(0.14, 0.48),
])

@export var kind: String = "shield"

func set_kind(value: String) -> void:
	kind = value
	queue_redraw()

func _draw() -> void:
	var bg := Tuning.C_DEFEND if kind == "shield" else Tuning.C_CONSOLE_BG
	var glyph := Tuning.C_TEXT if kind == "shield" else Tuning.C_GOLD
	var shape := SHIELD if kind == "shield" else ARROW_UP
	draw_rect(Rect2(Vector2.ZERO, size), bg, true)
	draw_rect(Rect2(Vector2.ZERO, size), Tuning.C_INK, false, 3.0)
	var pts := PackedVector2Array()
	for p: Vector2 in shape:
		pts.append(p * size * 0.82 + size * 0.09)
	draw_colored_polygon(pts, glyph)
