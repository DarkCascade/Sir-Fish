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

## Must track HealthFill's own authored width in hero_bars.tscn, or the bar
## visually stops short of (or overflows) its track.
##
## [ui-project-longshot] The row is measured off the concept board rather than
## eyeballed: a 60 px medallion, an 8 px gap and a 362 px track, in a 62-tall
## row with 8 between rows - which is what makes three of them fill the
## strip's right-hand third exactly. Inside the track each layer insets the one
## above it by a few px, so the bar reads as a WELL with a fill sitting in it:
##
##     HealthBorder  362 x 50   ink outline
##       HealthBg    356 x 44   the empty track
##         HealthFill 352 x 40  the coloured fill   <- this constant
##           Gloss             top strip, white at low alpha
##
## HpText is a child of HealthBg, NOT of HealthFill, and that is the one thing
## here that is easy to get wrong: parented to the fill it slides left with the
## damage and eventually clips off the bar entirely - exactly when the player
## most wants to read it.
const HERO_FILL_WIDTH := 352.0

## [presentation redesign S6.3] Past half the chip's own shorter side, same
## convention as CombatantBarsBase.PILL_RADIUS, so the class-icon tile reads as
## a round medallion instead of a rounded square.
const CHIP_RADIUS := 26.0

const KNOWN_ICON_CLASSES := [&"mage", &"ranger", &"warrior"]

## [ui-project-longshot] The concept board's three stat bars run green, blue,
## gold from top to bottom - and its numbers (102/120, 80/80, 70/70) are this
## party's own max HP, so the board is showing exactly these three heroes.
##
## Its glyphs (heart / bolt / shield) do not map to any class, so those are
## left as the existing class icons: the bolt in particular already means
## "lightning payout" on the reels, and borrowing it for the ranger would have
## the same glyph mean two things one panel apart. The colour rhythm is what
## carries the board's look, and it happens to land on the semantically right
## hero at every position anyway - the mage heals (green), the warrior
## guards (gold).
##
## Falls back to the hero's own accent_color for any class not listed, so a
## fourth hero is a resource edit and not a code change.
const CLASS_BAR_COLORS := {
	&"mage": Tuning.C_HEAL,
	&"ranger": Tuning.C_LIGHTNING,
	&"warrior": Tuning.C_DEFEND,
}

var _dead: bool = false

## [day-night] Detached rows live in the night modal's full-width VBox, not the
## console's fixed right-hand strip, so the track is re-anchored to fill that
## width and the fill is driven by an anchor ratio instead of the fixed-pixel
## HERO_FILL_WIDTH. Battle/console rows never set this and are untouched.
var _detached_stretch: bool = false
var _last_fraction: float = 1.0

## Smoothness pass: refresh() used to run the "%d / %d"-style format and
## reassign hp_text.text every frame regardless of whether current_hp had
## moved - a fresh String allocated per hero per frame purely to compare equal
## to what was already on screen. -2 never matches a real HP value (dead is
## sentinel -1), so the first refresh() still formats and writes once.
var _last_hp_shown: int = -2

var chip_border: ColorRect
var chip: ColorRect
var chip_glyph: ClassIconGlyph
var chip_label: Label
var hp_text: Label
var gloss: ColorRect
var buff_shield: Control

func _ready() -> void:
	health_border = $HealthBorder
	health_bg = $HealthBorder/HealthBg
	health_fill = $HealthBorder/HealthBg/HealthFill
	super._ready()
	_fill_width = HERO_FILL_WIDTH

	chip_border = $ChipBorder
	chip = $ChipBorder/Chip
	chip_glyph = $ChipBorder/Chip/ChipGlyph
	chip_label = $ChipBorder/Chip/ChipLabel
	hp_text = $HealthBorder/HealthBg/HpText
	gloss = $HealthBorder/HealthBg/HealthFill/Gloss
	buff_shield = $BuffShield
	_round(chip_border, CHIP_RADIUS + 2.0)
	_round(chip, CHIP_RADIUS)
	# The gloss is what turns a flat coloured rectangle into the board's
	# glassy gem bar. Rounded on the same pill radius as the fill it sits in,
	# or its square ends poke out through the fill's curved caps.
	_round(gloss, PILL_RADIUS)

