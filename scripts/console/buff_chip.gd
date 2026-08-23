extends Control
## Small buff indicator on a hero's battle bars (spec 11 / 17.2): a blue shield
## while the warrior is defending. Sized by whoever places it - the glyph is
## drawn as a fraction of `size`, not at a fixed pixel scale.

# PackedVector2Array literals are not constant expressions in GDScript.
static var SHIELD := PackedVector2Array([
	Vector2(0.5, 0.10), Vector2(0.84, 0.26), Vector2(0.84, 0.56),
	Vector2(0.5, 0.90), Vector2(0.16, 0.56), Vector2(0.16, 0.26),
])

@export var kind: String = "shield"

func _ready() -> void:
	resized.connect(queue_redraw)

func set_kind(value: String) -> void:
	kind = value
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Tuning.C_DEFEND, true)
	draw_rect(Rect2(Vector2.ZERO, size), Tuning.C_INK, false, 2.0)
	var pts := PackedVector2Array()
	for p: Vector2 in SHIELD:
		pts.append(p * size * 0.82 + size * 0.09)
	draw_colored_polygon(pts, Tuning.C_TEXT)
