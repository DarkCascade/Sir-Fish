class_name AbilityDef
extends Resource
## Authored ability data - shared and cached exactly like a CombatantStats
## .tres (content-phase-0 spec §3 Step 2). NEVER holds per-action state
## (target, fixed_damage, school) - see Ability, the RefCounted instance that
## does. A Resource referenced from the inspector is the SAME object across
## every spawn that points at it (the orc pair shares one primary asset), so
## mutating per-cast state here would leak between two simultaneous casters.
##
## special_requires_wounded_ally, special_targets_opponent and
## telegraphs_primary moved here from CombatantStats - they are facts about
## ONE ability, not about the character that owns it (spec §2.2).
## CombatantStats keeps special_every_n_actions: it decides HOW OFTEN the
## special fires, which is a property of the character's rhythm, not of what
## the special does.

## [v3] Gate this ability on "some living ally (incl. self) is below max HP"
## before it can fire. Read by BattleDirector._take_action() for the SPECIAL
## ability only - applying it to a primary would suppress it forever on a
## fully healthy party.
@export var special_requires_wounded_ally: bool = false

## [v3] Whether this ability needs a living opponent to fire. True by default;
## false for a self/ally-targeted ability (Defend, Heal) so it still fires
## when no opponent is alive - during the resolve window after the last enemy
## (or last hero) dies.
@export var special_targets_opponent: bool = true

## [v3.5 F6] Whether this ability plays a telegraph beat (darken pass +
## warning glow) before it resolves. Only ever consulted for the PRIMARY
## ability - see Ability.charge().
@export var telegraphs_primary: bool = false

## The colour Combatant._anim_special_cast() flashes at t=0 of every `special`
## clip - only ever read off a character's SPECIAL ability. Replaces
## Combatant.SPECIAL_FLASH_COLORS. Default matches that table's old fallback
## (Tuning.C_TEXT) for a character with no dedicated special.
@export var flash_color: Color = Color(0.960784, 0.945098, 0.901961, 1)

## Executes this ability for `source`. `ability` is the in-flight instance
## (Ability) - implementations read its target/school/fixed_damage but never
## write them; per-cast state belongs there, not here.
func resolve(_source: Combatant, _ability: Ability) -> void:
	pass
