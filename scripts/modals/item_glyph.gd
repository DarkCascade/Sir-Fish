@tool
extends Control
## A procedural medallion icon for a shop item (Buy tab juice pass): a rarity-
## ringed disc with a bold silhouette naming the weapon type inside it. Items
## carry no icon texture (Item is text-only - see item.gd), so this reads
## weapon_type/kind directly rather than waiting on art that does not exist.
##
## One _draw() rather than a stack of child Controls: the glow, disc, ring and
## glyph all share the same centre and radius math, and a single canvas_item
## draw call is cheap enough to run once per card with no pooling concerns
## (SHOP_ITEMS_FOR_SALE = 3).

@export var weapon_type: StringName = &"":
	set(v):
		weapon_type = v
		queue_redraw()
@export var kind: int = 0:  # Item.Kind, avoided as a dependency so this stays a leaf script
	set(v):
		kind = v
		queue_redraw()
@export var ring_color: Color = Color.WHITE:
	set(v):
		ring_color = v
		queue_redraw()

const C_DISC := Color(0.043137, 0.117647, 0.109804, 1)   # matches compare_flyout's "well"
const C_GLYPH := Color(0.94902, 0.913725, 0.815686, 1)    # C_TEXT

## [meshy-experiment] Meshy-generated flat icons, one per item type
## (res://assets/icons/weapon_*.png) - square images with their own dark teal
## backdrop, so they are inset only as far as the disc's INSCRIBED square (see
## _draw()): sized so their corners just touch the disc's circle rather than
## poke past it. Potions/relics have no generated art yet and fall back to
## the procedural vector shapes below.
##
## [town] spec 12.1 (step 11): the six armor / trinket types join the five
## weapons here - same style pass, same matte-clay-on-teal treatment - so a full
## Equipped section reads as icons rather than the generic gem fallback.
const WEAPON_TEXTURES := {
	&"sword": preload("res://assets/icons/weapon_sword.png"),
	&"axe": preload("res://assets/icons/weapon_axe.png"),
	&"bow": preload("res://assets/icons/weapon_bow.png"),
	&"dagger": preload("res://assets/icons/weapon_dagger.png"),
	&"staff": preload("res://assets/icons/weapon_staff.png"),
	&"helm": preload("res://assets/icons/weapon_helm.png"),
	&"mail": preload("res://assets/icons/weapon_mail.png"),
	&"shield": preload("res://assets/icons/weapon_shield.png"),
	&"ring": preload("res://assets/icons/weapon_ring.png"),
	&"amulet": preload("res://assets/icons/weapon_amulet.png"),
	&"idol": preload("res://assets/icons/weapon_idol.png"),
}

func _draw() -> void:
	var c := size * 0.5
	var r: float = minf(size.x, size.y) * 0.5

	# Soft outer glow: a few widening, fading rings rather than a real blur.
	for i: int in range(3, 0, -1):
		draw_circle(c, r * (1.0 + 0.16 * i), Color(ring_color.r, ring_color.g, ring_color.b, 0.05 * i))

	draw_circle(c, r * 0.94, C_DISC)

	if WEAPON_TEXTURES.has(weapon_type):
		# Half-side of the square inscribed in the disc circle (radius * 0.94),
		# so the image's corners land exactly on the circle instead of
		# overhanging it - the ring drawn afterward covers any rounding slop.
		var half: float = r * 0.94 * 0.7071
		draw_texture_rect(WEAPON_TEXTURES[weapon_type], Rect2(c - Vector2.ONE * half, Vector2.ONE * half * 2.0), false)
	else:
		var g: float = r * 0.62   # glyph half-extent
		match weapon_type:
			&"sword":
				_draw_blade(c, g, 1.0)
			&"dagger":
				_draw_blade(c, g, 0.62)
			&"axe":
				_draw_axe(c, g)
			&"bow":
				_draw_bow(c, g)
			&"staff":
				_draw_staff(c, g)
			_:
				_draw_gem(c, g)

	draw_arc(c, r * 0.94, 0.0, TAU, 40, ring_color, r * 0.09, true)

