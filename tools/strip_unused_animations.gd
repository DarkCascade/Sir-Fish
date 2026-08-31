@tool
extends EditorScenePostImport
## [web delivery / perf spec 2.2.2] Drops every animation clip the game never
## plays from an imported character .glb, at import time.
##
## Why a post-import script rather than the .import file's own subresource
## options: Godot 4.7's scene importer has NO per-animation skip. The
## ANIMATION internal-import category exposes only loop_mode / save_to_file /
## slices / optimizer / compression - `settings/import = false` parses without
## complaint and is then silently ignored (verified empirically: writing 90
## such entries into skeleton_mage.glb.import and reimporting produced a .scn
## of exactly the same 1,801,721 bytes). The only other lever,
## `import/skip_import` on the ANIMATION_NODE category, removes the whole
## AnimationPlayer and with it every clip - including the five that are used.
##
## The clips that survive are the union of what CombatantBakedAnimations.CLIPS
## actually references, per character. That table is the single source of truth
## for which clips the game plays; KEEP below must be kept in step with it, and
## tests/test_animation_clips.gd fails the suite if it drifts.
##
## Wired up via `import_script/path` in each character's .glb.import.

## stem -> clip names to keep. Derived from CombatantBakedAnimations.CLIPS.
## A .glb whose stem is absent here is passed through untouched, so attaching
## this script to an unrelated model is a no-op rather than a wipe.
const KEEP := {
	"knight": ["Idle", "Running_A", "1H_Melee_Attack_Chop", "Block", "Hit_A", "Death_A"],
	"mage": ["Idle", "Running_A", "Spellcast_Shoot", "Hit_A", "Death_A"],
	"rogue": ["Idle", "Running_A", "1H_Ranged_Shoot", "Hit_A", "Death_A"],
	"skeleton_mage": ["Idle", "Running_A", "Spellcast_Shoot", "Hit_A", "Death_A"],
	"skeleton_minion": ["Idle", "Running_A", "Unarmed_Melee_Attack_Kick", "Hit_A", "Death_A"],
	"skeleton_rogue": ["Idle", "Running_A", "Unarmed_Melee_Attack_Kick", "Hit_A", "Death_A"],
	"skeleton_warrior": ["Idle", "Running_A", "Unarmed_Melee_Attack_Punch_A", "Hit_A", "Death_A"],
}


func _post_import(scene: Node) -> Object:
	var stem: String = get_source_file().get_file().get_basename()
	if not KEEP.has(stem):
		return scene
	var keep: Array = KEEP[stem]
	var player: AnimationPlayer = _find_player(scene)
	if player == null:
		push_warning("strip_unused_animations: no AnimationPlayer in %s" % stem)
		return scene
	var removed: int = 0
	for lib_name: StringName in player.get_animation_library_list():
		var lib: AnimationLibrary = player.get_animation_library(lib_name)
		# get_animation_list() returns a live view; copy before mutating it.
		for clip: StringName in Array(lib.get_animation_list()):
			if keep.has(String(clip)):
				continue
			lib.remove_animation(clip)
			removed += 1
	var kept: int = 0
	for lib_name: StringName in player.get_animation_library_list():
		kept += player.get_animation_library(lib_name).get_animation_list().size()
	print("[strip_unused_animations] %s: removed %d, kept %d" % [stem, removed, kept])
	return scene


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for child: Node in n.get_children():
		var found: AnimationPlayer = _find_player(child)
		if found != null:
			return found
	return null
