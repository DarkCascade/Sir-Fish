extends Node
## SceneRouter / boot invariants (spec 13.1). Lands at step 5, on the same
## principle as steps 1-4's pinning tests: a step that buys isolation and ships
## no assertion of its own has spent the isolation and not collected.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_scene_router.tscn
##
## Kept to ~10 checks. The runtime side of step 5's acceptance (does the game
## boot, route and render the HUD) is a --headless --quit-after boot of
## boot.tscn, not this file.

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()
	t.guard_user_file(SaveGame.PATH)

	# --- totality: every Place has a PATHS entry (spec 13.1) ---------------
	# The failure mode is adding Place.FOO and forgetting its path, which
	# crashes only when someone routes there.
	var place_count: int = SceneRouter.Place.size()
	t.check(SceneRouter.PATHS.size() == place_count,
		"PATHS has one entry per Place (%d paths, %d places)" % [SceneRouter.PATHS.size(), place_count])
	var all_keyed := true
	for v: int in SceneRouter.Place.values():
		if not SceneRouter.PATHS.has(v):
			all_keyed = false
	t.check(all_keyed, "every Place enum value is a PATHS key")

	# --- existence, for BUILT places only (spec 13.1) ---------------------
	# TOWN and QUEST exist at step 5; INN widened in at step 7, MAYOR at step 8;
	# BLACKSMITH at 10 is still absent. Asserting all five here fails on arrival.
	t.check(ResourceLoader.exists(SceneRouter.PATHS[SceneRouter.Place.TOWN]),
		"town.tscn exists")
	t.check(ResourceLoader.exists(SceneRouter.PATHS[SceneRouter.Place.INN]),
		"inn.tscn exists (Place.INN, widened in at step 7)")
	t.check(ResourceLoader.exists(SceneRouter.PATHS[SceneRouter.Place.MAYOR]),
		"mayor_office.tscn exists (Place.MAYOR, widened in at step 8)")
	t.check(ResourceLoader.exists(SceneRouter.PATHS[SceneRouter.Place.QUEST]),
		"main.tscn (Place.QUEST) exists")

	# --- SceneRouter is a live autoload with a clean lifecycle ------------
	t.check(get_node_or_null("/root/SceneRouter") != null,
		"SceneRouter is registered and in the tree")
	t.check(get_node_or_null("/root/Hud") != null,
		"Hud is registered and in the tree")
	# Belt-and-braces over test_autoload_safety's scene-autoload blind spot
	# (step-5 Q4): SceneRouter's _ready()/_init() must name no sibling autoload.
	t.check(not _lifecycle_references_sibling("res://scripts/autoload/scene_router.gd"),
		"SceneRouter._ready()/_init() reference no sibling autoload")

	# --- spec 3.1 boot rule: the fallback persists exactly once ----------
	# After load_profile() returns false, boot.gd calls new_profile() then
	# save_profile() - and new_profile() itself must NOT write (spec 2.3), or
	# every launch clobbers the player's file.
	_delete_save()
	t.check(not SaveGame.load_profile(),
		"load_profile() returns false with no file")
	t.check(not FileAccess.file_exists(SaveGame.PATH),
		"load_profile() did not create a file")

	GameState.new_profile()
	t.check(not FileAccess.file_exists(SaveGame.PATH),
		"new_profile() alone writes no file")
	SaveGame.save_profile()
	t.check(FileAccess.file_exists(SaveGame.PATH) and SaveGame.load_profile(),
		"save_profile() after the fallback writes a loadable file")

	# boot.gd is the one place that decides a new profile is real, so its CODE
	# (comments stripped) must carry exactly one new_profile() and exactly one
	# save_profile() - spec 2.4's "When to save" list names the boot caller and
	# nothing else on this path. The regression this guards is someone moving
	# the save into new_profile() itself.
	var boot_code := _code_only("res://scripts/boot.gd")
	t.check(boot_code.count("new_profile()") == 1 and boot_code.count("save_profile()") == 1,
		"boot.gd's code persists the new-profile fallback exactly once (new_profile x%d, save_profile x%d)"
		% [boot_code.count("new_profile()"), boot_code.count("save_profile()")])

	t.finish(get_tree(), "test_scene_router")

func _delete_save() -> void:
	if FileAccess.file_exists(SaveGame.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.PATH))

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""

## Source with `#` comments and blank lines removed, so a substring count
## reflects actual calls rather than prose. Good enough for boot.gd, which has
## no `#` inside a string literal.
func _code_only(path: String) -> String:
	var out := ""
	for line: String in _read(path).split("\n"):
		var hash_at := line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		if not line.strip_edges().is_empty():
			out += line + "\n"
	return out

## Mirrors test_autoload_safety's lint for one script: is any known autoload
## name referenced inside a top-level _ready()/_init() body?
func _lifecycle_references_sibling(path: String) -> bool:
	var src := _read(path)
	var body := ""
	var capturing := false
	for line: String in src.split("\n"):
		var is_top_level := not line.is_empty() and not line[0] in [" ", "\t"]
		if is_top_level:
			capturing = line.strip_edges().begins_with("func _ready(") \
				or line.strip_edges().begins_with("func _init(")
			continue
		if capturing:
			body += line + "\n"
	for sibling: String in ["EventBus", "GameState", "SaveGame", "Hud", "Tuning",
			"RNG", "Itemizer", "Upgrades", "Debug"]:
		var re := RegEx.new()
		re.compile("\\b%s\\b" % sibling)
		if re.search(body) != null:
			return true
	return false
