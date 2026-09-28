class_name RuneFloorIsland
extends Node3D
## [expedition phase II] One encounter's island on the Rune Floor (PRD §5.6,
## §6.2): a chunky faceted moss top over a rock cone that tapers into the void,
## loose rocks and crystals, and what the encounter needs on it. A fight gets
## lantern posts at the board's corners; loot, shop and boss islands carry a
## marker (a chest, a hut, a glowing spire) so the track ahead reads as
## progress at a glance (§5.8).
##
## Every island is the same shape, because each one docks exactly where the last
## stood: RuneFloorTrack slides them down the run axis like a treadmill, and the
## board, the slots and the camera never move. Built from primitives in code,
## like the rest of the spike's scenery.
##
## Local frame: the node's basis is the world's field_basis(), so +x is the
## party's right and -z points up-run, toward the enemies. The origin is the moss
## top's centre; the board sits `board_along` up-run of it.

enum Kind { NONE, START, COMBAT, LOOT, SHOP, BOSS }

@export_group("Palette")
@export var moss: Color = Color("2f6f47")
@export var rock: Color = Color("1b2f36")
@export var wood: Color = Tuning.C_WOOD
@export var lantern_light: Color = Color("FFD98A")
@export var crystal: Color = Tuning.C_ARCANE
@export var crystal_glow: Color = Tuning.C_ARCANE_BRIGHT
@export var boss_glow: Color = Tuning.C_DANGER

@export_group("Shape")
@export var radius: float = 7.6
@export var depth: float = 6.5
## Squeezed across the run axis, so the island's edges and the void beyond them
## stay in frame either side of the fight.
@export_range(0.4, 1.0, 0.01) var across_scale: float = 0.72
## Where the board's centre sits, up-run of the island's centre. The lantern
## posts stand at its corners.
@export var board_along: float = 1.0
@export var bridge_width: float = 4.6

## Seconds the lantern and crystal lights take to kindle when the island docks.
const KINDLE_TIME := 0.45
## Omni energies at full kindle, per light, restored by set_docked().
const LANTERN_ENERGY := 2.6
const CRYSTAL_ENERGY := 0.9

var kind: Kind = Kind.NONE
## Which side of the run axis this island hangs on while it is still a preview
## (RuneFloorTrack's slot 2). Fixed at creation so an island never swaps sides.
var side: float = 1.0

var _seed: int = 0
var _dressing: Node3D        # lanterns, crystals, marker: rebuilt by set_kind()
var _bridge: Node3D
var _marker: Node3D
var _dock_lights: Array[OmniLight3D] = []
var _docked: bool = false
## Once the party has stood here the encounter is spent, and its marker stays
## down as the island slides away behind them.
var _visited: bool = false

func setup(a_kind: Kind, a_seed: int) -> void:
	_seed = a_seed
	side = 1.0 if a_seed % 2 == 0 else -1.0
	_build_body()
	set_kind(a_kind)

## Rebuilds what stands on the island for `a_kind`. The track calls this when
## the encounter list turns out different from what an island was built as -
## an endless run generates its next level only once it gets there.
func set_kind(a_kind: Kind) -> void:
	if a_kind == kind and _dressing != null:
		return
	kind = a_kind
	if _dressing != null:
		_dressing.queue_free()
	_dock_lights.clear()
	_marker = null
	_dressing = Node3D.new()
	_dressing.name = "Dressing"
	add_child(_dressing)
	_build_crystals()
	match kind:
		Kind.START, Kind.COMBAT, Kind.BOSS:
			_build_lantern_posts()
	match kind:
		Kind.LOOT: _build_chest_marker()
		Kind.SHOP: _build_shop_marker()
		Kind.BOSS: _build_boss_marker()
	set_docked(_docked, false)

## Docked is the island the party stands on. Its lanterns and crystals light
## up (only the docked island's do, so the omni count stays near the spike's),
## and its marker steps aside for good: RunController brings the real chest or
## hut, and a boss spire left standing would crowd the enemy rank.
func set_docked(on: bool, animate: bool) -> void:
	_docked = on
	_visited = _visited or on
	for light: OmniLight3D in _dock_lights:
		var energy: float = light.get_meta("energy", 1.0)
		if not animate:
			light.visible = on
			light.light_energy = energy if on else 0.0
			continue
		light.visible = true
		var tw := light.create_tween()
		tw.tween_property(light, "light_energy", energy if on else 0.0, KINDLE_TIME)
		if not on:
			tw.tween_callback(light.hide)
	if _marker != null:
		_marker.visible = not _visited

