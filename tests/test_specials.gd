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
	await _check_cleave_special()
	await _check_invoker_boss_theme()
	_check_invoker_tray()
	_check_charge_meter()
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
	# Scored the way the real spin scores it. The counts below assume no payline
	# doubles a cell, so pin that rather than letting a vocabulary change quietly
	# turn a single charge into two.
	var wins: Array = machine._winning_lines()
	_t.check(wins.is_empty(), "the hand-built board wins no payline (got %d)" % wins.size())
	await machine._resolve_board(wins)

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
## a hero with no special to invoke.
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
	# [P7 7.4] Defend replaced by Cleave - see _check_cleave_special() for the
	# hit-all/weapon-Power behaviour itself.
	var warrior := GameState.get_stats(&"warrior")
	_t.check(warrior.special is CleaveAbility,
		"the warrior's special is now Cleave, not Defend")

# --- the invoke ---------------------------------------------------------------

func _fill(hero_class: StringName) -> void:
	while not GameState.special_ready(hero_class):
		GameState.add_special_charge(hero_class)

## BattleDirector.invoke_hero_special() against a REAL director - it extends Node
## with no @onready, so it stands up bare with heroes/enemies assigned. The
## warrior is the subject on purpose: Cleave's special_targets_opponent is
## true, so this also exercises the invoke's opponent-required guard, which a
## purely self-targeted special (Defend, before P7 7.4) never touched.
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

# --- cleave (the warrior's special) -------------------------------------------

## [P7 7.4] Cleave hits every living enemy, scaled off the warrior's equipped
## weapon Power rather than source.compute_damage() - every hero's
## weapon_power/magic_power is 0 now that item Power drives combat damage (see
## resources/stats/warrior.tres), and a special that quietly fell back to
## compute_damage() is the regression that bit ProjectileAbility once already
## (66298b9). Forces resolution via _anim_impact() directly - the same call
## the special clip's own impact call track fires - instead of waiting on real
## animation timing.
func _check_cleave_special() -> void:
	print("--- cleave: the warrior's special ---")
	GameState.new_profile()
	var d := BattleDirector.new()
	add_child(d)
	var warrior := _spawn(&"warrior", -3.0, d)
	var enemy_a := _spawn(&"shadow_monster", 2.0, d)
	var enemy_b := _spawn(&"shadow_monster", 3.0, d)
	d.heroes = [warrior]
	d.enemies = [enemy_a, enemy_b]

	# A known weapon so per-target damage can be checked against
	# compute_damage()'s floor of 1, not just "some positive number".
	# equipped_item()/hero_weapon_power() read GameState.inventory, not just an
	# item's own equipped_by flag, so it has to be appended there too (see
	# test_forge.gd's _test_emits_party_bonuses_changed for the same two-step).
	var axe := Itemizer.generate_typed_item(&"axe", Item.Rarity.RARE, 10)
	GameState.inventory.append(axe)
	GameState.equip_item(axe, &"warrior")

	_fill(&"warrior")
	var before_a := enemy_a.current_hp
	var before_b := enemy_b.current_hp
	_t.check(d.invoke_hero_special(warrior), "cleave invokes with a full meter")
	_t.check(GameState.special_charge(&"warrior") == 0, "and spends the meter")
	_t.check(warrior.state == Combatant.State.ATTACKING, "and the warrior enters ATTACKING")

	warrior._anim_impact()
	# CleaveAbility.resolve() stages one target per Tuning.AOE_STAGGER; give
	# both targets time to resolve before checking either.
	await get_tree().create_timer(Tuning.AOE_STAGGER * 4.0).timeout

	_t.check(enemy_a.current_hp < before_a, "cleave damaged the first enemy")
	_t.check(enemy_b.current_hp < before_b, "cleave damaged the second enemy too, not just one")
	var dealt: int = before_a - enemy_a.current_hp
	_t.check(dealt > 1,
		"per-target damage scales off equipped weapon Power, not compute_damage()'s floor of 1 (got %d)" % dealt)

# --- the invoker buttons ------------------------------------------------------

const INVOKER_TRAY := preload("res://scenes/console/invoker_tray.tscn")

