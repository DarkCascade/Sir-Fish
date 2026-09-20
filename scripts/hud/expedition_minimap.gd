extends Control
## [minimap] A read-only progress strip for the current expedition: one marker
## per encounter in GameState.level.encounters, left to right in travel order,
## with the party's current encounter picked out. Visible only during a quest -
## Hud._process() gates it the same way it already gates CurrencyPlate, just
## the opposite way round (see hud.gd).
##
## No text anywhere, by design. Encounter TYPE reads through marker shape and
## colour alone - a circle for combat, a diamond for loot, a hexagon for the
## shop - and the boss slot gets a bigger, ringed marker. The party's position
## is a caret over the current marker; every marker already passed dims out.
##
## Procedural draw, not Meshy art (CLAUDE.md best practice 2): every mark here
## is a handful of vertices, has to recolour and resize per encounter type, and
## has to rebuild on the fly whenever the level regenerates (endless mode) -
## the opposite of what a fixed baked asset is good for.

const MARKER_RADIUS := 10.0
const BOSS_RADIUS := 14.0
const TRACK_INSET := 22.0     # keeps the first/last marker off the panel edge
const DONE_ALPHA := 0.35      # a cleared encounter dims rather than vanishes

## The current level's encounters and where the party is in them. Re-read from
## GameState on every rebuild rather than diffed, since the whole array is
## replaced wholesale on an endless-mode level change (RunController.
## _next_encounter) with no signal of its own beyond the next encounter_started.
var _encounters: Array[EncounterDef] = []
var _current_index: int = -1

## Eases 1 -> 0 right after the party marker lands on a new encounter, so the
## marker pops rather than just appearing - see _on_encounter_started().
var _marker_pop: float = 0.0

func _ready() -> void:
	EventBus.run_started.connect(_rebuild)
	EventBus.encounter_started.connect(_on_encounter_started)
	_rebuild()

func _rebuild() -> void:
	_read_encounters()
	_current_index = GameState.current_encounter_index
	queue_redraw()

func _on_encounter_started(index: int, _def: EncounterDef) -> void:
	_read_encounters()
	_current_index = index
	_marker_pop = 1.0
	var tw := create_tween()
	tw.tween_method(_set_pop, 1.0, 0.0, 0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	queue_redraw()

## A ternary here evaluates its `[]` branch as plain untyped Array, not
## Array[EncounterDef] - assigning that into _encounters throws a runtime type
## error the moment GameState.level is null, which it always is at boot
## (Hud._ready() runs before any expedition exists). An if/else sidesteps the
## inference entirely instead of fighting it with a cast.
func _read_encounters() -> void:
	if GameState.level != null:
		_encounters = GameState.level.encounters
	else:
		_encounters.clear()

func _set_pop(v: float) -> void:
	_marker_pop = v
	queue_redraw()

func _draw() -> void:
	if _encounters.is_empty():
		return
	var n := _encounters.size()
	var track_w := size.x - TRACK_INSET * 2.0
	var y := size.y * 0.5
	var xs: Array[float] = []
	for i: int in range(n):
		var t := 0.0 if n == 1 else float(i) / float(n - 1)
		xs.append(TRACK_INSET + track_w * t)

	draw_line(Vector2(xs[0], y), Vector2(xs[n - 1], y),
		Color(Tuning.C_TEXT_DIM, 0.3), 2.0, true)

	for i: int in range(n):
		var enc: EncounterDef = _encounters[i]
		var alpha := DONE_ALPHA if i < _current_index else 1.0
		_draw_marker(Vector2(xs[i], y), enc, alpha)
		if i == _current_index:
			_draw_party_marker(Vector2(xs[i], y), enc.is_boss)

func _draw_marker(at: Vector2, enc: EncounterDef, alpha: float) -> void:
	var r := BOSS_RADIUS if enc.is_boss else MARKER_RADIUS
	var color := Color(_color_for(enc), alpha)
	match enc.type:
		EncounterDef.Type.LOOT:
			draw_colored_polygon(_diamond(at, r), color)
		EncounterDef.Type.SHOP:
			draw_colored_polygon(_hex(at, r), color)
		_:
			draw_circle(at, r, color)
	if enc.is_boss:
		draw_arc(at, r + 4.0, 0.0, TAU, 20, Color(Tuning.C_SEAM_BRIGHT, alpha), 2.0, true)

func _color_for(enc: EncounterDef) -> Color:
	match enc.type:
		EncounterDef.Type.LOOT: return Tuning.C_GOLD
		EncounterDef.Type.SHOP: return Tuning.C_ARCANE
		_: return Tuning.C_DANGER

## A downward caret hovering over the current marker - "you are here", with no
## word needed. Pops a little larger right as it lands (_marker_pop) and
## settles to its resting size.
func _draw_party_marker(at: Vector2, is_boss: bool) -> void:
	var clearance := (BOSS_RADIUS if is_boss else MARKER_RADIUS) + 10.0
	# Named pop_scale, not scale - Control already has a `scale` property
	# (Vector2), and shadowing it here was a standing warning even though
	# nothing read the real one.
	var pop_scale := 1.0 + _marker_pop * 0.5
	var tip := at + Vector2(0, -clearance)
	var w := 7.0 * pop_scale
	var h := 11.0 * pop_scale
	draw_colored_polygon(PackedVector2Array([
		tip, tip + Vector2(-w, -h), tip + Vector2(w, -h),
	]), Tuning.C_GOLD_BRIGHT)

func _diamond(at: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0),
	])

func _hex(at: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(6):
		var a := TAU * float(i) / 6.0 - PI * 0.5
		pts.append(at + Vector2(cos(a), sin(a)) * r)
	return pts
