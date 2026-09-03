extends Control
## One reel column (spec 16.1-16.3). [slot phase 2] The reel is no longer a
## window onto a fixed 27-stop strip - it shows whatever the bag dealt this
## spin. `set_column()` loads the three scoring icons the machine drew for this
## column plus a ring of visual filler; the reel then scrolls and decelerates
## onto them exactly as before, so all the motion, the thunk and the win pulse
## are unchanged.
##
## [move-elements-to-editor] The five visible cells are authored instances in
## slot_reel.tscn, not instantiated here, so the reel opens in the editor and
## each cell carries its own inspector properties. Their POSITION is still
## script-driven - the reel scrolls, so a cell's y is a function of
## position_stops and cannot be authored.

const DEFAULT_CELL_H := 240.0
const SPIN_SPEED := 26.0      # stops per second while free-spinning

## How many icons the scrolling strip carries. Only three of them (around
## `_target_stop`) are the dealt scoring icons; the rest is filler the window
## clips away. Comfortably longer than the five visible cells so the reel can
## scroll for a beat before the dealt icons come into view.
const STRIP_LEN := 24

## Cell height, driven by the cabinet: the reel window shows exactly three cells
## whatever height the console band ends up with (see slot_machine.apply_height).
## Keep slot_symbol.tscn's and this scene's custom_minimum_size well below any
## cell_h the layout can produce - an authored floor silently overrides
## set_cell_height() and the payline stops lining up with the glyphs.
var cell_h: float = DEFAULT_CELL_H

## Fractional strip position. The integer part is the strip index sitting on the
## payline; the fraction is how far it has scrolled toward the next one.
var position_stops: float = 0.0

var _spinning: bool = false
## Attract mode: the reel drifts upward continuously and never stops (spec 16.6).
var _drifting: bool = false
## Decelerating onto a stop: stop_at()'s tween drives position_stops and
## _layout() has to keep running to move the cells with it.
var _stopping: bool = false
var _cells: Array[SlotSymbol] = []
var _stop_tween: Tween = null

## The strip of icon dicts the window scrolls over. Rebuilt every spin by
## set_column(); a ring of blanks until the first one.
var _strip: Array = []
## The index on `_strip` the reel is decelerating onto - its scoring icons sit
## at _target_stop - 1 / _target_stop / _target_stop + 1.
var _target_stop: int = 0

## Cells above (and below) the payline cell, derived from however many the scene
## authored. Five cells means two either side of the middle one.
var _visible_range: int = 2

## Smoothness pass: while drifting the reel reads fine relayed at half rate.
var _drift_layout_pending: bool = true

func _ready() -> void:
	for child: Node in get_children():
		if child is SlotSymbol:
			_cells.append(child as SlotSymbol)
	@warning_ignore("integer_division")
	_visible_range = (_cells.size() - 1) / 2
	_strip = _build_filler([])
	position_stops = float(RNG.randi_range(0, STRIP_LEN - 1))
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
		# Same shrink as the cabinet around it (Tuning.SLOT_CABINET_SCALE): this
		# shrinks around the cell's own centre, so _layout()'s per-cell position
		# (spaced at the full, unscaled cell_h) still stacks the reel correctly.
		# slot_machine.gd's win pulse tweens this same property on the payline
		# cell and has to rest here, not at Vector2.ONE.
		cell.scale = Vector2.ONE * Tuning.SLOT_CABINET_SCALE
		cell.queue_redraw()

func _process(delta: float) -> void:
	if _spinning:
		position_stops -= SPIN_SPEED * delta
		_layout()
	elif _drifting:
		position_stops -= SPIN_SPEED * Tuning.SLOT_ATTRACT_SPEED * delta
		_drift_layout_pending = not _drift_layout_pending
		if _drift_layout_pending:
			_layout()
	elif _stopping:
		_layout()
	else:
		set_process(false)

func start_spin() -> void:
	set_process(true)
	if _stop_tween != null and _stop_tween.is_valid():
		_stop_tween.kill()
	_stopping = false
	_drifting = false
	_spinning = true

