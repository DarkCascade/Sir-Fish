class_name HealAllyAbility
extends AbilityDef
## Heals the party's lowest-hp living hero for a multiple of the caster's own
## current damage. Replaces Ability._mage()'s special (content-phase-0 spec
## §3 Step 2). "Lowest hp living hero" is the only target rule any heal ability
## has ever used, so it stays a hardcoded call rather than an authored enum
## with one member - the extension point if a second heal ability ever needs a
## different rule.

@export var heal_multiplier: float = 1.0

func resolve(source: Combatant, ability: Ability) -> void:
	if ability.director == null:
		return
	var ally: Combatant = ability.director.lowest_hp_living_hero()
	if ally == null:
		return
	# [item power model] The heal is invoked, so it never carries fixed_damage,
	# and source.compute_damage() reads CombatantStats.weapon_power/magic_power
	# directly - 0 on every hero now that equipped item Power drives damage.
	# That silently shrank Healing Aura to ~1 HP regardless of the mage's own
	# gear, the same fallback-to-1 bug CleaveAbility's own brief flagged for
	# the warrior. GameState.hero_weapon_power() (her equipped staff's Power)
	# is the correct read of "the mage's current damage".
	var base := GameState.hero_weapon_power(source.stats.id)
	var amount := maxi(1, int(round(float(base) * source.damage_multiplier * heal_multiplier)))
	ally.heal(amount)
	BattleVfx.heal_icon(ally, amount)
