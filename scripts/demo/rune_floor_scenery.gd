extends Node3D
## [rune floor demo] The void the fight floats in: the main moss island, the
## rope bridge the enemies run in across, the islands beyond it (the encounter
## track made physical - loot, shop, boss), lantern posts at the board's
## corners, crystals, drifting motes, and a scatter of distant islets.
##
## Built in code because it is all primitives placed off the same field frame
## the combat uses (RuneFloorWorld.grid_centre() / field_basis()); the colours
## are exports so they can be tuned in the inspector.

@export_group("Palette")
@export var moss: Color = Color("2f6f47")
@export var rock: Color = Color("1b2f36")
@export var rock_far: Color = Color("12232a")
@export var wood: Color = Tuning.C_WOOD
@export var lantern_light: Color = Color("FFD98A")
@export var crystal: Color = Tuning.C_ARCANE
@export var crystal_glow: Color = Tuning.C_ARCANE_BRIGHT
@export var boss_glow: Color = Tuning.C_DANGER

@export_group("Layout")
## The main island, in the field frame: along = toward the enemies.
@export var island_along: float = -1.0
@export var island_radius: float = 7.6
## The main island is squeezed across the run axis by this much, so its edges
## and the void beyond them stay in frame either side of the fight.
@export_range(0.4, 1.0, 0.01) var island_across_scale: float = 0.72
## The next island, where each wave of enemies comes from, and the bridge to it.
@export var next_island_along: float = 15.5
@export var next_island_radius: float = 4.4
@export var bridge_width: float = 4.6

var _world = null   # RuneFloorWorld (untyped: custom API)

func _ready() -> void:
	_world = get_parent()
	_build_main_island()
	_build_bridge(island_along + island_radius - 0.6, next_island_along - next_island_radius + 0.6)
	_build_next_island()
	_build_far_islands()
	_build_lantern_posts()
	_build_crystals()
	_build_motes()

# --- the field frame ------------------------------------------------------------

## A point `across` to the party's right, `along` toward the enemies and `up`
## above the ground, measured from the board's centre.
func _at(across: float, along: float, up: float = 0.0) -> Vector3:
	return _world.grid_centre() + _world.perp_dir() * across \
		+ Tuning.RUN_DIR * along + Vector3.UP * up

func _mesh(mesh: Mesh, mat: Material, pos: Vector3, parent: Node = self) -> MeshInstance3D:
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

