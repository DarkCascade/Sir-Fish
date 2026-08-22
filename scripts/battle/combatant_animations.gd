class_name CombatantAnimations
extends RefCounted
## Dispatches to CombatantSkeletonAnimations for every combatant with a
## skeleton (spec 8.3 / 9.0.2). The shadow monster has no armature (spec
## 20.5, 23.2) - build_for() returns false for it, and its four clips are
## built here directly as TYPE_VALUE tracks on Visual (spec 9.0.2's rest
## composition applies to skeleton bone tracks only, so these are authored
## exactly like the shader-param/method-call tracks the composed clips also
## carry - see that file's own scope table).
##
## Impacts are scheduled by method-call tracks, never by a SceneTreeTimer: a
## call track is a position in the animation, so it scales with speed_scale
## and the visual and the number can never drift (spec 8.7).

const DEG := PI / 180.0

# Impact offsets, in seconds from animation start (spec 9).
const IMPACT_DELAYS := {
	&"warrior":        { "attack": 0.30, "special": 0.25 },
	&"ranger":         { "attack": 0.30, "special": 0.30 },
	&"priest":         { "attack": 0.55, "special": 0.40 },
	&"shadow_monster": { "attack": 0.28, "special": 0.0 },
	&"orc_barbarian":  { "attack": 0.42, "special": 0.0 },
	&"orc_warlord":    { "attack": 0.42, "special": 0.0 },
}

static func build(player: AnimationPlayer, stats: CombatantStats) -> void:
	# Models that ship their own baked action library (the KayKit warrior)
	# take it first; the GDScript-authored clips below/next door only address
	# the in-house rig's bone names. See CombatantBakedAnimations.
	if CombatantBakedAnimations.build_for(player, stats):
		return
	if CombatantSkeletonAnimations.build_for(player, stats):
		return
	assert(stats.id == &"shadow_monster",
		"CombatantAnimations: no builder for '%s'" % stats.id)
	_build_shadow(player)

static func impact_delay(id: StringName, anim: StringName) -> float:
	if not IMPACT_DELAYS.has(id):
		return 0.3
	return float((IMPACT_DELAYS[id] as Dictionary).get(String(anim), 0.3))

# --- track helpers ----------------------------------------------------------

static func _new_anim(length: float, loop: bool) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return a

static func _track(a: Animation, path: String, keys: Array) -> void:
	var t := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t, NodePath(path))
	a.value_track_set_update_mode(t, Animation.UPDATE_CONTINUOUS)
	for k: Array in keys:
		a.track_insert_key(t, float(k[0]), k[1])

## Method-call track on the Combatant node. The AnimationPlayer's root_node is
## Visual, so ".." is the Combatant.
static func _call(a: Animation, time: float, method: StringName, args: Array = []) -> void:
	var t := a.add_track(Animation.TYPE_METHOD)
	a.track_set_path(t, NodePath(".."))
	a.track_insert_key(t, time, { "method": method, "args": args })

static func _z(deg: float) -> Vector3:
	return Vector3(0, 0, deg * DEG)

static func _v(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)

# --- shadow monster (spec 8.3, 9.0.3, 9.4) -----------------------------------

static func _build_shadow(player: AnimationPlayer) -> void:
	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle", _shadow_idle())
	lib.add_animation(&"hurt", _shadow_hurt())
	lib.add_animation(&"die", _shadow_die())
	lib.add_animation(&"attack", _shadow_swipe())
	if player.has_animation_library(&""):
		player.remove_animation_library(&"")
	player.add_animation_library(&"", lib)
	player.speed_scale = 1.0

static func _shadow_idle() -> Animation:
	var a := _new_anim(1.60, true)
	_track(a, ":position", [
		[0.0, _v(0, 0, 0)], [0.4, _v(0, 0.04, 0)], [0.8, _v(0, 0, 0)],
		[1.2, _v(0, -0.04, 0)], [1.6, _v(0, 0, 0)],
	])
	_track(a, ":rotation", [
		[0.0, _z(3)], [0.8, _z(-3)], [1.6, _z(3)],
	])
	_track(a, ":scale", [[0.0, Vector3.ONE]])
	return a

static func _shadow_hurt() -> Animation:
	var a := _new_anim(0.30, false)
	# Knocked backwards, away from the opponent: -X in the shared forward space.
	_track(a, ":position", [[0.0, _v(-0.18, 0, 0)], [0.30, _v(0, 0, 0)]])
	# Positive z tips the head back, which is the recoil (spec 9.0.3).
	_track(a, ":rotation", [[0.0, _z(14)], [0.30, _z(0)]])
	return a

static func _shadow_die() -> Animation:
	# Ends lying on the ground and HOLDS the final pose - never loops, never
	# resets (spec 8.3). The corpse stays down.
	var a := _new_anim(0.80, false)
	_track(a, ":rotation", [[0.0, _z(0)], [0.55, _z(95)], [0.80, _z(88)]])
	_track(a, ":position", [
		[0.0, _v(0, 0, 0)], [0.35, _v(0, 0.14, 0)], [0.80, _v(0, 0.28, 0)],
	])
	_track(a, ":scale", [[0.0, Vector3.ONE]])
	return a

## Spec 9.4. Length 0.60, impact 0.28.
static func _shadow_swipe() -> Animation:
	var a := _new_anim(0.60, false)
	# +0.22 is the sign that reads correctly under the enemy's rotation.y =
	# PI: authored forward is local +X, which under that rotation points AT
	# the heroes.
	_track(a, ":position", [
		[0.0, _v(0, 0, 0)], [0.20, _v(0.22, 0, 0)], [0.36, _v(0.22, 0, 0)],
		[0.60, _v(0, 0, 0)],
	])
	_track(a, ":scale", [
		[0.0, Vector3.ONE], [0.20, _v(1.12, 0.90, 1.12)], [0.36, Vector3.ONE],
	])
	# The body's one shape key (spec 23.2: shape keys + object transforms,
	# since there is no armature). An ordinary TYPE_VALUE property track on
	# a MeshInstance3D's blend_shapes/<name> - not a bone track, so spec
	# 9.0.2's rest composition does not apply. The path is hardcoded since
	# the shadow monster has exactly one model, always: "Rig/Model/ShadowRig/
	# ShadowBody". The extra "ShadowRig" segment is Godot's glTF import
	# nesting the source .glb's own root object one level under the
	# synthetic scene root that becomes "Model" on instancing - the same
	# shape CombatantSkeletonAnimations.SKELETON_PATH relies on for every
	# hero (e.g. "Rig/Model/PriestRig/Skeleton3D").
	_track(a, "Rig/Model/ShadowRig/ShadowBody:blend_shapes/Lunge", [
		[0.0, 0.0], [0.20, 1.0], [0.36, 0.0],
	])
	_call(a, 0.28, &"_anim_impact")
	return a
