extends Control
## One hero's row in the status panel (spec 17.2). 1080 x 70.

var combatant: Combatant = null
var stats: CombatantStats = null

@onready var chip: ColorRect = $Chip
@onready var chip_label: Label = $Chip/ChipLabel
@onready var name_label: Label = $NameLabel
@onready var strike: ColorRect = $NameLabel/Strike
@onready var hp_fill: ColorRect = $HpFill
@onready var hp_text: Label = $HpText
@onready var buff_shield: Control = $BuffShield
@onready var buff_damage: Control = $BuffDamage

const HP_WIDTH := 416.0

var _last_fraction: float = -1.0

func setup(s: CombatantStats) -> void:
	stats = s
	chip.color = s.accent_color
	chip_label.text = s.display_name.substr(0, 1).to_upper()
	name_label.text = s.display_name
	strike.visible = false
	buff_shield.visible = false
	buff_damage.visible = false

func refresh(c: Combatant, party_buff_active: bool) -> void:
	combatant = c
	if c == null or not is_instance_valid(c):
		return
	var alive := c.is_alive()
	modulate = Color.WHITE if alive else Color(0.4, 0.4, 0.45)
	strike.visible = not alive
	hp_text.text = "DEAD" if not alive else "%d / %d" % [c.current_hp, c.max_hp]

	var fraction := c.hp_fraction()
	if not is_equal_approx(fraction, _last_fraction):
		_last_fraction = fraction
		var tw := create_tween()
		tw.tween_property(hp_fill, "size:x", HP_WIDTH * fraction, 0.25) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	buff_shield.visible = alive and c.is_defending()
	buff_damage.visible = alive and party_buff_active
