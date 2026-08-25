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

static func make(_source: Combatant, use_special: bool, a_target: Combatant,
		a_director) -> Ability:
	var ab := Ability.new()
	ab.is_special = use_special
	ab.anim_name = &"special" if use_special else &"attack"
	ab.target = a_target
	ab.director = a_director
	return ab

func impact_delay(source: Combatant) -> float:
	return CombatantAnimations.impact_delay(source.stats.id, anim_name)

# --- reach (overworld prototype) ---------------------------------------------

## Whether this action starts with a blink to the target. Melee only: ranged
## and magic attackers hold formation and send something flying
## instead, which is the whole distinction the overhead view needed.
func wants_teleport(source: Combatant) -> bool:
	if source.stats.attack_style != CombatantStats.AttackStyle.MELEE:
		return false
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return false
	# A special aimed at the caster's own side is not a strike. Without this
	# the warrior would blink into the enemy rank to raise his own shield.
	if is_special and not source.stats.special_targets_opponent:
		return false
	return true

## Where a blinking attacker lands: short of the target, on the line between
## the two, so it arrives beside the target rather than inside it. Scaled by
## the target's model, because the orc warlord is 1.7x and a fixed gap would
## put the attacker in his chest.
func strike_position(source: Combatant) -> Vector3:
	if target == null or not is_instance_valid(target):
		return source.global_position
	var to := target.global_position
	var away := to - source.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		# Degenerate only if the two are already stacked; back off down-run for
		# a hero, up-run for an enemy, so the pair still ends up facing.
		away = Tuning.RUN_DIR if source.is_hero else -Tuning.RUN_DIR
	var gap: float = Tuning.TELEPORT_STRIKE_GAP * maxf(1.0, target.stats.model_scale)
	return to - away.normalized() * gap

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

# --- shared -----------------------------------------------------------------

func _strike(source: Combatant, victim: Combatant) -> void:
	var amount := source.compute_damage()
	EventBus.combatant_attacked.emit(source, victim, amount)
	victim.take_damage(amount, source)