## Lays the rope bridge from this island's near edge back to the island `gap`
## metres down-run (centre to centre). Plank by plank when `animate`, so the
## crossing reads as the way opening up.
func lay_bridge(gap: float, animate: bool) -> void:
	clear_bridge()
	_bridge = Node3D.new()
	_bridge.name = "Bridge"
	add_child(_bridge)
	var from_along := -gap + radius - 0.6
	var to_along := -radius + 0.6
	var plank_mat := CelMaterials.cel_opaque(wood, Color.BLACK, 0.0, 0.01)
	var rope_mat := CelMaterials.cel_opaque(Tuning.C_WOOD_DARK, Color.BLACK, 0.0, 0.0)
	var post_mat := CelMaterials.cel_opaque(Tuning.C_WOOD_DARK)
	var length := to_along - from_along
	var steps := int(length / 0.55)
	# Laid from this island back toward the party, so the plank nearest the
	# party lands last.
	for i: int in range(steps + 1):
		var t := 1.0 - float(i) / float(maxi(steps, 1))
		var sag := -0.14 * sin(PI * t)
		var plank := _mesh(_box(Vector3(bridge_width, 0.1, 0.4)), plank_mat,
			_at(0.0, from_along + length * t, sag - 0.05), _bridge)
		plank.rotation.y = 0.02 * sin(float(i) * 1.7)
		if animate:
			var drop := plank.position
			plank.position = drop + Vector3.UP * 1.2
			plank.scale = Vector3.ONE * 0.01
			var tw := plank.create_tween()
			tw.tween_interval(0.025 * float(i))
			tw.tween_property(plank, "position", drop, 0.18) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(plank, "scale", Vector3.ONE, 0.12)
	for s: float in [-1.0, 1.0]:
		var across := s * bridge_width * 0.5
		for end_along: float in [from_along, to_along]:
			_mesh(_cyl(0.08, 0.1, 1.2, 6), post_mat, _at(across, end_along, 0.6), _bridge)
		# The hand rope, as a run of short segments so it can sag.
		var segs := 10
		for g: int in range(segs):
			var t0 := float(g) / float(segs)
			var t1 := float(g + 1) / float(segs)
			var p0 := _at(across, from_along + length * t0, 1.05 - 0.35 * sin(PI * t0))
			var p1 := _at(across, from_along + length * t1, 1.05 - 0.35 * sin(PI * t1))
			var seg := _mesh(_box(Vector3(0.05, 0.05, p0.distance_to(p1))), rope_mat,
				(p0 + p1) * 0.5, _bridge)
			seg.basis = Basis.looking_at(p1 - p0, Vector3.UP)

func clear_bridge() -> void:
	if _bridge != null:
		_bridge.queue_free()
		_bridge = null

# --- construction ---------------------------------------------------------------

## A point `across` to the party's right, `along` up-run and `up` above the moss,
## in this island's own frame.
func _at(across: float, along: float, up: float = 0.0) -> Vector3:
	return Vector3(across, up, -along)

func _mesh(mesh: Mesh, mat: Material, pos: Vector3, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	return mi

func _cyl(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m

func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

func _light(pos: Vector3, color: Color, energy: float, light_range: float,
		parent: Node, docked_only: bool) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	parent.add_child(l)
	l.position = pos
	if docked_only:
		l.set_meta("energy", energy)
		_dock_lights.append(l)
	return l

## The moss top, the rock cone and three loose shards hanging under it, squeezed
## across the run axis; then the loose rocks on the moss, which are not.
func _build_body() -> void:
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	body.scale = Vector3(across_scale, 1.0, 1.0)
	var top_mat := CelMaterials.cel_opaque(moss, Color.BLACK, 0.0, 0.02)
	var under_mat := CelMaterials.cel_opaque(rock, Color.BLACK, 0.0, 0.02)
	_mesh(_cyl(radius, radius, 0.5, 12), top_mat, Vector3(0, -0.25, 0), body)
	_mesh(_cyl(radius * 0.97, radius * 0.16, depth, 9), under_mat,
		Vector3(0, -0.5 - depth * 0.5, 0), body)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var spin := rng.randf() * TAU
	for i: int in range(3):
		var a := TAU * float(i) / 3.0 + spin
		var r := radius * 0.45
		var shard_h := depth * rng.randf_range(0.28, 0.42)
		_mesh(_cyl(radius * 0.16, 0.0, shard_h, 5), under_mat,
			Vector3(cos(a) * r, -0.5 - depth * 0.55 - shard_h * 0.5, sin(a) * r), body)
	# Loose rocks, kept clear of the board and both ranks.
	var rock_mat := CelMaterials.cel_opaque(Tuning.C_ROCK, Color.BLACK, 0.0, 0.02)
	for spot: Vector2 in [Vector2(-4.3, -2.4), Vector2(4.4, 1.6), Vector2(-3.6, 5.6),
			Vector2(3.4, -5.2), Vector2(-4.6, 2.2)]:
		var r := _mesh(_box(Vector3(0.7, 0.45, 0.55)), rock_mat, _at(spot.x, spot.y, 0.18), self)
		r.rotation = Vector3(0.2, spot.x * 0.7 + rng.randf_range(-0.4, 0.4), -0.15)

func _build_crystals() -> void:
	var mat := CelMaterials.cel_opaque(crystal, crystal_glow, 1.1, 0.012)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 3
	for spot: Vector2 in [Vector2(-4.6, 3.2), Vector2(4.7, -1.8), Vector2(-3.9, -5.3),
			Vector2(4.2, 5.4), Vector2(3.6, -6.6)]:
		for i: int in range(3):
			var h := rng.randf_range(0.8, 1.5)
			var shard := _mesh(_cyl(0.0, rng.randf_range(0.18, 0.3), h, 5), mat,
				_at(spot.x + rng.randf_range(-0.35, 0.35), spot.y + rng.randf_range(-0.35, 0.35), h * 0.45),
				_dressing)
			shard.rotation = Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35))
		_light(_at(spot.x, spot.y, 0.8), crystal, CRYSTAL_ENERGY, 3.2, _dressing, true)

