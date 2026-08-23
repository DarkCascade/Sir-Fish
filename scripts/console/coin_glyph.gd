@tool
extends Control
## The gold coin (presentation redesign S6.1). Draws the same coin texture as
## the slot reel's gold symbol (SlotSymbol.TEX_GOLD), so every "gold" glyph in
## the UI - status bar, upgrade button price plate, slot reel - reads as the
## same icon rather than three different drawings of a coin.

@export var radius: float = 18.0

func _draw() -> void:
	var c := size * 0.5
	var box := radius * 2.0
	draw_texture_rect(SlotSymbol.TEX_GOLD, Rect2(c - Vector2.ONE * box * 0.5, Vector2.ONE * box), false)
