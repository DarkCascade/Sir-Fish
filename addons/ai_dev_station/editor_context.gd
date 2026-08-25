@tool
extends RefCounted

## Turns the editor's current state into a text block that gets prepended to a
## prompt. This is the reason the station beats a tiled terminal: Claude starts
## the turn already knowing which scene is open and what you have selected.

const MAX_TREE_NODES := 120


static func project_dir() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/")


## Which context toggles have anything to offer right now.
static func available() -> Dictionary:
	return {
		"scene": EditorInterface.get_edited_scene_root() != null,
		"selection": not EditorInterface.get_selection().get_selected_nodes().is_empty(),
		"script": _current_script_path() != "",
	}


static func build(flags: Dictionary) -> String:
	var sections := PackedStringArray()
	if bool(flags.get("scene", false)):
		var s := scene_block()
		if not s.is_empty():
			sections.append(s)
	if bool(flags.get("selection", false)):
		var s := selection_block()
		if not s.is_empty():
			sections.append(s)
	if bool(flags.get("script", false)):
		var s := script_block()
		if not s.is_empty():
			sections.append(s)
	if sections.is_empty():
		return ""
	return "<godot_editor_context>\n%s\n</godot_editor_context>" % "\n\n".join(sections)


static func scene_block() -> String:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return ""
	var lines := PackedStringArray()
	lines.append("Open scene: %s" % (root.scene_file_path if root.scene_file_path != "" else "(unsaved)"))
	lines.append("Node tree:")
	var count := [0]
	_walk(root, root, 0, lines, count)
	if count[0] >= MAX_TREE_NODES:
		lines.append("  ... (tree truncated at %d nodes)" % MAX_TREE_NODES)
	return "\n".join(lines)


static func _walk(node: Node, root: Node, depth: int, lines: PackedStringArray, count: Array) -> void:
	if count[0] >= MAX_TREE_NODES:
		return
	count[0] += 1
	var suffix := ""
	var script: Variant = node.get_script()
	if script != null and script is Script:
		suffix = "  [%s]" % (script as Script).resource_path
	lines.append("  %s- %s (%s)%s" % ["  ".repeat(depth), node.name, node.get_class(), suffix])
	for child: Node in node.get_children():
		# Skip nodes that belong to an instanced sub-scene's internals.
		if child.owner != root and child.owner != null:
			continue
		_walk(child, root, depth + 1, lines, count)


static func selection_block() -> String:
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	if nodes.is_empty():
		return ""
	var root := EditorInterface.get_edited_scene_root()
	var lines := PackedStringArray(["Selected nodes:"])
	for node: Node in nodes:
		var path := str(node.name)
		if root != null and root.is_ancestor_of(node):
			path = str(root.get_path_to(node))
		if node == root:
			path = "."
		lines.append("  - %s (%s)" % [path, node.get_class()])
	return "\n".join(lines)


static func script_block() -> String:
	var path := _current_script_path()
	if path.is_empty():
		return ""
	var line := 0
	var editor := EditorInterface.get_script_editor().get_current_editor()
	if editor != null:
		var code_edit := editor.get_base_editor()
		if code_edit is CodeEdit:
			line = (code_edit as CodeEdit).get_caret_line() + 1
	return "Script open in the editor: %s (caret on line %d)" % [path, line]


static func _current_script_path() -> String:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return ""
	var script := script_editor.get_current_script()
	if script == null:
		return ""
	return script.resource_path
