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

## [levels] Level-1 base stats. Growth per level above 1 lives in the matching
## `*_per_level` field below - see `at_level()` / `hp_at()` / `weapon_power_at()`
## / `magic_power_at()`, the ONLY place a level and a base+growth pair combine
## (levels & stats spec §1.1). Replaces `base_damage`, which named a single
## number for an attack that is now school-specific.
##
## [item power model] weapon_power / magic_power are ENEMY-only now. A hero's
## swing damage comes entirely from its equipped weapon's Item.power(); the
## hero .tres rows carry 0 here. hp_at() still applies to both sides.
@export var max_hp: int = 100
@export var weapon_power: int = 10
@export var magic_power: int = 0

## [levels] Added per level above 1, authored per character rather than derived
## from a global fraction - a glass-cannon and a wall of a tank should not
## diverge only in their level-1 row (spec §1.2).
@export var hp_per_level: int = 0
@export var weapon_power_per_level: int = 0
@export var magic_power_per_level: int = 0

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

# --- [levels] level resolution (spec §1.1) ----------------------------------

## `base + growth * (level - 1)`, floored so a level below 1 never subtracts.
## Static and free of `self` on purpose: this resource is cached and shared
## (GameState._stats_cache), so nothing here may depend on which particular
## spawn is asking - the level always comes in as an argument.
static func at_level(base: int, growth: int, level: int) -> int:
	return base + growth * maxi(level - 1, 0)

func hp_at(level: int) -> int:
	return at_level(max_hp, hp_per_level, level)

func weapon_power_at(level: int) -> int:
	return at_level(weapon_power, weapon_power_per_level, level)

func magic_power_at(level: int) -> int:
	return at_level(magic_power, magic_power_per_level, level)
