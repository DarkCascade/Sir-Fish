class_name ClassIconGlyph
extends Control
## Class glyph drawn over a hero's icon tile in the party bars (reskin to
## match the referenced fantasy UI kit): a cross for the mage, a bow for
## the ranger, a shield for the warrior.
##
## [meshy-experiment] Was procedurally drawn (a cross/bow/shield built from
## polygons and arcs, matching slot_symbol.gd's approach) - then flat
## Meshy-generated icons keyed by a hardcoded per-class match.
##
## [content phase 1] The per-class texture/box-fraction match is gone - both
## now come from data (ClassDef.glyph / glyph_box_fraction, spec §3 Step 2),
## set directly via set_texture_data() rather than looked up here from a
## class id string.

var _texture: Texture2D = null
var _box_fraction: float = 0.7

func set_texture_data(tex: Texture2D, box_fraction: float = 0.7) -> void:
	_texture = tex
	_box_fraction = box_fraction
	queue_redraw()

func _draw() -> void:
	if _texture == null:
		return
	var box := minf(size.x, size.y) * _box_fraction
	var c := size * 0.5
	draw_texture_rect(_texture, Rect2(c - Vector2.ONE * box * 0.5, Vector2.ONE * box), false)
