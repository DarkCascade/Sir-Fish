extends RefCounted
## Shared PASS/FAIL bookkeeping for the headless test scenes (spec 19.3).
##
## Each test scene prints PASS/FAIL lines and exits non-zero on failure, so the
## whole suite can be driven from a terminal:
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/<name>.tscn

var failures: int = 0
var checks: int = 0

var _guarded_path: String = ""
var _guarded_bytes: PackedByteArray = PackedByteArray()
var _guarded_existed: bool = false

## Snapshots a user:// file so finish() puts it back exactly as it was, whether
## the test overwrote it or deleted it (town spec, step-2 Q8).
##
## Needed because the profile save lives at a fixed user:// path shared with the
## dev's own play sessions: once spec 3.1's boot.tscn loads that file, a test run
## that clobbered it would silently cost the dev their town progress. Guarding
## here rather than making SaveGame.PATH injectable keeps the production class
## free of a test seam.
func guard_user_file(path: String) -> void:
	_guarded_path = path
	_guarded_existed = FileAccess.file_exists(path)
	_guarded_bytes = PackedByteArray()
	if not _guarded_existed:
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		_guarded_bytes = f.get_buffer(f.get_length())

func _restore_guarded_file() -> void:
	if _guarded_path == "":
		return
	if _guarded_existed:
		var f := FileAccess.open(_guarded_path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_guarded_bytes)
	elif FileAccess.file_exists(_guarded_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_guarded_path))

func check(condition: bool, label: String) -> bool:
	checks += 1
	if condition:
		print("PASS  %s" % label)
	else:
		failures += 1
		print("FAIL  %s" % label)
	return condition

func check_near(actual: float, expected: float, tolerance: float, label: String) -> bool:
	return check(absf(actual - expected) <= tolerance,
		"%s (got %.4f, expected %.4f +/- %.4f)" % [label, actual, expected, tolerance])

func check_between(actual: float, low: float, high: float, label: String) -> bool:
	return check(actual >= low and actual <= high,
		"%s (got %.4f, allowed %.4f - %.4f)" % [label, actual, low, high])

## Prints the summary and quits with the right exit code. Restores any file
## handed to guard_user_file() first, so a failing test still cannot leave the
## dev's save clobbered.
func finish(tree: SceneTree, title: String) -> void:
	_restore_guarded_file()
	print("--- %s: %d checks, %d failures ---" % [title, checks, failures])
	if failures == 0:
		print("RESULT PASS")
	else:
		print("RESULT FAIL")
	tree.quit(1 if failures > 0 else 0)
