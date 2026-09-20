extends Node
## [specials] The invokable per-hero special: the charge meter each hero fills
## from their OWN slot icons, and the invoke that spends it.
##
## Why this exists at all: a hero special has been unreachable since the combat
## loop redesign. BattleDirector.request_turn() returns early for heroes, so
## _take_action() - the only thing that reads special_every_n_actions - never
## runs for one. The three hero specials, their AbilityDefs and their `special`
## animation clips were all finished content nothing could fire.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_specials.tscn

const TestSupport := preload("res://tests/test_support.gd")
const SLOT_MACHINE_SCENE := preload("res://scenes/console/slot_machine.tscn")

## The slot machine reaches director.living_heroes() when it resolves a board;
## nothing here needs a real BattleDirector (see _check_invoke_guards for the
## one case that does).
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
		return null if pool.is_empty() else pool[0]

	## A ranged owner's slot swing resolves through their ProjectileAbility, which
	## parents its projectile under world.projectile_root - see
	## test_slot_swing_gesture.gd's FakeWorld for the same two stubs.
	var world := FakeWorld.new()

	func lowest_hp_living_hero() -> Combatant:
		var best: Combatant = null
		for h: Combatant in living_heroes():
			if best == null or h.current_hp < best.current_hp:
				best = h
		return best

class FakeWorld extends Node3D:
	var projectile_root: Node3D

	func _init() -> void:
		projectile_root = Node3D.new()
		add_child(projectile_root)

	func shake(_amount: float, _time: float) -> void:
		pass

var _t := TestSupport.new()

func _ready() -> void:
	_t.guard_user_file(SaveGame.PATH)
	_check_meter()
	_check_run_scoping()
	await _check_board_charges_its_owner()
	_check_authored_specials()
	_check_invoke_guards()
	_t.finish(get_tree(), "test_specials")

# --- the meter ---------------------------------------------------------------

func _check_meter() -> void:
	print("--- charge meter ---")
	GameState.new_profile()
	var cost: int = Tuning.SPECIAL_CHARGE_COST
	_t.check(GameState.special_charge(&"warrior") == 0, "a fresh profile has no charges")
	_t.check(not GameState.special_ready(&"warrior"), "and no special is ready")

	for i: int in range(cost - 1):
		GameState.add_special_charge(&"warrior")
	_t.check(GameState.special_charge(&"warrior") == cost - 1,
		"charges accumulate one per icon (got %d of %d)" % [GameState.special_charge(&"warrior"), cost])
	_t.check(not GameState.special_ready(&"warrior"), "one short of the cost is not ready")

	GameState.add_special_charge(&"warrior")
	_t.check(GameState.special_ready(&"warrior"), "the meter is ready at exactly the cost")

	# Capped, so a long fight banks one activation rather than three.
	for i: int in range(5):
		GameState.add_special_charge(&"warrior")
	_t.check(GameState.special_charge(&"warrior") == cost,
		"charges cap at the cost (got %d)" % GameState.special_charge(&"warrior"))

	# One hero's icons never charge another's meter.
	_t.check(GameState.special_charge(&"ranger") == 0,
		"the warrior's charges did not leak into the ranger's meter")

	_t.check(GameState.spend_special_charges(&"warrior"), "spending a full meter succeeds")
	_t.check(GameState.special_charge(&"warrior") == 0, "and drains it")
	_t.check(not GameState.spend_special_charges(&"warrior"),
		"spending an empty meter fails rather than going negative")
	_t.check(GameState.special_charge(&"warrior") == 0, "a failed spend leaves the meter alone")

	# An icon with no owner charges nobody - see SlotMachine's accrual comment.
	var before: int = GameState.special_charge(&"warrior")
	GameState.add_special_charge(&"")
	_t.check(GameState.special_charge(&"warrior") == before,
		"an unowned icon charges no meter at all")

## Charges are combat momentum, not progression: they must not survive an
## expedition boundary, and they must not be in the save.
func _check_run_scoping() -> void:
	print("--- run scoping ---")
	GameState.new_profile()
	GameState.add_special_charge(&"warrior")
	_t.check(GameState.special_charge(&"warrior") == 1, "charged mid-run")
	GameState.start_expedition(load("res://resources/quests/easy.tres"))
	_t.check(GameState.special_charge(&"warrior") == 0,
		"start_expedition() clears every meter")

	GameState.add_special_charge(&"warrior")
	SaveGame.save_profile()
	var raw := FileAccess.open(SaveGame.PATH, FileAccess.READ)
	var text := raw.get_as_text()
	raw.close()
	_t.check(not text.contains("special_charges"),
		"charges are deliberately absent from the save (momentum, not progression)")

	GameState.new_profile()
	_t.check(GameState.special_charge(&"warrior") == 0, "new_profile() clears them too")
	GameState.quest = null
	GameState.completed_quest = null

# --- accrual off a real board ------------------------------------------------

func _spawn(id: StringName, x: float, d) -> Combatant:
	var stats := GameState.get_stats(id)
	var packed: PackedScene = load(stats.scene_path)
	var c := packed.instantiate() as Combatant
	add_child(c)
	c.position = Vector3(x, 0, 0)
	c.setup(stats, -1)
	c.director = d
	return c

