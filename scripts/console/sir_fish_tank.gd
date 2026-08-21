extends SubViewportContainer
## Sir Fish's tank (spec 17.7). A glass bowl bolted to the console at
## console-local (8, 898), 164 x 164, immediately left of the party damage button.
##
## The tank contents are built in code so the same scene can be instanced at 2x
## in the run summary's header (spec 18.2) without a second authored variant.

const WATER_SHADER := preload("res://assets/shaders/water.gdshader")

@onready var viewport: SubViewport = $FishViewport

func _ready() -> void:
	_build_tank()

func _build_tank() -> void:
	var tank := viewport.get_node_or_null("Tank")
	if tank == null:
		return

	# A lit water disc BEHIND the fish. The viewport is transparent_bg (spec 17.7),
	# so without this the glass tints straight onto the console's near-black panel
	# and the whole tank reads as a dark blob with a fish-shaped smudge in it.
	var water := CylinderMesh.new()
	water.top_radius = 0.60
	water.bottom_radius = 0.60
	water.height = 0.01
	water.radial_segments = 24
	var water_mi := MeshInstance3D.new()
	water_mi.name = "WaterBackdrop"
	water_mi.mesh = water
	water_mi.position = Vector3(0, 0, -0.55)
	water_mi.rotation_degrees = Vector3(90, 0, 0)
	var water_mat := StandardMaterial3D.new()
	water_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_mat.albedo_color = Color("3E8FB8")
	water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water_mi.material_override = water_mat
	tank.add_child(water_mi)

	# Glass bowl. Drawn last with depth_draw_never so the fish reads through it.
	var glass := SphereMesh.new()
	glass.radius = 0.62
	glass.height = 1.24
	glass.radial_segments = 20
	glass.rings = 12
	var glass_mi := MeshInstance3D.new()
	glass_mi.name = "Glass"
	glass_mi.mesh = glass
	var glass_mat := ShaderMaterial.new()
	glass_mat.shader = WATER_SHADER
	glass_mi.material_override = glass_mat
	glass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tank.add_child(glass_mi)

	var base := CylinderMesh.new()
	base.top_radius = 0.50
	base.bottom_radius = 0.50
	base.height = 0.10
	base.radial_segments = 20
	_mesh(tank, "Base", base, Tuning.C_GOLD, Vector3(0, -0.62, 0))

	var gravel := CylinderMesh.new()
	gravel.top_radius = 0.44
	gravel.bottom_radius = 0.44
	gravel.height = 0.08
	gravel.radial_segments = 18
	_mesh(tank, "Gravel", gravel, Tuning.C_WOOD, Vector3(0, -0.50, 0))

	var plaque := BoxMesh.new()
	plaque.size = Vector3(0.46, 0.12, 0.02)
	_mesh(tank, "Plaque", plaque, Tuning.C_GOLD, Vector3(0, -0.72, 0.30))

	# The plaque text is a Label3D so no font asset is ever baked into the mesh
	# (spec 23.5).
	var label := Label3D.new()
	label.name = "PlaqueText"
	label.text = "SIR FISH"
	label.font_size = 16
	label.pixel_size = 0.0016
	label.modulate = Tuning.C_INK
	label.outline_size = 0
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = false
	label.position = Vector3(0, -0.72, 0.32)
	tank.add_child(label)

static func _mesh(parent: Node3D, node_name: String, mesh: Mesh, color: Color,
		pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = CelMaterials.cel(color, Color.BLACK, 0.0, 0.010)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
