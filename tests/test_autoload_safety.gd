extends Node
## Autoload independence invariant, as a source lint (spec 3.2, 19.3, V1). [v3, new]
##
## Run headless from the project root:
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_autoload_safety.tscn
##
## No autoload may read state from, or call a method on, another autoload
## during _init() or _ready() - that is the whole invariant the (unenforceable)
## registration order used to stand in for. This test reads each project
## autoload's script source with FileAccess, isolates the body of _ready() and
## _init(), and fails if any OTHER autoload's identifier appears there.
##
## Two exemptions, both deliberate (spec 19.3):
##   - const/static var initializers are exempt - they are outside any
##     function body, so this scan never sees them in the first place.
##   - The three MCP* autoloads are exempt: they are not ours, and are not
##     scanned at all.
##
## This is a lint, not a proof: an indirect call (get_node("/root/GameState"),
## or a helper invoked from _ready()) slips past it. That is acceptable - the
## failure it guards against is someone adding a new autoload and reaching for
## a sibling directly in _ready(), which is the direct form this test catches.

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()
	var autoloads := _project_autoloads()

	t.check(autoloads.size() >= 6, "found at least 6 project autoloads (%d found)" % autoloads.size())

	# "Ours" - excludes the three MCP* autoloads, which are the addon's and are
	# explicitly not scanned (spec 19.3).
	var ours := {}
	for name: String in autoloads.keys():
		if not name.begins_with("MCP"):
			ours[name] = autoloads[name]

	for name: String in ours.keys():
		var path: String = ours[name]
		var body := _lifecycle_body(path)
		var offender := ""
		for other: String in ours.keys():
			if other == name:
				continue
			if _contains_identifier(body, other):
				offender = other
				break
		t.check(offender == "",
			"%s's _ready()/_init() does not reference %s directly" % [name, offender if offender != "" else "(any sibling)"])

	t.finish(get_tree(), "test_autoload_safety")

## Reads the setting "autoload/<Name>" for every project autoload and returns
## { Name: res://path.gd }.
func _project_autoloads() -> Dictionary:
	var out := {}
	for prop: Dictionary in ProjectSettings.get_property_list():
		var setting_name: String = prop["name"]
		if not setting_name.begins_with("autoload/"):
			continue
		var autoload_name := setting_name.trim_prefix("autoload/")
		var raw: String = ProjectSettings.get_setting(setting_name)
		out[autoload_name] = raw.trim_prefix("*")
	return out

## Extracts the concatenated source of every top-level _ready() and _init()
## function in the script at `path` (from the `func` line to the next line at
## column-0 indentation, exclusive).
func _lifecycle_body(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var lines: PackedStringArray = []
	while not file.eof_reached():
		lines.append(file.get_line())
	file.close()

	var body := ""
	var capturing := false
	for line: String in lines:
		var stripped := line.strip_edges(true, false)
		var is_top_level := not line.is_empty() and not line[0] in [" ", "\t"]
		if is_top_level:
			if stripped.begins_with("func _ready(") or stripped.begins_with("func _init("):
				capturing = true
				continue
			else:
				capturing = false
				continue
		if capturing:
			body += line + "\n"
	return body

## Whole-word match only, so "GameStateThing" does not falsely flag "GameState".
func _contains_identifier(body: String, identifier: String) -> bool:
	var re := RegEx.new()
	re.compile("\\b%s\\b" % identifier)
	return re.search(body) != null
