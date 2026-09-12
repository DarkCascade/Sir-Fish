class_name HealAllyAbility
extends AbilityDef
## Heals the party's lowest-hp living hero for a multiple of the caster's own
## compute_damage(). Replaces Ability._mage()'s special (content-phase-0 spec
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
	var amount := int(round(float(source.compute_damage()) * heal_multiplier))
	ally.heal(amount)
	BattleVfx.heal_icon(ally, amount)
