extends RefCounted
## Shared PASS/FAIL bookkeeping for the headless test scenes (spec 19.3).
##
## Each test scene prints PASS/FAIL lines and exits non-zero on failure, so the
## whole suite can be driven from a terminal:
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/<name>.tscn

var failures: int = 0
var checks: int = 0

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

## Prints the summary and quits with the right exit code.
func finish(tree: SceneTree, title: String) -> void:
	print("--- %s: %d checks, %d failures ---" % [title, checks, failures])
	if failures == 0:
		print("RESULT PASS")
	else:
		print("RESULT FAIL")
	tree.quit(1 if failures > 0 else 0)
