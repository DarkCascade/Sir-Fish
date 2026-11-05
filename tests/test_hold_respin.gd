extends Node
## Hold-and-respin (#101, backlog decision 7.6 as reshaped 2026-11-03).
##
## A tap on a landed cell starts a hold and drops Engine.time_scale to
## Tuning.HOLD_TIME_SCALE while the player picks cells to keep; confirming
## respins the rest from the bag minus the kept icons. This asserts:
##   - redraw() keeps the held cells, draws the others without replacement from
##     the bag minus the kept icons, and never repeats an icon on the board;
##   - a tap starts a hold only inside the window, on a landed reel, with a
##     hold in hand, and a started hold crawls the world and a finished one
##     puts it back;
##   - a hold is spent only by a respin that happens: confirming with nothing
##     held, or every cell held, costs nothing;
##   - a fight ending mid-pick releases the spin loop and the time scale at once.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_hold_respin.tscn

const TestSupport := preload("res://tests/test_support.gd")
const SlotMachineScript := preload("res://scripts/console/slot_machine.gd")
const SLOT_MACHINE_SCENE := preload("res://scenes/console/slot_machine.tscn")

var _t := TestSupport.new()

func _ready() -> void:
	_test_redraw()
	await _test_hold_gating()
	await _test_hold_lifecycle()
	await _test_spend_rules()
	await _test_fight_end_releases()
	Engine.time_scale = 1.0
	_t.finish(get_tree(), "test_hold_respin")

# --- redraw ---------------------------------------------------------------------

func _bag(n_icons: int, bag_size: int) -> Array:
	var bag: Array = []
	for i: int in range(n_icons):
		bag.append(SlotIcon.innate(&"warrior", i + 1))
	while bag.size() < bag_size:
		bag.append(SlotIcon.blank())
	return bag

func _test_redraw() -> void:
	print("--- redraw ---")
	var bag := _bag(7, 19)
	var kept_ok := true
	var unique_ok := true
	var changed := 0
	var trials := 2000
	for _n: int in range(trials):
		var board: Array = SlotMachineScript.draw_nine(bag)
		var held: Array = [4, 0]
		var after: Array = SlotMachineScript.redraw(bag, board, held)
		if after.size() != Tuning.SLOT_BOARD_CELLS:
			unique_ok = false
		for index: int in held:
			if not is_same(after[index], board[index]):
				kept_ok = false
		# Without replacement: no bag entry appears twice, kept cells included.
		for i: int in range(after.size()):
			for j: int in range(i + 1, after.size()):
				if is_same(after[i], after[j]):
					unique_ok = false
		for i: int in range(after.size()):
			if not held.has(i) and not is_same(after[i], board[i]):
				changed += 1
	_t.check(kept_ok, "redraw keeps every held cell as the same icon")
	_t.check(unique_ok, "redraw never repeats an icon on the board")
	_t.check(changed > 0, "redraw replaces the cells that were not held")

	# All nine held leaves nothing to draw: the board comes back unchanged.
	var board9: Array = SlotMachineScript.draw_nine(bag)
	var all: Array = SlotMachineScript.redraw(bag, board9, range(9))
	var same := true
	for i: int in range(9):
		same = same and is_same(all[i], board9[i])
	_t.check(same, "redraw with every cell held changes nothing")

	# A short bag still yields a full board.
	var tiny: Array = SlotMachineScript.redraw(_bag(2, 2), SlotMachineScript.draw_nine(_bag(2, 2)), [0])
	_t.check(tiny.size() == Tuning.SLOT_BOARD_CELLS, "redraw pads a short bag to nine cells")

# --- the state machine ------------------------------------------------------------

func _machine() -> Control:
	var machine := SLOT_MACHINE_SCENE.instantiate() as Control
	add_child(machine)
	machine._should_spin = true
	machine._landed.assign([true, true, true])
	machine._hold_window = true
	machine._holds_left = 1
	machine._board = SlotMachineScript.draw_nine(_bag(7, 19))
	machine._bag = _bag(7, 19)
	return machine

