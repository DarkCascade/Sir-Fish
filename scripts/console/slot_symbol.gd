@tool
class_name SlotSymbol
extends Control
## One reel cell. [slot phase 2] Draws the icon for whatever the bag dealt onto
## this cell, centred in a square that is a fixed fraction of the cell's shorter
## side. A blank cell draws nothing - the recessed reel window shows through.
##
## [rootwood-canopy] The icon sits on a rootwood, gold-rimmed tile (`tile_style`), and
## draws its board glyph (assets/ui/slot/glyph_*.png, see SlotIcon.board_glyph_path_for)
## untinted. An id with no glyph yet falls back to its tinted reliquary chip. A
## forged (Enhanced) icon gets a glowing rim, an innate one an amethyst inlay.
##
## [slot vocabulary] Six things can appear here: a strike drawn as its owner's
## weapon, fire, ice, lightning, or block, each with the number it will add
## printed in the corner (SlotIcon.board_value); or a special charge, drawn as
## a solid gold coin carrying its owner's side-on profile, with no number.
##
## @tool so this redraws live in the editor - see scenes/console/
## reel_layout_playground.tscn, a sandbox for eyeballing reel layout without
## Play mode. In the editor the cell has no dealt icon, so `preview_id` stands
## in for one.

## [slot vocabulary] The corner number's font and its size as a fraction of the
## tile. Baloo 2 is the console's chunky readable face; a thick ink outline keeps
## the number legible over any glyph.
const NUMBER_FONT := preload("res://assets/fonts/Baloo2-Variable.ttf")
@export_range(0.1, 0.6, 0.01) var number_fraction: float = 0.34:
	set(value):
		number_fraction = value
		queue_redraw()

## [slot vocabulary] The charge coin's diameter as a fraction of the tile, and
## the portrait's size within the coin.
@export_range(0.3, 1.0, 0.01) var coin_fraction: float = 0.82:
	set(value):
		coin_fraction = value
		queue_redraw()
@export_range(0.3, 1.0, 0.01) var portrait_fraction: float = 0.86:
	set(value):
		portrait_fraction = value
		queue_redraw()

## How much of the cell's shorter side the chip fills.
@export_range(0.1, 1.0, 0.01) var box_fraction: float = 0.78:
	set(value):
		box_fraction = value
		queue_redraw()

## Editor-only stand-in for a dealt icon (the reel overwrites `icon` every frame
## in Play mode). One of SlotIcon's ids, e.g. &"elem_fire", &"bomb_arrow".
@export var preview_id: StringName = &"":
	set(value):
		preview_id = value
		queue_redraw()

## [slot ui phase 3] The tile a dealt icon sits on, authored in slot_symbol.tscn.
## Null draws the icon straight onto the reel window, as before phase 3.
@export var tile_style: StyleBox:
	set(value):
		tile_style = value
		queue_redraw()

## [black-glass] Set by SlotReel.set_boss_active(), forwarded from
## SlotMachine.apply_boss_theme()/clear_boss_theme(). Recolours the innate-icon
## inlay from canopy leaf-green to the boss chrome's glowing seam.
@export var boss_active: bool = false:
	set(v):
		boss_active = v
		queue_redraw()

## The board glyph's size as a fraction of its tile.
@export_range(0.1, 1.0, 0.01) var glyph_fraction: float = 0.74:
	set(value):
		glyph_fraction = value
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
## every stop is a dictionary hit rather than a disk load. Board glyphs likewise.
static var _tex_cache: Dictionary = {}
static var _glyph_cache: Dictionary = {}
static var _enhanced_rim: StyleBoxFlat = null

func set_icon(value: Dictionary) -> void:
	# Cheap identity check: same id + roll + enhanced + owner/weapon means
	# nothing to redraw. [slot vocabulary] The roll, owner and weapon all show
	# on the tile now, so they are part of the identity.
	if icon.get("id", &"") == value.get("id", &"") \
			and icon.get("roll", 0) == value.get("roll", 0) \
			and icon.get("owner", &"") == value.get("owner", &"") \
			and icon.get("weapon", &"") == value.get("weapon", &"") \
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

## Board glyphs and charge portraits, cached by path. [slot vocabulary] Keyed
## by path rather than id: one id draws as different weapons for different owners.
static func _texture_at(path: String) -> Texture2D:
	if path == "":
		return null
	if _glyph_cache.has(path):
		return _glyph_cache[path]
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_glyph_cache[path] = tex
	return tex

## The icon this cell draws: the dealt one, or the editor's preview_id.
func _effective_icon() -> Dictionary:
	if not icon.is_empty():
		return icon
	return { "id": preview_id, "roll": 6 }

## [slot ui phase 3] The forged (Enhanced) rim: a filled rounded box a few px
## larger than the tile, in the Enhanced rarity colour with a soft glow. The tile
## covers its middle, leaving a glowing edge. Built once in code because its
## colour is Tuning's, not an inspector value.
static func _enhanced_style() -> StyleBoxFlat:
	if _enhanced_rim == null:
		var hot: Color = Tuning.RARITY_COLORS[Item.Rarity.ENHANCED]
		_enhanced_rim = StyleBoxFlat.new()
		_enhanced_rim.bg_color = hot
		_enhanced_rim.set_corner_radius_all(16)
		_enhanced_rim.shadow_color = Color(hot, 0.5)
		_enhanced_rim.shadow_size = 10
	return _enhanced_rim

