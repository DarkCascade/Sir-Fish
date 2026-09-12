extends RefCounted
## RigProfile.finalizer for shadow_monster (content-phase-0 spec §3 Step 3) -
## the genuinely procedural half of the old CombatantRig._finalize_shadow():
## a translucent smoke material the .glb does not carry, plus the eyes and
## smoke-wisp particles, which have no Blender equivalent and are added here
## as plain child nodes rather than baked into the imported mesh.
##
## [overworld prototype] shadow_monster.tscn also gives Model a +0.9075 Z
## offset. The .glb's body mesh is authored 0.9 units off its own origin
## (Blender Y = +0.907 on ShadowBody), which a side-on orthographic camera
## could not show - the offset ran straight into the screen. Under the
## overhead camera it puts the blob a metre to one side of its own health bar,
## its hit anchor, and the point melee attackers blink to. The offset is
## corrected on the node rather than in the .glb so the imported asset stays
## byte-identical to what Blender exports.
##
## Idempotency guards mirror the generic loop's (spec 8.2b.2): setup() calls
## this on every encounter. The smoke-material loop is scoped to the imported
## "Model" subtree only, not all of `rig` - eyes and wisps are siblings of
## Model, not descendants of it, so scoping to `rig` instead would catch them
## too and stomp the eyes' cel material with smoke on the second pass.

func apply(rig: Node3D, stats: CombatantStats) -> void:
	var model := rig.get_node_or_null("Model")
	if model != null:
		for mi: MeshInstance3D in CelMaterials._all_mesh_instances(model):
			var existing := mi.material_override
			if existing is ShaderMaterial and (existing as ShaderMaterial).shader == CelMaterials.SMOKE_SHADER:
				continue
			mi.material_override = CelMaterials.smoke(stats.body_color)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if CombatantRig.find_by_name(rig, "EyeL") == null:
		rig.add_child(_shadow_eye(-1))
		rig.add_child(_shadow_eye(1))

	if CombatantRig.find_by_name(rig, "SmokeWisps") == null:
		rig.add_child(_smoke_wisps())

func _shadow_eye(side: int) -> MeshInstance3D:
	var eye := SphereMesh.new()
	eye.radius = 0.055
	eye.height = 0.11
	eye.radial_segments = 8
	eye.rings = 5
	var e := MeshInstance3D.new()
	e.name = "Eye%s" % ("L" if side < 0 else "R")
	e.mesh = eye
	# Forward is +X (see Tuning.yaw_along), so the eyes sit forward on X and
	# separate across Z. They were authored on the old side-on convention,
	# where an enemy only ever turned 180 degrees and a 90-degree error never
	# showed; under the overhead camera a combatant faces any direction, so a
	# blob whose eyes point off its own shoulder is immediately visible.
	#
	# y is 0.30, not the authored 1.18: the .glb body only reaches y = 0.58, so
	# the old height left the eyes hovering in clear air above the blob. This
	# puts them on its front surface (the body's radius is about 0.58, and
	# (0.42, 0.30, 0.17) has length 0.55).
	e.position = Vector3(0.42, 0.30, 0.17 * float(side))
	e.material_override = CelMaterials.cel(
		Tuning.C_SHADOW_EYES, Tuning.C_SHADOW_EYES, 3.0, 0.0)
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return e

func _smoke_wisps() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "SmokeWisps"
	p.amount = 24
	p.lifetime = 1.4
	p.position = Vector3(0, 1.0, 0)
	p.local_coords = true

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0, 0.4, 0)
	pm.scale_min = 0.10
	pm.scale_max = 0.10
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct

	var ramp := Gradient.new()
	ramp.set_color(0, Color(Tuning.C_SHADOW_BODY, 0.7))
	ramp.set_color(1, Color(Tuning.C_SHADOW_BODY, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	p.process_material = pm

	var draw := SphereMesh.new()
	draw.radius = 0.5
	draw.height = 1.0
	draw.radial_segments = 8
	draw.rings = 4
	p.draw_pass_1 = draw
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Tuning.C_SHADOW_BODY
	p.material_override = dm
	return p
