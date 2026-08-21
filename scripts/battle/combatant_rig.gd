class_name CombatantRig
extends RefCounted
## Reassigns materials on a combatant's Blender-imported model under
## Visual/Rig/Model (spec 8.2b, 20.4/20.5 - M8a-M8c). All six combatants now
## have a real model, so this file no longer builds anything from Godot
## primitives; `build()` is a materials-only pass, safe to redo on every
## setup() call.
##
## Idempotency guard on the generic path is load-bearing, not decorative:
## Combatant.setup() calls _build() unconditionally on every encounter (not
## just the first), so this runs again on an already-finalized model.
## Without the guard, the second pass reads mi.get_active_material(0), which
## by then returns the FIRST pass's own cel ShaderMaterial override rather
## than the original imported StandardMaterial3D - so the real albedo is
## gone and every part goes white (spec 8.2b.2, R18).

static func build(rig: Node3D, stats: CombatantStats) -> void:
	# The shadow monster's body is the one surface that is not cel-shaded at
	# all: spec 6.2 is explicit that its translucent smoke material has no
	# inverted-hull next_pass to depth-test against, so the generic
	# cel-reassignment loop below would be actively wrong for it. This is
	# the same art-construction exemption category as the priest's orb
	# branch further down (spec 4.1) - it dispatches and returns instead of
	# falling through, because nothing about the generic loop applies.
	if stats.id == &"shadow_monster":
		_finalize_shadow(rig, stats)
		return

	# The orc pair shares one mesh, one armature and one action set (spec
	# 20.5, A3) - the warlord differs only by model_scale, colours,
	# shoulder pads and speed_scale, none of which the .glb can encode
	# since it is the SAME .glb for both characters. Colour therefore has
	# to come from CombatantStats at runtime here, unlike every other
	# character below, where the generic loop reads the colour the .glb
	# already carries. Reading albedo from the .glb for orcs would give
	# the warlord the barbarian's colours.
	if stats.id == &"orc_barbarian" or stats.id == &"orc_warlord":
		_finalize_orc(rig, stats)
		return

	for mi: MeshInstance3D in CelMaterials._all_mesh_instances(rig):
		var existing := mi.material_override
		if existing is ShaderMaterial and (existing as ShaderMaterial).shader == CelMaterials.CEL_SHADER:
			continue
		var albedo := Color.WHITE
		var src := mi.get_active_material(0)
		if src is BaseMaterial3D:
			albedo = (src as BaseMaterial3D).albedo_color
		mi.material_override = CelMaterials.cel(albedo)

	# The priest's orb is the one real-model surface that needs emission
	# (spec 9.3's charge glow, animated 1.5 -> 5.0 by CombatantSkeletonAnimations
	# via a plain shader-parameter value track, not a bone track). This is a
	# one-off art-construction detail on the finished model, not a combat
	# branch, so it is exempted from spec 4.1's standing rule.
	if stats.id == &"priest":
		var orb := _find_by_name(rig, "P_Orb") as MeshInstance3D
		if orb != null:
			var existing := orb.material_override
			if not (existing is ShaderMaterial
					and (existing as ShaderMaterial).get_shader_parameter("emission_strength") != null
					and (existing as ShaderMaterial).get_shader_parameter("emission_strength") > 0.0):
				orb.material_override = CelMaterials.cel(Tuning.C_PRIEST_ACCENT, Tuning.C_PRIEST_ACCENT, 1.5)

