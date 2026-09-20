class_name ProjectileAbility
extends AbilityDef
## Fires a projectile that resolves its own damage/effect on arrival - resolve()
## only launches it. Replaces Ability._ranger() (its primary and special are
## now two separate ProjectileAbility resources - one arrow, one bomb arrow)
## and _mage()'s primary (content-phase-0 spec §3 Step 2).

@export var scene: PackedScene
## Passed straight through to Projectile.launch() as its `bomb` payload flag
## (Projectile.is_bomb) - the ranger's bomb-arrow special sets this true,
## every other projectile ability leaves it false. Authored per-resource
## rather than read off Ability.is_special, so a projectile special need not
## always double as its caster's primary attack.
@export var bomb_payload: bool = false

func resolve(source: Combatant, ability: Ability) -> void:
	if scene == null or ability.director == null:
		return
	var proj = scene.instantiate()
	ability.director.world.projectile_root.add_child(proj)
	# [owner swings] fixed_damage is the slot board's own summed total for this
	# hero (Ability.make_slot_strike); -1 means "roll it yourself", which is what
	# an ordinary ability cast still does. Without this a ranger/mage slot swing
	# arrived for compute_damage(), and every hero's weapon_power is 0 now that
	# item Power drives damage - so their whole share of the board landed as 1.
	proj.launch(source, ability.target, ability.director, bomb_payload, ability.fixed_damage)
