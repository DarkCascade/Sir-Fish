class_name ClassIconGlyph
extends Control
## Class glyph drawn over a hero's icon tile in the party bars (reskin to
## match the referenced fantasy UI kit): a cross for the mage, a bow for
## the ranger, a shield for the warrior.
##
## [meshy-experiment] Was procedurally drawn (a cross/bow/shield built from
## polygons and arcs, matching slot_symbol.gd's approach) - now flat
## Meshy-generated icons instead, in the same cream-on-near-black style as
## the shop's item glyphs and the console's bonus strip. The mage's icon is
## the identical heal-cross art the bonus strip uses for slot_mend: the two
## already meant the same thing (healing) and drawing it from two unrelated
## hand-authored shapes was two things that could drift, not two features.

const TEX_HEAL := preload("res://assets/icons/glyph_heal.png")
const TEX_BOW := preload("res://assets/icons/glyph_bow.png")
const TEX_SHIELD := preload("res://assets/icons/glyph_shield.png")

@export var kind: StringName = &""

func set_kind(value: StringName) -> void:
	kind = value
	queue_redraw()

func _draw() -> void:
	match kind:
		&"mage":
			_draw_texture(TEX_HEAL, 0.66)
		&"ranger":
			_draw_texture(TEX_BOW, 0.78)
		&"warrior":
			_draw_texture(TEX_SHIELD, 0.72)
		_:
			pass

func _draw_texture(tex: Texture2D, box_fraction: float) -> void:
	var box := minf(size.x, size.y) * box_fraction
	var c := size * 0.5
	draw_texture_rect(tex, Rect2(c - Vector2.ONE * box * 0.5, Vector2.ONE * box), false)
