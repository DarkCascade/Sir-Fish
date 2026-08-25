class_name CombatantSkeletonAnimations
extends RefCounted
## Builds the six required clips (spec 8.3) directly onto $Visual/AnimationPlayer
## for a hero whose real Blender model has landed under Visual/Rig/Model
## (spec 20.4 / M8b). See QUESTIONS-m8b.md Q2 for why this is GDScript-authored
## rather than a copy of the Blender-baked AnimationLibrary: there is no
## execute_editor_script / execute_game_script tool in this MCP build to pull
## the baked keyframe data out of an imported .glb into editable .tscn text,
## and no tool can assign an existing resource to a node property. The mesh,
## the 17-bone armature and the skinning are still fully Blender-authored;
## only the six clips are typed in here instead of imported.
##
## SPEC 9.0.2 - READ BEFORE TOUCHING A NUMBER BELOW.
## A Skeleton3D bone track (TYPE_ROTATION_3D / TYPE_POSITION_3D) is an
## ABSOLUTE pose, not a delta - it REPLACES the bone's rest transform rather
## than composing with it. Every authored number in spec 9.1-9.5 is a delta
## from the character's modelled rest pose, so every key below is built by
## _bone_rot_key()/_bone_pos_key(), which compose the delta with the bone's
## actual rest transform read live from the imported Skeleton3D. Writing a
## bare degree value or a bare Vector3 straight into a track is the exact bug
## that blocked M8b on the warrior (R12): a small authored delta silently
## replaced the bone's rest orientation instead of offsetting it, so a -20
## degree idle sway rendered as a ~90 degree swing out of the silhouette.

const DEG := PI / 180.0

## The warrior, the ranger and the mage are all absent on purpose: they now
## run on KayKit models (knight.glb, rogue.glb, mage.glb) whose 41-bone
## armature shares no bone name with the in-house rig every clip below is
## keyed against. Their clips come from CombatantBakedAnimations, which
## CombatantAnimations.build() consults first.
static var SKELETON_PATH := {
	&"orc_barbarian": "Rig/Model/OrcRig/Skeleton3D",
	&"orc_warlord": "Rig/Model/OrcRig/Skeleton3D",
}

static func build_for(player: AnimationPlayer, stats: CombatantStats) -> bool:
	if not SKELETON_PATH.has(stats.id):
		return false
	var skel_str: String = SKELETON_PATH[stats.id]
	var visual: Node = player.get_parent()
	var skel := visual.get_node(NodePath(skel_str)) as Skeleton3D
	assert(skel != null, "CombatantSkeletonAnimations: no Skeleton3D at %s" % skel_str)

	var lib := AnimationLibrary.new()
	match stats.id:
		# Enemies take no special (spec 8.3). idle/run/hurt/die are the shared
		# humanoid builders unchanged (spec 9.0.3, R16); attack is the one
		# authored clip and the warlord takes it as-is from the barbarian.
		#
		# [overworld prototype] `run` used to be heroes-only, because the
		# side-on world scrolled past a stationary enemy line and an enemy
		# never travelled. Enemies now sprint in from off the top-right corner
		# (BattleDirector._run_enemy_in), so they need legs. required_anims()
		# still does not DEMAND run of an enemy - the shadow monster floats and
		# has none - it is simply available to those built on this rig.
		&"orc_barbarian", &"orc_warlord":
			lib.add_animation(&"idle", _humanoid_idle(skel, skel_str))
			lib.add_animation(&"run", _humanoid_run(skel, skel_str))
			lib.add_animation(&"attack", _orc_attack(skel, skel_str))
			lib.add_animation(&"hurt", _humanoid_hurt(skel, skel_str))
			lib.add_animation(&"die", _humanoid_die(skel, skel_str))
	if player.has_animation_library(&""):
		player.remove_animation_library(&"")
	player.add_animation_library(&"", lib)
	# The warlord plays SLOWER, not faster (spec 8.7): "heavier" is the
	# stated intent, and speed_scale = 1.15 would make the biggest thing on
	# the battlefield the twitchiest. Matches the placeholder's identical rule.
	player.speed_scale = (1.0 / 1.15) if stats.id == &"orc_warlord" else 1.0
	return true

# --- rest-composing helpers (spec 9.0.2) ---------------------------------

## Screen-plane (spec 9.0) rotation delta, composed on top of a bone's rest
## pose. `world_axis` is expressed in the bone's PARENT space before use, or
## the swing tilts out of the screen plane (a bone's own local axes are
## whatever Blender's bone roll produced, not necessarily screen-aligned).
static func _bone_rot_key_axis(skel: Skeleton3D, bone_idx: int, world_axis: Vector3,
		deg: float) -> Quaternion:
	var rest: Transform3D = skel.get_bone_rest(bone_idx)
	var parent_idx: int = skel.get_bone_parent(bone_idx)
	var parent_basis := Basis()
	if parent_idx >= 0:
		parent_basis = skel.get_bone_global_rest(parent_idx).basis
	var axis: Vector3 = (parent_basis.inverse() * world_axis).normalized()
	var delta := Basis(axis, deg_to_rad(deg))
	return (delta * rest.basis).get_rotation_quaternion()