static func _find_by_name(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child: Node in node.get_children():
		var found := _find_by_name(child, node_name)
		if found != null:
			return found
	return null

# --- orc barbarian / orc warlord --------------------------------------------

## Runtime colouring for the shared orc asset (spec 20.5). Unlike the
## generic loop above, this never reads the imported material - every value
## comes from `stats` or a fixed Tuning constant, so it is idempotent by
## construction: there is nothing on the node itself for a second setup()
## call to read back incorrectly (spec 8.2b.2's trap was specifically about
## reading a material the FIRST pass had already overwritten; this never
## reads the node's own material at all).
static func _finalize_orc(rig: Node3D, stats: CombatantStats) -> void:
	var body := stats.body_color
	var accent := stats.accent_color
	_recolor(rig, "O_Torso", body)
	_recolor(rig, "O_Head", body)
	_recolor(rig, "O_TuskL", accent)
	_recolor(rig, "O_TuskR", accent)
	_recolor(rig, "O_ArmL", accent)
	_recolor(rig, "O_ArmR", accent)
	_recolor(rig, "O_LegL", body.darkened(0.25))
	_recolor(rig, "O_LegR", body.darkened(0.25))
	_recolor(rig, "O_WeaponHaft", Tuning.C_WOOD_DARK)
	_recolor(rig, "O_WeaponHead", Tuning.C_ORC_IRON)

	# Shoulder pads have no Blender equivalent (spec A3: "no new asset") -
	# procedural, same category as the shadow monster's eyes. Guarded for
	# idempotency the same way (spec 8.2b.2): a second setup() call must not
	# add a second pair.
	if stats.id == &"orc_warlord" and _find_by_name(rig, "ShoulderPadL") == null:
		_box(rig, "ShoulderPadL", Vector3(0.30, 0.16, 0.30), Vector3(-0.34, 1.34, 0), Tuning.C_GOLD)
		_box(rig, "ShoulderPadR", Vector3(0.30, 0.16, 0.30), Vector3(0.34, 1.34, 0), Tuning.C_GOLD)

static func _recolor(rig: Node3D, part_name: String, color: Color) -> void:
	var mi := _find_by_name(rig, part_name) as MeshInstance3D
	if mi != null:
		mi.material_override = CelMaterials.cel(color)

# --- shadow monster ---------------------------------------------------------

## The real model (spec 20.5 / M8c) has no armature - its body mesh keeps
## the translucent smoke material instead of the cel + outline pairing (spec
## 6.2, 8.6), so it is reassigned here rather than by the generic cel loop
## above, which would be actively wrong for it. The eyes and the smoke-wisp
## particles have no Blender equivalent - they are added here as plain
## child nodes rather than baked into the imported mesh.
##
## Idempotency guards mirror the generic loop's (spec 8.2b.2): setup()
## calls this on every encounter. The smoke-material loop is scoped to the
## imported "Model" subtree only, not all of `rig` - eyes and wisps are
## siblings of Model, not descendants of it, so scoping to `rig` instead
## would catch them too and stomp the eyes' cel material with smoke on the
## second pass.
static func _finalize_shadow(rig: Node3D, stats: CombatantStats) -> void:
	var model := rig.get_node_or_null("Model")
	if model != null:
		for mi: MeshInstance3D in CelMaterials._all_mesh_instances(model):
			var existing := mi.material_override
			if existing is ShaderMaterial and (existing as ShaderMaterial).shader == CelMaterials.SMOKE_SHADER:
				continue
			mi.material_override = CelMaterials.smoke(stats.body_color)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if _find_by_name(rig, "EyeL") == null:
		rig.add_child(_shadow_eye(-1))
		rig.add_child(_shadow_eye(1))

	if _find_by_name(rig, "SmokeWisps") == null:
		rig.add_child(_smoke_wisps())

static func _shadow_eye(side: int) -> MeshInstance3D:
	var eye := SphereMesh.new()
	eye.radius = 0.055
	eye.height = 0.11
	eye.radial_segments = 8
	eye.rings = 5
	var e := MeshInstance3D.new()
	e.name = "Eye%s" % ("L" if side < 0 else "R")
	e.mesh = eye
	e.position = Vector3(0.16 * float(side), 1.18, 0.44)
	e.material_override = CelMaterials.cel(
		Tuning.C_SHADOW_EYES, Tuning.C_SHADOW_EYES, 3.0, 0.0)
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return e

static func _smoke_wisps() -> GPUParticles3D:
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

# --- primitive helpers -------------------------------------------------------
## Only the orc's procedural shoulder pads still use these (via _box/_mesh).

static func _mesh(parent: Node3D, node_name: String, mesh: Mesh, color: Color,
		pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = CelMaterials.cel(color)
	parent.add_child(mi)
	return mi

static func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3,
		color: Color) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mesh(parent, node_name, m, color, pos)
