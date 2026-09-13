@tool
class_name QuestRouteStrip
extends Control
## [mayor notice board] A quest's encounter sequence drawn as a row of stops -
## one per QuestDef.encounter_types entry, the last always the boss (quest_def.gd's
## own invariant: the LAST entry is a COMBAT and becomes the boss fight).
##
## Two layouts off one script, because the notice card and the detail sheet
## differ only in scale: compact (fixed-size glyphs packed left, for a
## QuestNotice) and labelled (stops spread across the full width on a
## connecting line, each captioned, for the QuestNoticeSheet).
##
## PLACEHOLDER ART. The glyphs are geometric primitives - ring / square /
## diamond / filled disc - standing in for real fight / loot / shop / boss
## icons. Recognisable icons are a Meshy job (CLAUDE.md best practice 2), and
## the existing assets/icons/*.png carry opaque backdrops that cannot sit on
## parchment. Fill STOP_TEXTURES with white-on-alpha PNGs and _draw_glyph()
## uses them instead, modulated by the stop's colour.

enum Stop { COMBAT, LOOT, SHOP, BOSS }

const STOP_TEXTURES := {}
const STOP_LABELS := {
	Stop.COMBAT: "Fight",
	Stop.LOOT: "Loot",
	Stop.SHOP: "Shop",
	Stop.BOSS: "Boss",
}
## Space between a labelled stop's disc and its caption.
const LABEL_GAP := 8.0

@export var encounter_types: Array[int] = [0, 1, 0, 2, 0]:
	set(v):
		encounter_types = v
		update_minimum_size()
		queue_redraw()
## Compact (false) packs glyphs left at stop_size; labelled (true) spreads
## captioned discs across the full width.
@export var labelled: bool = false:
	set(v):
		labelled = v
		update_minimum_size()
		queue_redraw()
## Glyph box in compact mode; the largest disc diameter in labelled mode (it
## shrinks to fit a long route).
@export var stop_size: float = 30.0:
	set(v):
		stop_size = v
		update_minimum_size()
		queue_redraw()
@export var gap: float = 6.0:
	set(v):
		gap = v
		update_minimum_size()
		queue_redraw()
@export var label_font_size: int = 34:
	set(v):
		label_font_size = v
		update_minimum_size()
		queue_redraw()
@export var ink: Color = Tuning.C_INK:
	set(v):
		ink = v
		queue_redraw()
@export var boss_color: Color = Tuning.C_DANGER_INK:
	set(v):
		boss_color = v
		queue_redraw()
## Fill behind each labelled stop's ring, so the connecting line reads as
## passing behind the stops.
@export var disc_color: Color = Color(0.85098, 0.835294, 0.768627, 1):
	set(v):
		disc_color = v
		queue_redraw()

func _get_minimum_size() -> Vector2:
	if labelled:
		return Vector2(0.0, stop_size + LABEL_GAP + label_font_size * 1.25)
	var n := encounter_types.size()
	return Vector2(n * stop_size + maxi(n - 1, 0) * gap, stop_size)

func _stop_at(i: int) -> Stop:
	if i == encounter_types.size() - 1:
		return Stop.BOSS
	match encounter_types[i]:
		EncounterDef.Type.LOOT:
			return Stop.LOOT
		EncounterDef.Type.SHOP:
			return Stop.SHOP
	return Stop.COMBAT

func _draw() -> void:
	var n := encounter_types.size()
	if n == 0:
		return
	if labelled:
		_draw_labelled(n)
		return
	for i: int in range(n):
		var c := Vector2(i * (stop_size + gap) + stop_size * 0.5, size.y * 0.5)
		_draw_glyph(_stop_at(i), c, stop_size * 0.5)

func _draw_labelled(n: int) -> void:
	var slot: float = size.x / n
	var d: float = minf(stop_size, slot * 0.86)
	var y: float = d * 0.5
	var font := get_theme_default_font()
	# A nine-stop route leaves ~94px a slot on the sheet; shrink the captions
	# before "Fight" starts touching its neighbour.
	var fs: int = label_font_size if n <= 6 else int(label_font_size * 0.82)
	draw_line(Vector2(slot * 0.5, y), Vector2(size.x - slot * 0.5, y), Color(ink, 0.4), 4.0)
	for i: int in range(n):
		var stop := _stop_at(i)
		var col: Color = boss_color if stop == Stop.BOSS else ink
		var c := Vector2(slot * (i + 0.5), y)
		draw_circle(c, d * 0.5, disc_color)
		draw_arc(c, d * 0.5 - 2.5, 0.0, TAU, 40, col, 5.0, true)
		_draw_glyph(stop, c, d * 0.27)
		var text: String = STOP_LABELS[stop]
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - w * 0.5, d + LABEL_GAP + font.get_ascent(fs)),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _draw_glyph(stop: Stop, c: Vector2, r: float) -> void:
	var col: Color = boss_color if stop == Stop.BOSS else ink
	if STOP_TEXTURES.has(stop):
		var tex: Texture2D = STOP_TEXTURES[stop]
		draw_texture_rect(tex, Rect2(c - Vector2.ONE * r, Vector2.ONE * r * 2.0), false, col)
		return
	var w: float = maxf(r * 0.3, 2.0)
	match stop:
		Stop.COMBAT:
			draw_arc(c, r * 0.72, 0.0, TAU, 32, col, w, true)
		Stop.LOOT:
			var h: float = r * 0.66
			draw_rect(Rect2(c - Vector2(h, h), Vector2(h, h) * 2.0), col, false, w)
		Stop.SHOP:
			var k: float = r * 0.92
			draw_polyline(PackedVector2Array([c + Vector2(0, -k), c + Vector2(k, 0),
				c + Vector2(0, k), c + Vector2(-k, 0), c + Vector2(0, -k)]), col, w, true)
		Stop.BOSS:
			draw_circle(c, r * 0.85, col)
