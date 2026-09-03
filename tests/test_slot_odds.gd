extends Node
## The icon bag (spec: Slot Phase 2, §2).
##
## Run headless from the project root:
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_slot_odds.tscn
##
## [slot phase 2] Replaces the old 27-stop match-to-win verification wholesale.
## The reel is a bag now: nine icons drawn WITHOUT replacement each spin. This
## asserts:
##   - the draw is unbiased - a single-copy icon lands with frequency 9 / bag,
##     and never appears twice on one board (the without-replacement property);
##   - board density matches the §2 calibration table at each progression stage;
##   - the bag is never empty of icons, so a cold streak can never leave the
##     party with no output across a fight.

const TestSupport := preload("res://tests/test_support.gd")
const SlotMachineScript := preload("res://scripts/console/slot_machine.gd")

const DRAWS := 200_000

## (label, non-blank icons, bag size, expected icons per spin) from §2.
const STAGES := [
	["start (1 hero, 3 Uncommons)", 4, 16, 2.25],
	["mid (1 hero, 3 Magic)", 7, 19, 3.32],
	["late (1 hero, 3 Enhanced, blanks bought down)", 13, 17, 6.88],
]

func _ready() -> void:
	var t := TestSupport.new()
	_test_density(t)
	_test_unbiased(t)
	_test_never_all_blank(t)
	_test_cold_streak(t)
	t.finish(get_tree(), "test_slot_odds")

# --- board density (§2 table) ---------------------------------------------------

func _test_density(t: RefCounted) -> void:
	print("--- board density by stage ---")
	for stage: Array in STAGES:
		var label: String = stage[0]
		var n_icons: int = stage[1]
		var bag_size: int = stage[2]
		var want: float = stage[3]
		var bag := _bag(n_icons, bag_size)
		t.check(bag.size() == bag_size,
			"%s: bag is %d entries" % [label, bag_size])

		var total_icons := 0
		var trials := 20_000
		for _i: int in range(trials):
			var board: Array = SlotMachineScript.draw_nine(bag)
			for ic: Dictionary in board:
				if not SlotIcon.is_blank(ic):
					total_icons += 1
		var per_spin := float(total_icons) / float(trials)
		# The exact expectation of a hypergeometric draw: n_icons * 9 / bag_size.
		var exact := float(n_icons) * 9.0 / float(bag_size)
		print("  %s: %.2f icons/spin (table %.2f, exact %.3f)" % [label, per_spin, want, exact])
		t.check_near(per_spin, exact, 0.06,
			"%s: observed density tracks the hypergeometric mean" % label)
		t.check_near(exact, want, 0.05,
			"%s: the §2 table value matches n*9/bag" % label)

# --- unbiased draw-without-replacement ---------------------------------------

func _test_unbiased(t: RefCounted) -> void:
	print("--- unbiased draw ---")
	# A bag of one MARKED single-copy icon, eight other icons, and blanks.
	var marked := { "id": &"dmg_flat", "roll": 99, "enhanced": true }
	var bag: Array = [marked]
	for i: int in range(8):
		bag.append({ "id": _rotating_id(i), "roll": 5, "enhanced": false })
	for _i: int in range(12):
		bag.append(SlotIcon.blank())
	var bag_size := bag.size()

	var appearances := 0
	var double_count := 0
	for _i: int in range(DRAWS):
		var board: Array = SlotMachineScript.draw_nine(bag)
		var here := 0
		for ic: Dictionary in board:
			if int(ic.get("roll", 0)) == 99 and bool(ic.get("enhanced", false)):
				here += 1
		if here > 0:
			appearances += 1
		if here > 1:
			double_count += 1

	var rate := float(appearances) / float(DRAWS)
	var expect := 9.0 / float(bag_size)   # P(a given single copy is among the 9 drawn)
	print("  marked-icon appearance rate: %.4f (expected %.4f), doubles: %d" % [rate, expect, double_count])
	t.check_near(rate, expect, 0.01,
		"a single-copy icon is drawn at 9 / bag_size, no position bias")
	t.check(double_count == 0,
		"a single-copy icon never appears twice on one board (draw is without replacement)")

# --- the bag is never empty of icons (§2) -----------------------------------

func _test_never_all_blank(t: RefCounted) -> void:
	# The innate icon alone guarantees a non-blank in the bag even with zero gear.
	var bag := _bag(1, 13)   # 1 innate + 12 blanks, no items
	var icons := 0
	for ic: Dictionary in bag:
		if not SlotIcon.is_blank(ic):
			icons += 1
	t.check(icons >= 1, "an ungeared solo party still has one icon in the bag (the innate)")

func _test_cold_streak(t: RefCounted) -> void:
	# Start stage, a full fight's worth of spins: the probability that EVERY
	# board comes up all-blank is vanishing, so the party always gets output.
	var bag := _bag(4, 16)
	var dead_fights := 0
	var fights := 2000
	var spins_per_fight := 15
	for _f: int in range(fights):
		var any_output := false
		for _s: int in range(spins_per_fight):
			for ic: Dictionary in SlotMachineScript.draw_nine(bag):
				if not SlotIcon.is_blank(ic):
					any_output = true
					break
			if any_output:
				break
		if not any_output:
			dead_fights += 1
	print("--- cold streak: %d of %d start-stage fights produced no output at all ---"
		% [dead_fights, fights])
	t.check(dead_fights == 0,
		"no start-stage fight (15 spins) ever produced zero output")

# --- helpers ----------------------------------------------------------------

## A bag of `n_icons` non-blank icons (one innate, the rest rotating modifier
## icons) padded with blanks to `bag_size`.
func _bag(n_icons: int, bag_size: int) -> Array:
	var bag: Array = [SlotIcon.innate(&"warrior")]
	for i: int in range(maxi(n_icons - 1, 0)):
		bag.append({ "id": _rotating_id(i), "roll": 5, "enhanced": false })
	while bag.size() < bag_size:
		bag.append(SlotIcon.blank())
	return bag

func _rotating_id(i: int) -> StringName:
	var ids: Array[StringName] = [&"dmg_flat", &"slot_bolt", &"slot_mend", &"elem_fire"]
	return ids[i % ids.size()]
