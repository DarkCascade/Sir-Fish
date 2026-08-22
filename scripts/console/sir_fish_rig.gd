extends RefCounted
## Sir Fish's modelled rig support (spec 17.7 / 23.5, M8a).
##
## The body, helm and seven reaction clips are authored in Blender and swapped
## in as res://assets/meshes/sir_fish.glb (see sir_fish_tank.tscn's "Model"
## child of SirFish). This file now only does the two things the swap still
## needs from code: turning off shadow casting on the fish's meshes (it sits
## in its own viewport with its own light, spec 17.7) and building the bubble
## burst particle system, which is gameplay VFX and was never part of the mesh.
## The fish renders in the colours its own .glb carries.

## Turns off shadow casting on every MeshInstance3D under `model`.
static func reassign_materials(model: Node) -> void:
	for mi: MeshInstance3D in _all_mesh_instances(model):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _all_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root as MeshInstance3D)
	for child: Node in root.get_children():
		out.append_array(_all_mesh_instances(child))
	return out

## Same particle burst the placeholder used - a one-shot fizz of bubbles for
## cheer/triumph (spec 17.7). Not part of the mesh; built here every time.
static func build_bubbles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Bubbles"
	p.amount = 14
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.8
	p.emitting = false
	p.position = Vector3(0.16, 0.10, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.06
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 20.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0, 1.2, 0)
	pm.scale_min = 1.0
	pm.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.33))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.5))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 3
	p.draw_pass_1 = mesh
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	p.material_override = sm
	return p
