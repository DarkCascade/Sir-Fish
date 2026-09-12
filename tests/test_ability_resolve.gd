extends Node
## Content Phase 0 Step 2 regression: exercises the AbilityDef dispatch
## end-to-end (Ability.make() -> Ability.resolve() -> AbilityDef.resolve())
## for one representative ability of each of the four shapes, bypassing
## animation/impact-track timing entirely - the thing under test is dispatch
## correctness (does the right kind of thing actually happen), not timing.
## test_content_registry.gd already pins the impact tracks themselves.
##
## No pre-existing test drove Ability.resolve() through a real dispatch before
## this pass added AbilityDef - test_level_curves.gd reads SlotIcon/Itemizer
## directly and never touches Ability, and test_retarget.gd exercises
## Projectile without going through Ability.make() at all. This closes that
## gap for the shape Step 2 changed.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_ability_resolve.tscn

const TestSupport := preload("res://tests/test_support.gd")

## Stand-ins exposing only what an AbilityDef.resolve() implementation
## actually calls - the same minimal-fake approach test_retarget.gd uses for
## Projectile, rather than standing up a real BattleWorld.
class FakeWorld extends Node:
	var projectile_root: Node
	var shook: bool = false

	func _init() -> void:
		projectile_root = self

	func shake(_amp: float, _dur: float) -> void:
		shook = true

class FakeDirector extends Node:
	var world: FakeWorld
	var enemies: Array[Combatant] = []
	var heroes: Array[Combatant] = []

	func _init() -> void:
		world = FakeWorld.new()
		add_child(world)

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
		for h: Combatant in heroes:
			if is_instance_valid(h) and h.is_alive() \
					and (best == null or h.current_hp < best.current_hp):
				best = h
		return best

var _t := TestSupport.new()

func _ready() -> void:
	_case_warrior_primary()
	_case_generic_enemy_primary()
	_case_orc_primary()
	_case_shadow_primary()
	_case_ranger_primary()
	_case_mage_primary()
	_case_warrior_special()
	_case_mage_special()
	_t.finish(get_tree(), "test_ability_resolve")

func _spawn(id: StringName, x: float) -> Combatant:
	var stats := GameState.get_stats(id)
	var packed: PackedScene = load(stats.scene_path)
	var c := packed.instantiate() as Combatant
	add_child(c)
	c.position = Vector3(x, 0, 0)
	c.setup(stats, -1)
	return c

func _case_warrior_primary() -> void:
	print("--- warrior primary: MeleeStrikeAbility (tinted slash) ---")
	var d := FakeDirector.new()
	add_child(d)
	var warrior := _spawn(&"warrior", -3.0)
	var enemy := _spawn(&"shadow_monster", 2.0)
	warrior.director = d
	var before := enemy.current_hp
	Ability.make(warrior, false, enemy, d).resolve(warrior)
	_t.check(enemy.current_hp < before, "warrior's primary struck the target")

func _case_generic_enemy_primary() -> void:
	print("--- skeleton_minion primary: melee_strike_generic.tres ---")
	var d := FakeDirector.new()
	add_child(d)
	var minion := _spawn(&"skeleton_minion", -2.0)
	var target := _spawn(&"warrior", 2.0)
	minion.director = d
	var before := target.current_hp
	Ability.make(minion, false, target, d).resolve(minion)
	_t.check(target.current_hp < before,
		"the shared generic melee asset struck the target")

func _case_orc_primary() -> void:
	print("--- orc_barbarian primary: dedicated MeleeStrikeAbility ---")
	var d := FakeDirector.new()
	add_child(d)
	var orc := _spawn(&"orc_barbarian", -2.0)
	var target := _spawn(&"warrior", 2.0)
	orc.director = d
	var before := target.current_hp
	Ability.make(orc, false, target, d).resolve(orc)
	_t.check(target.current_hp < before, "the orc's dedicated melee asset struck the target")
	_t.check(d.world.shook, "the orc's world_shake fired")

func _case_shadow_primary() -> void:
	print("--- shadow_monster primary: MeleeStrikeAbility (CLAW style) ---")
	var d := FakeDirector.new()
	add_child(d)
	var shadow := _spawn(&"shadow_monster", -2.0)
	var target := _spawn(&"warrior", 2.0)
	shadow.director = d
	var before := target.current_hp
	Ability.make(shadow, false, target, d).resolve(shadow)
	_t.check(target.current_hp < before, "the shadow's claw-style melee struck the target")

func _case_ranger_primary() -> void:
	print("--- ranger primary: ProjectileAbility (arrow) ---")
	var d := FakeDirector.new()
	add_child(d)
	var ranger := _spawn(&"ranger", -3.0)
	var enemy := _spawn(&"shadow_monster", 2.0)
	ranger.director = d
	d.enemies = [enemy]
	Ability.make(ranger, false, enemy, d).resolve(ranger)
	_t.check(d.world.projectile_root.get_child_count() == 1,
		"ranger's primary launched exactly one projectile")

func _case_mage_primary() -> void:
	print("--- mage primary: ProjectileAbility (magic bolt, telegraphs) ---")
	var d := FakeDirector.new()
	add_child(d)
	var mage := _spawn(&"mage", -3.0)
	var enemy := _spawn(&"shadow_monster", 2.0)
	mage.director = d
	d.enemies = [enemy]
	_t.check(mage.stats.primary.telegraphs_primary, "mage's primary is flagged to telegraph")
	Ability.make(mage, false, enemy, d).resolve(mage)
	_t.check(d.world.projectile_root.get_child_count() == 1,
		"mage's primary launched exactly one projectile (the magic bolt)")

func _case_warrior_special() -> void:
	print("--- warrior special: SelfBuffAbility (Defend) ---")
	var d := FakeDirector.new()
	add_child(d)
	var warrior := _spawn(&"warrior", -3.0)
	warrior.director = d
	Ability.make(warrior, true, null, d).resolve(warrior)
	_t.check(warrior.is_defending(), "warrior's special applies Defend")

func _case_mage_special() -> void:
	print("--- mage special: HealAllyAbility ---")
	var d := FakeDirector.new()
	add_child(d)
	var mage := _spawn(&"mage", -3.0)
	var ally := _spawn(&"warrior", -1.0)
	mage.director = d
	d.heroes = [mage, ally]
	ally.current_hp = 1
	Ability.make(mage, true, null, d).resolve(mage)
	_t.check(ally.current_hp > 1, "mage's special heals the lowest-hp living ally")
