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

## [content phase 1] A hero's class identity - roster_order, innate icon,
## executor ownership, party-bar look and equippable item types (spec §3 Step
## 2). Hero-only; null on an enemy. roster_order used to live directly on this
## resource (content phase 0 spec §3 Step 5 / D3) and has moved onto
## ClassDef.roster_order - see GameState._rebuild_party_order().
@export var class_def: ClassDef

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
## [content phase 0] The character's authored abilities (spec §3 Step 2) -
## replaces the id-keyed match in ability.gd. `primary` answers every
## ordinary action; `special` is read only when special_every_n_actions > 0.
## special_requires_wounded_ally, special_targets_opponent and
## telegraphs_primary now live on AbilityDef, since they are facts about the
## ability, not the character - see ability_def.gd.
@export var primary: AbilityDef
@export var special: AbilityDef
@export var attack_style: AttackStyle = AttackStyle.MELEE
@export var model_scale: float = 1.0
@export var body_color: Color = Color.WHITE
@export var accent_color: Color = Color.WHITE
@export var scene_path: String = ""

## [content phase 0] Replaces the three parallel animation-binding registries
## CombatantAnimations.build() used to try in order
## (CombatantBakedAnimations.CLIPS, CombatantSkeletonAnimations.SKELETON_PATH,
## the shadow-monster-only fallback) - see rig_profile.gd (spec §3 Step 3).
@export var rig_profile: RigProfile

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

## [content phase 0] Free-form descriptors an EnemyPool can filter on (spec §3
## Step 4) - &"undead", &"fungal", &"caster", &"brute", &"swarm",
## &"skirmisher", &"orc" today. No tag is load-bearing on its own; a monster
## with no tags simply never matches a require_tags filter, which is the
## correct behaviour for a hero (heroes carry no tags) and for a future enemy
## that predates whatever filter a new quest wants.
@export var tags: Array[StringName] = []

## [content phase 0] A rough encounter-budget cost (spec §3 Step 4) - bigger
## for a tougher combatant, authored per character rather than derived from
## HP/power, since "how much of an encounter's budget this costs" is a design
## call, not an arithmetic one. Not consumed anywhere yet; Phase 1's generated
## encounters are the first reader.
@export var threat: int = 1

## [content phase 0] An optional named boss form of this combatant (spec §3
## Step 4) - e.g. a skeleton_warrior's own elite variant, distinct from the
## runtime HP/scale multiply BattleDirector.start_combat() applies to
## whichever unit fills a boss slot. Unused by anything in Phase 0; left null
## everywhere until Phase 1 authors one.
@export var elite_variant: CombatantStats

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
