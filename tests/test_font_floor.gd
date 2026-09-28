extends Node
## [mobile legibility] Holds every scene and resource to Tuning.MIN_FONT_SIZE,
## the smallest text that read comfortably in the 2026-09-27 phone playtest.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_font_floor.tscn
##
## Reads the files as text and finds every font size they set: a theme's
## default_font_size, a node's theme_override_font_sizes/font_size, a theme
## type's .../font_sizes/font_size, or an exported `font_size` property. Text a
## script draws at a literal size is not covered here; the floor applies to it
## all the same (CLAUDE.md, "Mobile legibility").
##
## A ratchet, not a purge. The sizes that predate the rule are listed in
## GRANDFATHERED, one count per file. A file may not gain an under-floor size,
## no new file may have one, and when a listed file is fixed its count here has
## to come down with it, so the list only ever shrinks. Issue #205 raises them.

const TestSupport := preload("res://tests/test_support.gd")

## res:// path -> how many under-floor sizes the file held when the rule began.
const GRANDFATHERED := {
	"res://scenes/town/mayor_office.tscn": 5,
	"res://scenes/modals/compare_flyout.tscn": 4,
	"res://scenes/modals/item_row.tscn": 3,
	"res://scenes/overlay/battle_overlay.tscn": 2,
	"res://scenes/console/upgrade_button.tscn": 1,
	"res://scenes/debug/character_viewer.tscn": 1,
	"res://scenes/modals/spoils_reel.tscn": 1,
	"res://scenes/modals/stat_chip.tscn": 1,
	"res://scenes/town/quest_plaque.tscn": 1,
}

## Not the game's own content. Any dot-directory is skipped too (.godot, and
## .claude, which can hold whole git worktrees of this project).
const SKIP_DIRS := ["res://addons", "res://scratch"]

var _size_re := RegEx.create_from_string("font_size(?:s/[A-Za-z_]+)?\\s*=\\s*(\\d+)")

func _ready() -> void:
	var t := TestSupport.new()
	var under := {}          # path -> Array[int] of sizes below the floor
	var scanned := 0
	for path: String in _files("res://"):
		scanned += 1
		var sizes: Array[int] = []
		for m: RegExMatch in _size_re.search_all(FileAccess.get_file_as_string(path)):
			var size := int(m.get_string(1))
			if size < Tuning.MIN_FONT_SIZE:
				sizes.append(size)
		if not sizes.is_empty():
			under[path] = sizes

	t.check(scanned > 50, "scanned the project's scenes and resources (%d files)" % scanned)

	for path: String in under.keys():
		var sizes: Array = under[path]
		var allowed: int = int(GRANDFATHERED.get(path, 0))
		t.check(sizes.size() <= allowed,
			"%s: %d size(s) under the %d px floor %s, %d grandfathered (fix: Tuning.MIN_FONT_SIZE or larger)"
			% [path, sizes.size(), Tuning.MIN_FONT_SIZE, str(sizes), allowed])

	for path: String in GRANDFATHERED.keys():
		var now: int = (under.get(path, []) as Array).size()
		t.check(now >= int(GRANDFATHERED[path]),
			"%s: GRANDFATHERED count %d still matches the file (%d found; if lower, lower the count)"
			% [path, GRANDFATHERED[path], now])

	t.finish(get_tree(), "test_font_floor")

func _files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	if SKIP_DIRS.has(dir_path.trim_suffix("/")):
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		out.append_array(_files(dir_path.path_join(sub)))
	for file: String in dir.get_files():
		if file.ends_with(".tscn") or file.ends_with(".tres"):
			out.append(dir_path.path_join(file))
	return out
