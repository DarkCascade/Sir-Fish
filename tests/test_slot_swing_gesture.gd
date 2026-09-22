extends Node
## Regression: a board that rolls both a DAMAGE icon and a gesture icon (then
## CLEAVE or BLEED, [slot vocabulary] now a charge coin) used to silently eat
## the warrior's real swing.
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
## skipped when its executor is one of the heroes really swinging this board,
## since that real swing already carries the visual.
##
## [owner swings] Still the right regression even though damage is banked per
## owner now: a hero whose own charge coin and strike land on the same board
## gets a gesture and a real swing at once.
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

	## [owner swings] A ranger/mage slot swing resolves through that hero's own
	## PRIMARY ability, and theirs is a ProjectileAbility - which parents its
	## projectile under world.projectile_root and, for a melee world_shake, calls
	## world.shake(). Two stubs are the whole surface those two need, and without
	## them a ranged owner's swing throws instead of landing its damage.
	var world := FakeWorld.new()

	func lowest_hp_living_hero() -> Combatant:
		var best: Combatant = null
		for h: Combatant in living_heroes():
			if best == null or h.current_hp < best.current_hp:
				best = h
		return best

## Just the two members the ability defs reach for (projectile_ability.gd:20,
## melee_strike_ability.gd:42).
class FakeWorld extends Node3D:
	var projectile_root: Node3D

	func _init() -> void:
		projectile_root = Node3D.new()
		add_child(projectile_root)

	func shake(_amount: float, _time: float) -> void:
		pass

var _t := TestSupport.new()

func _ready() -> void:
	_test_should_gesture_unit()
	_test_swing_owner_routing()
	await _case_cleave_plus_damage()
	await _case_bleed_plus_damage()
	await _case_owned_icons_swing_their_own_hero()
	await _case_absent_owner_still_lands()
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
	add_child(d.world)
	var warrior := _spawn(&"warrior", -3.0, d)
	var mage := _spawn(&"mage", -1.0, d)
	var machine := _make_machine(d)

	# [owner swings] _should_gesture takes the list of heroes who will really
	# swing this board, rather than a single DAMAGE executor.
	_t.check(not machine._should_gesture(warrior, [warrior] as Array[Combatant]),
		"hero has a real swing this board -> suppressed (the actual bug)")
	_t.check(machine._should_gesture(warrior, [] as Array[Combatant]),
		"no swing at all this board -> still gestures")
	_t.check(machine._should_gesture(mage, [warrior] as Array[Combatant]),
		"a different hero swings -> this one still gestures")
	_t.check(machine._should_gesture(mage, [warrior, mage] as Array[Combatant]) == false,
		"both heroes swing -> each is suppressed, not just the first")

## [owner swings] Which hero an icon's damage becomes, before any animation is
## involved. This is the whole routing rule: the owner if they are on the field,
## the DAMAGE executor otherwise, and never nobody.
func _test_swing_owner_routing() -> void:
	print("--- _swing_hero_for routing ---")
	var d := FakeDirector.new()
	add_child(d)
	add_child(d.world)
	var warrior := _spawn(&"warrior", -3.0, d)
	var ranger := _spawn(&"ranger", -2.0, d)
	var mage := _spawn(&"mage", -1.0, d)
	d.heroes = [warrior, ranger, mage]
	var machine := _make_machine(d)

	_t.check(machine._swing_hero_for({"owner": &"ranger"}) == ranger,
		"a ranger-owned icon is swung by the ranger, not the DAMAGE executor")
	_t.check(machine._swing_hero_for({"owner": &"mage"}) == mage,
		"a mage-owned icon is swung by the mage")
	_t.check(machine._swing_hero_for({"owner": &"warrior"}) == warrior,
		"a warrior-owned icon is still swung by the warrior")
	# The two fallbacks: an icon with no owner (a rigged board, a legacy save)
	# and an owner who is not on the field (recruited but benched, or dead).
	_t.check(machine._swing_hero_for({}) == warrior,
		"an unowned icon falls back to the DAMAGE executor")
	_t.check(machine._swing_hero_for({"owner": &"sporecap"}) == warrior,
		"an owner who is not on the field falls back to the DAMAGE executor")

	# With the ranger dead her icons must not vanish - they fall to the executor.
	ranger.current_hp = 0
	ranger.state = Combatant.State.DEAD
	_t.check(machine._swing_hero_for({"owner": &"ranger"}) == warrior,
		"a dead owner's icon falls back rather than dropping its damage")

