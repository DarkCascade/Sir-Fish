extends Node3D
## The loot encounter's chest (spec 14.2). Pops in, beats, then opens with the
## full juice list.
##
## [move-elements-to-editor] Body, the four corner straps, the Lid and
## InteriorGlow are authored in treasure_chest.tscn - meshes, cel materials and
## offsets are inspector-editable there. The hinge is Lid's own position (the
## body's back edge), so open() only has to swing Lid.rotation:x.
##
## The coin shower and the radial flash stay in code: both are transient, are
## spawned in numbers and tween themselves away, so there is nothing for the
## editor to hold.

signal opened()

@onready var _lid: Node3D = $Lid
@onready var _light: OmniLight3D = $InteriorGlow

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
