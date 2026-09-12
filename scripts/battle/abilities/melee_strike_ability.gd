class_name MeleeStrikeAbility
extends AbilityDef
## A melee swing: an arc VFX, optional dust puff / smoke burst / world shake,
## then Ability.strike(). Replaces Ability._warrior()'s primary, _shadow(),
## _orc() and _generic_enemy() - four data points on one shape
## (content-phase-0 spec §3 Step 2). The generic case (SLASH, tint_color left
## transparent, no extras) is what every plain enemy .tres now points at - see
## resources/abilities/melee_strike_generic.tres.

## SLASH is BattleVfx.slash_arc(), tinted by tint_color or the source's own
## accent_color. CLAW is BattleVfx.claw_arc(), a fixed three-blade shape with
## no tint or scale knobs - the shadow monster's own look, kept as a style
## rather than folded into slash_arc's parameters since it is not a
## recolour/rescale of the same shape.
enum ArcStyle { SLASH, CLAW }

@export var arc_style: ArcStyle = ArcStyle.SLASH
## Alpha 0 means "use source.stats.accent_color" (every plain enemy, so one
## asset can be shared across all of them); an opaque colour overrides it (the
## warrior's near-white, the orc's iron weapon-head grey). Unused when
## arc_style is CLAW.
@export var tint_color: Color = Color(0, 0, 0, 0)
@export var arc_scale: float = 1.4
@export var dust_puff: bool = false
@export var smoke_burst: bool = false
@export var world_shake: bool = false

func resolve(source: Combatant, ability: Ability) -> void:
	var target := ability.target
	if target == null or not target.is_alive():
		return
	if arc_style == ArcStyle.CLAW:
		BattleVfx.claw_arc(target)
	else:
		var color := source.stats.accent_color if tint_color.a <= 0.0 else tint_color
		BattleVfx.slash_arc(target, color, arc_scale)
	if smoke_burst:
		BattleVfx.smoke_burst(source)
	if dust_puff:
		BattleVfx.dust_puff(target, 12)
	if world_shake and ability.director != null:
		ability.director.world.shake(0.04, 0.15)
	ability.strike(source, target)
