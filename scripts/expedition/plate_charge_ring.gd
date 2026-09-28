extends Control
class_name PlateChargeRing
## [rune floor dock] A hero plate's portrait in a segmented charge ring (design
## A of the dock mockups). One segment per point of Tuning.SPECIAL_CHARGE_COST,
## so a charge coin (SLOT_CHARGE_ICON_CHARGE) visibly fills three at once.
## HeroPlate feeds it; the ring only draws.

@export var portrait: Texture2D:
	set(value):
		portrait = value
		queue_redraw()
## The owner's rune colour - the same colour this hero's icons glow on the board.
@export var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()
@export var ring_width: float = 14.0
@export var portrait_radius: float = 58.0
## Degrees of gap between segments.
@export var gap_degrees: float = 5.0

var track_color := Tuning.C_GLASS_FACET
var charge: int = 0
## True when a press would fire right now: the whole ring turns gold.
var lit: bool = false
## [expedition phase II] The hero is not in the party yet: the portrait draws as a
## dark silhouette in an empty track, the "recruit to fill" teaser (#220).
var silhouette: bool = false:
	set(value):
		if value != silhouette:
			silhouette = value
			queue_redraw()

const SILHOUETTE_TINT := Color(0.16, 0.15, 0.2)

func set_state(new_charge: int, is_lit: bool) -> void:
	if new_charge == charge and is_lit == lit:
		return
	charge = new_charge
	lit = is_lit
	queue_redraw()

func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - ring_width * 0.5
	var count: int = Tuning.SPECIAL_CHARGE_COST
	var step := TAU / float(count)
	var gap := deg_to_rad(gap_degrees)
	for i: int in range(count):
		var start := -PI * 0.5 + step * float(i) + gap * 0.5
		var colour: Color = Tuning.C_GOLD_BRIGHT if lit else (color if i < charge else track_color)
		draw_arc(centre, radius, start, start + step - gap, 12, colour, ring_width, true)

	draw_circle(centre, portrait_radius, Tuning.C_OBSIDIAN_DEEP)
	if portrait == null:
		return
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i: int in range(48):
		var a := TAU * float(i) / 48.0
		var unit := Vector2(cos(a), sin(a))
		points.append(centre + unit * portrait_radius)
		uvs.append(Vector2(0.5, 0.5) + unit * 0.5)
	draw_colored_polygon(points, SILHOUETTE_TINT if silhouette else Color.WHITE, uvs, portrait)
