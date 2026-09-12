class_name Ability
extends RefCounted
## One in-flight action. Created by BattleDirector when a combatant's cooldown
## expires, held on Combatant.pending, and resolved by the animation's method
## track at the ability's impact_delay (spec 9, 10.2).
##
## [content phase 0] Step 2 split the old per-character `match` dispatch into
## AbilityDef (authored, shared, cached data - see ability_def.gd and its four
## subclasses under abilities/) and this class, which stays the RefCounted
## in-flight instance: which def is resolving, which target, and the two
## per-cast overrides (fixed_damage, school) a slot-driven swing or an
## explicit school choice needs. A Resource is cached and shared across every
## spawn, so none of that per-cast state may live on AbilityDef - the same
## reason Combatant.level is not stored on CombatantStats.

## The def this instance resolves through, once known - see _resolved_def().
## Left unset by make()/make_slot_strike() and filled in lazily, because
## make_slot_strike() does not have `source` available at construction time.
var def: AbilityDef = null
var anim_name: StringName = &"attack"
var is_special: bool = false
var target: Combatant = null
var director = null               # BattleDirector (untyped: custom API)
## [levels] Which power stat this action draws from - Combatant.School, or -1
## for the source's own default_school() (spec §1.4). Every current ability
## resolves through its source's default correctly as-is; this exists for the
## day an ability wants the OTHER school (a caster's melee special, say)
## without an id branch.
var school: int = -1

## [combat loop redesign] When >= 0, strike() deals exactly this much instead
## of rolling source.compute_damage(). Set by make_slot_strike() so a
## slot-driven hero swing carries the board's aggregated attack-icon total -
## the character's own power no longer feeds combat damage at all.
var fixed_damage: int = -1

static func make(_source: Combatant, use_special: bool, a_target: Combatant,
		a_director) -> Ability:
	var ab := Ability.new()
	ab.is_special = use_special
	ab.anim_name = &"special" if use_special else &"attack"
	ab.target = a_target
	ab.director = a_director
	return ab

## [combat loop redesign] A plain swing whose damage is supplied by the
## caller (SlotMachine._hero_swing), not rolled. Always the primary `attack`
## clip, never a special. Resolves through the source's own PRIMARY ability
## (see _resolved_def()), so the warrior still gets its slash arc and the
## ranger/mage would still send a projectile the day the party has one.
static func make_slot_strike(a_target: Combatant, amount: int, a_director) -> Ability:
	var ab := Ability.new()
	ab.anim_name = &"attack"
	ab.target = a_target
	ab.director = a_director
	ab.fixed_damage = maxi(0, amount)
	return ab

## Resolves (and caches) which AbilityDef answers for this in-flight action.
func _resolved_def(source: Combatant) -> AbilityDef:
	if def == null:
		def = source.stats.special if is_special else source.stats.primary
	return def

## Telegraph beat - only fires ahead of a PRIMARY ability whose def has
## telegraphs_primary set (mage only, today).
func charge(source: Combatant) -> void:
	if is_special:
		return
	var d := _resolved_def(source)
	if d == null or not d.telegraphs_primary:
		return
	if Tuning.MAGE_DARKEN_ENABLED:
		BattleVfx.darken_pass(source)
	if target != null and target.is_alive():
		BattleVfx.warning_glow(target)

func resolve(source: Combatant) -> void:
	if not source.is_alive():
		return
	# [combat loop redesign] A slot-driven swing was aimed when the spin
	# resolved; if that enemy has since died (a chain bolt, an overkill), hit
	# another rather than whiffing the party's whole turn.
	if fixed_damage >= 0 and (target == null or not is_instance_valid(target) \
			or not target.is_alive()):
		target = director.random_living_enemy() if director != null else null
	var d := _resolved_def(source)
	if d == null:
		return
	d.resolve(source, self)

## Shared damage application - called by an AbilityDef.resolve() that deals
## direct melee damage (MeleeStrikeAbility). Public now that the dispatch
## itself lives outside this file.
func strike(source: Combatant, victim: Combatant) -> void:
	var amount := fixed_damage if fixed_damage >= 0 else source.compute_damage(school)
	EventBus.combatant_attacked.emit(source, victim, amount)
	victim.take_damage(amount, source)