## Spec 16.6 / Q17. Out of combat the reels keep moving but stop mattering: no
## stops, no board evaluation, no resolution.
func start_drift() -> void:
	set_process(true)
	if _stop_tween != null and _stop_tween.is_valid():
		_stop_tween.kill()
	_stopping = false
	_spinning = false
	_drifting = true
	_drift_layout_pending = true

func stop_drift() -> void:
	_drifting = false

# --- bag content ----------------------------------------------------------

## Load this column's three dealt scoring icons (top / middle / bottom, i.e. the
## cells at offsets -1 / 0 / +1 from the payline) plus a ring of visual filler
## drawn from `filler` (the whole bag). Picks a fresh stop index each call so the
## dealt icons land somewhere new.
func set_column(top: Dictionary, mid: Dictionary, bot: Dictionary, filler: Array) -> void:
	_strip = _build_filler(filler)
	_target_stop = RNG.randi_range(_visible_range + 1, STRIP_LEN - _visible_range - 2)
	_strip[_target_stop - 1] = top
	_strip[_target_stop] = mid
	_strip[_target_stop + 1] = bot

## Attract-mode content: no scoring icons, just filler so the drifting reel has
## something to show. Safe to call any time the reel is idle or drifting.
func set_filler_strip(filler: Array) -> void:
	_strip = _build_filler(filler)
	_target_stop = 0
	_layout()

func _build_filler(pool: Array) -> Array:
	var out: Array = []
	if pool.is_empty():
		for i: int in range(STRIP_LEN):
			out.append(SlotIcon.blank())
		return out
	for i: int in range(STRIP_LEN):
		out.append(pool[RNG.randi_range(0, pool.size() - 1)])
	return out

## The three icons currently dealt onto this column's scoring cells, top to
## bottom. Read by SlotMachine after all reels have stopped.
func scoring_icons() -> Array:
	return [
		_strip_at(_target_stop - 1),
		_strip_at(_target_stop),
		_strip_at(_target_stop + 1),
	]

## The icon on the payline (centre scoring cell) - what the payline bonus reads.
func center_icon() -> Dictionary:
	return _strip_at(_target_stop)

func _strip_at(index: int) -> Dictionary:
	if _strip.is_empty():
		return SlotIcon.blank()
	return _strip[posmod(index, _strip.size())]

# --- deceleration -------------------------------------------------------------

## Decelerates onto `target_stop` (or this reel's own `_target_stop` when -1)
## with a slight overshoot and snap back - the physical thunk of a real reel.
func stop_at(target_stop: int = -1, duration: float = 0.18) -> void:
	var stop := _target_stop if target_stop < 0 else target_stop
	_spinning = false
	_drifting = false
	_stopping = true
	set_process(true)
	var current := position_stops
	# Always approach from below so the reel keeps scrolling in one direction.
	var target := float(stop)
	while target < current + 2.0:
		target += float(_strip.size())
	_stop_tween = create_tween()
	_stop_tween.tween_property(self, "position_stops", target, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_stop_tween.tween_callback(func() -> void:
		position_stops = fposmod(position_stops, float(_strip.size()))
		_stopping = false
		_layout())

## The SlotSymbol control sitting on the payline, for the win pulse - the middle
## authored cell.
func payline_cell() -> SlotSymbol:
	return _cells[_visible_range]

## The scoring cell for `row` (0 = top, 1 = payline, 2 = bottom) - i.e.
## _cells[1..3]. Used by SlotMachine's per-icon resolve pulse.
func scoring_cell(row: int) -> SlotSymbol:
	var index := _visible_range - 1 + clampi(row, 0, 2)
	if index < 0 or index >= _cells.size():
		return null
	return _cells[index]

func _layout() -> void:
	if _strip.is_empty():
		return
	var base := int(floor(position_stops))
	var frac := position_stops - float(base)
	for i: int in range(_cells.size()):
		var k := i - _visible_range
		var cell := _cells[i]
		cell.set_icon(_strip_at(base + k))
		var new_y := cell_h + float(k) * cell_h - frac * cell_h
		if not is_equal_approx(cell.position.y, new_y):
			cell.position.y = new_y
		# Legibility drops naturally from the speed while spinning for real; the
		# slow attract drift stays readable.
		var new_alpha := 0.55 if _spinning else 1.0
		if not is_equal_approx(cell.modulate.a, new_alpha):
			cell.modulate.a = new_alpha