func _real_wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func _test_hold_gating() -> void:
	print("--- gating ---")
	var m := _machine()
	m._hold_window = false
	_t.check(not m.hold_cell(4), "a tap outside the window does nothing")
	m._hold_window = true
	m._landed.assign([true, false, false])
	_t.check(not m.hold_cell(1), "a cell whose reel has not landed cannot be held")
	_t.check(m.hold_cell(0), "a cell on a landed reel can start a hold")
	m.confirm_hold()
	m._respin_held = []
	m._holds_left = 0
	m._hold_window = true
	m._landed.assign([true, true, true])
	_t.check(not m.hold_cell(4), "with no hold left a tap does nothing")
	_t.check(not m.hold_cell(-1) and not m.hold_cell(9), "an out-of-range cell is ignored")
	m.queue_free()
	await _real_wait(0.3)
	Engine.time_scale = 1.0

func _test_hold_lifecycle() -> void:
	print("--- lifecycle ---")
	var m := _machine()
	var started := [0]
	var ended := [0]
	m.hold_started.connect(func(_h: Array) -> void: started[0] += 1)
	m.hold_ended.connect(func() -> void: ended[0] += 1)
	_t.check(m.hold_cell(4), "a tap starts the hold")
	_t.check(m.is_holding() and started[0] == 1, "the machine reports holding and signals once")
	await _real_wait(Tuning.HOLD_TIME_SCALE_RAMP + 0.2)
	_t.check_near(Engine.time_scale, Tuning.HOLD_TIME_SCALE, 0.01, "the world crawls while picking")
	_t.check(m.hold_cell(2) and m.held_cells() == [2, 4], "a second tap adds a cell, listed ascending")
	_t.check(m.hold_cell(2) and m.held_cells() == [4], "tapping a held cell lets it go")
	m.confirm_hold()
	_t.check(not m.is_holding() and ended[0] == 1, "confirming ends the hold once")
	_t.check(m._respin_held == [4], "confirming with a cell kept queues the respin")
	await _real_wait(Tuning.HOLD_TIME_SCALE_RAMP + 0.2)
	_t.check_near(Engine.time_scale, 1.0, 0.01, "the world returns to full speed")
	m.queue_free()
	await _real_wait(0.1)

func _test_spend_rules() -> void:
	print("--- spend ---")
	var m := _machine()
	m.hold_cell(4)
	m.hold_cell(4)   # let it go again: nothing held
	m.confirm_hold()
	_t.check(m.holds_left() == 1 and m._respin_held.is_empty(),
		"confirming with nothing held costs no hold and queues no respin")

	m._hold_window = true
	for i: int in range(9):
		m.hold_cell(i)
	m.confirm_hold()
	_t.check(m.holds_left() == 1 and m._respin_held.is_empty(),
		"holding every cell costs no hold - there is nothing to respin")

	m._hold_window = true
	m.hold_cell(3)
	m.confirm_hold()
	_t.check(m.holds_left() == 0 and m._respin_held == [3],
		"a real respin spends the hold")
	m.queue_free()
	await _real_wait(0.3)
	Engine.time_scale = 1.0

func _test_fight_end_releases() -> void:
	print("--- fight end ---")
	var m := _machine()
	var released := [false]
	m._hold_picked.connect(func() -> void: released[0] = true)
	m.hold_cell(4)
	await _real_wait(Tuning.HOLD_TIME_SCALE_RAMP + 0.2)
	m._on_combat_ended(false)
	_t.check(Engine.time_scale == 1.0, "a fight ending mid-pick restores the time scale at once")
	_t.check(released[0] and not m.is_holding(), "and releases the spin loop's wait")
	_t.check(m.holds_left() == 1 and m._respin_held.is_empty(), "and does not spend the hold or respin")
	m.queue_free()
	await _real_wait(0.1)