## The reported case: a solo warrior, one enemy, a board with a gesture icon
## ahead of a DAMAGE icon. Before the fix, the enemy never took the swing's
## damage - the cosmetic gesture ate it. [slot vocabulary] The gesture icon is
## a warrior-owned charge coin now (cleave used to arm a buff; it only charges).
func _case_cleave_plus_damage() -> void:
	print("--- board: CHARGE + DAMAGE, solo warrior ---")
	var d := FakeDirector.new()
	add_child(d)
	add_child(d.world)
	var warrior := _spawn(&"warrior", -3.0, d)
	var enemy := _spawn(&"shadow_monster", 2.0, d)
	d.heroes = [warrior]
	d.enemies = [enemy]
	var machine := _make_machine(d)
	machine._board = _rigged_board(&"cleave", SlotIcon.BASE_WEAPON)
	var saved_charges: Dictionary = GameState.special_charges.duplicate()
	GameState.special_charges[&"warrior"] = 0

	var before := enemy.current_hp
	await machine._resolve_board([])
	_t.check(enemy.current_hp < before,
		"the real swing landed despite the charge coin resolving first (got hp %d, was %d)"
			% [enemy.current_hp, before])
	# The rigged strike has no owner, so it charges nobody; the coin is the lot.
	_t.check(GameState.special_charge(&"warrior") == Tuning.SLOT_CHARGE_ICON_CHARGE,
		"the coin charged its owner SLOT_CHARGE_ICON_CHARGE (got %d)"
			% GameState.special_charge(&"warrior"))
	GameState.special_charges = saved_charges

## [slot vocabulary] Bleed is a weapon stat, not an icon: a warrior whose sword
## carries `bleed` opens a bleed off his swings at Tuning.BLEED_PROC_CHANCE, and
## a sword without it never does.
func _case_bleed_plus_damage() -> void:
	print("--- bleed as a weapon stat, solo warrior ---")
	var d := FakeDirector.new()
	add_child(d)
	add_child(d.world)
	var warrior := _spawn(&"warrior", -3.0, d)
	var enemy := _spawn(&"shadow_monster", 2.0, d)
	d.heroes = [warrior]
	d.enemies = [enemy]
	var machine := _make_machine(d)

	var saved_inventory: Array[Item] = GameState.inventory.duplicate()
	var sword := Itemizer.generate_typed_item(&"sword", Item.Rarity.COMMON, 1)
	sword.equipped_by = &"warrior"
	GameState.inventory = [sword]
	for _i: int in range(30):
		machine._swing_for(warrior, 5, enemy)
	_t.check(not enemy.is_bleeding(), "a sword with no bleed modifier never opens a bleed")

	sword.modifiers = [{ "id": &"bleed", "roll": 6 }]
	# 30 swings at BLEED_PROC_CHANCE: missing every one is ~0.65^30, never.
	for _i: int in range(30):
		machine._swing_for(warrior, 5, enemy)
	_t.check(enemy.is_bleeding(), "a bleed sword opens a bleed off its swings")
	GameState.inventory = saved_inventory

