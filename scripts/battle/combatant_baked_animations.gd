class_name CombatantBakedAnimations
extends RefCounted
## Retargets the animation clips a character's .glb already ships with onto
## $Visual/AnimationPlayer, under the six names spec 8.3 requires
## (idle/run/attack/special/hurt/die).
##
## This is the path for third-party models that arrive with a baked action
## library - the KayKit warrior (knight.glb) was the first, joined by the
## KayKit ranger (rogue.glb), the KayKit mage (mage.glb) and the four KayKit
## skeletons. It replaces, for those characters only, the GDScript-authored
## clips in CombatantSkeletonAnimations: those are keyed against the old
## in-house 17-bone rig (Root / Arm.R / Thigh.L ...) and cannot address a
## 41-bone KayKit armature (root / upperarm.r / upperleg.l ...) at all.
## Characters still on the in-house rig keep using that file unchanged - see
## CombatantAnimations.build() for the dispatch, now driven by
## CombatantStats.rig_profile.source rather than a try-each-builder chain.
##
## [content phase 0] The per-character CLIPS table moved to data -
## RigProfile.clips, one resource per character (spec §3 Step 3). This file
## keeps only the retarget MECHANISM: track re-rooting and length-rescaling,
## neither of which is expressible as plain data.
##
## Two things have to be fixed up on the way across, and both are the reason
## this cannot be a plain `player.add_animation_library(src.get_animation_library(""))`:
##
## 1. TRACK PATHS. A clip inside the .glb is authored relative to the .glb's
##    own AnimationPlayer root (paths like "Rig:hips"). Ours lives on Visual,
##    which is two nodes higher, so every track path is re-rooted through the
##    live `visual.get_path_to(imported_root)` rather than a hardcoded prefix -
##    the .glb's internal node names are the importer's business, not ours.
##
## 2. LENGTH. Spec 5.2's "real cycle" is attack_cooldown + the action's
##    animation length, so a clip's duration is a balance number, not an art
##    one. Each RigProfile clip entry states the length the combat loop was
##    tuned for and the key times are scaled to hit it, instead of letting
##    KayKit's authored durations quietly re-tune the fight.
##
## Impacts stay on method-call tracks for the reason CombatantAnimations
## documents: a call track is a position *in* the animation, so it survives
## speed_scale and can never drift from the visual.

static func build(player: AnimationPlayer, profile: RigProfile) -> void:
	var visual: Node = player.get_parent()
	var rig: Node = visual.get_node_or_null(^"Rig")
	assert(rig != null, "CombatantBakedAnimations: no Rig node under Visual")
	var src := _find_player(rig)
	assert(src != null,
		"CombatantBakedAnimations: no imported AnimationPlayer under Visual/Rig")
	if src == null:
		return
	var src_root: Node = src.get_node(src.root_node)
	var prefix := String(visual.get_path_to(src_root))

	var lib := AnimationLibrary.new()
	var specs := profile.resolved_clips()
	for anim_name: Variant in specs:
		var spec: Dictionary = specs[anim_name]
		var source_name: String = spec["clip"]
		assert(src.has_animation(source_name),
			"CombatantBakedAnimations: source player has no clip '%s'" % source_name)
		if not src.has_animation(source_name):
			continue
		lib.add_animation(StringName(anim_name), _retarget(src.get_animation(source_name), prefix, spec))
	if player.has_animation_library(&""):
		player.remove_animation_library(&"")
	player.add_animation_library(&"", lib)

## The imported AnimationPlayer sits inside the .glb instance under
## Visual/Rig/Model. Found by search rather than by path for the same reason
## the track prefix is: the node names inside the .glb belong to the importer.
static func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null

static func _retarget(source: Animation, prefix: String, spec: Dictionary) -> Animation:
	var a: Animation = source.duplicate(true)
	var target_length: float = spec["length"]
	var factor := 1.0
	if a.length > 0.0:
		factor = target_length / a.length

	for t: int in a.get_track_count():
		a.track_set_path(t, NodePath("%s/%s" % [prefix, a.track_get_path(t)]))
		if is_equal_approx(factor, 1.0):
			continue
		# Key times must be rewritten in the direction that keeps them
		# monotonic as they move: shrinking, each key lands before where it
		# was (walk forward); stretching, after (walk backward). Rewriting a
		# key past its neighbour re-sorts the track and the next index no
		# longer refers to the key we think it does.
		var count := a.track_get_key_count(t)
		if factor < 1.0:
			for k: int in count:
				a.track_set_key_time(t, k, a.track_get_key_time(t, k) * factor)
		else:
			for k: int in range(count - 1, -1, -1):
				a.track_set_key_time(t, k, a.track_get_key_time(t, k) * factor)

	a.length = target_length
	a.loop_mode = Animation.LOOP_LINEAR if spec.get("loop", false) else Animation.LOOP_NONE
	if spec.has("cast"):
		_call(a, float(spec["cast"]), &"_anim_special_cast")
	if spec.has("charge"):
		_call(a, float(spec["charge"]), &"_anim_charge")
	if spec.has("impact"):
		_call(a, float(spec["impact"]), &"_anim_impact")
	if spec.has("glow_node"):
		# Same curve the in-house mage clip hardcoded: a resting glow that
		# charges up through the telegraph and falls back once the beat
		# resolves (spec 9.3). This is authored fresh, not sourced from the
		# .glb, so it is built directly in target-time units - nothing here
		# goes through the length-scaling factor above.
		_shader_param_track(a,
			"%s/%s:material_override:shader_parameter/emission_strength" % [prefix, spec["glow_node"]],
			[[0.0, 1.5], [0.30, 5.0], [float(spec["impact"]), 5.0], [target_length, 1.5]])
	return a

## Method-call track on the Combatant node - same convention as
## CombatantAnimations._call: the AnimationPlayer's root_node is Visual, so
## ".." is the Combatant.
static func _call(a: Animation, time: float, method: StringName) -> void:
	var t := a.add_track(Animation.TYPE_METHOD)
	a.track_set_path(t, NodePath(".."))
	a.track_insert_key(t, time, { "method": method, "args": [] })

## Same mechanism as CombatantSkeletonAnimations._shader_param_track - an
## ordinary TYPE_VALUE track, aliased under a clearer name since it targets a
## shader parameter rather than a bone.
static func _shader_param_track(a: Animation, path: String, keys: Array) -> void:
	var t := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t, NodePath(path))
	a.value_track_set_update_mode(t, Animation.UPDATE_CONTINUOUS)
	for k: Array in keys:
		a.track_insert_key(t, k[0], k[1])
