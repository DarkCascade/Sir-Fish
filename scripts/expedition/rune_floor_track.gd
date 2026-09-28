class_name RuneFloorTrack
extends Node3D
## [expedition phase II] The encounter track made physical (PRD §5.6, §5.8): the
## island the party stands on, the next one across the bridge, and a smaller one
## hanging off to the side beyond it as a preview.
##
## A crossing is a treadmill, not traversal. The party stays at PARTY_ANCHOR and
## every island slides one slot back down the run axis: the next island docks
## exactly where the last one stood, so the slots, the camera and the board -
## all solved against PARTY_ANCHOR and RUN_DIR - never move. The island left
## behind slides out under the camera and is freed, so at most four islands
## exist at once, and only for the length of a crossing (§6.3).
##
## Slots: 0 is docked (the party's), 1 is next, on the axis, full size, joined
## by the bridge; 2 is the preview, off to one side, lower and smaller; 3 is
## where a new island appears, deep in the fog. Between slots an island's pose is
## interpolated, so the preview drifts into line as it comes up.

## Centre to centre, along the run axis, between docked islands.
@export var pitch: float = 19.5
## The docked island's centre, relative to the board's centre (along the run).
@export var dock_along: float = -1.0
## Slot 2's pose: how far off the axis, how far down, how small.
@export var preview_across: float = 8.0
@export var preview_drop: float = 3.0
@export_range(0.2, 1.0, 0.01) var preview_scale: float = 0.55
## Slot 3's, where islands appear.
@export var spawn_drop: float = 9.0
@export_range(0.05, 1.0, 0.01) var spawn_scale: float = 0.35
## Shown on the islands ahead until a crossing says what they really are. Only
## the looping demo, which never crosses, ever shows these.
@export var preview_kinds: Array[RuneFloorIsland.Kind] = [
	RuneFloorIsland.Kind.COMBAT, RuneFloorIsland.Kind.BOSS]

var _world = null   # RuneFloorWorld (untyped: custom API)
## Index = slot. Null where the track ends (a quest's last encounter).
var _islands: Array = []
var _crossing: Tween
var _progress: float = 0.0
var _spawned: int = 0

func _ready() -> void:
	_world = get_parent()
	reset()

## Back to the start of the track: the party on a bare start island, the preview
## kinds ahead. The retry path and a fresh expedition both begin here.
func reset() -> void:
	if _crossing != null and _crossing.is_valid():
		_crossing.kill()
	_crossing = null
	for island: Variant in _islands:
		if island != null:
			(island as Node).queue_free()
	_islands.clear()
	_islands.append(_make(RuneFloorIsland.Kind.START))
	for kind: RuneFloorIsland.Kind in preview_kinds.slice(0, 2):
		_islands.append(_make(kind))
	while _islands.size() < 3:
		_islands.append(null)
	_place_all(0.0)
	_islands[0].set_docked(true, false)
	_lay_next_bridge(false)

## The party sets off. `kinds` names what the next three encounters are - the
## one being travelled to, then the two after it; NONE past a quest's end. The
## islands already ahead are corrected to match, a new one appears at the back,
## and the whole track slides one slot over `duration` seconds.
func begin_crossing(kinds: Array, duration: float) -> void:
	# A crossing nobody docked (end_crossing() never called) docks now.
	_finish_crossing()
	while _islands.size() < 4:
		_islands.append(null)
	for i: int in range(3):
		var kind: RuneFloorIsland.Kind = kinds[i] if i < kinds.size() else RuneFloorIsland.Kind.NONE
		var slot := i + 1
		var island: Variant = _islands[slot]
		if kind == RuneFloorIsland.Kind.NONE:
			if island != null:
				(island as Node).queue_free()
			_islands[slot] = null
		elif island == null:
			_islands[slot] = _make(kind)
		else:
			(island as RuneFloorIsland).set_kind(kind)
	var leaving: Variant = _islands[0]
	if leaving != null:
		(leaving as RuneFloorIsland).set_docked(false, true)
	# The bridge the party is about to cross belongs to the next island, and
	# slides with it; the leaving island has none of its own.
	_place_all(0.0)
	_crossing = create_tween()
	_crossing.tween_method(_place_all, 0.0, 1.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Waits out the crossing, then docks the next island: its lights kindle, the
## island behind is freed, and the bridge to the one after is laid.
func end_crossing() -> void:
	if is_crossing():
		await _crossing.finished
	_finish_crossing()

func is_crossing() -> bool:
	return _crossing != null and _crossing.is_valid() and _crossing.is_running()

## The island the party stands on, and the one after it (null past the end).
func docked_island() -> RuneFloorIsland:
	return _islands[0] if not _islands.is_empty() else null

func next_island() -> RuneFloorIsland:
	return _islands[1] if _islands.size() > 1 else null

# --- internals ------------------------------------------------------------------

func _finish_crossing() -> void:
	if _crossing == null:
		return
	if _crossing.is_valid():
		_crossing.kill()
	_crossing = null
	var behind: Variant = _islands.pop_front()
	if behind != null:
		(behind as Node).queue_free()
	_place_all(0.0)
	var docked: Variant = _islands[0] if not _islands.is_empty() else null
	if docked != null:
		(docked as RuneFloorIsland).set_docked(true, true)
	_lay_next_bridge(true)

func _lay_next_bridge(animate: bool) -> void:
	var next: Variant = _islands[1] if _islands.size() > 1 else null
	if next != null and _islands[0] != null:
		(next as RuneFloorIsland).lay_bridge(pitch, animate)

func _make(kind: RuneFloorIsland.Kind) -> RuneFloorIsland:
	var island := RuneFloorIsland.new()
	island.name = "Island%d" % _spawned
	add_child(island)
	island.setup(kind, _spawned)
	_spawned += 1
	return island

## Every island at its slot, `t` of the way to the slot below.
func _place_all(t: float) -> void:
	_progress = t
	for slot: int in range(_islands.size()):
		var island: Variant = _islands[slot]
		if island != null:
			(island as RuneFloorIsland).transform = _pose(float(slot) - t, (island as RuneFloorIsland).side)

## The pose at a (possibly fractional) slot. Slots 1 and below are one straight
## line at full size, so a crossing moves the docked and next islands rigidly
## together; above 1 an island swings out to its side, sinks and shrinks.
func _pose(slot: float, side: float) -> Transform3D:
	var across := 0.0
	var drop := 0.0
	var s := 1.0
	if slot > 1.0:
		var a := minf(slot - 1.0, 1.0)
		across = lerpf(0.0, preview_across, a)
		drop = lerpf(0.0, preview_drop, a)
		s = lerpf(1.0, preview_scale, a)
	if slot > 2.0:
		var b := minf(slot - 2.0, 1.0)
		drop = lerpf(preview_drop, spawn_drop, b)
		s = lerpf(preview_scale, spawn_scale, b)
	var origin: Vector3 = _world.grid_centre() \
		+ _world.perp_dir() * (across * side) \
		+ Tuning.RUN_DIR * (dock_along + slot * pitch) \
		+ Vector3.DOWN * drop
	return Transform3D((_world.field_basis() as Basis).scaled_local(Vector3.ONE * s), origin)
