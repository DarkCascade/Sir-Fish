extends Node
## [web delivery / perf spec 2.2.2] Pins the import-time animation strip against
## drift.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_animation_clips.tscn
##
## tools/strip_unused_animations.gd deletes every clip a character's .glb ships
## with except a hardcoded keep-list, at import time. That keep-list is a second
## copy of what CombatantBakedAnimations.CLIPS references, and the two can drift:
## retarget a hero onto a different clip in CLIPS, and the strip script will
## happily delete the clip the game now needs. Nothing else in the suite would
## catch it - the failure is a silent missing animation at runtime, on one
## character, in one state.
##
## So this walks CLIPS itself (the source of truth) and asserts every clip it
## names is actually present in that character's imported scene. It deliberately
## reads the IMPORTED scene rather than the .glb on disk, because the imported
## scene is what the strip script produces and what the game loads.
##
## It also asserts the strip actually happened - a keep-list that silently
## stopped being applied would leave the clips present and the payload bloated,
## which this test would otherwise pass.

const TestSupport := preload("res://tests/test_support.gd")

## Characters whose clips come from the .glb (CombatantBakedAnimations), mapped
## to the .glb the retarget reads from. Characters on the in-house rig
## (orc_barbarian, orc_warlord, sporecap) are absent on purpose: their clips are
## GDScript-authored by CombatantSkeletonAnimations and their .glb ships no
## animations at all, so there is nothing to strip and nothing to pin.
const MODELS := {
	&"warrior": "res://assets/meshes/knight.glb",
	&"mage": "res://assets/meshes/mage.glb",
	&"ranger": "res://assets/meshes/rogue.glb",
	&"skeleton_warrior": "res://assets/meshes/skeleton_warrior.glb",
	&"skeleton_mage": "res://assets/meshes/skeleton_mage.glb",
	&"skeleton_rogue": "res://assets/meshes/skeleton_rogue.glb",
	&"skeleton_minion": "res://assets/meshes/skeleton_minion.glb",
}

## The strip is only worth having if it actually removes the bulk. KayKit ships
## 76-95 clips per model; the keep-lists are 5-6. Anything above this ceiling
## means the post-import script silently stopped running - most likely because
## `import_script/path` was reset by a reimport through the editor UI.
const MAX_CLIPS_AFTER_STRIP := 12

var _t := TestSupport.new()

func _ready() -> void:
	for id: StringName in MODELS:
		_check_character(id)
	_t.finish(get_tree(), "test_animation_clips")

func _check_character(id: StringName) -> void:
	var path: String = MODELS[id]
	var packed: PackedScene = load(path)
	if not _t.check(packed != null, "%s: %s loads" % [id, path]):
		return
	var root: Node = packed.instantiate()
	var player: AnimationPlayer = _find_player(root)
	if not _t.check(player != null, "%s: imported scene has an AnimationPlayer" % id):
		root.free()
		return

	var present: Array[String] = []
	for lib_name: StringName in player.get_animation_library_list():
		for clip: StringName in player.get_animation_library(lib_name).get_animation_list():
			present.append(String(clip))

	# Every clip CombatantBakedAnimations names for this character must survive.
	var wanted := _wanted_clips(id)
	_t.check(not wanted.is_empty(), "%s: CLIPS names at least one clip" % id)
	for clip: String in wanted:
		_t.check(present.has(clip),
			"%s: clip '%s' survived the strip (present: %s)" % [id, clip, present])

	# And the strip must still be doing its job.
	_t.check(present.size() <= MAX_CLIPS_AFTER_STRIP,
		"%s: %d clips after strip, ceiling %d" % [id, present.size(), MAX_CLIPS_AFTER_STRIP])

	root.free()

## Pulls the distinct "clip" values out of CombatantBakedAnimations.CLIPS for one
## character - the same table the retarget reads at runtime, so this cannot go
## stale against it the way a second hardcoded list would.
func _wanted_clips(id: StringName) -> Array[String]:
	var out: Array[String] = []
	if not CombatantBakedAnimations.CLIPS.has(id):
		return out
	var entry: Dictionary = CombatantBakedAnimations.CLIPS[id]
	for state: StringName in entry:
		var spec: Dictionary = entry[state]
		var clip: String = String(spec.get("clip", ""))
		if clip != "" and not out.has(clip):
			out.append(clip)
	return out

func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for child: Node in n.get_children():
		var found: AnimationPlayer = _find_player(child)
		if found != null:
			return found
	return null