## The common case - spec 9's "rotation.z" deltas, world +Z being the
## screen-plane axis (spec 9.0).
static func _bone_rot_key(skel: Skeleton3D, bone_idx: int, deg: float) -> Quaternion:
	return _bone_rot_key_axis(skel, bone_idx, Vector3(0.0, 0.0, 1.0), deg)

## World +Y (the up axis) for the rare "turn to face camera" deltas (spec
## 9.1's defend). Never key Vector3.ZERO meaning "neutral" - neutral is
## get_bone_rest(idx).origin, expressed here by composing rather than
## replacing.
static func _bone_rot_key_y(skel: Skeleton3D, bone_idx: int, deg: float) -> Quaternion:
	return _bone_rot_key_axis(skel, bone_idx, Vector3(0.0, 1.0, 0.0), deg)

## Position deltas are relative to rest too, and - by the same logic as
## rotation - `world_delta` must be expressed in the bone's PARENT space
## before it is added, or a depth/forward/up offset authored in screen-space
## terms lands in the wrong direction for any bone whose parent isn't
## world-aligned (every bone except the parentless Root).
static func _bone_pos_key(skel: Skeleton3D, bone_idx: int, world_delta: Vector3) -> Vector3:
	var rest: Transform3D = skel.get_bone_rest(bone_idx)
	var parent_idx: int = skel.get_bone_parent(bone_idx)
	var parent_basis := Basis()
	if parent_idx >= 0:
		parent_basis = skel.get_bone_global_rest(parent_idx).basis
	return rest.origin + parent_basis.inverse() * world_delta

# --- track helpers --------------------------------------------------------

static func _new_anim(length: float, loop: bool) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return a

static func _rot_z(a: Animation, skel: Skeleton3D, skel_str: String, bone: String,
		keys: Array) -> void:
	var idx := skel.find_bone(bone)
	assert(idx >= 0, "no bone '%s'" % bone)
	var t := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(t, NodePath("%s:%s" % [skel_str, bone]))
	for k: Array in keys:
		var time: float = k[0]
		var deg: float = k[1]
		a.rotation_track_insert_key(t, time, _bone_rot_key(skel, idx, deg))

static func _rot_y(a: Animation, skel: Skeleton3D, skel_str: String, bone: String,
		keys: Array) -> void:
	var idx := skel.find_bone(bone)
	assert(idx >= 0, "no bone '%s'" % bone)
	var t := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(t, NodePath("%s:%s" % [skel_str, bone]))
	for k: Array in keys:
		var time: float = k[0]
		var deg: float = k[1]
		a.rotation_track_insert_key(t, time, _bone_rot_key_y(skel, idx, deg))

static func _pos_track(a: Animation, skel: Skeleton3D, skel_str: String, bone: String,
		keys: Array) -> void:
	var idx := skel.find_bone(bone)
	assert(idx >= 0, "no bone '%s'" % bone)
	var t := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(t, NodePath("%s:%s" % [skel_str, bone]))
	for k: Array in keys:
		var time: float = k[0]
		var delta: Vector3 = k[1]
		a.position_track_insert_key(t, time, _bone_pos_key(skel, idx, delta))

## A plain property VALUE track (not a bone track), for the mage's orb
## emission_strength (spec 9.3). Not subject to spec 9.0.2's absolute-pose
## trap - shader parameters are ordinary property assignment, not a bone pose,
## so no rest composition applies here.
static func _shader_param_track(a: Animation, path: String, keys: Array) -> void:
	var t := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t, NodePath(path))
	a.value_track_set_update_mode(t, Animation.UPDATE_CONTINUOUS)
	for k: Array in keys:
		a.track_insert_key(t, k[0], k[1])

## Same mechanism as the shader-param helper above (an ordinary TYPE_VALUE
## track), aliased under a clearer name for the orc's Visual-level
## rotation/position/scale keys - not shader parameters, but not a bone
## track either, so spec 9.0.2's rest composition still does not apply.
static func _value_track(a: Animation, path: String, keys: Array) -> void:
	_shader_param_track(a, path, keys)

## Method-call track on the Combatant node, same convention as
## CombatantAnimations._call - the AnimationPlayer's root_node is Visual, so
## ".." is the Combatant.
static func _call(a: Animation, time: float, method: StringName) -> void:
	var t := a.add_track(Animation.TYPE_METHOD)
	a.track_set_path(t, NodePath(".."))
	a.track_insert_key(t, time, {"method": method, "args": []})

# --- shared humanoid clips (spec 8.3's idle/run/hurt/die - identical numbers
# for every humanoid hero in the pre-M8 procedural rig, carried over unchanged) --

const ARM_R_IDLE := -20.0