## The accrual rule, through the real resolution path: each resolved icon charges
## the hero that owns it, and only that hero.
func _check_board_charges_its_owner() -> void:
	print("--- a resolved board charges its owners ---")
	GameState.new_profile()
	var d := FakeDirector.new()
	add_child(d)
	add_child(d.world)
	var warrior := _spawn(&"warrior", -3.0, d)
	var ranger := _spawn(&"ranger", -2.0, d)
	var enemy := _spawn(&"shadow_monster", 2.0, d)
	d.heroes = [warrior, ranger]
	d.enemies = [enemy]
	var machine := SLOT_MACHINE_SCENE.instantiate() as Control
	add_child(machine)
	machine.director = d

	# Two warrior-owned icons, one ranger-owned, one unowned, the rest blank.
	var board: Array = []
	for i: int in range(9):
		board.append(SlotIcon.blank())
	board[0] = {"id": SlotIcon.BASE_WEAPON, "roll": 4, "enhanced": false, "owner": &"warrior"}
	board[1] = {"id": SlotIcon.BASE_ARMOR, "roll": 3, "enhanced": false, "owner": &"warrior"}
	board[2] = {"id": SlotIcon.BASE_TRINKET, "roll": 4, "enhanced": false, "owner": &"ranger"}
	board[3] = {"id": SlotIcon.BASE_WEAPON, "roll": 4, "enhanced": false}
	machine._board = board
	await machine._resolve_board(&"")

	_t.check(GameState.special_charge(&"warrior") == 2,
		"the warrior's two icons charged him twice (got %d)" % GameState.special_charge(&"warrior"))
	_t.check(GameState.special_charge(&"ranger") == 1,
		"the ranger's one icon charged her once (got %d)" % GameState.special_charge(&"ranger"))
	# The unowned icon still DEALT its damage (via the executor fallback) but
	# charged nobody - the two rules are deliberately separate.
	_t.check(GameState.special_charge(&"warrior") == 2,
		"the unowned icon charged nobody, though its damage still landed")
	_t.check(enemy.current_hp < enemy.max_hp, "the board still dealt its damage")

# --- the authored specials ---------------------------------------------------

## What each hero's special actually is, so a resource swap cannot quietly leave
## a hero with no special to invoke. Cleave replacing the warrior's Defend is
## still to come; this records what ships today.
func _check_authored_specials() -> void:
	print("--- authored hero specials ---")
	for id: StringName in [&"warrior", &"ranger", &"mage"]:
		var stats := GameState.get_stats(id)
		_t.check(stats != null and stats.special != null,
			"%s has a special AbilityDef to invoke" % id)
		# required_anims() only demands the clip while this is > 0, and the rig
		# profiles all author a `special` clip - keep them agreeing.
		_t.check(stats.special_every_n_actions > 0,
			"%s still declares a special cadence, so its `special` clip stays required" % id)
		_t.check(stats.rig_profile != null and stats.rig_profile.clips.has(&"special"),
			"%s's rig profile authors a `special` clip" % id)

	var mage := GameState.get_stats(&"mage")
	_t.check(mage.special.special_requires_wounded_ally,
		"the mage's heal still declares the wounded-ally rule an invoke has to honour")
	var ranger := GameState.get_stats(&"ranger")
	_t.check(ranger.special is ProjectileAbility and (ranger.special as ProjectileAbility).bomb_payload,
		"the ranger's special is already the bomb arrow")

# --- the invoke ---------------------------------------------------------------

func _fill(hero_class: StringName) -> void:
	while not GameState.special_ready(hero_class):
		GameState.add_special_charge(hero_class)

## BattleDirector.invoke_hero_special() against a REAL director - it extends Node
## with no @onready, so it stands up bare with heroes/enemies assigned. The
## warrior is the subject on purpose: his special is a SelfBuffAbility (Defend),
## which needs neither a target nor a BattleWorld to resolve.
func _check_invoke_guards() -> void:
	print("--- invoke guards ---")
	GameState.new_profile()
	var d := BattleDirector.new()
	add_child(d)
	var warrior := _spawn(&"warrior", -3.0, d)
	var enemy := _spawn(&"shadow_monster", 2.0, d)
	d.heroes = [warrior]
	d.enemies = [enemy]

	_t.check(not d.invoke_hero_special(warrior), "an empty meter refuses the invoke")
	_fill(&"warrior")
	_t.check(d.invoke_hero_special(warrior), "a full meter invokes the special")
	_t.check(GameState.special_charge(&"warrior") == 0, "invoking drains the meter")

	# He is mid-special now, so a second press must bounce off the same ATTACKING
	# guard slot_attack() uses - otherwise the two clips eat each other, which is
	# the bug test_slot_swing_gesture.gd exists for.
	_fill(&"warrior")
	_t.check(not d.invoke_hero_special(warrior),
		"a hero already mid-action refuses the invoke")
	_t.check(GameState.special_ready(&"warrior"),
		"and keeps the meter for the next press, rather than eating it")

	# The mage's wounded-ally rule: refused with the meter intact at full HP.
	var mage := _spawn(&"mage", -1.0, d)
	d.heroes = [warrior, mage]
	_fill(&"mage")
	_t.check(not d.invoke_hero_special(mage),
		"the mage's heal refuses to fire into a party at full hp")
	_t.check(GameState.special_ready(&"mage"), "and keeps her meter")
	mage.current_hp = maxi(1, mage.max_hp - 5)
	_t.check(d.invoke_hero_special(mage), "and fires once somebody is actually hurt")

	# A dead hero never acts.
	var ranger := _spawn(&"ranger", -2.0, d)
	d.heroes = [warrior, mage, ranger]
	_fill(&"ranger")
	ranger.current_hp = 0
	ranger.state = Combatant.State.DEAD
	_t.check(not d.invoke_hero_special(ranger), "a dead hero refuses the invoke")
	_t.check(GameState.special_ready(&"ranger"), "and keeps her meter")
