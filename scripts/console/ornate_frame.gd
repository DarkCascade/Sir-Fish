extends Control
class_name OrnateFrame
## The console's reusable chrome (presentation redesign S5): a beveled stone
## panel with a gold trace and diamond joints at the corners and edge
## midpoints. Every console panel puts one of these behind its content rather
## than a bare Panel/ColorRect, so a single script is the one place the
## chrome's look lives - drawn, no image files, matching the codebase's
## existing procedural-glyph convention (coin_glyph.gd, slot_symbol.gd).
##
## Pass A only (no vine art yet - see S5.4 in the redesign spec): this covers
## the beveled stone, the gold trace and the diamond joints, which is most of
## the concept's frame language on its own.

@export var border: float = 14.0
@export var corner_radius: float = 18.0
@export var diamond_size: float = 22.0
## Leave false on any panel shorter than roughly 4x diamond_size (a title
## banner, a price plate) - _diamond()'s clamp pulls the top-mid and
## bottom-mid diamonds in from the edge on a short panel, and on one short
## enough they clamp to nearly the same point, reading as a cluster of
## diamonds punched through the centre of whatever the panel holds. Corners
## alone (false) always read cleanly regardless of panel size.
@export var edge_diamonds: bool = true
## Inverts the bevel (dark top/left, bright bottom/right) and fills with
## C_CONSOLE_INSET instead of `fill`, so a reel window or a price plate reads
## as carved INTO the cabinet rather than sitting proud of it.
@export var inset_well: bool = false
@export var fill: Color = Tuning.C_CONSOLE_PANEL
## When false, draws only the bevel/trace/diamonds - no stone face, no inner
## panel fill. For overlaying joints onto a panel that already paints its own
## background (e.g. the slot cabinet, which keeps its existing StyleBoxFlat).
@export var draw_fill: bool = true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var outer := Rect2(Vector2.ZERO, size)
	var panel_fill := Tuning.C_CONSOLE_INSET if inset_well else fill
	var bright := Tuning.C_GOLD_DARK if inset_well else Tuning.C_GOLD_BRIGHT
	var dark := Tuning.C_GOLD_BRIGHT if inset_well else Tuning.C_GOLD_DARK

	# 1. Outer stone face.
	if draw_fill:
		_draw_rounded(outer, Tuning.C_CONSOLE_STONE, corner_radius)

	# 2. Two-tone bevel: straight edges only (the rounding on `corner_radius`
	# at this panel scale is subtle enough that a mitred corner reads fine).
	var w := 3.0
	draw_line(Vector2(corner_radius, w * 0.5), Vector2(size.x - corner_radius, w * 0.5), bright, w)
	draw_line(Vector2(w * 0.5, corner_radius), Vector2(w * 0.5, size.y - corner_radius), bright, w)
	draw_line(Vector2(corner_radius, size.y - w * 0.5), Vector2(size.x - corner_radius, size.y - w * 0.5), dark, w)
	draw_line(Vector2(size.x - w * 0.5, corner_radius), Vector2(size.x - w * 0.5, size.y - corner_radius), dark, w)

	# 3. Gold trace around the full outer edge.
	_draw_rounded_outline(outer, Tuning.C_GOLD, corner_radius, 2.0)

	# 4. Inner panel fill.
	if draw_fill:
		var inner := outer.grow(-border)
		if inner.size.x > 0.0 and inner.size.y > 0.0:
			_draw_rounded(inner, panel_fill, maxf(corner_radius - border * 0.5, 2.0))

	# 5. Diamond joints.
	_diamond(Vector2(corner_radius, corner_radius))
	_diamond(Vector2(size.x - corner_radius, corner_radius))
	_diamond(Vector2(corner_radius, size.y - corner_radius))
	_diamond(Vector2(size.x - corner_radius, size.y - corner_radius))
	if edge_diamonds:
		_diamond(Vector2(size.x * 0.5, 0.0))
		_diamond(Vector2(size.x * 0.5, size.y))
		_diamond(Vector2(0.0, size.y * 0.5))
		_diamond(Vector2(size.x, size.y * 0.5))

func _draw_rounded(rect: Rect2, color: Color, radius: float) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(radius))
	box.anti_aliasing = true
	draw_style_box(box, rect)

func _draw_rounded_outline(rect: Rect2, color: Color, radius: float, width: float) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.set_corner_radius_all(int(radius))
	box.set_border_width_all(int(width))
	box.border_color = color
	box.anti_aliasing = true
	draw_style_box(box, rect)

## A small diamond ringed in gold, centred on `at` and clamped so it never
## draws off the panel edge (an edge-midpoint diamond sits ON the border, so
## half of it would otherwise be clipped by the parent's own bounds).
func _diamond(at: Vector2) -> void:
	var c := at.clamp(Vector2(diamond_size * 0.5, diamond_size * 0.5),
		size - Vector2(diamond_size * 0.5, diamond_size * 0.5))
	var ring := _diamond_poly(c, diamond_size * 0.5)
	var core := _diamond_poly(c, diamond_size * 0.34)
	draw_colored_polygon(ring, Tuning.C_GOLD)
	draw_colored_polygon(core, Tuning.C_ARCANE)

func _diamond_poly(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0),
	])
