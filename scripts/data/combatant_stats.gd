class_name CombatantStats
extends Resource

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
## before it can fire. Priest-only: true only on priest.tres. Applying this
## universally would suppress the warrior's Defend at full party HP, which
## is backwards - Defend is pre-emptive mitigation, most useful before anyone
## is hurt (spec 4.1 / 10.2, V6).
@export var special_requires_wounded_ally: bool = false
## [v3] Whether this character's special needs a living opponent to fire.
## True by default (ranger's bomb arrow is aimed). False for the warrior
## (Defend buffs itself) and the priest (Heal targets an ally) - neither
## should abort just because no enemy is alive (spec 4.1 / 10.2, V6).
@export var special_targets_opponent: bool = true
## [v3.5 F6] Whether this character plays a telegraph beat (darken pass +
## warning glow) before its special resolves. Priest-only; replaces a
## hardcoded `stats.id == &"priest"` branch in ability.gd (spec 2.6).
@export var telegraphs_primary: bool = false
@export var model_scale: float = 1.0
@export var body_color: Color = Color.WHITE
@export var accent_color: Color = Color.WHITE
@export var scene_path: String = ""

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
