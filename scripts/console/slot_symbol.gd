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

## [presentation redesign] Was 0.8 - fine at the reel's original ~133px cell
## height, crowded at the ~77-92px cells the status-row growth left behind
## (see slot_machine.gd's WINDOW_MARGIN comment). Lower fraction = more
## padding around the glyph regardless of how tall the cell ends up being.
@export_range(0.1, 1.0, 0.01) var box_fraction: float = 0.66:
	set(value):
		box_fraction = value
		queue_redraw()

const TEX_LIGHTNING := preload("res://assets/icons/slot_lightning.png")
const TEX_GOLD := preload("res://assets/icons/slot_gold.png")
const TEX_HEAL := preload("res://assets/icons/slot_heal.png")

## Per-symbol zoom on top of box_fraction: the icons read small at actual
## reel-cell sizes, so each is blown up in place (same cell, same centre)
## rather than resized by growing the cell itself. Heal reads smaller than
## the other two at the same box size, hence the larger multiplier.
const ICON_ZOOM := {
	Tuning.Sym.LIGHTNING: 1.75,
	Tuning.Sym.GOLD: 1.75,
	Tuning.Sym.PLUS: 2.25,
}

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

func _draw() -> void:
	var c := size * 0.5
	var box := minf(size.x, size.y) * box_fraction * float(ICON_ZOOM.get(symbol, 1.0))
	var tex := _texture_for(symbol)
	if tex != null:
		draw_texture_rect(tex, Rect2(c - Vector2.ONE * box * 0.5, Vector2.ONE * box), false)
	# BLANK falls through: an empty space, the recessed reel window shows through

static func _texture_for(sym: int) -> Texture2D:
	match sym:
		Tuning.Sym.LIGHTNING: return TEX_LIGHTNING
		Tuning.Sym.GOLD: return TEX_GOLD
		Tuning.Sym.PLUS: return TEX_HEAL
		_: return null

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
