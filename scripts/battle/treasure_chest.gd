extends Node3D
## The loot encounter's chest (spec 14.2). Pops in, beats, then opens with the
## full juice list.

signal opened()

var _lid: Node3D = null
var _light: OmniLight3D = null

func _ready() -> void:
	_build()

func pop_in() -> void:
	scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 1.15, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3.ONE, 0.15)
	BattleVfx.dust_puff_at(global_position, 14)

func open() -> void:
	var lid_tw := create_tween()
	lid_tw.tween_property(_lid, "rotation:x", deg_to_rad(-105.0), 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var light_tw := create_tween()
	light_tw.tween_property(_light, "light_energy", 5.0, 0.25)

	BattleVfx.gold_burst(global_position + Vector3(0, 0.5, 0))
	_spawn_coins()
	_radial_flash()

	var squash := create_tween()
	squash.tween_property(self, "scale", Vector3(1.1, 0.9, 1.1), 0.15)
	squash.tween_property(self, "scale", Vector3.ONE, 0.15)
	squash.tween_callback(func() -> void: opened.emit())

func fade_out() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

func _spawn_coins() -> void:
	for i: int in range(6):
		var coin := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.18, 0.18)
		coin.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Tuning.C_GOLD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		coin.material_override = m
		add_child(coin)
		coin.position = Vector3(0, 0.5, 0.4)
		var target := Vector3(RNG.randf_range(-1.0, 1.0), 1.4, 0.4)
		var tw := coin.create_tween()
		tw.tween_property(coin, "position", target, 0.35) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(coin, "position",
			target + Vector3(RNG.randf_range(-0.4, 0.4), -1.6, 0.0), 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(coin.queue_free)

func _radial_flash() -> void:
	var flash := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	flash.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(Color.WHITE, 0.9)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash.material_override = m
	add_child(flash)
	flash.position = Vector3(0, 0.5, 0.6)
	flash.scale = Vector3.ZERO
	var tw := flash.create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * 3.0, 0.35)
	tw.tween_method(func(a: float) -> void:
			if is_instance_valid(flash):
				m.albedo_color = Color(Color.WHITE, a),
		0.9, 0.0, 0.35)
	tw.chain().tween_callback(flash.queue_free)

func _build() -> void:
	var body := BoxMesh.new()
	body.size = Vector3(1.0, 0.62, 0.7)
	_add(self, "Body", body, Tuning.C_WOOD, Vector3(0, 0.31, 0))
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			var corner := BoxMesh.new()
			corner.size = Vector3(0.10, 0.66, 0.10)
			_add(self, "Corner%d%d" % [sx, sz], corner, Tuning.C_GOLD,
				Vector3(0.46 * float(sx), 0.31, 0.31 * float(sz)))

	_lid = Node3D.new()
	_lid.name = "Lid"
	_lid.position = Vector3(0, 0.62, -0.35)      # hinge at the back edge
	add_child(_lid)
	var lid_mesh := CylinderMesh.new()
	lid_mesh.top_radius = 0.35
	lid_mesh.bottom_radius = 0.35
	lid_mesh.height = 1.0
	lid_mesh.radial_segments = 12
	var lid_mi := _add(_lid, "LidMesh", lid_mesh, Tuning.C_WOOD, Vector3(0, 0, 0.35))
	lid_mi.rotation_degrees = Vector3(0, 0, 90)

	_light = OmniLight3D.new()
	_light.name = "InteriorGlow"
	_light.light_color = Tuning.C_GOLD
	_light.light_energy = 0.0
	_light.omni_range = 3.0
	_light.position = Vector3(0, 0.4, 0)
	add_child(_light)

func _add(parent: Node3D, node_name: String, mesh: Mesh, color: Color,
		pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = CelMaterials.cel(color)
	parent.add_child(mi)
	return mi
