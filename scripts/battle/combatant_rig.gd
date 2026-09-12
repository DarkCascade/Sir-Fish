class_name CombatantRig
extends RefCounted
## Per-character material work on a combatant's Blender-imported model under
## Visual/Rig/Model (spec 8.2b, 20.5 - M8a-M8c). All six combatants have a
## real model, so this file builds nothing from Godot primitives; `build()`
## is a materials-only pass, safe to redo on every setup() call.
##
## [content phase 0] The `if stats.id ==` chain is gone (spec §3 Step 3).
## Hiding surplus prop meshes is now pure data - RigProfile.hidden_parts - and
## the genuinely procedural finishing work (the shadow monster's smoke
## material + eyes + wisps, the orc pair's runtime recolour + warlord shoulder
## pads, the mage staff's emissive baseline) lives in a RigProfile.finalizer
## script under scripts/battle/rig_finalizers/, reached through data instead
## of an id branch.

static func build(rig: Node3D, stats: CombatantStats) -> void:
	var profile := stats.rig_profile
	if profile == null:
		return
	for part_name: String in profile.hidden_parts:
		var mi := find_by_name(rig, part_name) as MeshInstance3D
		if mi != null:
			mi.visible = false
	if profile.finalizer != null:
		profile.finalizer.new().apply(rig, stats)

## Public so a RigProfile.finalizer script (scripts/battle/rig_finalizers/)
## can reuse the same name-search lookup rather than duplicating it.
static func find_by_name(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child: Node in node.get_children():
		var found := find_by_name(child, node_name)
		if found != null:
			return found
	return null

# --- primitive helpers -------------------------------------------------------
## Only the orc warlord's procedural shoulder pads still use these.

static func add_mesh(parent: Node3D, node_name: String, mesh: Mesh, color: Color,
		pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = CelMaterials.cel(color)
	parent.add_child(mi)
	return mi

static func add_box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3,
		color: Color) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return add_mesh(parent, node_name, m, color, pos)
