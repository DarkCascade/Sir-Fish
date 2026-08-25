extends RefCounted
## Sir Fish's modelled rig support (spec 17.7 / 23.5, M8a).
##
## The body, helm and seven reaction clips are authored in Blender and swapped
## in as res://assets/meshes/sir_fish.glb (see sir_fish_tank.tscn's "Model"
## child of SirFish). This file now only does the one thing the swap still needs
## from code: turning off shadow casting on the fish's meshes (it sits in its
## own viewport with its own light, spec 17.7). The fish renders in the colours
## its own .glb carries.
##
## [move-elements-to-editor] build_bubbles() is gone - the burst is an authored
## GPUParticles3D in sir_fish_tank.tscn, under SirFish.

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
