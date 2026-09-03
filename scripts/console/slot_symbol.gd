@tool
class_name SlotSymbol
extends Control
## One reel cell. [slot phase 2] Draws the icon for whatever the bag dealt onto
## this cell: a reliquary chip texture (assets/ui/reliquary/chip_*.png) centred
## in a square that is a fixed fraction of the cell's shorter side, tinted per
## element, with an accent ring for a forged (Enhanced) icon and an inner ring
## for an innate one. A blank cell draws nothing - the recessed reel window
## shows through.
##
## @tool so this redraws live in the editor - see scenes/console/
## reel_layout_playground.tscn, a sandbox for eyeballing reel layout without
## Play mode. In the editor the cell has no dealt icon, so `preview_id` stands
## in for one.

## How much of the cell's shorter side the chip fills.
@export_range(0.1, 1.0, 0.01) var box_fraction: float = 0.78:
	set(value):
		box_fraction = value
		queue_redraw()

## Editor-only stand-in for a dealt icon (the reel overwrites `icon` every frame
## in Play mode). One of SlotIcon's ids, e.g. &"dmg_flat", &"slot_bolt".
@export var preview_id: StringName = &"":
	set(value):
		preview_id = value
		queue_redraw()

## The coin texture kept ONLY because coin_glyph.gd reuses it as the shared
## "gold" glyph across the console. Nothing on the reel draws it any more.
const TEX_GOLD := preload("res://assets/icons/slot_gold.png")

# PackedVector2Array literals are not constant expressions in GDScript, so these
# glyph outlines are static vars. Not drawn by this cell any more, but still
# shared, unmutated, by other UI glyphs that echo the reel's old iconography:
# coin_glyph.gd (STAR), status_icon.gd (PLUS), upgrade_button.gd (BOLT, STAR).
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

## The icon this cell is currently showing: { id, roll, enhanced, innate? }, or
## an empty dict for a blank. See SlotIcon.
var icon: Dictionary = {}

## Chip textures are loaded once, keyed by id, so a spinning reel swapping icons
## every stop is a dictionary hit rather than a disk load.
static var _tex_cache: Dictionary = {}

func set_icon(value: Dictionary) -> void:
	# Cheap identity check: same id + roll + enhanced means nothing to redraw.
	if icon.get("id", &"") == value.get("id", &"") \
			and icon.get("enhanced", false) == value.get("enhanced", false):
		icon = value
		return
	icon = value
	queue_redraw()

func _effective_id() -> StringName:
	if not icon.is_empty():
		return StringName(icon.get("id", &""))
	return preview_id

static func _chip(id: StringName) -> Texture2D:
	if _tex_cache.has(id):
		return _tex_cache[id]
	var tex := SlotIcon.chip_texture(id)
	_tex_cache[id] = tex
	return tex

func _draw() -> void:
	var id := _effective_id()
	if id == SlotIcon.BLANK or SlotIcon.kind_of(id) == SlotIcon.Kind.BLANK:
		return
	var tex := _chip(id)
	var box := minf(size.x, size.y) * box_fraction
	var c := size * 0.5
	var rect := Rect2(c - Vector2.ONE * box * 0.5, Vector2.ONE * box)

	var tint := Color.WHITE
	match SlotIcon.element_of(id):
		&"fire": tint = Tuning.C_FIRE
		&"ice": tint = Tuning.C_ICE
		&"light": tint = Tuning.C_LIGHTNING

	# Innate icon: a soft inner ring in the party-gold, so the player can tell
	# the one chip they cannot lose by unequipping from a geared one.
	if bool(icon.get("innate", false)) or SlotIcon.is_innate(id):
		draw_arc(c, box * 0.60, 0.0, TAU, 28, Color(Tuning.C_GOLD_BRIGHT, 0.5), 3.0)

	if tex != null:
		draw_texture_rect(tex, rect, false, tint)
	else:
		# Art missing: a plain rounded token so the board still reads as "an icon
		# is here" rather than a blank.
		draw_circle(c, box * 0.42, Color(tint, 0.85))
		draw_arc(c, box * 0.42, 0.0, TAU, 24, Tuning.C_INK, 2.0)

	# Enhanced (forged) icon: a forge-hot ring around the chip so it reads as its
	# own thing on the board (§4).
	if bool(icon.get("enhanced", false)):
		var hot := Tuning.RARITY_COLORS[Item.Rarity.ENHANCED]
		draw_arc(c, box * 0.52, 0.0, TAU, 32, hot, 4.0)
		draw_arc(c, box * 0.52, 0.0, TAU, 32, Color(hot, 0.35), 8.0)
