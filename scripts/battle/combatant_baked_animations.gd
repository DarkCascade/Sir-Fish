class_name CombatantBakedAnimations
extends RefCounted
## Retargets the animation clips a character's .glb already ships with onto
## $Visual/AnimationPlayer, under the six names spec 8.3 requires
## (idle/run/attack/special/hurt/die).
##
## This is the path for third-party models that arrive with a baked action
## library - the KayKit warrior (knight.glb) was the first, joined by the
## KayKit ranger (rogue.glb) and the KayKit mage (mage.glb). It replaces, for
## those characters only, the GDScript-authored clips in
## CombatantSkeletonAnimations: those are keyed against the old in-house
## 17-bone rig (Root / Arm.R / Thigh.L ...) and cannot address a 41-bone
## KayKit armature (root / upperarm.r / upperleg.l ...) at all. Characters
## still on the in-house rig keep using that file unchanged - see
## CombatantAnimations.build() for the dispatch order. Every KayKit
## Adventurers character shares one animation library regardless of which
## variant .glb it ships in, so warrior, ranger and mage all draw clips from
## the same name pool below even though they are three different files.
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
##    one. Each entry below states the length the combat loop was tuned for
##    and the key times are scaled to hit it, instead of letting KayKit's
##    authored durations quietly re-tune the fight.
##
## Impacts stay on method-call tracks for the reason CombatantAnimations
## documents: a call track is a position *in* the animation, so it survives
## speed_scale and can never drift from the visual.

