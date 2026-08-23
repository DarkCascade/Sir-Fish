extends CombatantBarsBase
## The hero party-bar card (spec 11 / reskin to the fantasy UI kit reference):
## gold card frame, class icon tile, and exact HP numbers on a pill bar. Three
## of these sit stacked vertically in the console's resource strip
## (party_bars.gd), in the party-status column.
##
## The layout is authored entirely in hero_bars.tscn now, at whatever HP/class
## the scene's dummy node values show - setup() only overwrites data (colors,
## text, which glyph) never positions, so this scene can be opened and tuned
## directly (see status_panel_preview.tscn) without a battle running.
##
## [UI pass] No cooldown row - the console's party status is HP-only, unlike
## the enemy overlay pair (combatant_bars.gd) which still shows one.

## [layout experiment] Was 100/168 for the 172-wide card - hero_bars.tscn's
## card is 340 wide now (party_bars.gd's own full-width row has the room),
## and this must track HealthFill's own authored width in the .tscn or the bar
## visually stops short of (or overflows) its track.
const HERO_FILL_WIDTH := 230.0

## [presentation redesign S6.3] Past half the chip's own shorter side (32),
## same convention as CombatantBarsBase.PILL_RADIUS, so the class-icon tile
## reads as a round medallion instead of a rounded square. Card is a themed
## Panel now - its corners come from Panel/styles/panel in theme.tres, not
## this shader.
const CHIP_RADIUS := 22.0

const KNOWN_ICON_CLASSES := [&"priest", &"ranger", &"warrior"]

var _dead: bool = false

var card: Panel
var chip_border: ColorRect
var chip: ColorRect
var chip_glyph: ClassIconGlyph
var chip_label: Label
var hp_text: Label
var buff_shield: Control

func _ready() -> void:
	health_border = $HealthBorder
	health_bg = $HealthBorder/HealthBg
	health_fill = $HealthBorder/HealthBg/HealthFill
	super._ready()
	_fill_width = HERO_FILL_WIDTH

	card = $Card
	chip_border = $ChipBorder
	chip = $ChipBorder/Chip
	chip_glyph = $ChipBorder/Chip/ChipGlyph
	chip_label = $ChipBorder/Chip/ChipLabel
	hp_text = $HealthBorder/HealthBg/HealthFill/HpText
	buff_shield = $BuffShield
	_round(chip_border, CHIP_RADIUS + 2.0)
	_round(chip, CHIP_RADIUS)

## Called by party_bars.gd the moment a hero's bars are spawned.
func setup(c: Combatant) -> void:
	combatant = c
	var stats := c.stats if c != null else null
	if stats != null:
		chip.color = stats.accent_color
		var has_glyph: bool = stats.id in KNOWN_ICON_CLASSES
		chip_glyph.set_kind(stats.id if has_glyph else &"")
		chip_label.text = stats.display_name.substr(0, 1).to_upper()
		chip_label.visible = not has_glyph
	refresh()

func refresh() -> void:
	if combatant == null or not is_instance_valid(combatant):
		return
	var alive := combatant.is_alive()
	if alive and _dead:
		set_alive()
	elif not alive and not _dead:
		set_dead()
	if poll_health:
		var fraction := combatant.hp_fraction() if alive else 0.0
		if not is_equal_approx(fraction, _polled_fraction):
			var healed := fraction > _polled_fraction and _polled_fraction >= 0.0
			_polled_fraction = fraction
			tween_health_fraction(fraction, healed)
			if not healed:
				flash_background()
	hp_text.text = "DEAD" if not alive else "%d" % [combatant.current_hp]
	buff_shield.visible = alive and combatant.is_defending()

## A dead hero's bar stays in the party strip, greyed and reading DEAD, rather
## than vanishing: the roster is the only place the party's losses are shown.
func set_dead() -> void:
	_dead = true
	buff_shield.visible = false
	set_health_fraction(0.0)
	modulate = Color(0.45, 0.45, 0.52)

func set_alive() -> void:
	_dead = false
	modulate = Color.WHITE