func _light(pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	add_child(l)
	l.position = pos
	return l

# --- islands --------------------------------------------------------------------

## A chunky faceted island: a flat moss top over a rock cone that tapers into the
## void, with a few loose shards hanging under it. Its top surface is y = top.
func _island(centre: Vector3, radius: float, depth: float, yaw: float,
		top_color: Color, under_color: Color, outline: float = 0.02,
		across_scale: float = 1.0) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = centre
	root.basis = (_world.field_basis() as Basis).rotated(Vector3.UP, yaw) 		.scaled_local(Vector3(across_scale, 1.0, 1.0))
	_mesh(_cyl(radius, radius, 0.5, 12), CelMaterials.cel(top_color, Color.BLACK, 0.0, outline),
		Vector3(0, -0.25, 0), root)
	_mesh(_cyl(radius * 0.97, radius * 0.16, depth, 9),
		CelMaterials.cel(under_color, Color.BLACK, 0.0, outline),
		Vector3(0, -0.5 - depth * 0.5, 0), root)
	for i: int in range(3):
		var a := TAU * float(i) / 3.0 + 0.6
		var r := radius * 0.45
		var shard_h := depth * 0.35
		_mesh(_cyl(radius * 0.16, 0.0, shard_h, 5), CelMaterials.cel(under_color, Color.BLACK, 0.0, outline),
			Vector3(cos(a) * r, -0.5 - depth * 0.55 - shard_h * 0.5, sin(a) * r), root)
	return root

func _build_main_island() -> void:
	var centre := _at(0.0, island_along)
	_island(centre, island_radius, 6.5, 0.0, moss, rock, 0.02, island_across_scale)
	# Loose rocks on the moss, kept clear of the board and both ranks.
	var rock_mat := CelMaterials.cel(Tuning.C_ROCK, Color.BLACK, 0.0, 0.02)
	for spot: Vector3 in [Vector3(-4.3, -3.4, 0.0), Vector3(4.4, 0.6, 0.0),
			Vector3(-3.6, 4.6, 0.0), Vector3(3.4, -6.2, 0.0), Vector3(-4.6, 1.2, 0.0)]:
		var r := _mesh(_box(Vector3(0.7, 0.45, 0.55)), rock_mat, _at(spot.x, spot.y, 0.18))
		r.rotation = Vector3(0.2, spot.x * 0.7, -0.15)

func _build_next_island() -> void:
	_island(_at(0.0, next_island_along), next_island_radius, 4.5, 0.9, moss.darkened(0.12), rock)
	# The chest waiting beyond this fight - off to the side of the enemies' lane.
	var chest := _at(2.9, next_island_along + 1.4, 0.0)
	var b: Basis = _world.field_basis()
	var body := _mesh(_box(Vector3(0.95, 0.55, 0.62)), CelMaterials.cel(wood), chest + Vector3.UP * 0.28)
	body.basis = b
	var lid := _mesh(_box(Vector3(0.98, 0.22, 0.66)), CelMaterials.cel(wood.lightened(0.1)), chest + Vector3.UP * 0.66)
	lid.basis = b
	var band := _mesh(_box(Vector3(1.0, 0.1, 0.68)), CelMaterials.cel(Tuning.C_GOLD, Tuning.C_GOLD, 0.8, 0.0),
		chest + Vector3.UP * 0.52)
	band.basis = b
	_light(chest + Vector3.UP * 1.0, Tuning.C_GOLD, 1.6, 3.5)

func _build_far_islands() -> void:
	# The shop and the boss - the rest of the level, hanging further out and down.
	var shop := _at(7.5, 27.0, -2.5)
	_island(shop, 3.0, 3.5, 0.4, moss.darkened(0.3), rock_far, 0.0)
	var house := _mesh(_box(Vector3(1.6, 1.2, 1.4)), CelMaterials.cel(wood), shop + Vector3.UP * 0.6)
	house.basis = _world.field_basis()
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(1.9, 0.9, 1.6)
	var roof := _mesh(roof_mesh, CelMaterials.cel(Tuning.C_VELVET), shop + Vector3.UP * 1.65)
	roof.basis = _world.field_basis()
	_light(shop + Vector3.UP * 1.0 - Tuning.RUN_DIR * 1.0, lantern_light, 1.2, 3.0)

	var boss := _at(-5.5, 38.0, -5.0)
	_island(boss, 2.4, 3.0, 1.3, moss.darkened(0.45), rock_far, 0.0)
	_mesh(_cyl(0.0, 0.55, 2.6, 5), CelMaterials.cel(Color("1a1016"), boss_glow, 1.4, 0.0), boss + Vector3.UP * 1.3)
	_light(boss + Vector3.UP * 1.6, boss_glow, 2.0, 5.0)

	# Distant islets for depth, well below and around the stage.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in range(9):
		var across := rng.randf_range(-22.0, 22.0)
		var along := rng.randf_range(-10.0, 34.0)
		if absf(across) < 10.0 and along < 20.0:
			across = signf(across if across != 0.0 else 1.0) * rng.randf_range(11.0, 20.0)
		var r := rng.randf_range(0.8, 2.2)
		_island(_at(across, along, rng.randf_range(-14.0, -6.0)), r, r * 1.6,
			rng.randf() * TAU, moss.darkened(0.55), rock_far, 0.0)

func _build_bridge(from_along: float, to_along: float) -> void:
	var b: Basis = _world.field_basis()
	var plank_mat := CelMaterials.cel(wood, Color.BLACK, 0.0, 0.01)
	var rope_mat := CelMaterials.cel(Tuning.C_WOOD_DARK, Color.BLACK, 0.0, 0.0)
	var length := to_along - from_along
	var steps := int(length / 0.55)
	for i: int in range(steps + 1):
		var t := float(i) / float(maxi(steps, 1))
		var sag := -0.14 * sin(PI * t)
		var plank := _mesh(_box(Vector3(bridge_width, 0.1, 0.4)), plank_mat,
			_at(0.0, from_along + length * t, sag - 0.05))
		plank.basis = b.rotated(Vector3.UP, 0.02 * sin(float(i) * 1.7))
	for side: float in [-1.0, 1.0]:
		var across := side * bridge_width * 0.5
		for end_along: float in [from_along, to_along]:
			_mesh(_cyl(0.08, 0.1, 1.2, 6), CelMaterials.cel(Tuning.C_WOOD_DARK), _at(across, end_along, 0.6))
		# The hand rope, as a run of short segments so it can sag.
		var segs := 10
		for s: int in range(segs):
			var t0 := float(s) / float(segs)
			var t1 := float(s + 1) / float(segs)
			var p0 := _at(across, from_along + length * t0, 1.05 - 0.35 * sin(PI * t0))
			var p1 := _at(across, from_along + length * t1, 1.05 - 0.35 * sin(PI * t1))
			var seg := _mesh(_box(Vector3(0.05, 0.05, p0.distance_to(p1))), rope_mat, (p0 + p1) * 0.5)
			seg.look_at(p1, Vector3.UP)

# --- lanterns, crystals, motes -------------------------------------------------

func _build_lantern_posts() -> void:
	var post_mat := CelMaterials.cel(Tuning.C_WOOD_DARK, Color.BLACK, 0.0, 0.01)
	var lamp_mat := CelMaterials.cel(lantern_light, lantern_light, 2.2, 0.01)
	var reach := 3.0
	for across: float in [-reach, reach]:
		for along: float in [-reach, reach]:
			_mesh(_cyl(0.06, 0.08, 1.7, 6), post_mat, _at(across, along, 0.85))
			_mesh(_box(Vector3(0.3, 0.36, 0.3)), lamp_mat, _at(across, along, 1.86))
			_light(_at(across, along, 1.9), lantern_light, 2.6, 5.5)

func _build_crystals() -> void:
	var mat := CelMaterials.cel(crystal, crystal_glow, 1.1, 0.012)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for spot: Vector2 in [Vector2(-4.6, 2.2), Vector2(4.7, -2.8), Vector2(-3.9, -6.3),
			Vector2(4.2, 4.4), Vector2(-2.4, 17.6), Vector2(3.6, -7.6)]:
		for i: int in range(3):
			var h := rng.randf_range(0.8, 1.5)
			var shard := _mesh(_cyl(0.0, rng.randf_range(0.18, 0.3), h, 5), mat,
				_at(spot.x + rng.randf_range(-0.35, 0.35), spot.y + rng.randf_range(-0.35, 0.35), h * 0.45))
			shard.rotation = Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35))
		_light(_at(spot.x, spot.y, 0.8), crystal, 0.9, 3.2)

func _build_motes() -> void:
	var p := CPUParticles3D.new()
	add_child(p)
	p.position = _at(0.0, 2.0, 2.0)
	p.amount = 48
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(11.0, 2.5, 13.0)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
	sphere.radial_segments = 6
	sphere.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(Tuning.C_PORTAL, 1.0) * 2.2
	sphere.material = mat
	p.mesh = sphere
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.2, 1.0))
	fade.add_point(Vector2(0.8, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = fade