func _draw_blade(c: Vector2, g: float, blade_frac: float) -> void:
	var blade_len := g * 1.7 * blade_frac
	var blade_w := g * 0.26
	var tip := c + Vector2(0, -blade_len)
	var pts := PackedVector2Array([
		tip,
		c + Vector2(blade_w, -blade_len * 0.15),
		c + Vector2(blade_w, blade_len * 0.15),
		c + Vector2(-blade_w, blade_len * 0.15),
		c + Vector2(-blade_w, -blade_len * 0.15),
	])
	draw_colored_polygon(pts, C_GLYPH)
	# crossguard
	draw_rect(Rect2(c + Vector2(-g * 0.85, blade_len * 0.12), Vector2(g * 1.7, g * 0.16)), C_GLYPH)
	# handle + pommel
	draw_rect(Rect2(c + Vector2(-blade_w * 0.5, blade_len * 0.28), Vector2(blade_w, g * 0.62)), C_GLYPH)
	draw_circle(c + Vector2(0, blade_len * 0.28 + g * 0.62), g * 0.16, C_GLYPH)

func _draw_axe(c: Vector2, g: float) -> void:
	var haft_top := c + Vector2(0, -g * 1.15)
	var haft_bot := c + Vector2(0, g * 1.15)
	draw_line(haft_top, haft_bot, C_GLYPH, g * 0.16, true)
	# Head: a rounded fan/wedge sweeping out from a point near the haft - a
	# filled pie-slice reads unmistakably as a curved axe blade at icon size;
	# a thin crescent (two arcs) tried first collapsed into a flag/pennant
	# shape once scaled down this small.
	var apex := c + Vector2(-g * 0.05, -g * 0.35)
	var outer_r := g * 1.35
	var a_from := deg_to_rad(-95.0)
	var a_to := deg_to_rad(75.0)
	var steps := 14
	var pts := PackedVector2Array([apex])
	for i: int in range(steps + 1):
		var a: float = lerpf(a_from, a_to, float(i) / float(steps))
		pts.append(apex + Vector2(cos(a), sin(a)) * outer_r)
	draw_colored_polygon(pts, C_GLYPH)

func _draw_bow(c: Vector2, g: float) -> void:
	var rect := Rect2(c - Vector2(g * 0.9, g * 1.15), Vector2(g * 1.8, g * 2.3))
	draw_arc(rect.position + rect.size * 0.5, g * 1.15, -PI * 0.42, PI * 0.42, 24, C_GLYPH, g * 0.16, true)
	var top := c + Vector2(g * 0.78, -g * 0.98)
	var bot := c + Vector2(g * 0.78, g * 0.98)
	draw_line(top, bot, C_GLYPH, g * 0.06, true)
	# nocked arrow
	draw_line(c + Vector2(-g * 1.1, 0), c + Vector2(g * 0.78, 0), C_GLYPH, g * 0.07, true)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-g * 1.1, -g * 0.16),
		c + Vector2(-g * 1.45, 0),
		c + Vector2(-g * 1.1, g * 0.16),
	]), C_GLYPH)

func _draw_staff(c: Vector2, g: float) -> void:
	draw_line(c + Vector2(0, -g * 0.55), c + Vector2(0, g * 1.15), C_GLYPH, g * 0.15, true)
	draw_circle(c + Vector2(0, -g * 0.85), g * 0.42, C_GLYPH)
	draw_circle(c + Vector2(0, -g * 0.85), g * 0.20, Color(1, 1, 1, 0.85))

func _draw_gem(c: Vector2, g: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -g), c + Vector2(g, 0), c + Vector2(0, g), c + Vector2(-g, 0),
	]), C_GLYPH)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -g * 0.4), c + Vector2(g * 0.4, 0), c + Vector2(0, g * 0.4), c + Vector2(-g * 0.4, 0),
	]), Color(1, 1, 1, 0.6))
