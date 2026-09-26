extends Node
## Decision 3.11's twelve off-board stat modifiers (backlog §3, issue #75).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_stat_modifiers.tscn
##
## Drives each StatModifiers rule on real Combatants with a forced modifier. A
## stat whose own percent is its chance is forced to a 100 roll; the ones that
## proc at Tuning.STAT_PROC_CHANCE are swung until they fire, and every proc is
## checked for its exact effect.

const TestSupport := preload("res://tests/test_support.gd")

const STATS: Array[StringName] = [
	&"stagger", &"mark", &"execute", &"twin_strike", &"arc", &"siphon",
	&"deflect", &"cover", &"bulwark", &"thorns", &"vitality", &"resolve",
]

var _t := TestSupport.new()

func _ready() -> void:
	_t.guard_user_file(SaveGame.PATH)
	GameState.inventory = []
	GameState.special_charges.clear()

	var warrior := _spawn(&"warrior")
	var mage := _spawn(&"mage")
	var enemy := _spawn(&"skeleton_minion")
	var enemy_b := _spawn(&"skeleton_minion")
	var enemies: Array[Combatant] = [enemy, enemy_b]
	var nobody: Array[Combatant] = []

	# --- weapon stats ---------------------------------------------------------
	var weapon := _give(&"warrior", &"sword", &"execute")
	var execute_roll := int(weapon.modifiers[0]["roll"])
	enemy.current_hp = enemy.max_hp
	_t.check(StatModifiers.execute_bonus(warrior, enemy) == 0, "execute: nothing above the threshold")
	enemy.current_hp = maxi(1, int(enemy.max_hp * 0.2))
	_t.check(StatModifiers.execute_bonus(warrior, enemy) == execute_roll,
		"execute: a target under the threshold takes the roll (%d)" % execute_roll)
	enemy.current_hp = enemy.max_hp

	_give(&"warrior", &"sword", &"stagger")
	var stagger := GameState.hero_stat(&"warrior", &"stagger")
	var want_delay := enemy.stats.attack_cooldown * float(stagger) / 100.0
	var procs := 0
	var exact := true
	for i: int in range(80):
		enemy.cooldown_remaining = 1.0
		StatModifiers.on_hero_swing(warrior, enemy, 5, nobody)
		if enemy.cooldown_remaining > 1.0:
			procs += 1
			exact = exact and is_equal_approx(enemy.cooldown_remaining - 1.0, want_delay)
	_t.check(procs > 0 and exact,
		"stagger: each proc pushes the next action back by its share of the cooldown (%d procs)" % procs)
	_t.check(procs > 10 and procs < 50, "stagger: procs near STAT_PROC_CHANCE over 80 swings (%d)" % procs)

	_give(&"warrior", &"sword", &"mark")
	var mark := GameState.hero_stat(&"warrior", &"mark")
	for i: int in range(80):
		if enemy.mark_pct() > 0:
			break
		StatModifiers.on_hero_swing(warrior, enemy, 5, nobody)
	_t.check(enemy.mark_pct() == mark, "mark: a proc marks the target for its percent (%d)" % enemy.mark_pct())
	_t.check(StatModifiers.incoming(enemy, 100, warrior, false, nobody) == int(round(100.0 * (1.0 + mark / 100.0))),
		"mark: a marked enemy takes the percent more from a hero")
	_t.check(StatModifiers.incoming(enemy, 100, enemy_b, false, nobody) == 100,
		"mark: only hero hits are raised")

	var twin_weapon := _give(&"warrior", &"sword", &"twin_strike")
	twin_weapon.modifiers[0]["roll"] = 100
	enemy.current_hp = enemy.max_hp
	StatModifiers.on_hero_swing(warrior, enemy, 7, nobody)
	var before_twin := enemy.current_hp
	await get_tree().create_timer(Tuning.TWIN_STRIKE_DELAY + 0.1).timeout
	_t.check(enemy.current_hp < before_twin, "twin_strike: a 100 roll lands a second hit after the delay")

	_give(&"warrior", &"sword", &"arc")
	enemy.current_hp = enemy.max_hp
	enemy_b.current_hp = enemy_b.max_hp
	for i: int in range(40):
		StatModifiers.on_hero_swing(warrior, enemy, 5, enemies)
	await get_tree().create_timer(Tuning.ARC_DELAY + 0.1).timeout
	_t.check(enemy_b.current_hp < enemy_b.max_hp, "arc: a proc jumps to the other living enemy")

	var siphon_weapon := _give(&"mage", &"staff", &"siphon")
	siphon_weapon.modifiers[0]["roll"] = 100
	var charge_before := GameState.special_charge(&"mage")
	StatModifiers.on_hero_swing(mage, enemy, 5, nobody)
	_t.check(GameState.special_charge(&"mage") == charge_before + 1, "siphon: a 100 roll adds one charge")

	# --- armor stats ----------------------------------------------------------
	_give(&"warrior", &"tower_shield", &"bulwark")
	warrior.apply_party_bonuses()
	var bulwark := GameState.hero_stat(&"warrior", &"bulwark")
	_t.check(StatModifiers.block_grant(warrior, 100) == int(round(100.0 * (1.0 + bulwark / 100.0))),
		"bulwark: a Block grant is raised by its percent (%d%%)" % bulwark)
	_t.check(StatModifiers.block_grant(enemy, 100) == 100, "bulwark: never on an enemy")

	_give(&"warrior", &"spiked_shield", &"thorns")
	warrior.apply_party_bonuses()
	_t.check(warrior.thorns == GameState.hero_stat(&"warrior", &"thorns") and warrior.thorns > 0,
		"thorns: cached on the hero when gear changes (%d)" % warrior.thorns)
	enemy.current_hp = enemy.max_hp
	warrior.take_damage(5, enemy)
	_t.check(enemy.current_hp < enemy.max_hp, "thorns: an enemy that hits the wearer takes damage back")

	_give(&"warrior", &"kite_shield", &"cover")
	warrior.apply_party_bonuses()
	var allies: Array[Combatant] = [warrior, mage]
	var warrior_before := warrior.current_hp
	var kept := StatModifiers.incoming(mage, 100, enemy, false, allies)
	var share := int(round(100.0 * warrior.cover_fraction))
	_t.check(share > 0 and kept == 100 - share and warrior.current_hp < warrior_before,
		"cover: the coverer takes its share of a hit on an ally (kept %d, share %d)" % [kept, share])
	_t.check(StatModifiers.incoming(mage, 100, enemy, true, allies) == 100,
		"cover: a covered share is never covered again")
	_t.check(StatModifiers.incoming(warrior, 100, enemy, false, allies) == 100,
		"cover: the coverer does not cover itself")

	_give(&"warrior", &"round_shield", &"deflect")
	warrior.apply_party_bonuses()
	_t.check(warrior.deflect_chance > 0.0 and warrior.deflect_chance <= Tuning.DEFLECT_CHANCE_CAP,
		"deflect: cached as a capped chance (%.2f)" % warrior.deflect_chance)
	warrior.deflect_chance = 1.0
	var hp_before := warrior.current_hp
	warrior.take_damage(50, enemy)
	_t.check(warrior.current_hp == hp_before, "deflect: a deflected hit never lands")
	warrior.deflect_chance = 0.0

	var hp_base := GameState.hero_max_hp(&"warrior")
	var vit := _give(&"warrior", &"mail", &"vitality")
	var vit_roll := int(vit.modifiers[0]["roll"])
	var vit_basis := float(vit.level * Tuning.VITALITY_HP_PER_LEVEL)
	_t.check(vit_roll >= int(floor(vit_basis * Tuning.FORGE_ICON_POWER_MIN)) and vit_roll <= int(ceil(vit_basis * Tuning.FORGE_ICON_POWER_MAX)),
		"vitality: the roll scales with item level (%d at L%d)" % [vit_roll, vit.level])
	_t.check(GameState.hero_max_hp(&"warrior") == hp_base + vit_roll,
		"vitality: max HP rises by the roll (%d -> %d)" % [hp_base, GameState.hero_max_hp(&"warrior")])

	GameState.special_charges.clear()
	_give(&"warrior", &"helm", &"resolve")
	var resolve := GameState.hero_stat(&"warrior", &"resolve")
	StatModifiers.grant_resolve([warrior])
	_t.check(resolve > 0 and GameState.special_charge(&"warrior") == resolve,
		"resolve: the fight starts with its charge (%d)" % resolve)

	# --- off the board --------------------------------------------------------
	for id: StringName in STATS:
		_t.check(SlotIcon.from_modifier({"id": id, "roll": 5}).is_empty() and id in SlotIcon.STAT_MODIFIER_IDS,
			"%s: a stat, never a board icon" % id)

	_t.finish(get_tree(), "test_stat_modifiers")

func _spawn(id: StringName) -> Combatant:
	var stats := GameState.get_stats(id)
	var c := (load(stats.scene_path) as PackedScene).instantiate() as Combatant
	add_child(c)
	c.setup(stats, -1)
	return c

## Equips a Magic `type` on `hero` whose one modifier is forced to `stat`,
## replacing whatever that slot held.
func _give(hero: StringName, type: StringName, stat: StringName) -> Item:
	var item := Itemizer.generate_typed_item(type, Item.Rarity.MAGIC, 5)
	Itemizer.force_modifier(item, 0, stat)
	GameState.inventory.append(item)
	GameState.equip_item(item, hero)
	return item
