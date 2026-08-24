@tool
class_name SlotSymbol
extends Control
## One reel cell. Draws an icon texture centred in a square that's a fixed
## fraction of the cell's shorter side, so the reels can be resized without a
## second set of hand-tuned numbers.
##
## @tool so this redraws live in the editor - see scenes/console/
## reel_layout_playground.tscn, a sandbox for eyeballing reel layout changes
## without needing Play mode.

## How much of the cell's shorter side the glyph fills.
##
## [ui-project-longshot] Raised from 0.66 and ICON_ZOOM retired for the drawn
## symbols. The zoom existed because the imported PNGs carried a lot of empty
## margin, so the icon had to be blown up past its own box to read - which is
## also why symbols were overlapping the payline and their neighbours. A
## polygon has no baked margin, so one honest fraction now covers it.
@export_range(0.1, 1.0, 0.01) var box_fraction: float = 0.78:
	set(value):
		box_fraction = value
		queue_redraw()

const TEX_GOLD := preload("res://assets/icons/slot_gold.png")

## The coin keeps its texture: slot_gold.png reads correctly against the board
## and is the one imported icon this pass did not need to replace. The other
## two are drawn - see _draw_gem().
##
## Its old 1.75 zoom went with it and is now 1.0. That multiplier existed to
## fight a much SHORTER reel cell (the console's old proportions gave the
## cabinet ~77 px rows); against the current 121 px cells it drew a 165 px coin
## into a 121 px cell, so the coin overhung its neighbours and crossed the
## payline. Whatever else changes, this must stay at or under 1 / box_fraction.
const GOLD_ZOOM := 1.0

# PackedVector2Array literals are not constant expressions in GDScript, so these
# glyph outlines are static vars. No longer drawn by this cell itself (see
# _draw() below) but still shared, unmutated, by other UI glyphs that echo the
# reel's iconography: coin_glyph.gd (STAR), status_icon.gd/class_icon_glyph.gd
# (PLUS), bonus_strip.gd/upgrade_button.gd (BOLT, STAR).
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

## [ui-project-longshot] The bolt and the cross are drawn, not textured.
##
## The imported PNGs they replace were neon-sign artwork - a violet bolt inside
## a rune circle, and a green HEART - and the concept board wants neither: its
## symbols are chunky cut gems with an ink outline, and its heal glyph is a
## CROSS. Drawing them also puts their colour under Tuning, so the reel's bolt
## and the party bar's blue are guaranteed to be the same blue instead of one
## being whatever hue was baked into a file.
func _draw() -> void:
	var c := size * 0.5
	match symbol:
		Tuning.Sym.GOLD:
			var box := minf(size.x, size.y) * box_fraction * GOLD_ZOOM
			draw_texture_rect(TEX_GOLD,
				Rect2(c - Vector2.ONE * box * 0.5, Vector2.ONE * box), false)
		Tuning.Sym.LIGHTNING:
			_draw_gem(BOLT, Tuning.C_LIGHTNING, Tuning.C_ARCANE_BRIGHT)
		Tuning.Sym.PLUS:
			_draw_gem(PLUS, Tuning.C_HEAL, Color("C8F5A8"))
		# BLANK falls through: an empty space, the recessed reel window shows through

## One symbol as a cut gem: outer glow, body, lit facet, ink outline.
##
## The facet is the half that matters. A flat polygon in one colour reads as a
## sticker no matter how much glow is piled around it; shrinking the same
## outline toward its own centroid and lifting it gives a second, brighter face
## whose edge follows the silhouette - which is what a cut stone looks like,
## and it costs one extra polygon.
##
## The glow is stacked polylines rather than a shader because every other glyph
## in this console is drawn the same way (coin_glyph, ornate_frame,
## bonus_strip), and one blur shader for one symbol would be the only thing in
## the file needing a material.
func _draw_gem(shape: PackedVector2Array, body: Color, bright: Color) -> void:
	var box := minf(size.x, size.y) * box_fraction
	var origin := size * 0.5 - Vector2.ONE * box * 0.5
	var pts := PackedVector2Array()
	var centroid := Vector2.ZERO
	for p: Vector2 in shape:
		var mapped := origin + p * box
		pts.append(mapped)
		centroid += mapped
	centroid /= float(pts.size())

	var closed := pts.duplicate()
	closed.append(pts[0])

	# Glow: widest and faintest first, so the passes build up toward the edge.
	for i: int in range(3):
		var t := float(i) / 2.0
		draw_polyline(closed, Color(bright.r, bright.g, bright.b, lerpf(0.09, 0.34, t)),
			box * lerpf(0.16, 0.045, t))

	draw_colored_polygon(pts, body)

	# The lit facet, pulled toward the centroid and lifted a little - the light
	# in this console comes from above, the same direction OrnateFrame bevels.
	var facet := PackedVector2Array()
	for p: Vector2 in pts:
		facet.append(p.lerp(centroid, 0.34) - Vector2(0.0, box * 0.055))
	draw_colored_polygon(facet, Color(bright.r, bright.g, bright.b, 0.72))

	draw_polyline(closed, Tuning.C_INK, maxf(box * 0.035, 2.0))

static func label_for(sym: int) -> String:
	match sym:
		Tuning.Sym.LIGHTNING: return "LIGHTNING"
		Tuning.Sym.GOLD: return "GOLD"
		Tuning.Sym.PLUS: return "HEAL"
		_: return "BLANK"

static func result_text(sym: int, count: int) -> String:
	match sym:
		Tuning.Sym.LIGHTNING:
			if count >= 3:
				return "More Lightning"
			else:
				return "Lightning"
		Tuning.Sym.GOLD:
			if count >= 3:
				return "More Gold"
			else:
				return "Gold"
		Tuning.Sym.PLUS:
			if count >= 3:
				return "Heal All"
			else:
				return "Heal One"
		_: return "BLANK"