## The tray's three buttons against a REAL director: who is on which slot, that
## the right hero and the right art reach both the button and its meter, that the
## mage's button reads honestly (dark at a full meter and a full-HP party, lit
## once somebody is hurt), and that a press does what invoke_hero_special does.
func _check_invoker_tray() -> void:
	print("--- invoker tray ---")
	GameState.new_profile()
	var d := BattleDirector.new()
	add_child(d)
	var warrior := _spawn(&"warrior", -3.0, d)
	var enemy := _spawn(&"shadow_monster", 2.0, d)
	d.heroes = [warrior]
	d.enemies = [enemy]

	var tray := INVOKER_TRAY.instantiate()
	add_child(tray)
	tray.director = d
	var ranger_b: SpecialInvoker = tray.get_node("RangerInvoker")
	var warrior_b: SpecialInvoker = tray.get_node("WarriorInvoker")
	var mage_b: SpecialInvoker = tray.get_node("MageInvoker")

	# Formation: ranger left, warrior middle, mage right - a fixed slot per class.
	_t.check(ranger_b.position.x < warrior_b.position.x and warrior_b.position.x < mage_b.position.x,
		"the tray reads ranger, warrior, mage from left to right")

	# The hero reaches BOTH the button and its Meter child (one field to set).
	for pair: Array in [[ranger_b, &"ranger"], [warrior_b, &"warrior"], [mage_b, &"mage"]]:
		var b: SpecialInvoker = pair[0]
		_t.check(b.hero_class == pair[1] and (b.get_node("Meter") as ChargeMeter).hero_class == pair[1],
			"%s's button and its meter both track %s" % [pair[1], pair[1]])

	# Each hero has their own render.
	_t.check(ranger_b.get_node("Art").texture != warrior_b.get_node("Art").texture
		and mage_b.get_node("Art").texture != warrior_b.get_node("Art").texture
		and ranger_b.get_node("Art").texture != mage_b.get_node("Art").texture,
		"the three buttons carry three different renders")
	for b: SpecialInvoker in [ranger_b, mage_b]:
		var sz := (b.get_node("Art").texture as Texture2D).get_size()
		var aspect := sz.x / sz.y
		_t.check(absf(aspect - SpecialInvoker.ART_ASPECT) < 0.005,
			"%s's render keeps the cleave's aspect, so the shared tab anchors hold (%.4f vs %.4f)"
				% [b.hero_class, aspect, SpecialInvoker.ART_ASPECT])

	# A hero not in the party has no button; the solo start is just the warrior.
	_t.check(warrior_b.visible and not ranger_b.visible and not mage_b.visible,
		"a solo warrior shows only his own button")
	GameState.active_party = [&"warrior", &"ranger", &"mage"] as Array[StringName]
	EventBus.run_started.emit()
	_t.check(ranger_b.visible and warrior_b.visible and mage_b.visible,
		"a full party shows all three")

	# The mage: full meter, full-HP party -> dark and refuses; hurt -> lit and fires.
	var mage := _spawn(&"mage", -1.0, d)
	var ranger := _spawn(&"ranger", -2.0, d)
	d.heroes = [warrior, mage, ranger]
	_fill(&"mage")
	mage_b._refresh()
	_t.check(mage_b.modulate == SpecialInvoker.DIM,
		"a FULL mage meter at full party HP leaves her button dark, not lit-and-dead")
	mage_b._on_pressed()
	_t.check(GameState.special_ready(&"mage"), "and pressing it spends nothing")
	warrior.current_hp = maxi(1, warrior.max_hp - 5)
	mage_b._refresh()
	_t.check(mage_b.modulate == Color.WHITE, "it lights the moment someone is hurt")
	mage_b._on_pressed()
	_t.check(GameState.special_charge(&"mage") == 0, "and pressing it fires and drains her meter")

	# She aims at no opponent, so she stays usable as the last enemy dies.
	warrior.current_hp = maxi(1, warrior.max_hp - 5)
	enemy.current_hp = 0
	enemy.state = Combatant.State.DEAD
	_fill(&"mage")
	mage.state = Combatant.State.IDLE
	mage_b._refresh()
	_t.check(mage_b.modulate == Color.WHITE, "the mage's button stays lit with no enemy left alive")

	# The ranger's special needs a target: no enemy -> dark; it stays a meter question
	# otherwise. Bring an enemy back and her button lights with a full meter.
	_fill(&"ranger")
	ranger_b._refresh()
	_t.check(ranger_b.modulate == SpecialInvoker.DIM, "the ranger's button is dark with no enemy to aim at")
	var enemy2 := _spawn(&"shadow_monster", 3.0, d)
	d.enemies = [enemy2]
	ranger_b._refresh()
	_t.check(ranger_b.modulate == Color.WHITE, "and lights once there is something to shoot")
	ranger_b._on_pressed()
	_t.check(GameState.special_charge(&"ranger") == 0,
		"pressing the ranger's button fires the bomb arrow and drains her meter")

	# Out of combat (no director) it falls back to the meter alone.
	tray.director = null
	warrior_b._refresh()
	_t.check(warrior_b.modulate == SpecialInvoker.DIM, "with no director an empty meter reads dark")

	tray.queue_free()