## Called by party_bars.gd the moment a hero's bars are spawned.
func setup(c: Combatant) -> void:
	combatant = c
	var stats := c.stats if c != null else null
	if stats != null:
		# The medallion and the bar carry the SAME colour, so the icon reads as
		# the label for its own bar rather than as a second piece of colour
		# information competing with it.
		base_fill_color = CLASS_BAR_COLORS.get(stats.id, stats.accent_color)
		chip.color = base_fill_color
		health_fill.color = base_fill_color
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
	# "current / max", as the board reads them. The maximum is the half that
	# makes a bar's fill mean anything - 102 alone says nothing about whether
	# this hero is in trouble.
	var hp_shown: int = combatant.current_hp if alive else -1
	if hp_shown != _last_hp_shown:
		_last_hp_shown = hp_shown
		hp_text.text = "DEAD" if not alive else "%d" % [hp_shown]
	var defending := alive and combatant.is_defending()
	if defending != buff_shield.visible:
		buff_shield.visible = defending

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

# --- [day-night] detached mode (day/night spec §5.4) -----------------------
## Draw this card from profile data instead of a live Combatant, for the night
## modals in town. `combatant` stays null, so refresh() keeps early-returning
## and NOTHING on the battle path changes: poll_health is false, no _process
## reads it, and party_bars.gd never sees one of these.
func setup_detached(stats: CombatantStats) -> void:
	combatant = null
	base_fill_color = CLASS_BAR_COLORS.get(stats.id, stats.accent_color)
	chip.color = base_fill_color
	health_fill.color = base_fill_color
	var has_glyph: bool = stats.id in KNOWN_ICON_CLASSES
	chip_glyph.set_kind(stats.id if has_glyph else &"")
	chip_label.text = stats.display_name.substr(0, 1).to_upper()
	chip_label.visible = not has_glyph
	buff_shield.visible = false
	_stretch_to_row_width()

## [day-night] §5.4: the night modal wants this bar to span the panel, not sit
## at its 307 px console width. Anchor the outline and the empty track to the
## row's right edge; the fill then follows via the anchor_right ratio the two
## fraction methods below drive (rather than base set_health_fraction's fixed
## HERO_FILL_WIDTH * fraction). One-time, detached rows only.
func _stretch_to_row_width() -> void:
	_detached_stretch = true
	# Fill switches to a pure ratio: right edge = anchor_right * track width.
	health_fill.anchor_right = clampf(_last_fraction, 0.0, 1.0)
	health_fill.offset_right = 0.0
	# The row is inside a Container, so its own width is only known after a
	# layout pass; the two tracks re-anchor once it is.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	health_border.anchor_right = 1.0
	health_border.offset_right = -8.0
	health_bg.anchor_right = 1.0
	health_bg.offset_right = -3.0

## Snap. Seeds the "before" picture in both night modals.
func show_hp(current: int, maximum: int) -> void:
	_last_hp_shown = current
	hp_text.text = "DEAD" if current <= 0 else "%d" % current
	set_health_fraction(float(current) / float(maxi(maximum, 1)))
	modulate = Color(0.45, 0.45, 0.52) if current <= 0 else Color.WHITE

## Fill. `hp_text` counts up in step with the bar rather than snapping at the
## end - the number and the fill are one statement (this file's own rule).
func tween_hp(target: int, maximum: int, duration: float) -> void:
	var from: int = _last_hp_shown
	_last_hp_shown = target
	_dead = false
	tween_health_fraction(float(target) / float(maxi(maximum, 1)), true, duration)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: int) -> void: hp_text.text = "%d" % v,
		from, target, duration)
	tw.tween_property(self, "modulate", Color.WHITE, duration)

# --- fraction: fixed-pixel on the battle path, anchor ratio when stretched ---

func set_health_fraction(fraction: float) -> void:
	_last_fraction = clampf(fraction, 0.0, 1.0)
	if _detached_stretch:
		health_fill.anchor_right = _last_fraction
		health_fill.offset_right = 0.0
	else:
		super.set_health_fraction(fraction)

func tween_health_fraction(fraction: float, heal_flash: bool = true,
		duration: float = 0.25) -> void:
	if not _detached_stretch:
		super.tween_health_fraction(fraction, heal_flash, duration)
		return
	_last_fraction = clampf(fraction, 0.0, 1.0)
	create_tween().tween_property(health_fill, "anchor_right", _last_fraction, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if not heal_flash:
		return
	var flash := create_tween()
	flash.tween_property(health_fill, "color", Tuning.C_HEAL, 0.15)
	flash.tween_property(health_fill, "color", base_fill_color, 0.15)
