class_name CombatantStats
extends Resource

## [overworld prototype] How this character reaches its target, which is now a
## real distance across the field rather than a fixed gap on one axis.
##
## MELEE blinks to the target and back (see Ability._teleport_strike). RANGED
## and MAGIC never move - they spawn something that flies to the target and
## resolves on arrival. This is a data flag rather than an `id` check for the
## same reason special_targets_opponent is: the two orcs share one .glb and
## one id prefix, the shadow monster is melee without being an orc, and adding
## a fourth enemy should not mean editing a match statement in ability.gd.
enum AttackStyle { MELEE, RANGED, MAGIC }

@export var id: StringName = &""
@export var display_name: String = ""
@export var is_hero: bool = false
@export var max_hp: int = 100
@export var base_damage: int = 10
## RECOVERY after an action ends, not the interval between actions (spec 5.2).
## The real cycle is attack_cooldown + the action's animation length; see the
## `real cycle` column of spec 5.2, which is the authoritative balance figure.
@export var attack_cooldown: float = 1.5
@export var special_every_n_actions: int = 0  # 0 = no special
## [v3] Gate the special on "some living ally (incl. self) is below max HP"
## before it can fire. Mage-only: true only on mage.tres. Applying this
## universally would suppress the warrior's Defend at full party HP, which
## is backwards - Defend is pre-emptive mitigation, most useful before anyone
## is hurt (spec 4.1 / 10.2, V6).
@export var special_requires_wounded_ally: bool = false
## [v3] Whether this character's special needs a living opponent to fire.
## True by default (ranger's bomb arrow is aimed). False for the warrior
## (Defend buffs itself) and the mage (Heal targets an ally) - neither
## should abort just because no enemy is alive (spec 4.1 / 10.2, V6).
@export var special_targets_opponent: bool = true
## [v3.5 F6] Whether this character plays a telegraph beat (darken pass +
## warning glow) before its special resolves. Mage-only; replaces a
## hardcoded `stats.id == &"mage"` branch in ability.gd (spec 2.6).
@export var telegraphs_primary: bool = false
@export var attack_style: AttackStyle = AttackStyle.MELEE
@export var model_scale: float = 1.0
@export var body_color: Color = Color.WHITE
@export var accent_color: Color = Color.WHITE
@export var scene_path: String = ""

## [drops] Probability this combatant leaves an item when it dies. Rolled once,
## at death, and banked until the fight is won (§5) - a party that wipes carries
## nothing home. Heroes leave it at 0.0. The field lives on the shared stats
## resource rather than an enemies-only one because there is only one stats
## resource, and an is_hero guard at the roll site is cheaper than a second
## class.
@export_range(0.0, 1.0, 0.01) var drop_chance: float = 0.0

## [drops] Lowest rarity this combatant's drop may roll, as an Item.Rarity
## index. The normal weighted roll (§13.2) is taken first and then RAISED to
## this floor, so a floor of 1 does not flatten the curve above it - it only
## removes Commons. Only the boss sets it.
@export_range(0, 3, 1) var drop_rarity_floor: int = 0

## The exact set of animation names this character must expose (spec 8.3 / Q5).
##
## Derived from data rather than authored, so there is no second source of truth
## to drift: v1 carried both a "every combatant must have all six" rule and a
## table qualifying `run` as heroes-only, which contradicted each other and left
## the "build failure" unenforceable. This is also the fixed list M8's export
## validation checks per character.
func required_anims() -> Array[StringName]:
	var names: Array[StringName] = [&"idle", &"attack", &"hurt", &"die"]
	if is_hero:
		names.append(&"run")
	if special_every_n_actions > 0:
		names.append(&"special")
	return names
