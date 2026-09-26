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
	apply_hand_props(rig, stats)
	if profile.finalizer != null:
		profile.finalizer.new().apply(rig, stats)

# --- [backlog P3b, issue #77] equipped items show in hand -----------------------

## Props that ship on no hero .glb, instanced onto the hand the first time they
## are wanted. The Adventurers 2.0 pack's meshes share the 1.x props' authoring
## frame exactly (the pack's sword_1handed has the knight's 1H_Sword's vertex
## bounds to the float), so an external prop copies the local transform of the
## native prop named in `like`.
const EXTERNAL_PROPS := {
	"axe_1handed": { "scene": preload("res://assets/meshes/props/axe_1handed.gltf"), "like": "1H_Sword" },
}

## The KayKit BoneAttachment3Ds, as Godot names them on import (`handslot.r`).
const HAND_SLOTS: Array[String] = ["handslot_r", "handslot_l"]

## Shows the equipped weapon's `prop` in the right hand and the armor's in the
## left, and hides every other prop on either hand. A two-handed weapon empties
## the left hand. Heroes only: an enemy keeps whatever its .glb and
## RigProfile.hidden_parts give it. Cheap enough to redo on every equipment
## change (Combatant.apply_party_bonuses() calls it again).
static func apply_hand_props(rig: Node3D, stats: CombatantStats) -> void:
	if not stats.is_hero:
		return
	var wanted: Array[String] = []
	var weapon := GameState.equipped_item(stats.id, Item.Slot.WEAPON)
	var weapon_row: Dictionary = Itemizer.ITEM_TYPES.get(weapon.weapon_type, {}) if weapon != null else {}
	if weapon_row.has("prop"):
		wanted.append(String(weapon_row["prop"]))
	if not bool(weapon_row.get("two_handed", false)):
		var armor := GameState.equipped_item(stats.id, Item.Slot.ARMOR)
		var armor_row: Dictionary = Itemizer.ITEM_TYPES.get(armor.weapon_type, {}) if armor != null else {}
		if armor_row.has("prop"):
			wanted.append(String(armor_row["prop"]))
	for prop: String in wanted:
		_ensure_external_prop(rig, prop)
	for slot_name: String in HAND_SLOTS:
		var hand := find_by_name(rig, slot_name)
		if hand == null:
			continue
		for child: Node in hand.get_children():
			if child is Node3D:
				(child as Node3D).visible = wanted.has(String(child.name))

static func _ensure_external_prop(rig: Node3D, prop: String) -> void:
	if not EXTERNAL_PROPS.has(prop) or find_by_name(rig, prop) != null:
		return
	var like := find_by_name(rig, String(EXTERNAL_PROPS[prop]["like"])) as Node3D
	if like == null:
		return
	var inst := (EXTERNAL_PROPS[prop]["scene"] as PackedScene).instantiate() as Node3D
	inst.name = prop
	like.get_parent().add_child(inst)
	inst.transform = like.transform

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
