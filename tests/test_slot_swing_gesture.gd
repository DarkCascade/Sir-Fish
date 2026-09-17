extends Node
## Regression: a board that rolls both a DAMAGE icon and a CLEAVE or BLEED icon
## used to silently eat the warrior's real swing.
##
## Playtest report: "sword icons were hit and the warrior played his attack
## animation but the enemy did not react and no floating damage number
## appeared." Root cause - warrior.tres's `executes` lists DAMAGE(1) alongside
## BLOCK(3)/BLEED(4)/CLEAVE(5), so the warrior is always both the CLEAVE/BLEED
## executor AND the DAMAGE executor. CLEAVE/BLEED resolve earlier in the board
## than the aggregated swing (SlotMachine._hero_swing runs after the whole
## board loop), so their `fallback:false` cosmetic slot_gesture() call started
## the warrior's "attack" clip FIRST; by the time _hero_swing() tried to start
## the REAL one, Combatant.slot_attack()'s `state == State.ATTACKING` guard
## silently dropped it - no `pending`, so the clip's impact call track had
## nothing to resolve. The player saw a swing with no damage.
##
## Fixed by SlotMachine._should_gesture(): a fallback:false cosmetic gesture is
## skipped when its executor is also this board's DAMAGE executor, since the
## real swing already carries the visual.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_slot_swing_gesture.tscn

const TestSupport := preload("res://tests/test_support.gd")
const SLOT_MACHINE_SCENE := preload("res://scenes/console/slot_machine.tscn")

## Exposes only what SlotMachine's director calls actually need - the same
## minimal-fake approach test_retarget.gd / test_ability_resolve.gd use rather
## than standing up a real BattleDirector/BattleWorld.
class FakeDirector extends Node:
	var heroes: Array[Combatant] = []
	var enemies: Array[Combatant] = []

	func living_heroes() -> Array[Combatant]:
		var out: Array[Combatant] = []
		for h: Combatant in heroes:
			if is_instance_valid(h) and h.is_alive():
				out.append(h)
		return out

	func living_enemies() -> Array[Combatant]:
		var out: Array[Combatant] = []
		for c: Combatant in enemies:
			if is_instance_valid(c) and c.is_alive():
				out.append(c)
		return out

	func random_living_enemy() -> Combatant:
		var pool := living_enemies()
		return null if pool.is_empty() else pool[RNG.randi_range(0, pool.size() - 1)]

	func lowest_hp_living_hero() -> Combatant:
		var best: Combatant = null
		for h: Combatant in living_heroes():
			if best == null or h.current_hp < best.current_hp:
				best = h
		return best

var _t := TestSupport.new()

func _ready() -> void:
	_test_should_gesture_unit()
	await _case_cleave_plus_damage()
	await _case_bleed_plus_damage()
	_t.finish(get_tree(), "test_slot_swing_gesture")

## Combatant.director is what slot_attack()'s own guard checks (SEPARATE from
## SlotMachine.director, set on the machine itself in _make_machine) - every
## spawned combatant needs it or slot_attack() no-ops on the null check before
## anything else, which reads identically to this exact bug from the outside.
func _spawn(id: StringName, x: float, d: FakeDirector) -> Combatant:
	var stats := GameState.get_stats(id)
	var packed: PackedScene = load(stats.scene_path)
	var c := packed.instantiate() as Combatant
	add_child(c)
	c.position = Vector3(x, 0, 0)
	c.setup(stats, -1)
	c.director = d
	return c

func _make_machine(d: FakeDirector) -> Control:
	var machine := SLOT_MACHINE_SCENE.instantiate() as Control
	add_child(machine)
	machine.director = d
	return machine

## Pins the helper's own truth table directly - no animation timing involved.
func _test_should_gesture_unit() -> void:
	print("--- _should_gesture unit cases ---")
	var d := FakeDirector.new()
	add_child(d)
	var warrior := _spawn(&"warrior", -3.0, d)
	var mage := _spawn(&"mage", -1.0, d)
	var machine := _make_machine(d)

	_t.check(not machine._should_gesture(warrior, true, warrior),
		"same executor + board has damage -> suppressed (the actual bug)")
	_t.check(machine._should_gesture(warrior, false, warrior),
		"same executor but no damage icon this board -> still gestures")
	_t.check(machine._should_gesture(mage, true, warrior),
		"different executor -> gestures even though the board has damage")
	_t.check(machine._should_gesture(warrior, true, null),
		"no damage executor at all -> gestures (nothing to collide with)")

## The reported case: a solo warrior, one enemy, a board with a CLEAVE icon
## ahead of a DAMAGE icon. Before the fix, the enemy never took the swing's
## damage - the cosmetic CLEAVE gesture ate it.
func _case_cleave_plus_damage() -> void:
	print("--- board: CLEAVE + DAMAGE, solo warrior ---")
	var d := FakeDirector.new()
	add_child(d)
	var warrior := _spawn(&"warrior", -3.0, d)
	var enemy := _spawn(&"shadow_monster", 2.0, d)
	d.heroes = [warrior]
	d.enemies = [enemy]
	var machine := _make_machine(d)
	machine._board = _rigged_board(&"cleave", SlotIcon.BASE_WEAPON)

	var before := enemy.current_hp
	await machine._resolve_board(&"")
	_t.check(enemy.current_hp < before,
		"the real swing landed despite the CLEAVE icon resolving first (got hp %d, was %d)"
			% [enemy.current_hp, before])
	_t.check(not machine._pending_cleave,
		"CLEAVE's own buff still armed-and-consumed normally (unaffected by the gesture fix)")

## Same collision, BLEED's side: BLEED shares the warrior's executes list too.
func _case_bleed_plus_damage() -> void:
	print("--- board: BLEED + DAMAGE, solo warrior ---")
	var d := FakeDirector.new()
	add_child(d)
	var warrior := _spawn(&"warrior", -3.0, d)
	var enemy := _spawn(&"shadow_monster", 2.0, d)
	d.heroes = [warrior]
	d.enemies = [enemy]
	var machine := _make_machine(d)
	machine._board = _rigged_board(&"bleed", SlotIcon.BASE_WEAPON)

	var before := enemy.current_hp
	await machine._resolve_board(&"")
	_t.check(enemy.current_hp < before,
		"the real swing landed despite the BLEED icon resolving first (got hp %d, was %d)"
			% [enemy.current_hp, before])
	_t.check(enemy.is_bleeding(), "BLEED's own effect still applied (unaffected by the gesture fix)")

## A 9-cell board: `first_id` at index 0, `damage_id` at index 8, everything
## else blank - first_id resolves well before the aggregated swing fires.
func _rigged_board(first_id: StringName, damage_id: StringName) -> Array:
	var board: Array = []
	for i: int in range(9):
		board.append(SlotIcon.blank())
	board[0] = {"id": first_id, "roll": 6, "enhanced": false}
	board[8] = {"id": damage_id, "roll": 12, "enhanced": false}
	return board
