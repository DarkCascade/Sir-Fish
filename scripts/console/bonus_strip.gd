extends Control
## The party's aggregate item bonuses, drawn procedurally (spec 17.6).
##
## This is the ONLY place a player can see what their inventory is doing, so it
## appears both in the screen-corner overlay (bonus_panel.gd) and in the shop
## modal (spec 15.1). In the shop it is what makes selling a real decision
## instead of free money: the player can see exactly what leaves the party
## with the item.
##
## Six entries (spec 17.6, V9): five numeric-bonus glyphs, each omitted when its
## value is zero, plus a sixth "element chip" shown only when the party carries
## an elemental modifier. `element` (spec 13.5) has no magnitude of its own -
## it only recolours hero damage numbers (spec 11.4) - but a player whose
## numbers turned orange has no way to find out why without this chip, which is
## a pillar-1 legibility failure. Order is fixed (numeric glyphs, then the
## element chip last) so the strip does not reshuffle as it fills.

## [presentation redesign] Was 20/10/18/22 when this lived as a thin strip
## atop the upgrade tray (spec 17.6), then lived enlarged in status_panel's
## BonusRow. [screen-corner variant] Moved again, out of the console
## entirely, into a top-right screen overlay (bonus_panel.gd) - see `vertical`
## below for the layout that move needed.
const GLYPH := 38.0
const GAP := 14.0
const PAD := 26.0
const FONT_SIZE := 34

## sword (dmg_flat), chevron (dmg_pct), bolt (slot_bolt), coin (slot_purse),
## plus (slot_mend). Order is fixed so the strip does not reshuffle as it fills.
const ROWS: Array[StringName] = [
	&"dmg_flat", &"dmg_pct", &"slot_bolt", &"slot_purse", &"slot_mend",
]

static var SWORD := PackedVector2Array([
	Vector2(0.50, 0.02), Vector2(0.62, 0.22), Vector2(0.58, 0.62),
	Vector2(0.42, 0.62), Vector2(0.38, 0.22),
])

static var CHEVRON := PackedVector2Array([
	Vector2(0.50, 0.10), Vector2(0.92, 0.52), Vector2(0.72, 0.52),
	Vector2(0.50, 0.32), Vector2(0.28, 0.52), Vector2(0.08, 0.52),
])

## [screen-corner variant] When true, entries stack top-to-bottom (glyph then
## text, left-aligned) instead of the default centred horizontal row. Used by
## the top-right screen overlay so the panel can sit in a narrow corner
## instead of spanning the console's full width.
@export var vertical: bool = false

var _bonuses: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.party_bonuses_changed.connect(_on_bonuses_changed)
	# reset_run() clears the inventory wholesale, so rebuild from scratch on a
	# fresh run rather than relying on per-item signals (spec 18.3).
	EventBus.run_started.connect(refresh)
	refresh()

func _on_bonuses_changed(_new_bonuses: Dictionary) -> void:
	refresh()

func refresh() -> void:
	_bonuses = GameState.party_bonuses()
	if vertical:
		var rows := _visible_entries().size()
		custom_minimum_size = Vector2(custom_minimum_size.x, _vertical_row_h() * maxf(rows, 1) + PAD)
		size = custom_minimum_size
	queue_redraw()

## [ui-project-longshot] Whether this strip has anything to say. The
## screen-corner panel (bonus_panel.gd) uses it to hide itself entirely
## rather than sit there reading "No party bonuses" - the concept board has
## no such element, and a permanently visible empty panel is the loudest
## thing on screen that carries no information. The shop's copy of this
## strip keeps the empty-state text, where the player has gone looking for
## it on purpose.
func has_bonuses() -> bool:
	return not _visible_entries().is_empty()

# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	var font := get_theme_default_font()
	var entries := _visible_entries()
	if entries.is_empty():
		# The screen-corner variant is hidden outright by its owner
		# (has_bonuses()) rather than shown empty, same reasoning as
		# BonusRow below - see has_bonuses() doc.
		if vertical:
			return
		var empty := "No party bonuses"
		var w := font.get_string_size(empty, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		font.draw_string(get_canvas_item(),
			Vector2((size.x - w) * 0.5, size.y * 0.5 + FONT_SIZE * 0.35),
			empty, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color("7A7290"))
		return

	if vertical:
		_draw_vertical(entries, font)
		return

	# Measure first so the whole strip can be centred.
	var total := 0.0
	for e: Dictionary in entries:
		var text: String = e["text"]
		total += GLYPH + GAP * 0.5 \
			+ font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + PAD
	total -= PAD

	var x := (size.x - total) * 0.5
	var mid := size.y * 0.5
	for e: Dictionary in entries:
		var color: Color = e.get("color", Tuning.C_TEXT_DIM)
		_draw_glyph(String(e["id"]), Vector2(x, mid - GLYPH * 0.5), color)
		x += GLYPH + GAP * 0.5
		var text: String = e["text"]
		font.draw_string(get_canvas_item(), Vector2(x, mid + FONT_SIZE * 0.35),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
		x += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + PAD

func _vertical_row_h() -> float:
	return maxf(GLYPH, FONT_SIZE) + GAP

## One glyph + text pair per row, left-aligned and stacked top-to-bottom, for
## the top-right screen overlay (a narrow column has no room for the
## horizontal strip's centred layout).
func _draw_vertical(entries: Array[Dictionary], font: Font) -> void:
	var row_h := _vertical_row_h()
	var x := PAD * 0.5
	var y := PAD * 0.5
	for e: Dictionary in entries:
		var color: Color = e.get("color", Tuning.C_TEXT_DIM)
		_draw_glyph(String(e["id"]), Vector2(x, y), color)
		var text: String = e["text"]
		font.draw_string(get_canvas_item(),
			Vector2(x + GLYPH + GAP * 0.5, y + GLYPH * 0.5 + FONT_SIZE * 0.35),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
		y += row_h

func _visible_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in ROWS:
		var value := int(_bonuses.get(id, 0))
		if value == 0:
			continue
		out.append({ "id": id, "text": _format(id, value) })
	# [v3] Sixth entry, last: the element chip. No magnitude, so no +N - it is
	# a label for a colour the player is already seeing on hero damage numbers
	# (spec 17.6, V9).
	var element: StringName = _bonuses.get("element", &"")
	if element != &"":
		out.append({
			"id": &"element",
			"text": _element_label(element),
			"color": _element_color(element),
		})
	return out

func _format(id: StringName, value: int) -> String:
	# dmg_pct and slot_mend are percentages; the rest are flat.
	if id == &"dmg_pct" or id == &"slot_mend":
		return "+%d%%" % value
	return "+%d" % value

## GameState.party_bonuses() ties fire -> ice -> lightning by dictionary
## insertion order (spec 17.6). Mirrored here only for display.
func _element_color(element: StringName) -> Color:
	match element:
		&"fire": return Tuning.C_FIRE
		&"ice": return Tuning.C_ICE
		&"light": return Tuning.C_LIGHTNING
	return Tuning.C_TEXT_DIM

func _element_label(element: StringName) -> String:
	match element:
		&"fire": return "Fire"
		&"ice": return "Ice"
		&"light": return "Lightning"
	return ""

func _draw_glyph(id: String, origin: Vector2, color: Color = Tuning.C_TEXT_DIM) -> void:
	match id:
		"dmg_flat":
			draw_colored_polygon(_map(SWORD, origin), Tuning.C_ORC_IRON)
		"dmg_pct":
			draw_colored_polygon(_map(CHEVRON, origin), Tuning.C_DANGER)
		"slot_bolt":
			draw_colored_polygon(_map(SlotSymbol.BOLT, origin), Tuning.C_LIGHTNING)
		"slot_purse":
			var c := origin + Vector2(GLYPH, GLYPH) * 0.5
			draw_circle(c, GLYPH * 0.42, Tuning.C_GOLD)
			draw_arc(c, GLYPH * 0.42, 0.0, TAU, 20, Tuning.C_INK, 2.0)
		"slot_mend":
			draw_colored_polygon(_map(SlotSymbol.PLUS, origin), Tuning.C_HEAL)
		"element":
			# A 20px filled circle in the element's colour with a 2px ink ring
			# (spec 17.6).
			var c := origin + Vector2(GLYPH, GLYPH) * 0.5
			draw_circle(c, GLYPH * 0.5, color)
			draw_arc(c, GLYPH * 0.5, 0.0, TAU, 20, Tuning.C_INK, 2.0)

static func _map(points: PackedVector2Array, origin: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(origin + p * GLYPH)
	return out
