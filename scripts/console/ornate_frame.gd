extends Control
class_name OrnateFrame
## The console's reusable chrome: a carved mossy-stone panel with a gold trace,
## blue gem inlays at the joints, and vine growth over the frame. Every console
## panel puts one of these behind its content rather than a bare
## Panel/ColorRect, so a single script is the one place the chrome's look
## lives - drawn, no image files, matching the codebase's existing
## procedural-glyph convention (coin_glyph.gd, slot_symbol.gd).
##
## [ui-project-longshot] Rewritten from the flat two-line version. The concept
## board's frames are CARVED - they have a lit top edge, a shadowed underside,
## a recessed well with its own reversed bevel, and living overgrowth. The old
## pass drew a flat green rectangle with a hairline gold border, which read as
## a UI widget sitting on top of a picture rather than as an object with the
## picture behind it.
##
## Four things do that work here, in the order the eye picks them up:
##
##   1. TWO bevels, not one. The outer edge is lit from above and shadowed
##      below; the inner well is lit from BELOW and shadowed above. That
##      inversion is the whole trick - it is what says "this face is proud and
##      this one is sunk" rather than "here are two rectangles".
##   2. A gold trace on both, so the carving has a worked metal inlay following
##      it rather than the stone just stopping.
##   3. Gem inlays at the joints, which is where the concept puts its only
##      saturated blue in the whole console.
##   4. Vines. Overgrowth is what makes the frame read as something the forest
##      has been at, and it is the single largest difference between a fantasy
##      frame and a bevelled div.

@export var border: float = 14.0
@export var corner_radius: float = 18.0
@export var diamond_size: float = 16.0
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
## When false, draws only the bevel/trace/joints - no stone face, no inner
## panel fill. For overlaying joints onto a panel that already paints its own
## background (e.g. the slot cabinet, which keeps its existing StyleBoxFlat).
@export var draw_fill: bool = true

## Vine growth over the frame. Off by default: a price plate 40 px tall has no
## room for it, and every frame wearing the same vines reads as a repeated
## texture rather than as growth. Turn it on for the few large panels that
## carry the look - the status plates and the slot cabinet.
@export var vines: bool = false
## How many tendrils per vined edge. Deliberately low - the concept's frames
## are stone that has SOME growth on them, not a trellis.
@export var vine_count: int = 3
## Seed for the vine layout, so two frames side by side do not grow identical
## tendrils. Any distinct int will do; the value itself means nothing.
@export var vine_seed: int = 1

## Carved edges read as carved because the lit and shadowed faces are WIDE
## enough to be faces rather than lines. At 3 px (the old value) the bevel was
## an outline; at 7 it is a chamfer.
const BEVEL := 7.0
const TRACE := 2.5

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var outer := Rect2(Vector2.ZERO, size)

	# 1. The stone face itself.
	if draw_fill:
		_draw_rounded(outer, Tuning.C_CONSOLE_STONE, corner_radius)

	# 2. Outer bevel: lit above, shadowed below (or inverted for a well).
	var lit := Tuning.C_CONSOLE_STONE_DARK if inset_well else Tuning.C_CONSOLE_STONE_LIT
	var shade := Tuning.C_CONSOLE_STONE_LIT if inset_well else Tuning.C_CONSOLE_STONE_DARK
	_bevel(outer, corner_radius, lit, shade, BEVEL)

	# 3. Gold trace following the outer carving.
	_draw_rounded_outline(outer.grow(-BEVEL * 0.5), Tuning.C_GOLD, corner_radius - BEVEL * 0.5, TRACE)

	# 4. The recessed well, with its bevel INVERTED against the outer one -
	# see this file's header for why that inversion is the whole effect.
	if draw_fill:
		var inner := outer.grow(-border)
		if inner.size.x > 0.0 and inner.size.y > 0.0:
			var well_radius := maxf(corner_radius - border * 0.5, 2.0)
			_draw_rounded(inner, Tuning.C_CONSOLE_INSET if inset_well else fill, well_radius)
			_bevel(inner, well_radius, shade, lit, BEVEL * 0.55)
			_draw_rounded_outline(inner, Tuning.C_GOLD_DARK, well_radius, 1.5)

	# 5. Overgrowth, under the joints so a gem always sits on top of a tendril
	# rather than being crossed by one.
	if vines:
		_draw_vines()

	# 6. Gem inlays at the joints.
	_diamond(Vector2(corner_radius, corner_radius))
	_diamond(Vector2(size.x - corner_radius, corner_radius))
	_diamond(Vector2(corner_radius, size.y - corner_radius))
	_diamond(Vector2(size.x - corner_radius, size.y - corner_radius))
	if edge_diamonds:
		_diamond(Vector2(size.x * 0.5, 0.0))
		_diamond(Vector2(size.x * 0.5, size.y))
		_diamond(Vector2(0.0, size.y * 0.5))
		_diamond(Vector2(size.x, size.y * 0.5))

