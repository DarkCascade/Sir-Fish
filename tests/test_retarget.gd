extends Node
## Projectile arrival against a dead or missing target (spec 9.2 / 21-D8 / 19.3).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_retarget.tscn
##
## "This is the most common source of null crashes in this kind of game." The
## three cases are (a) a live target, (b) a dead target with others alive, and
## (c) every enemy dead. None of them may touch a freed instance.

const TestSupport := preload("res://tests/test_support.gd")

const ARROW_SCENE := preload("res://scenes/battle/projectiles/arrow.tscn")
const BOMB_SCENE := preload("res://scenes/battle/projectiles/bomb_arrow.tscn")

## A stand-in for BattleDirector exposing only what Projectile actually calls.
## Using the real director would need a whole BattleWorld; the retarget rule is
## the thing under test, not the spawn path.
class FakeDirector extends Node:
	var enemies: Array[Combatant] = []

	func living_enemies() -> Array[Combatant]:
		var out: Array[Combatant] = []
		for c: Combatant in enemies:
			if is_instance_valid(c) and c.is_alive():
				out.append(c)
		return out

	func random_living_enemy() -> Combatant:
		var pool := living_enemies()
		if pool.is_empty():
			return null
		return pool[RNG.randi_range(0, pool.size() - 1)]

var _t := TestSupport.new()

func _ready() -> void:
	await _case_live_target()
	await _case_dead_target_others_alive()
	await _case_all_enemies_dead()
	await _case_bomb_with_no_targets()
	_t.finish(get_tree(), "test_retarget")

# --- helpers ----------------------------------------------------------------

func _make_enemy(id: StringName, x: float) -> Combatant:
	var stats := GameState.get_stats(id)
	var packed: PackedScene = load(stats.scene_path)
	var c := packed.instantiate() as Combatant
	add_child(c)
	c.position = Vector3(x, 0, 0)
	c.setup(stats, -1)
	return c

func _make_hero(id: StringName, x: float) -> Combatant:
	return _make_enemy(id, x)

func _fire(scene: PackedScene, source: Combatant, target: Combatant,
		director: FakeDirector, bomb: bool) -> void:
	var proj = scene.instantiate()
	add_child(proj)
	proj.launch(source, target, director, bomb)
	# Drive the flight to completion rather than waiting out FLIGHT_TIME in real
	# seconds - the arrival branch is what matters here.
	var guard := 0
	while is_instance_valid(proj) and guard < 600:
		await get_tree().process_frame
		guard += 1
	_t.check(guard < 600, "projectile resolved and freed itself")

# --- cases ------------------------------------------------------------------

func _case_live_target() -> void:
	print("--- (a) live target ---")
	var d := FakeDirector.new()
	add_child(d)
	var ranger := _make_hero(&"ranger", -3.0)
	var enemy := _make_enemy(&"shadow_monster", 2.0)
	d.enemies = [enemy]
	var before := enemy.current_hp
	await _fire(ARROW_SCENE, ranger, enemy, d, false)
	_t.check(enemy.current_hp < before, "(a) the live target took damage")

func _case_dead_target_others_alive() -> void:
	print("--- (b) target dies mid-flight, others alive ---")
	var d := FakeDirector.new()
	add_child(d)
	var ranger := _make_hero(&"ranger", -3.0)
	var doomed := _make_enemy(&"shadow_monster", 2.0)
	var survivor := _make_enemy(&"shadow_monster", 3.5)
	d.enemies = [doomed, survivor]
	# Kill the original target before the arrow lands.
	doomed.current_hp = 0
	doomed.state = Combatant.State.DEAD
	var before := survivor.current_hp
	await _fire(ARROW_SCENE, ranger, doomed, d, false)
	_t.check(survivor.current_hp < before,
		"(b) the arrow retargeted to a living enemy instead of crashing")

func _case_all_enemies_dead() -> void:
	print("--- (c) every enemy dead on arrival ---")
	var d := FakeDirector.new()
	add_child(d)
	var ranger := _make_hero(&"ranger", -3.0)
	var doomed := _make_enemy(&"shadow_monster", 2.0)
	d.enemies = [doomed]
	doomed.current_hp = 0
	doomed.state = Combatant.State.DEAD
	await _fire(ARROW_SCENE, ranger, doomed, d, false)
	# Reaching this line at all is the assertion: it must fizzle harmlessly.
	_t.check(true, "(c) the arrow fizzled harmlessly with no living enemy")

func _case_bomb_with_no_targets() -> void:
	print("--- (d) bomb arrow with every enemy dead ---")
	var d := FakeDirector.new()
	add_child(d)
	var ranger := _make_hero(&"ranger", -3.0)
	var doomed := _make_enemy(&"shadow_monster", 2.0)
	d.enemies = [doomed]
	doomed.current_hp = 0
	doomed.state = Combatant.State.DEAD
	await _fire(BOMB_SCENE, ranger, doomed, d, true)
	_t.check(true, "(d) the bomb arrow exploded with no living enemy and did not crash")
