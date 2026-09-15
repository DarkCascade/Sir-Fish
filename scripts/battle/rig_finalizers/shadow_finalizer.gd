extends RefCounted
## RigProfile.finalizer for shadow_monster - a translucent smoke material the
## .glb does not carry, plus the eyes and smoke-wisp particles, which have no
## Blender equivalent and are added here as plain child nodes rather than
## baked into the imported mesh.
##
## [KayKit Rig_Medium rework] shadow_monster moved from a shape-key blob with
## no armature onto the same character_pipeline route as the other humanoid
## enemies (bandit_officer etc.) - a real bipedal Skeleton3D, BAKED clips off
## Rig_Medium, standard DEFAULT_SCENE_TRANSFORM (no more per-scene position
## hack). The smoke-material loop below is unchanged by that move - it was
## already generic over every MeshInstance3D under "Model" - but the eye and
## wisp positions were tuned for the old blob's proportions and are retuned
## here for the humanoid's actual head height (measured off the built glb's
## head-weighted vertices: Blender z 1.22-2.20, scaled by the scene's 0.85).
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
	# separate across Z.
	#
	# y is head height on the humanoid rig: the built glb's head-weighted
	# vertices span Blender z 1.22-2.20 (bone rest data, scratch/character_
	# pipeline/shadow_monster/shadow_monster_built.blend), and Model's own
	# scene transform scales that by 0.85 - an eye-band roughly 45% up the
	# head puts y around 1.4. x/z are a modest fraction of the head's own
	# half-width/half-depth (~0.44/0.43 in that same raw frame) so the eyes
	# sit on the face rather than at its rim.
	e.position = Vector3(0.16, 1.40, 0.09 * float(side))
	e.material_override = CelMaterials.cel(
		Tuning.C_SHADOW_EYES, Tuning.C_SHADOW_EYES, 3.0, 0.0)
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return e

func _smoke_wisps() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "SmokeWisps"
	p.amount = 24
	p.lifetime = 1.4
	# Torso height on the humanoid rig, not the old blob's centre - the
	# emission sphere below still reaches from about the waist up past the
	# head, same as it did on the blob.
	p.position = Vector3(0, 0.95, 0)
	p.local_coords = true

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.45
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