## [black-glass] The gold is baked into the renders, so the boss theme is a shader
## tint shared by each button's art and meter, driven through the tray facade.
## Its own tray with no director: waiting out the tween with a live director
## lets an earlier press's projectile resolve against this test's stub world.
func _check_invoker_boss_theme() -> void:
	print("--- invoker boss theme ---")
	var tray := INVOKER_TRAY.instantiate()
	add_child(tray)
	var buttons: Array = [tray.get_node("RangerInvoker"), tray.get_node("WarriorInvoker"),
		tray.get_node("MageInvoker")]
	var mats := {}
	for b: SpecialInvoker in buttons:
		var art_mat: Material = b.get_node("Art").material
		_t.check(art_mat is ShaderMaterial and art_mat == b.get_node("Meter").material,
			"%s's art and meter share one tint, so the pips shift with the frame" % b.hero_class)
		mats[art_mat] = true
		_t.check(is_zero_approx(b.boss_tint()), "%s's button starts untinted" % b.hero_class)
	_t.check(mats.size() == buttons.size(), "each button owns its own tint")

	var before: Array = buttons.map(func(b: SpecialInvoker) -> Color: return b.modulate)
	tray.apply_boss_theme()
	await get_tree().create_timer(SpecialInvoker.BOSS_THEME_TIME + 0.1).timeout
	for b: SpecialInvoker in buttons:
		_t.check(is_equal_approx(b.boss_tint(), 1.0), "apply_boss_theme tints %s's button fully" % b.hero_class)
	_t.check(buttons.map(func(b: SpecialInvoker) -> Color: return b.modulate) == before,
		"the tint leaves the lit/dim modulate alone")

	tray.clear_boss_theme()
	await get_tree().create_timer(SpecialInvoker.BOSS_THEME_TIME + 0.1).timeout
	for b: SpecialInvoker in buttons:
		_t.check(is_zero_approx(b.boss_tint()), "clear_boss_theme reverts %s's button" % b.hero_class)
	tray.queue_free()

# --- the charge meter ---------------------------------------------------------

## ChargeMeter.lit_pips() is the only thing relating SPECIAL_PIP_COUNT (3, from
## the art) to SPECIAL_CHARGE_COST (10). Pure and static, so it is checked here
## without a viewport.
func _check_charge_meter() -> void:
	print("--- charge meter pip mapping ---")
	var cost: int = Tuning.SPECIAL_CHARGE_COST
	var pips: int = Tuning.SPECIAL_PIP_COUNT

	var empty := ChargeMeter.lit_pips(0, cost, pips)
	_t.check(empty == Vector2.ZERO, "an empty meter lights no pips and fills none")

	var full := ChargeMeter.lit_pips(cost, cost, pips)
	_t.check(full == Vector2(float(pips), 0.0),
		"a full meter lights every pip with nothing left filling (got %s)" % [full])

	# Overfull cannot happen (add_special_charge caps), but must not light a
	# fourth pip if it ever did.
	_t.check(ChargeMeter.lit_pips(cost * 3, cost, pips) == Vector2(float(pips), 0.0),
		"charges past the cost never light more pips than exist")

	# The partial wedge is what keeps 3 pips honest about a 10-charge meter:
	# every single charge has to move something.
	var seen: Array = []
	var last := Vector2(-1, -1)
	for c: int in range(cost + 1):
		var got := ChargeMeter.lit_pips(c, cost, pips)
		_t.check(got != last, "charge %d moves the meter (got %s, was %s)" % [c, got, last])
		last = got
		seen.append(got.x)
	_t.check(seen[0] == 0.0 and seen[cost] == float(pips),
		"the meter runs from no pips at 0 to every pip at the cost")

	# Monotonic: a charge can never dim a pip that was already lit.
	var ok := true
	for i: int in range(1, seen.size()):
		if float(seen[i]) < float(seen[i - 1]):
			ok = false
	_t.check(ok, "lit pips never go backwards as charges rise")

	# Degenerate configs must not divide by zero - both are Tuning constants a
	# future pass could set to anything.
	_t.check(ChargeMeter.lit_pips(5, 0, pips) == Vector2.ZERO, "a zero cost is survivable")
	_t.check(ChargeMeter.lit_pips(5, cost, 0) == Vector2.ZERO, "a zero pip count is survivable")