func _draw() -> void:
	var id := _effective_id()
	if id == SlotIcon.BLANK or SlotIcon.kind_of(id) == SlotIcon.Kind.BLANK:
		return
	var box := minf(size.x, size.y) * box_fraction
	var c := size * 0.5
	var rect := Rect2(c - Vector2.ONE * box * 0.5, Vector2.ONE * box)

	# Enhanced (forged) icon: a forge-hot rim around the tile so it reads as its
	# own thing on the board (§4).
	if bool(icon.get("enhanced", false)):
		draw_style_box(_enhanced_style(), rect.grow(5.0))

	if tile_style != null:
		draw_style_box(tile_style, rect)

	var shown := _effective_icon()
	if SlotIcon.kind_of(id) == SlotIcon.Kind.CHARGE:
		_draw_charge_coin(shown, c, box)
	else:
		var glyph := _texture_at(SlotIcon.board_glyph_path_for(shown))
		if glyph != null:
			# Board glyphs carry their own colour, so they are never element-tinted.
			var g := box * glyph_fraction
			draw_texture_rect(glyph, Rect2(c - Vector2.ONE * g * 0.5, Vector2.ONE * g), false)
		else:
			_draw_chip_fallback(id, rect.grow(-box * 0.08), c, box)
		_draw_value(shown, rect, box)

	# Innate icon: an amethyst inlay set into the tile's top rim, like the gems at
	# the vine frame's corners, so the player can tell the one icon they cannot
	# lose by unequipping from a geared one.
	if bool(icon.get("innate", false)) or SlotIcon.is_innate(id):
		var at := Vector2(c.x, rect.position.y)
		var r := box * 0.09
		draw_colored_polygon(_diamond(at, r + 3.0), Tuning.C_SEAM if boss_active else Tuning.C_GOLD)
		draw_colored_polygon(_diamond(at, r), Tuning.C_SEAM_BRIGHT if boss_active else Tuning.C_ROOTWOOD_GEM)

## [slot vocabulary] A special charge: a solid gold coin with a bright rim and an
## ink edge, carrying its owner's side-on profile. A coin with no portrait on
## disk (or no owner, on a rigged board) stays a plain coin.
func _draw_charge_coin(shown: Dictionary, c: Vector2, box: float) -> void:
	var r := box * coin_fraction * 0.5
	draw_circle(c, r + 3.0, Tuning.C_INK)
	draw_circle(c, r, Tuning.C_GOLD)
	draw_arc(c, r - 3.0, 0.0, TAU, 48, Tuning.C_GOLD_BRIGHT, 3.0, true)
	draw_arc(c, r * 0.88, 0.0, TAU, 48, Color(Tuning.C_INK, 0.35), 2.0, true)
	var portrait := _texture_at(SlotIcon.charge_portrait_path(shown))
	if portrait != null:
		var p := r * 2.0 * portrait_fraction
		draw_texture_rect(portrait, Rect2(c - Vector2.ONE * p * 0.5, Vector2.ONE * p), false)

## [slot vocabulary] The number the icon will add, bottom-right of the tile,
## ink-outlined. Overcharge is included, so the tile reads what the swing banks.
func _draw_value(shown: Dictionary, rect: Rect2, box: float) -> void:
	var mult := 1.0 if Engine.is_editor_hint() else Upgrades.overcharge_mult()
	var value := SlotIcon.board_value(shown, mult)
	if value < 0:
		return
	var px := int(round(box * number_fraction))
	var text := str(value)
	var text_size := NUMBER_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	var at := rect.end - Vector2(text_size.x + box * 0.06, box * 0.07)
	draw_string_outline(NUMBER_FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px,
		maxi(4, int(px / 5.0)), Tuning.C_INK)
	draw_string(NUMBER_FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color.WHITE)

## No board glyph for this id yet: the reliquary chip, tinted per element as the
## reel drew it before phase 3. The chips are opaque squares, so they are inset
## inside the tile's rim rather than drawn over it.
func _draw_chip_fallback(id: StringName, rect: Rect2, c: Vector2, box: float) -> void:
	var tint := Color.WHITE
	match SlotIcon.element_of(id):
		&"fire": tint = Tuning.C_FIRE
		&"ice": tint = Tuning.C_ICE
		&"light": tint = Tuning.C_LIGHTNING
	var tex := _chip(id)
	if tex != null:
		draw_texture_rect(tex, rect, false, tint)
	else:
		# Art missing: a plain rounded token so the board still reads as "an icon
		# is here" rather than a blank.
		draw_circle(c, box * 0.36, Color(tint, 0.85))
		draw_arc(c, box * 0.36, 0.0, TAU, 24, Tuning.C_INK, 2.0)

func _diamond(at: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0),
	])
