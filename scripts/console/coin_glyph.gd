extends Control
## The gold coin from spec 16.7, reused wherever a gold amount is shown
## (status panel, shop prices, sell buttons). Drawn, never an image file.

@export var radius: float = 18.0

func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, radius, Tuning.C_GOLD)
	draw_arc(c, radius, 0.0, TAU, 32, Tuning.C_INK, radius * 0.14)
	draw_circle(c, radius * 0.71, Color("FFDD66"))
	draw_arc(c, radius * 0.71, 0.0, TAU, 32, Color("B8860B"), radius * 0.10)
	var star := PackedVector2Array()
	for p: Vector2 in SlotSymbol.STAR:
		star.append(c + (p - Vector2(0.5, 0.5)) * radius * 2.4)
	draw_colored_polygon(star, Color("B8860B"))
