extends Node
## The detaching health chunk's arithmetic (spec 11.2 / 19.3).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_damage_chunk.tscn
##
## This is the case v1 could not force through MCP, so it is a headless test with
## exact arithmetic rather than a screenshot. The worked example spec 11.2 gives:
## a 100 HP character hit for 20 gives f_prev = 1.0, f_new = 0.8, so the chunk is
## the rightmost 20% of the bar - x from 108.8 to 136.0, width 27.2 px, full
## 16 px height.

const TestSupport := preload("res://tests/test_support.gd")

const BARS_SCENE := preload("res://scenes/overlay/combatant_bars.tscn")

func _ready() -> void:
	var t := TestSupport.new()
	var bars = BARS_SCENE.instantiate()
	add_child(bars)
	# The rect is returned in global coords; the bar sits at the origin here, so
	# global and local agree and the spec's numbers can be read off directly.
	bars.global_position = Vector2.ZERO
	await get_tree().process_frame

	var fill: ColorRect = bars.get_node("HealthFill")
	var fill_x: float = fill.global_position.x
	print("HealthFill origin x = %.2f, height = %.2f" % [fill_x, fill.size.y])

	# --- spec 11.2's worked example ---
	var rect: Rect2 = bars.lost_segment_rect(1.0, 0.8)
	t.check_near(rect.position.x - fill_x, 108.8, 0.01, "100hp/-20: chunk starts at x = 108.8")
	t.check_near(rect.position.x - fill_x + rect.size.x, 136.0, 0.01,
		"100hp/-20: chunk ends at x = 136.0")
	t.check_near(rect.size.x, 27.2, 0.01, "100hp/-20: chunk width = 27.2")
	t.check_near(rect.size.y, 16.0, 0.01, "100hp/-20: chunk height = 16.0 (full fill height)")

	# --- a spread of other HP/damage pairs ---
	# label, max_hp, previous_hp, damage
	var cases: Array = [
		["280hp warlord hit for 22", 280, 280, 22],
		["40hp shadow monster hit for 14", 40, 40, 14],
		["70hp priest at 35 hit for 10", 70, 35, 10],
		["120hp warrior hit for exactly lethal", 120, 120, 120],
		["80hp ranger overkilled", 80, 12, 50],
	]
	for row: Array in cases:
		var label: String = row[0]
		var max_hp: int = row[1]
		var prev_hp: int = row[2]
		var damage: int = row[3]
		var new_hp: int = maxi(0, prev_hp - damage)
		var f_prev := float(prev_hp) / float(max_hp)
		var f_new := float(new_hp) / float(max_hp)
		var r: Rect2 = bars.lost_segment_rect(f_prev, f_new)
		var expect_x0 := 136.0 * f_new
		var expect_x1 := 136.0 * f_prev
		var expect_w := maxf(expect_x1 - expect_x0, 1.0)
		t.check_near(r.position.x - fill_x, expect_x0, 0.01, "%s: left edge" % label)
		t.check_near(r.size.x, expect_w, 0.01, "%s: width" % label)
		t.check(r.size.x > 0.0, "%s: width is positive" % label)
		t.check_near(r.size.y, 16.0, 0.01, "%s: full height" % label)

	# A zero-damage / no-change call must still produce a drawable rect rather
	# than a degenerate one, or the chunk scene would be invisible-but-alive.
	var zero: Rect2 = bars.lost_segment_rect(0.5, 0.5)
	t.check_near(zero.size.x, 1.0, 0.01, "no-change: width clamps to a 1 px minimum")

	# The fill snaps to the new fraction with no tween: the chunk carries the
	# motion (spec 11.2 step 4).
	bars.set_health_fraction(0.8)
	t.check_near(fill.size.x, 108.8, 0.01, "fill snaps immediately to 136 x 0.8")

	t.finish(get_tree(), "test_damage_chunk")