# --- carving -------------------------------------------------------------------

## The lit/shadowed faces of one carved edge. Straight runs only: at these
## panel sizes the rounding on `corner_radius` is subtle enough that a mitred
## corner reads fine, and chasing the arc would cost a polygon per corner for
## a few pixels nobody looks at.
func _bevel(rect: Rect2, radius: float, lit: Color, shade: Color, w: float) -> void:
	var l := rect.position.x
	var t := rect.position.y
	var r := rect.end.x
	var b := rect.end.y
	var inset := radius * 0.7
	# Top and left catch the light; bottom and right fall away from it. Each
	# face is a trapezoid rather than a line so the corners mitre into each
	# other instead of overlapping into a darker square.
	draw_colored_polygon(PackedVector2Array([
		Vector2(l + inset, t), Vector2(r - inset, t),
		Vector2(r - inset - w, t + w), Vector2(l + inset + w, t + w)]), lit)
	draw_colored_polygon(PackedVector2Array([
		Vector2(l, t + inset), Vector2(l + w, t + inset + w),
		Vector2(l + w, b - inset - w), Vector2(l, b - inset)]), lit)
	draw_colored_polygon(PackedVector2Array([
		Vector2(l + inset, b), Vector2(l + inset + w, b - w),
		Vector2(r - inset - w, b - w), Vector2(r - inset, b)]), shade)
	draw_colored_polygon(PackedVector2Array([
		Vector2(r, t + inset), Vector2(r, b - inset),
		Vector2(r - w, b - inset - w), Vector2(r - w, t + inset + w)]), shade)

# --- overgrowth ----------------------------------------------------------------

## Tendrils creeping along the top and bottom edges of the frame.
##
## Laid out from a seeded RNG rather than authored point-by-point, for the same
## reason the field scatter is: a handful of numbers describes "some vines"
## better than a coordinate list does, and every frame in the console can then
## grow its own without a second asset. `vine_seed` is what keeps two adjacent
## panels from growing the identical plant.
##
## Drawn as a chain of shortening segments rather than a real curve: a vine
## tapering to a point is most of what reads as growth, and draw_line's width
## is per-call, so the taper IS the segmentation.
func _draw_vines() -> void:
	var rand := RandomNumberGenerator.new()
	rand.seed = vine_seed * 7919
	for edge: int in [0, 1]:                       # 0 = top, 1 = bottom
		var y := 0.0 if edge == 0 else size.y
		var outward := 1.0 if edge == 0 else -1.0
		for i: int in range(vine_count):
			# Spread the anchors across the span but keep them off the corners,
			# where a gem already sits.
			var t := (float(i) + 0.5) / float(vine_count)
			var x := lerpf(corner_radius * 1.8, size.x - corner_radius * 1.8, t) \
				+ rand.randf_range(-size.x * 0.04, size.x * 0.04)
			_tendril(Vector2(x, y), outward, rand)