## [owner swings] A board whose damage is owned entirely by the ranger and the
## mage. Before the split every DAMAGE icon fed one warrior swing, so those two
## stood idle while he hit for their gear.
##
## Note what a ranged owner's swing now costs: it resolves through that hero's
## own PRIMARY ability (Ability.make_slot_strike -> _resolved_def), so the ranger
## and mage really do send projectiles off the board - "the day the party has one"
## in make_slot_strike's own comment is today. FakeWorld exists for exactly that.
## Their arrival is asynchronous, hence the generous wait below.
func _case_owned_icons_swing_their_own_hero() -> void:
	print("--- board: ranger-owned + mage-owned damage ---")
	var d := FakeDirector.new()
	add_child(d)
	add_child(d.world)
	var warrior := _spawn(&"warrior", -3.0, d)
	var ranger := _spawn(&"ranger", -2.0, d)
	var mage := _spawn(&"mage", -1.0, d)
	var enemy := _spawn(&"shadow_monster", 2.0, d)
	d.heroes = [warrior, ranger, mage]
	d.enemies = [enemy]
	var machine := _make_machine(d)
	var board: Array = []
	for i: int in range(9):
		board.append(SlotIcon.blank())
	board[0] = {"id": SlotIcon.BASE_WEAPON, "roll": 12, "enhanced": false, "owner": &"ranger"}
	board[4] = {"id": SlotIcon.BASE_WEAPON, "roll": 12, "enhanced": false, "owner": &"mage"}
	machine._board = board

	var before := enemy.current_hp
	await machine._resolve_board([])
	_t.check(ranger.state == Combatant.State.ATTACKING, "the ranger plays her own swing")
	_t.check(mage.state == Combatant.State.ATTACKING, "the mage plays his own swing")
	_t.check(warrior.state != Combatant.State.ATTACKING,
		"the warrior does not swing for gear that is not his")

	# Their arrows/bolts are still in flight when the spin's own resolution ends,
	# and they arrive at different times (flight time scales with distance), so
	# this waits for the enemy's hp to STOP moving - waiting only for the first
	# drop would measure one share and miss the other.
	await _await_hp_settled(enemy, 3.0)
	# Not just "some damage": both shares must arrive at full strength. Each icon
	# is roll 12 + SLOT_ATTACK_ICON_FLOOR, +/- DAMAGE_VARIANCE, so the pair is
	# ~38 before armor. A projectile that ignored the swing's own total would
	# arrive for compute_damage() instead - 1 per hit, the bug this pins.
	var dealt := before - enemy.current_hp
	var one_icon: int = 12 + Tuning.SLOT_ATTACK_ICON_FLOOR
	_t.check(dealt > one_icon * 3 / 2,
		"both owners' shares arrive, not a 1-damage compute_damage() fallback (dealt %d, one icon is %d)"
			% [dealt, one_icon])

## Waits until `c`'s hp has been unchanged for QUIET seconds, or `timeout`
## elapses - "every projectile still in flight has arrived".
func _await_hp_settled(c: Combatant, timeout: float) -> void:
	const QUIET := 0.35
	var waited := 0.0
	var quiet := 0.0
	var last := c.current_hp
	while waited < timeout and quiet < QUIET:
		await get_tree().process_frame
		var dt := get_tree().root.get_process_delta_time()
		waited += dt
		if c.current_hp != last:
			last = c.current_hp
			quiet = 0.0
		else:
			quiet += dt

## [owner swings] The fallback, end to end: an icon owned by a hero who is not
## on the field must still land its damage, through the DAMAGE executor. This is
## the guarantee that the split moved damage around rather than losing some.
func _case_absent_owner_still_lands() -> void:
	print("--- board: icon owned by an absent hero, solo warrior ---")
	var d := FakeDirector.new()
	add_child(d)
	add_child(d.world)
	var warrior := _spawn(&"warrior", -3.0, d)
	var enemy := _spawn(&"shadow_monster", 2.0, d)
	d.heroes = [warrior]
	d.enemies = [enemy]
	var machine := _make_machine(d)
	var board: Array = []
	for i: int in range(9):
		board.append(SlotIcon.blank())
	board[0] = {"id": SlotIcon.BASE_WEAPON, "roll": 12, "enhanced": false, "owner": &"ranger"}
	machine._board = board

	var before := enemy.current_hp
	await machine._resolve_board([])
	_t.check(enemy.current_hp < before,
		"a ranger-owned icon with no ranger on the field still lands, via the warrior (got hp %d, was %d)"
			% [enemy.current_hp, before])

## A 9-cell board: `first_id` at index 0, `damage_id` at index 8, everything
## else blank - first_id resolves well before the aggregated swing fires.
func _rigged_board(first_id: StringName, damage_id: StringName) -> Array:
	var board: Array = []
	for i: int in range(9):
		board.append(SlotIcon.blank())
	board[0] = {"id": first_id, "roll": 6, "enhanced": false, "owner": &"warrior"}
	board[8] = {"id": damage_id, "roll": 12, "enhanced": false}
	return board
