extends Node
## Cell locks (Tuning.LOCK_MODE): the run's locks, spent a cell at a time.
##
## A tap on a settled cell locks it; every spin it stays locked the cell keeps its
## icon and one lock is spent. This asserts:
##   - a lock needs a board at rest, a non-blank cell, and a lock left to pay for
##     it, and a second tap frees the cell;
##   - the next board keeps the locked cells, spends one lock each, and draws the
##     rest without repeating an icon - also when the bag was rebuilt between
##     spins, so its entries are new copies;
##   - a lock the bag can no longer back is dropped for free, and one the count
##     cannot cover is trimmed;
##   - a lock count that has run out frees every cell once the board is at rest,
##     and a fight ending frees them while keeping the unspent locks.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_cell_locks.tscn

const TestSupport := preload("res://tests/test_support.gd")
const SlotMachineScript := preload("res://scripts/console/slot_machine.gd")
const SLOT_MACHINE_SCENE := preload("res://scenes/console/slot_machine.tscn")

var _t := TestSupport.new()

func _ready() -> void:
	_test_lock_rules()
	_test_deal_keeps_and_spends()
	_test_rebuilt_bag()
	_test_unbacked_and_overcommitted()
	_test_settle_and_combat_end()
	_test_tap_routing()
	_test_unlock_cell()
	await _test_targeting()
	Engine.time_scale = 1.0
	_t.finish(get_tree(), "test_cell_locks")

func _bag(n_icons: int, bag_size: int) -> Array:
	var bag: Array = []
	for i: int in range(n_icons):
		bag.append(SlotIcon.innate(&"warrior", i + 1))
	while bag.size() < bag_size:
		bag.append(SlotIcon.blank())
	return bag

## A machine holding a board at rest: bag of 7 distinct icons + 12 blanks, nine
## cells dealt, three locks, the edit window open.
func _machine() -> Control:
	var m := SLOT_MACHINE_SCENE.instantiate() as Control
	add_child(m)
	m._should_spin = true
	m._bag = _bag(7, 19)
	m._board = SlotMachineScript.draw_nine(m._bag)
	m._locks_left = 3
	m._lock_edit_open = true
	return m

## Board indices of the non-blank / blank cells.
func _cells_where(board: Array, blank: bool) -> Array:
	var out: Array = []
	for i: int in range(board.size()):
		if SlotIcon.is_blank(board[i]) == blank:
			out.append(i)
	return out

## No non-blank icon value shows up twice on the board.
func _no_repeats(board: Array) -> bool:
	var seen: Array = []
	for icon: Dictionary in board:
		if SlotIcon.is_blank(icon):
			continue
		if seen.has(icon):
			return false
		seen.append(icon)
	return true

## A board with at least `n` non-blank cells, so a test never depends on luck.
func _rich_machine(n: int) -> Control:
	var m := _machine()
	while _cells_where(m._board, false).size() < n:
		m._board = SlotMachineScript.draw_nine(m._bag)
	return m

func _test_lock_rules() -> void:
	print("--- lock rules ---")
	var m := _rich_machine(3)
	var live: Array = _cells_where(m._board, false)
	var blanks: Array = _cells_where(m._board, true)
	var changes := [0]
	m.locks_changed.connect(func(_l: Array, _n: int) -> void: changes[0] += 1)

	m._lock_edit_open = false
	_t.check(not m.lock_cell(live[0]), "a board still spinning takes no lock")
	m._lock_edit_open = true
	_t.check(not m.lock_cell(-1) and not m.lock_cell(9), "an out-of-range cell is ignored")
	if not blanks.is_empty():
		_t.check(not m.lock_cell(blanks[0]), "a blank cell is never worth a lock")
	_t.check(m.lock_cell(live[0]) and m.locked_cells() == [live[0]], "a settled icon locks")
	_t.check(changes[0] == 1, "locking signals once")
	_t.check(m.lock_cell(live[0]) and m.locked_cells().is_empty(), "a second tap frees the cell")
	_t.check(m.locks_left() == 3, "a tap costs nothing: locks are spent when a spin is dealt")

	m._locks_left = 2
	m.lock_cell(live[0])
	m.lock_cell(live[1])
	_t.check(not m.lock_cell(live[2]), "locked cells cannot outnumber the locks left")
	_t.check(m.locked_cells() == [live[0], live[1]], "and the earlier locks stand")
	m.queue_free()

