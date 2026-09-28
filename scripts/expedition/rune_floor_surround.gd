extends Node3D
## [expedition phase II] The void the Rune Floor's islands float in: a scatter of
## distant islets far below and around the stage, and motes drifting over the
## fight. This is the per-biome half of the old spike scenery (PRD §6.2, §8 Q1);
## the per-encounter half is RuneFloorIsland, which RuneFloorTrack slides past.
## Nothing here moves with a crossing: it is far enough off that standing still
## reads as distance.
##
## Built in code from primitives placed off the field frame the combat uses
## (RuneFloorWorld.grid_centre() / field_basis()); the colours are exports so
## they can be tuned in the inspector. A second biome swaps this node, not the
## islands (#218).

@export_group("Palette")
@export var moss: Color = Color("2f6f47")
@export var rock_far: Color = Color("12232a")
@export var mote: Color = Tuning.C_PORTAL

var _world = null   # RuneFloorWorld (untyped: custom API)

func _ready() -> void:
	_world = get_parent()
	_build_islets()
	_build_motes()

## A point `across` to the party's right, `along` toward the enemies and `up`
## above the ground, measured from the board's centre.
func _at(across: float, along: float, up: float = 0.0) -> Vector3:
	return _world.grid_centre() + _world.perp_dir() * across \
		+ Tuning.RUN_DIR * along + Vector3.UP * up

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

## Distant islets for depth, well below the stage and clear of the track.
func _build_islets() -> void:
	var top_mat := CelMaterials.cel_opaque(moss.darkened(0.55), Color.BLACK, 0.0, 0.0)
	var under_mat := CelMaterials.cel_opaque(rock_far, Color.BLACK, 0.0, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in range(9):
		var across := rng.randf_range(-22.0, 22.0)
		var along := rng.randf_range(-10.0, 34.0)
		if absf(across) < 10.0 and along < 20.0:
			across = signf(across if across != 0.0 else 1.0) * rng.randf_range(11.0, 20.0)
		var r := rng.randf_range(0.8, 2.2)
		var depth := r * 1.6
		var root := Node3D.new()
		add_child(root)
		root.position = _at(across, along, rng.randf_range(-14.0, -6.0))
		root.basis = (_world.field_basis() as Basis).rotated(Vector3.UP, rng.randf() * TAU)
		_mesh(_cyl(r, r, 0.5, 12), top_mat, Vector3(0, -0.25, 0), root)
		_mesh(_cyl(r * 0.97, r * 0.16, depth, 9), under_mat, Vector3(0, -0.5 - depth * 0.5, 0), root)

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
	mat.albedo_color = Color(mote, 1.0) * 2.2
	sphere.material = mat
	p.mesh = sphere
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.2, 1.0))
	fade.add_point(Vector2(0.8, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = fade
