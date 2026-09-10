class_name Ability
extends RefCounted
## One in-flight action. Created by BattleDirector when a combatant's cooldown
## expires, held on Combatant.pending, and resolved by the animation's method
## track at the ability's impact_delay (spec 9, 10.2).

const ARROW_SCENE := preload("res://scenes/battle/projectiles/arrow.tscn")
const BOMB_ARROW_SCENE := preload("res://scenes/battle/projectiles/bomb_arrow.tscn")
const MAGIC_BOLT_SCENE := preload("res://scenes/battle/projectiles/magic_bolt.tscn")

var anim_name: StringName = &"attack"
var is_special: bool = false
var target: Combatant = null
var director = null               # BattleDirector (untyped: custom API)
## [levels] Which power stat this action draws from - Combatant.School, or -1
## for the source's own default_school() (spec §1.4). Every current ability
## resolves through its source's default correctly as-is; this exists for the
## day an ability wants the OTHER school (a caster's melee special, say)
## without a match-on-id branch in _strike().
var school: int = -1

## [combat loop redesign] When >= 0, _strike() deals exactly this much instead
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

## [combat loop redesign] A plain melee swing whose damage is supplied by the
## caller (SlotMachine._hero_swing), not rolled. Always the primary `attack`
## clip, never a special. Resolves through the same source.stats.id dispatch as
## a normal turn, so the warrior still gets its slash arc and the ranger/mage
## would still send a projectile the day the party has one.
static func make_slot_strike(a_target: Combatant, amount: int, a_director) -> Ability:
	var ab := Ability.new()
	ab.anim_name = &"attack"
	ab.target = a_target
	ab.director = a_director
	ab.fixed_damage = maxi(0, amount)
	return ab

func impact_delay(source: Combatant) -> float:
	return CombatantAnimations.impact_delay(source.stats.id, anim_name)

## Telegraph beat - only characters flagged telegraphs_primary use it.
func charge(source: Combatant) -> void:
	if not source.stats.telegraphs_primary or is_special:
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
	match source.stats.id:
		&"warrior":
			_warrior(source)
		&"ranger":
			_ranger(source)
		&"mage":
			_mage(source)
		&"shadow_monster":
			_shadow(source)
		&"orc_barbarian", &"orc_warlord":
			_orc(source)
		_:
			# [levels] Every skeleton_* enemy and sporecap fell through here with
			# no case and no default - they play their authored attack animation
			# (see CombatantAnimations.IMPACT_DELAYS, which has an entry for each
			# of them) but never actually struck. That is the entire ENDLESS_MID_POOL
			# and BOSS_POOL (game_state.gd) dealing zero combat damage. A plain
			# melee strike, the same shape as _shadow(), is a safe default for any
			# id with no special-case behaviour - none of them carry a
			# special_every_n_actions, so is_special is never true here.
			_generic_enemy(source)

# --- warrior ----------------------------------------------------------------

func _warrior(source: Combatant) -> void:
	if is_special:
		# Defend replaces the action entirely and deals no damage (spec 9.1).
		source.apply_defend()
		BattleVfx.defend_icon(source, Tuning.WARRIOR_DEFEND_DURATION)
		return
	if target == null or not target.is_alive():
		return
	BattleVfx.slash_arc(target, Tuning.C_TEXT, 1.4)
	_strike(source, target)

# --- ranger -----------------------------------------------------------------

func _ranger(source: Combatant) -> void:
	var scene: PackedScene = BOMB_ARROW_SCENE if is_special else ARROW_SCENE
	var proj = scene.instantiate()
	director.world.projectile_root.add_child(proj)
	proj.launch(source, target, director, is_special)

# --- mage --------------------------------------------------------------------

func _mage(source: Combatant) -> void:
	if is_special:
		var ally: Combatant = director.lowest_hp_living_hero()
		if ally == null:
			return
		var amount := int(round(float(source.compute_damage()) * Tuning.MAGE_HEAL_MULT))
		ally.heal(amount)
		BattleVfx.heal_icon(ally, amount)
		return
	if target == null or not target.is_alive():
		return
	# An aimed bolt, not a pillar dropped from the sky (see magic_bolt.gd for
	# why the overhead camera forced the change). Damage now resolves when the
	# bolt lands, so there is no _strike() here - MagicBolt does it, including
	# the combatant_attacked emit the slot machine's damage buffer reads.
	var bolt = MAGIC_BOLT_SCENE.instantiate()
	director.world.projectile_root.add_child(bolt)
	bolt.launch(source, target, director, false)

# --- enemies ----------------------------------------------------------------

func _shadow(source: Combatant) -> void:
	if target == null or not target.is_alive():
		return
	BattleVfx.claw_arc(target)
	BattleVfx.smoke_burst(source)
	_strike(source, target)

func _orc(source: Combatant) -> void:
	if target == null or not target.is_alive():
		return
	BattleVfx.slash_arc(target, Tuning.C_ORC_IRON, 1.9)
	BattleVfx.dust_puff(target, 12)
	director.world.shake(0.04, 0.15)
	_strike(source, target)

## [levels] The default for any enemy id with no dedicated case above -
## skeleton_minion/mage/rogue/warrior and sporecap, today. A plain melee swing
## tinted by the attacker's own accent color, same shape as _shadow().
func _generic_enemy(source: Combatant) -> void:
	if target == null or not target.is_alive():
		return
	BattleVfx.slash_arc(target, source.stats.accent_color, 1.4)
	_strike(source, target)

# --- shared -----------------------------------------------------------------

func _strike(source: Combatant, victim: Combatant) -> void:
	# [combat loop redesign] fixed_damage (>= 0) is a slot-supplied swing total;
	# anything else rolls the source's own power as before.
	var amount := fixed_damage if fixed_damage >= 0 else source.compute_damage(school)
	EventBus.combatant_attacked.emit(source, victim, amount)
	victim.take_damage(amount, source)
