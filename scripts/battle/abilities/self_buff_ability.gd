class_name SelfBuffAbility
extends AbilityDef
## Buffs the caster itself and deals no damage. Replaces Ability._warrior()'s
## special - Defend (content-phase-0 spec §3 Step 2).

@export var damage_reduction: float = 0.5
@export var duration: float = 2.0

func resolve(source: Combatant, _ability: Ability) -> void:
	source.apply_defend(damage_reduction, duration)
	BattleVfx.defend_icon(source, duration)