func _test_deal_keeps_and_spends() -> void:
	print("--- the next board ---")
	var m := _rich_machine(3)
	var live: Array = _cells_where(m._board, false)
	var a: int = live[0]
	var b: int = live[1]
	var before: Array = m._board.duplicate()
	m.lock_cell(a)
	m.lock_cell(b)
	var after: Array = m._deal_board()
	_t.check(after.size() == Tuning.SLOT_BOARD_CELLS, "a full board is dealt")
	_t.check(is_same(after[a], before[a]) and is_same(after[b], before[b]),
		"locked cells keep the very icons they held")
	_t.check(m.locks_left() == 1, "each locked cell spends one lock")
	_t.check(m.locked_cells() == [a, b], "the cells stay locked for the spin")
	_t.check(_no_repeats(after), "no icon is repeated around the locked cells")
	m.queue_free()

func _test_rebuilt_bag() -> void:
	print("--- a rebuilt bag ---")
	var repeats_ok := true
	var kept_ok := true
	for _n: int in range(300):
		var m := _rich_machine(3)
		var live: Array = _cells_where(m._board, false)
		var a: int = live[0]
		var icon: Dictionary = m._board[a]
		m.lock_cell(a)
		# Every spin rebuilds the bag: same icons, new dictionaries.
		m._bag = _bag(7, 19)
		var after: Array = m._deal_board()
		if after[a] != icon:
			kept_ok = false
		if not _no_repeats(after):
			repeats_ok = false
		m.queue_free()
	_t.check(kept_ok, "a lock survives the bag being rebuilt between spins")
	_t.check(repeats_ok, "and its icon is not dealt a second time (300 boards)")

func _test_unbacked_and_overcommitted() -> void:
	print("--- unbacked and over-committed ---")
	var m := _rich_machine(3)
	var live: Array = _cells_where(m._board, false)
	m.lock_cell(live[0])
	# The icon's owner left the bag: nothing to keep, nothing to pay for.
	var gone: Dictionary = m._board[live[0]]
	var thinned: Array = []
	for icon: Dictionary in m._bag:
		if icon != gone:
			thinned.append(icon)
	m._bag = thinned
	m._deal_board()
	_t.check(m.locked_cells().is_empty() and m.locks_left() == 3,
		"a lock whose icon left the bag is dropped for free")
	m.queue_free()

	var n := _rich_machine(3)
	var cells: Array = _cells_where(n._board, false)
	n._locked = [cells[0], cells[1], cells[2]]
	n._locks_left = 2
	n._deal_board()
	_t.check(n.locked_cells() == [cells[0], cells[1]] and n.locks_left() == 0,
		"more locked cells than locks left is trimmed to what can be paid")
	n.queue_free()

func _test_settle_and_combat_end() -> void:
	print("--- running out, and fights ending ---")
	var m := _rich_machine(3)
	var live: Array = _cells_where(m._board, false)
	var seen := []
	m.locks_changed.connect(func(l: Array, _n: int) -> void: seen.append(l.size()))
	m._locked = [live[0]]
	m._locks_left = 0
	m._settle_locks()
	_t.check(m.locked_cells().is_empty() and seen == [0],
		"with no locks left, the board at rest frees every cell")

	m._locked = [live[0], live[1]]
	m._locks_left = 2
	m._on_combat_ended(false)
	_t.check(m.locked_cells().is_empty() and m.locks_left() == 2,
		"a fight ending frees the cells and keeps the unspent locks")
	_t.check(not m.lock_cell(live[0]), "and a board that is gone takes no lock")
	m.queue_free()

func _test_tap_routing() -> void:
	print("--- tap routing ---")
	var m := _rich_machine(3)
	var live: Array = _cells_where(m._board, false)
	_t.check(Tuning.LOCK_MODE, "the experiment ships with LOCK_MODE on")
	_t.check(m.taps_available(), "taps are available while locks remain")
	_t.check(m.tap_cell(live[0]) and m.locked_cells() == [live[0]],
		"a tap locks in lock mode")
	m._locks_left = 0
	m._locked.clear()
	_t.check(not m.taps_available(), "with nothing left to spend or free, taps are not")
	m.queue_free()

