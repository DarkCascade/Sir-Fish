extends Node3D
## [backlog P4] Dev character viewer (pipeline review recommendation 2, issue
## #84). Instances any registered CombatantStats directly through
## GameState.get_stats() + Combatant.setup() - no BattleDirector, no
## RunController, no town/quest flow anywhere in the path, so nothing here
## ever reaches SaveGame.save_profile(). Permanent, not scratch/: it replaces
## the throwaway res://scratch/<name>.tscn route CLAUDE.md's KayKit section
## falls back to when a check needs a real scene tree.
##
## Reachable three ways:
##   - play this scene (`scene play --path res://scenes/debug/character_viewer.tscn`,
##     or play_scene), then `Debug.command = "viewer <stats_id>"`;
##   - Tab / Shift+Tab cycles GameState.all_stats_ids() live, for a human
##     at the keyboard with no MCP driving it;
##   - the existing Debug verbs (anim, bone, sethp, damage, kill) resolve
##     against whatever this scene is showing via _find()'s viewer fallback
##     (scripts/autoload/debug.gd) - none of them needed to change.
##
## Registers into the "character_viewer" group so Debug can find it without a
## direct scene reference (mirrors how BattleDirector is found via
## "battle_world" today).

@onready var _combatant_root: Node3D = $CombatantRoot
@onready var _label: Label = $UI/Label
@onready var _camera: Camera3D = $Camera3D

var _ids: Array[StringName] = []
var _index: int = 0
var _current: Combatant = null

func _ready() -> void:
	add_to_group("character_viewer")
	_camera.transform = Transform3D(Basis(), Vector3(0, 1.6, 4.3))
	_camera.look_at(Vector3(0, 1.05, 0), Vector3.UP)
	_ids = GameState.all_stats_ids()
	_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	if _ids.is_empty():
		_label.text = "(no characters registered - GameState.all_stats_ids() is empty)"
		return
	_show_index(0)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.keycode != KEY_TAB:
		return
	_step(-1 if event.shift_pressed else 1)
	get_viewport().set_input_as_handled()

func _step(delta: int) -> void:
	if _ids.is_empty():
		return
	_show_index(wrapi(_index + delta, 0, _ids.size()))

func _show_index(i: int) -> void:
	_index = i
	_spawn(_ids[i])

## Debug.command's "viewer <stats_id>" entry point (scripts/autoload/debug.gd).
func show_character(id: StringName) -> void:
	var found := _ids.find(id)
	if found >= 0:
		_index = found
	_spawn(id)

func current_combatant() -> Combatant:
	return _current

## Each character ships its own scene at CombatantStats.scene_path - an
## instance of combatant.tscn with its imported model already parented under
## Visual/Rig (see e.g. scenes/battle/enemies/bandit_officer.tscn) - never the
## bare combatant.tscn, which has no model and no baked AnimationPlayer.
## Mirrors BattleDirector._spawn_combatant() minus the threaded-load cache,
## which a one-at-a-time dev viewer has no need for.
func _spawn(id: StringName) -> void:
	var stats := GameState.get_stats(id)
	if stats == null or stats.scene_path.is_empty():
		_label.text = "%s has no scene_path - nothing to show" % id
		return
	var packed := load(stats.scene_path) as PackedScene
	if packed == null:
		_label.text = "%s: failed to load %s" % [id, stats.scene_path]
		return
	if _current != null:
		_current.queue_free()
	_current = packed.instantiate() as Combatant
	_combatant_root.add_child(_current)
	_current.setup(stats)
	_update_label()

func _update_label() -> void:
	if _current == null or _current.stats == null:
		_label.text = "(nothing shown)"
		return
	var clips: Array[String] = []
	for clip_name: String in _current.anim.get_animation_list():
		clips.append(clip_name)
	_label.text = "%s  (%d / %d)   Tab / Shift+Tab to cycle\nclips: %s" % [
		_current.stats.id, _index + 1, _ids.size(), ", ".join(clips)]
