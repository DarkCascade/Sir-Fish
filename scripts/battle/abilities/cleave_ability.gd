class_name CleaveAbility
extends AbilityDef
## The warrior's special: hits every living enemy (backlog decision 7.4).
## Replaces SelfBuffAbility/Defend on warrior_special.tres. Mirrors
## Projectile._explode()'s AoE resolution (left-to-right by world X,
## Tuning.AOE_STAGGER apart, each target rolling Tuning.DAMAGE_VARIANCE on
## its own) since that pattern is already proven for the ranger's bomb arrow -
## SlotMachine._hit_all() does the equivalent for board-driven AoE but is not
## reusable here (it resolves off the slot bag, not an invoked special).
##
## [item power model] source.compute_damage() returns 1 for every hero now -
## weapon_power/magic_power and their *_per_level are 0 on every hero
## CombatantStats, since equipped item Power drives damage. Cleave instead
## derives its total from the warrior's equipped weapon Power, the same
## number the slot board's own innate damage icon uses
## (GameState.hero_weapon_power).

func resolve(source: Combatant, ability: Ability) -> void:
	if ability.director == null:
		return
	var targets: Array[Combatant] = ability.director.living_enemies()
	if targets.is_empty():
		return
	var base := GameState.hero_weapon_power(source.stats.id)
	var per_target := maxi(1, int(round(float(base) * Tuning.WARRIOR_CLEAVE_MULT)))
	targets.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		return a.global_position.x < b.global_position.x)
	for enemy: Combatant in targets:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		BattleVfx.slash_arc(enemy, source.stats.accent_color, 1.4)
		var rolled := maxi(1, int(round(float(per_target) * RNG.randf_range(
			1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE))))
		EventBus.combatant_attacked.emit(source, enemy, rolled)
		enemy.take_damage(rolled, source)
		await _tree_timer(Tuning.AOE_STAGGER)

## Projectile._tree_timer()'s twin - resolve() outlives no node of its own to
## drive an await off, so it has to come from the tree the same way.
func _tree_timer(seconds: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	await tree.create_timer(seconds).timeout