static func _humanoid_idle(skel: Skeleton3D, s: String) -> Animation:
	var a := _new_anim(1.60, true)
	_pos_track(a, skel, s, "Root", [
		[0.0, Vector3(0, 0, 0)], [0.4, Vector3(0, 0.04, 0)], [0.8, Vector3(0, 0, 0)],
		[1.2, Vector3(0, -0.04, 0)], [1.6, Vector3(0, 0, 0)],
	])
	_rot_z(a, skel, s, "Root", [[0.0, 3], [0.8, -3], [1.6, 3]])
	_rot_z(a, skel, s, "Arm.R", [[0.0, ARM_R_IDLE], [0.8, -30], [1.6, ARM_R_IDLE]])
	_rot_z(a, skel, s, "Arm.L", [[0.0, 6], [0.8, -4], [1.6, 6]])
	return a

static func _humanoid_run(skel: Skeleton3D, s: String) -> Animation:
	var a := _new_anim(0.70, true)
	_pos_track(a, skel, s, "Root", [
		[0.0, Vector3(0, 0, 0)], [0.175, Vector3(0, 0.09, 0)], [0.35, Vector3(0, 0, 0)],
		[0.525, Vector3(0, 0.09, 0)], [0.70, Vector3(0, 0, 0)],
	])
	_rot_z(a, skel, s, "Root", [[0.0, -6], [0.70, -6]])
	_rot_z(a, skel, s, "Thigh.L", [[0.0, 35], [0.35, -35], [0.70, 35]])
	_rot_z(a, skel, s, "Thigh.R", [[0.0, -35], [0.35, 35], [0.70, -35]])
	_rot_z(a, skel, s, "Arm.L", [[0.0, -30], [0.35, 30], [0.70, -30]])
	_rot_z(a, skel, s, "Arm.R", [[0.0, 30], [0.35, -30], [0.70, 30]])
	return a

static func _humanoid_hurt(skel: Skeleton3D, s: String) -> Animation:
	var a := _new_anim(0.30, false)
	_pos_track(a, skel, s, "Root", [[0.0, Vector3(-0.18, 0, 0)], [0.30, Vector3(0, 0, 0)]])
	_rot_z(a, skel, s, "Root", [[0.0, 14], [0.30, 0]])
	_pos_track(a, skel, s, "Head", [[0.0, Vector3(0, -0.06, 0)], [0.30, Vector3(0, 0, 0)]])
	return a

static func _humanoid_die(skel: Skeleton3D, s: String) -> Animation:
	var a := _new_anim(0.80, false)
	_rot_z(a, skel, s, "Root", [[0.0, 0], [0.55, 95], [0.80, 88]])
	_pos_track(a, skel, s, "Root", [
		[0.0, Vector3(0, 0, 0)], [0.35, Vector3(0, 0.14, 0)], [0.80, Vector3(0, 0.28, 0)],
	])
	_rot_z(a, skel, s, "Arm.L", [[0.0, 0], [0.80, -40]])
	_rot_z(a, skel, s, "Arm.R", [[0.0, ARM_R_IDLE], [0.80, -25]])
	return a

# --- orc barbarian / orc warlord (spec 9.5) ---------------------------------

## Shared by both orcs (spec 9.0.3, R16) - the warlord takes this unchanged
## and differs only via speed_scale, model_scale and colour (spec 8.7, A3).
## The Visual-level rotation/position/scale keys are ordinary TYPE_VALUE
## tracks, exactly as in the placeholder: spec 9.0.2's rest composition is
## scoped to skeleton bone tracks only (its own scope table) and does not
## apply to Visual itself.
static func _orc_attack(skel: Skeleton3D, s: String) -> Animation:
	var a := _new_anim(0.85, false)
	_rot_z(a, skel, s, "Arm.R", [
		[0.0, ARM_R_IDLE], [0.28, -120], [0.48, 95], [0.68, 60], [0.85, ARM_R_IDLE],
	])
	_rot_z(a, skel, s, "Arm.L", [
		[0.0, 0], [0.28, -120], [0.48, 95], [0.68, 55], [0.85, 0],
	])
	_value_track(a, ":rotation", [
		[0.0, Vector3(0, 0, 0)], [0.28, Vector3(0, 0, deg_to_rad(12))],
		[0.48, Vector3(0, 0, deg_to_rad(-18))], [0.68, Vector3(0, 0, deg_to_rad(4))],
		[0.85, Vector3(0, 0, 0)],
	])
	_value_track(a, ":position", [
		[0.0, Vector3(0, 0, 0)], [0.28, Vector3(0, 0.06, 0)], [0.48, Vector3(0.20, 0, 0)],
		[0.68, Vector3(-0.04, 0, 0)], [0.85, Vector3(0, 0, 0)],
	])
	_value_track(a, ":scale", [
		[0.0, Vector3.ONE], [0.48, Vector3(0.92, 1.10, 0.92)], [0.68, Vector3.ONE],
	])
	_call(a, 0.42, &"_anim_impact")
	return a
