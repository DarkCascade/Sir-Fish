extends Control
## The gold coin (presentation redesign S6.1): a gold disc, a darker inner
## ring, and the slot's own star mark at the centre - reusing SlotSymbol.STAR
## rather than a second star shape, since the concept's coin and its star
## reel symbol read as the same mark on purpose.

@export var radius: float = 18.0

func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, radius, Tuning.C_GOLD)
	draw_arc(c, radius, 0.0, TAU, 32, Tuning.C_GOLD_DARK, radius * 0.16)
	draw_circle(c, radius * 0.68, Tuning.C_GOLD_DARK)
	draw_arc(c, radius * 0.68, 0.0, TAU, 32, Tuning.C_GOLD, radius * 0.08)
	var star := PackedVector2Array()
	for p: Vector2 in SlotSymbol.STAR:
		star.append(c + (p - Vector2(0.5, 0.5)) * radius * 1.15)
	draw_colored_polygon(star, Tuning.C_GOLD_BRIGHT)