## clip      - the animation name inside the .glb.
## length    - the retargeted clip's duration in seconds (spec 5.2, above).
## loop      - LOOP_LINEAR vs LOOP_NONE.
## impact    - time of the _anim_impact call track, omitted for clips that
##             resolve nothing.
## cast      - time of the _anim_special_cast telegraph flash (spec 9.6).
## charge    - time of the _anim_charge telegraph call (mage primary only;
##             spec 9.3 / Ability.charge() - gated on stats.telegraphs_primary,
##             which is only ever true for the mage).
## glow_node - path to a MeshInstance3D, RELATIVE TO THE IMPORTED ROOT (not
##             just a bare name - the value track needs an exact NodePath, unlike
##             CombatantRig's name-search lookups), to drive an emission_strength
##             value track on: 1.5 -> 5.0 -> 1.5 across [0.0, 0.30, impact,
##             length] (spec 9.3's charge glow). Requires "impact". The
##             mage's staff is the only user - see
##             CombatantRig._finalize_mage for the baseline material.
const CLIPS := {
	&"mage": {
		&"idle":    { "clip": "Idle", "length": 1.60, "loop": true },
		&"run":     { "clip": "Running_A", "length": 0.70, "loop": true },
		# Spellcast_Shoot's authored 0.93s needs almost no retargeting to reach
		# either target length, so the cast/release pose survives intact rather
		# than being visibly sped up or slowed down. Length and impact are the
		# in-house rig's _mage_cast() numbers unchanged (spec 9.3), so the
		# real cycle and every VFX/telegraph timing keyed off them are
		# unaffected by the model swap.
		&"attack":  { "clip": "Spellcast_Shoot", "length": 0.95, "loop": false,
			"impact": 0.55, "charge": 0.30, "glow_node": "Rig/Skeleton3D/handslot_r/2H_Staff" },
		&"special": { "clip": "Spellcast_Shoot", "length": 0.85, "loop": false,
			"impact": 0.40, "cast": 0.0, "glow_node": "Rig/Skeleton3D/handslot_r/2H_Staff" },
		&"hurt":    { "clip": "Hit_A", "length": 0.30, "loop": false },
		&"die":     { "clip": "Death_A", "length": 0.80, "loop": false },
	},
	&"ranger": {
		&"idle":    { "clip": "Idle", "length": 1.60, "loop": true },
		&"run":     { "clip": "Running_A", "length": 0.70, "loop": true },
		# Both attack and special use the same draw/release clip (spec 9.2) - the
		# bomb-arrow telegraph and impact are handled entirely by the
		# projectile/Ability system, not by which pose plays. Length 0.80,
		# impact 0.30: identical to the in-house rig's _ranger_shot() this
		# replaces, so the real cycle (spec 5.2) and every VFX timing keyed off
		# it are unaffected by the model swap.
		&"attack":  { "clip": "1H_Ranged_Shoot", "length": 0.80, "loop": false,
			"impact": 0.30 },
		&"special": { "clip": "1H_Ranged_Shoot", "length": 0.80, "loop": false,
			"impact": 0.30, "cast": 0.0 },
		&"hurt":    { "clip": "Hit_A", "length": 0.30, "loop": false },
		&"die":     { "clip": "Death_A", "length": 0.80, "loop": false },
	},
	&"warrior": {
		# Sword-and-board idle; the knight's default Idle already reads as a
		# guard stance, so no separate 1H idle is needed.
		&"idle":    { "clip": "Idle", "length": 1.60, "loop": true },
		&"run":     { "clip": "Running_A", "length": 0.70, "loop": true },
		# Chop, not Slice_Diagonal/Horizontal: spec 9.1's primary is an
		# overhead swing (Arm.R -110 -> 55), and Chop is the one 1H clip
		# whose arc matches it. Impact stays at 0.30 so the damage number,
		# the slash arc VFX and the hit flash land on the same frame they
		# did before the model swap.
		&"attack":  { "clip": "1H_Melee_Attack_Chop", "length": 0.70, "loop": false,
			"impact": 0.30 },
		# Defend (spec 9.1) raises the shield and deals no damage, so Block -
		# not Block_Attack, which swings. The impact call still fires because
		# Ability._warrior() applies the defend buff from resolve().
		&"special": { "clip": "Block", "length": 0.55, "loop": false,
			"impact": 0.25, "cast": 0.0 },
		&"hurt":    { "clip": "Hit_A", "length": 0.30, "loop": false },
		# Death_A over Death_B: 0.80s authored, exactly spec 9's die length,
		# and it settles into a pose the corpse can hold (see
		# Combatant._on_animation_finished, which leaves DEAD untouched).
		&"die":     { "clip": "Death_A", "length": 0.80, "loop": false },
	},
	# The four KayKit Skeletons (spec: enemy rotation expansion) ship the same
	# 95-clip library as the Adventurers pack above - same author, same
	# animation names - but no weapon prop meshes at all (bare bone hands), so
	# every attack below is one of the Unarmed_* clips instead of a weapon
	# swing; the mage keeps its casting pose for flavour even though it deals
	# its damage at melee range like the rest (no ranged-enemy targeting
	# exists yet, so attack_style stays MELEE for all four).
	&"skeleton_warrior": {
		&"idle":    { "clip": "Idle", "length": 1.60, "loop": true },
		&"run":     { "clip": "Running_A", "length": 0.70, "loop": true },
		&"attack":  { "clip": "Unarmed_Melee_Attack_Punch_A", "length": 0.70, "loop": false,
			"impact": 0.30 },
		&"hurt":    { "clip": "Hit_A", "length": 0.30, "loop": false },
		&"die":     { "clip": "Death_A", "length": 0.80, "loop": false },
	},
	&"skeleton_mage": {
		&"idle":    { "clip": "Idle", "length": 1.60, "loop": true },
		&"run":     { "clip": "Running_A", "length": 0.70, "loop": true },
		&"attack":  { "clip": "Spellcast_Shoot", "length": 0.85, "loop": false,
			"impact": 0.45 },
		&"hurt":    { "clip": "Hit_A", "length": 0.30, "loop": false },
		&"die":     { "clip": "Death_A", "length": 0.80, "loop": false },
	},
	&"skeleton_rogue": {
		&"idle":    { "clip": "Idle", "length": 1.60, "loop": true },
		&"run":     { "clip": "Running_A", "length": 0.70, "loop": true },
		&"attack":  { "clip": "Unarmed_Melee_Attack_Kick", "length": 0.60, "loop": false,
			"impact": 0.24 },
		&"hurt":    { "clip": "Hit_A", "length": 0.30, "loop": false },
		&"die":     { "clip": "Death_A", "length": 0.80, "loop": false },
	},
	&"skeleton_minion": {
		&"idle":    { "clip": "Idle", "length": 1.60, "loop": true },
		&"run":     { "clip": "Running_A", "length": 0.70, "loop": true },
		&"attack":  { "clip": "Unarmed_Melee_Attack_Kick", "length": 0.55, "loop": false,
			"impact": 0.20 },
		&"hurt":    { "clip": "Hit_A", "length": 0.30, "loop": false },
		&"die":     { "clip": "Death_A", "length": 0.80, "loop": false },
	},
}

static func has_clips_for(stats: CombatantStats) -> bool:
	return CLIPS.has(stats.id)

static func build_for(player: AnimationPlayer, stats: CombatantStats) -> bool:
	if not CLIPS.has(stats.id):
		return false
	var visual: Node = player.get_parent()
	var rig: Node = visual.get_node_or_null(^"Rig")
	if rig == null:
		return false
	var src := _find_player(rig)
	assert(src != null,
		"CombatantBakedAnimations: %s has no imported AnimationPlayer under Visual/Rig" % stats.id)
	if src == null:
		return false
	var src_root: Node = src.get_node(src.root_node)
	var prefix := String(visual.get_path_to(src_root))

	var lib := AnimationLibrary.new()
	var specs: Dictionary = CLIPS[stats.id]
	for anim_name: StringName in specs:
		var spec: Dictionary = specs[anim_name]
		var source_name: String = spec["clip"]
		assert(src.has_animation(source_name),
			"CombatantBakedAnimations: %s has no clip '%s'" % [stats.id, source_name])
		if not src.has_animation(source_name):
			continue
		lib.add_animation(anim_name, _retarget(src.get_animation(source_name), prefix, spec))
	if player.has_animation_library(&""):
		player.remove_animation_library(&"")
	player.add_animation_library(&"", lib)
	player.speed_scale = 1.0
	return true

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