func _tendril(start: Vector2, outward: float, rand: RandomNumberGenerator) -> void:
	var dir := Vector2(rand.randf_range(-1.0, 1.0), 0.0).normalized()
	if is_zero_approx(dir.x):
		dir = Vector2(1.0, 0.0)
	# Clamped rather than a straight fraction of the width: at size.x * 0.10 a
	# 360-wide status plate grew 36 px stubs while the 1032-wide cabinet grew
	# 100 px runners, so the two panels did not look like the same forest had
	# reached them.
	var length: float = clampf(size.x * 0.11, 48.0, 155.0) * rand.randf_range(0.8, 1.25)
	var segments := 7
	var p := start
	var width: float = clampf(border * 0.55, 4.0, 9.0)
	var swing: float = rand.randf_range(0.35, 0.75)
	for i: int in range(segments):
		var f := float(i) / float(segments)
		# The vine hugs the edge, arcing away from it and back - sin() over the
		# tendril's length is what curls it rather than letting it run straight
		# off the frame.
		var step := Vector2(dir.x * length / float(segments),
			outward * sin(f * PI) * swing * width * 2.4)
		var next := p + step
		draw_line(p, next, Tuning.C_VINE_DARK, width)
		draw_line(p + Vector2(0, -outward * width * 0.22), next + Vector2(0, -outward * width * 0.22),
			Tuning.C_VINE, width * 0.55)
		# Leaves alternate sides, and the last two nodes carry a bloom instead -
		# a flower at the tip is where the eye lands, so it goes where the vine
		# is thinnest.
		if i % 2 == 0 and i < segments - 2:
			_leaf(next, dir.x, outward * (1.0 if i % 4 == 0 else -1.0), width * 2.4)
		p = next
		width *= 0.86
	_bloom(p, clampf(border * 0.42, 4.0, 7.5))

func _leaf(at: Vector2, along: float, side: float, r: float) -> void:
	var tip := at + Vector2(along * r * 0.9, side * r)
	var mid := at + Vector2(along * r * 0.15, side * r * 0.5)
	draw_colored_polygon(PackedVector2Array([
		at, mid + Vector2(-along * r * 0.35, 0), tip, mid + Vector2(along * r * 0.35, 0),
	]), Tuning.C_VINE)

func _bloom(at: Vector2, r: float) -> void:
	for i: int in range(5):
		var a := TAU * float(i) / 5.0
		draw_circle(at + Vector2(cos(a), sin(a)) * r * 0.72, r * 0.62, Tuning.C_FLOWER)
	draw_circle(at, r * 0.5, Tuning.C_GOLD_BRIGHT)

# --- primitives ----------------------------------------------------------------

func _draw_rounded(rect: Rect2, color: Color, radius: float) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(maxf(radius, 0.0)))
	box.anti_aliasing = true
	draw_style_box(box, rect)

func _draw_rounded_outline(rect: Rect2, color: Color, radius: float, width: float) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.set_corner_radius_all(int(maxf(radius, 0.0)))
	box.set_border_width_all(int(maxf(width, 1.0)))
	box.border_color = color
	box.anti_aliasing = true
	draw_style_box(box, rect)

## A cut blue gem in a gold setting, centred on `at` and clamped so it never
## draws off the panel edge (an edge-midpoint gem sits ON the border, so half
## of it would otherwise be clipped by the parent's own bounds).
##
## Three layers, because a two-layer diamond reads as a flat rhombus: a gold
## ring, the gem body, and a bright upper-left facet. The facet is what makes
## it a cut stone - it catches the same light the frame's top bevel does, so
## the gem and the carving agree about where the light is.
func _diamond(at: Vector2) -> void:
	var c := at.clamp(Vector2(diamond_size * 0.5, diamond_size * 0.5),
		size - Vector2(diamond_size * 0.5, diamond_size * 0.5))
	draw_colored_polygon(_diamond_poly(c, diamond_size * 0.5), Tuning.C_GOLD)
	draw_colored_polygon(_diamond_poly(c, diamond_size * 0.36), Tuning.C_GEM)
	var r := diamond_size * 0.36
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r * 0.55, -r * 0.42), c, c + Vector2(-r * 0.55, -r * 0.42),
	]), Tuning.C_GEM_BRIGHT)

func _diamond_poly(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0),
	])