## A quick tap frees a locked cell and never locks one.
func _test_unlock_cell() -> void:
	print("--- quick-tap unlock ---")
	var m := _rich_machine(3)
	var live: Array = _cells_where(m._board, false)
	var changes := [0]
	m.locks_changed.connect(func(_l: Array, _n: int) -> void: changes[0] += 1)
	_t.check(not m.unlock_cell(live[0]) and m.locked_cells().is_empty() and changes[0] == 0,
		"a tap on a cell that is not locked does nothing, and locks nothing")
	m.lock_cell(live[0])
	m.lock_cell(live[1])
	changes[0] = 0
	m._lock_edit_open = false
	_t.check(not m.unlock_cell(live[0]), "a board still spinning cannot be unlocked")
	m._lock_edit_open = true
	_t.check(m.unlock_cell(live[0]) and m.locked_cells() == [live[1]] and changes[0] == 1,
		"a tap on a locked cell frees it, and only it, and signals once")
	_t.check(m.locks_left() == 3, "freeing a cell costs and refunds nothing")
	_t.check(not m.unlock_cell(live[0]), "and a second tap on it does nothing")
	m.queue_free()

func _real_wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

## A held press aims at a cell with the world crawling, and lets go by locking it.
func _test_targeting() -> void:
	print("--- aiming a lock ---")
	# A headless run's first tween lags behind its first wait; one throwaway wait
	# first keeps the time-scale checks below honest.
	await _real_wait(0.5)
	var m := _rich_machine(3)
	var live: Array = _cells_where(m._board, false)
	var blanks: Array = _cells_where(m._board, true)
	var seen: Array = []
	m.target_changed.connect(func(i: int) -> void: seen.append(i))

	m._lock_edit_open = false
	_t.check(not m.begin_target(live[0]), "a board still spinning cannot be aimed at")
	m._lock_edit_open = true
	_t.check(not m.begin_target(-1) and not m.begin_target(9), "an out-of-range cell is refused")
	_t.check(m.begin_target(live[0]) and m.is_targeting() and m.target_cell() == live[0],
		"a held press starts aiming at the cell under it")
	_t.check(not m.begin_target(live[1]), "a second press cannot start while one is aiming")
	await _real_wait(Tuning.HOLD_TIME_SCALE_RAMP + 0.2)
	_t.check_near(Engine.time_scale, Tuning.HOLD_TIME_SCALE, 0.01, "the world crawls while aiming")

	m.move_target(live[1])
	_t.check(m.target_cell() == live[1], "dragging moves the target")
	m.move_target(42)
	_t.check(m.target_cell() == -1, "dragging off the board leaves no target")
	m.move_target(live[2])
	_t.check(seen == [live[0], live[1], -1, live[2]], "each change of target is signalled once")

	m.end_target(true)
	_t.check(not m.is_targeting() and m.locked_cells() == [live[2]],
		"releasing locks the cell the finger ended on")
	_t.check(seen[seen.size() - 1] == -1, "and the target is cleared")
	await _real_wait(Tuning.HOLD_TIME_SCALE_RAMP + 0.2)
	_t.check_near(Engine.time_scale, 1.0, 0.01, "and the world returns to full speed")

	m.begin_target(live[2])
	m.end_target(true)
	_t.check(m.locked_cells().is_empty(), "releasing on a locked cell frees it")

	m.begin_target(live[0])
	m.end_target(false)
	_t.check(m.locked_cells().is_empty(), "a press cancelled without committing locks nothing")

	if not blanks.is_empty():
		m.begin_target(blanks[0])
		m.end_target(true)
		_t.check(m.locked_cells().is_empty(), "releasing over a blank cell locks nothing")

	m.begin_target(live[0])
	m.move_target(-1)
	m.end_target(true)
	_t.check(m.locked_cells().is_empty(), "releasing off the board locks nothing")

	m._locks_left = 0
	m.begin_target(live[0])
	m.end_target(true)
	_t.check(m.locked_cells().is_empty(), "with no locks left a release locks nothing")
	await _real_wait(Tuning.HOLD_TIME_SCALE_RAMP + 0.2)

	m._locks_left = 3
	m.begin_target(live[0])
	await _real_wait(Tuning.HOLD_TIME_SCALE_RAMP + 0.2)
	m._on_combat_ended(false)
	_t.check(not m.is_targeting() and Engine.time_scale == 1.0,
		"a fight ending mid-press stops aiming and restores the time scale at once")
	m.queue_free()
	await _real_wait(0.1)
