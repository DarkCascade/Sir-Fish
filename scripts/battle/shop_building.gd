extends Node3D
## The shop encounter's building (spec 14.3). Same pop-in tween as the chest.

func _ready() -> void:
	_build()

func pop_in() -> void:
	scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 1.15, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3.ONE, 0.15)
	BattleVfx.dust_puff_at(global_position, 14)

func fade_out() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

func _build() -> void:
	var walls := BoxMesh.new()
	walls.size = Vector3(2.0, 1.6, 1.4)
	_add("Walls", walls, Tuning.C_PRIEST_CLOTH, Vector3(0, 0.8, 0))

	var roof := PrismMesh.new()
	roof.size = Vector3(2.4, 1.0, 1.6)
	_add("Roof", roof, Tuning.C_WARRIOR_ACCENT, Vector3(0, 2.1, 0))

	var door := BoxMesh.new()
	door.size = Vector3(0.6, 1.0, 0.1)
	_add("Door", door, Tuning.C_WOOD, Vector3(0, 0.5, 0.72))

	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(0.9, 0.4, 0.06)
	_add("Sign", sign_mesh, Tuning.C_GOLD, Vector3(0, 1.35, 0.76))

	var glow := OmniLight3D.new()
	glow.name = "WindowGlow"
	glow.light_color = Tuning.C_GOLD
	glow.light_energy = 2.0
	glow.omni_range = 2.5
	glow.position = Vector3(0.6, 1.0, 0.6)
	add_child(glow)

func _add(node_name: String, mesh: Mesh, color: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = CelMaterials.cel(color)
	add_child(mi)
