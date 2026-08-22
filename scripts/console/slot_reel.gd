extends Control
## One reel window (spec 16.1-16.3). Three symbols visible per stop; the middle
## cell is the one on the payline.

const DEFAULT_CELL_H := 240.0
const VISIBLE_RANGE := 2      # cells drawn above and below the payline cell
const SYMBOL_SCENE := preload("res://scenes/console/slot_symbol.tscn")
const SPIN_SPEED := 26.0      # stops per second while free-spinning

## Cell height, driven by the cabinet: the reel window shows exactly three cells
## whatever height the console band ends up with (see slot_machine.apply_height).
var cell_h: float = DEFAULT_CELL_H

## Fractional stop position. The integer part is the strip index sitting on the
## payline; the fraction is how far it has scrolled toward the next one.
var position_stops: float = 0.0

var _spinning: bool = false
## Attract mode: the reel drifts upward continuously and never stops (spec 16.6).
var _drifting: bool = false
var _cells: Array[SlotSymbol] = []
var _stop_tween: Tween = null

func _ready() -> void:
	clip_contents = true
	for k: int in range(-VISIBLE_RANGE, VISIBLE_RANGE + 1):
		var cell := SYMBOL_SCENE.instantiate() as SlotSymbol
		add_child(cell)
		_cells.append(cell)
	position_stops = float(RNG.randi_range(0, Tuning.SLOT_REEL_STOPS - 1))
	_resize_cells()
	_layout()

func set_cell_height(value: float) -> void:
	cell_h = value
	_resize_cells()
	_layout()

func _resize_cells() -> void:
	var w := size.x if size.x > 0.0 else custom_minimum_size.x
	for cell: SlotSymbol in _cells:
		cell.size = Vector2(w, cell_h)
		cell.pivot_offset = cell.size * 0.5
		# Same shrink as the cabinet around it (Tuning.SLOT_CABINET_SCALE), and
		# for the same reason: each glyph was filling its cell edge to edge.
		# This shrinks around the cell's own centre, so _layout()'s per-cell
		# `position` (spaced at the full, unscaled cell_h) still stacks the
		# reel correctly - only the glyph inside each slot gets smaller, with
		# visible padding above and below it. slot_machine.gd's win pulse
		# tweens this same property on the payline cell and has to rest here,
		# not at Vector2.ONE - see the comment at that call site.
		cell.scale = Vector2.ONE * Tuning.SLOT_CABINET_SCALE
		cell.queue_redraw()

func _process(delta: float) -> void:
	if _spinning:
		position_stops -= SPIN_SPEED * delta
	elif _drifting:
		position_stops -= SPIN_SPEED * Tuning.SLOT_ATTRACT_SPEED * delta
	_layout()

func start_spin() -> void:
	if _stop_tween != null and _stop_tween.is_valid():
		_stop_tween.kill()
	_drifting = false
	_spinning = true

## Spec 16.6 / Q17. Out of combat the reels keep moving but stop mattering:
## no stops, no payline evaluation, no payouts. "The slot does nothing" is read
## as "nothing that affects the game", not as dead air - pillar 2.
func start_drift() -> void:
	if _stop_tween != null and _stop_tween.is_valid():
		_stop_tween.kill()
	_spinning = false
	_drifting = true

func stop_drift() -> void:
	_drifting = false

## Decelerates onto `target_stop` with a slight overshoot and snap back - the
## physical thunk of a real reel (spec 16.3 step 4).
func stop_at(target_stop: int, duration: float = 0.18) -> void:
	_spinning = false
	_drifting = false
	var current := position_stops
	# Always approach from below so the reel keeps scrolling in one direction.
	var target := float(target_stop)
	while target < current + 2.0:
		target += float(Tuning.SLOT_REEL_STOPS)
	_stop_tween = create_tween()
	_stop_tween.tween_property(self, "position_stops", target, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_stop_tween.tween_callback(func() -> void:
		position_stops = fposmod(position_stops, float(Tuning.SLOT_REEL_STOPS)))

func payline_symbol() -> int:
	var index := int(floor(position_stops)) % Tuning.SLOT_REEL_STOPS
	return Tuning.SLOT_STRIP[index]

## The SlotSymbol control currently sitting on the payline, for the win pulse.
func payline_cell() -> SlotSymbol:
	return _cells[VISIBLE_RANGE]

func _layout() -> void:
	var base := int(floor(position_stops))
	var frac := position_stops - float(base)
	for i: int in range(_cells.size()):
		var k := i - VISIBLE_RANGE
		var cell := _cells[i]
		var strip_index := posmod(base + k, Tuning.SLOT_REEL_STOPS)
		cell.set_symbol(Tuning.SLOT_STRIP[strip_index])
		cell.position = Vector2(0.0, cell_h + float(k) * cell_h - frac * cell_h)
		# Legibility naturally drops while the reel is moving fast (spec 16.3).
		# Legibility drops naturally from the speed while spinning for real; the
		# slow attract drift stays readable.
		cell.modulate.a = 0.55 if _spinning else 1.0
