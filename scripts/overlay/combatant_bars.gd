extends CombatantBarsBase
## The compact health + cooldown pair floating over an enemy (spec 11). Lives
## in the 2D overlay, never in 3D, so it can be positioned pixel-exactly over
## the character. The hero card (172x58, name chip, exact HP numbers, a
## defend pip, a DEAD state) is a separate scene - hero_bars.tscn/.gd - since
## the two no longer share a single runtime-branching layout.

const ENEMY_FILL_WIDTH := 136.0

func _ready() -> void:
	cooldown_border = $CooldownBorder
	cooldown_bg = $CooldownBg
	cooldown_fill = $CooldownFill
	health_border = $HealthBorder
	health_bg = $HealthBg
	health_fill = $HealthFill
	super._ready()
	_fill_width = ENEMY_FILL_WIDTH
	_cd_width = ENEMY_FILL_WIDTH

## Called by BattleOverlay the moment the bars are spawned, before pop_in().
func setup(c: Combatant) -> void:
	combatant = c
	refresh()

func refresh() -> void:
	if combatant == null or not is_instance_valid(combatant):
		return
	cooldown_fill.size.x = _cd_width * combatant.cooldown_fraction()