## Four posts at the board's corners. The lamps glow on their own; their omni
## lights only kindle on the docked island.
func _build_lantern_posts() -> void:
	var post_mat := CelMaterials.cel_opaque(Tuning.C_WOOD_DARK, Color.BLACK, 0.0, 0.01)
	var lamp_mat := CelMaterials.cel_opaque(lantern_light, lantern_light, 2.2, 0.01)
	var reach := 3.0
	for across: float in [-reach, reach]:
		for along: float in [board_along - reach, board_along + reach]:
			_mesh(_cyl(0.06, 0.08, 1.7, 6), post_mat, _at(across, along, 0.85), _dressing)
			_mesh(_box(Vector3(0.3, 0.36, 0.3)), lamp_mat, _at(across, along, 1.86), _dressing)
			_light(_at(across, along, 1.9), lantern_light, LANTERN_ENERGY, 5.5, _dressing, true)

## The chest waiting on a loot island, off to the side of the enemies' lane.
func _build_chest_marker() -> void:
	_marker = Node3D.new()
	_dressing.add_child(_marker)
	var at := _at(2.9, board_along + 2.4)
	_mesh(_box(Vector3(0.95, 0.55, 0.62)), CelMaterials.cel_opaque(wood), at + Vector3.UP * 0.28, _marker)
	_mesh(_box(Vector3(0.98, 0.22, 0.66)), CelMaterials.cel_opaque(wood.lightened(0.1)), at + Vector3.UP * 0.66, _marker)
	_mesh(_box(Vector3(1.0, 0.1, 0.68)), CelMaterials.cel_opaque(Tuning.C_GOLD, Tuning.C_GOLD, 0.8, 0.0),
		at + Vector3.UP * 0.52, _marker)
	_light(at + Vector3.UP * 1.0, Tuning.C_GOLD, 1.6, 3.5, _marker, false)

## The shop's hut, with a lamp at its door.
func _build_shop_marker() -> void:
	_marker = Node3D.new()
	_dressing.add_child(_marker)
	var at := _at(-2.8, board_along + 2.6)
	_mesh(_box(Vector3(1.6, 1.2, 1.4)), CelMaterials.cel_opaque(wood), at + Vector3.UP * 0.6, _marker)
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(1.9, 0.9, 1.6)
	_mesh(roof_mesh, CelMaterials.cel_opaque(Tuning.C_VELVET), at + Vector3.UP * 1.65, _marker)
	_light(at + Vector3.UP * 1.0 + _at(0.0, -1.0), lantern_light, 1.2, 3.0, _marker, false)

## A dark spire burning in the boss's red, visible from the first island.
func _build_boss_marker() -> void:
	_marker = Node3D.new()
	_dressing.add_child(_marker)
	var at := _at(-3.4, board_along + 4.2)
	_mesh(_cyl(0.0, 0.55, 2.6, 5), CelMaterials.cel_opaque(Color("1a1016"), boss_glow, 1.4, 0.0),
		at + Vector3.UP * 1.3, _marker)
	_light(at + Vector3.UP * 1.6, boss_glow, 2.0, 5.0, _marker, false)
