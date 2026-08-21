class_name Ability
extends RefCounted
## One in-flight action. Created by BattleDirector when a combatant's cooldown
## expires, held on Combatant.pending, and resolved by the animation's method
## track at the ability's impact_delay (spec 9, 10.2).

const ARROW_SCENE := preload("res://scenes/battle/projectiles/arrow.tscn")
const BOMB_ARROW_SCENE := preload("res://scenes/battle/projectiles/bomb_arrow.tscn")

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

## Telegraph beat - only characters flagged telegraphs_primary use it.
func charge(source: Combatant) -> void:
	if not source.stats.telegraphs_primary or is_special:
		return
	if Tuning.PRIEST_DARKEN_ENABLED:
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
		&"priest":
			_priest(source)
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

# --- priest -----------------------------------------------------------------

func _priest(source: Combatant) -> void:
	if is_special:
		var ally: Combatant = director.lowest_hp_living_hero()
		if ally == null:
			return
		var amount := int(round(float(source.compute_damage()) * Tuning.PRIEST_HEAL_MULT))
		ally.heal(amount)
		BattleVfx.heal_icon(ally, amount)
		return
	if target == null or not target.is_alive():
		return
	BattleVfx.lightning_bolt(director, target, Tuning.C_LIGHTNING)
	director.world.shake(0.05, 0.18)
	_strike(source, target)

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
