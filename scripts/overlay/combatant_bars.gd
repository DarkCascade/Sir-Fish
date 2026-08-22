extends Control
## Health + cooldown pair for one combatant (spec 11). Lives in the 2D overlay,
## never in 3D, so it can be positioned pixel-exactly over the character.
##
## Two layouts from one scene. Enemies keep the compact 140 x 34 pair authored in
## the scene file, floating over the character in the battle overlay. Heroes get
## the wider variant - name chip, exact HP numbers, a defend pip and a DEAD state
## - and live in the console's resource strip instead (see party_bars.gd), where
## they sit still and read as a party roster rather than three labels drifting
## around the battlefield.

const ENEMY_FILL_WIDTH := 136.0

## Three of these sit side by side in the console strip (party_bars.gd).
const HERO_SIZE := Vector2(172, 58)
const HERO_CD_WIDTH := 168.0
const HERO_FILL_WIDTH := 100.0

var combatant: Combatant = null

var _fill_width: float = ENEMY_FILL_WIDTH
var _cd_width: float = ENEMY_FILL_WIDTH
var _is_hero: bool = false
var _dead: bool = false

## Overlay bars are pushed their health by BattleOverlay's damage handlers, which
## also spawn the detaching chunk (spec 11.2). The console's party bars have no
## such handler and no chunk to detach, so they pull the fraction on every frame
## instead and tween the difference.
var poll_health: bool = false
var _polled_fraction: float = -1.0

@onready var cooldown_border: ColorRect = $CooldownBorder
@onready var cooldown_bg: ColorRect = $CooldownBg
@onready var cooldown_fill: ColorRect = $CooldownFill
@onready var health_border: ColorRect = $HealthBorder
@onready var health_bg: ColorRect = $HealthBg
@onready var health_fill: ColorRect = $HealthFill
@onready var chip: ColorRect = $Chip
@onready var chip_label: Label = $Chip/ChipLabel
@onready var hp_text: Label = $HpText
@onready var buff_shield: Control = $BuffShield

## Called by BattleOverlay the moment the bars are spawned, before pop_in().
func setup(c: Combatant) -> void:
	combatant = c
	_is_hero = c != null and c.is_hero
	if _is_hero:
		_layout_hero()
	refresh()

## The hero variant is built here rather than in a second scene file so the two
## stay one thing: BattleOverlay spawns one bars scene and never branches.
func _layout_hero() -> void:
	custom_minimum_size = HERO_SIZE
	size = HERO_SIZE
	pivot_offset = HERO_SIZE * 0.5
	_fill_width = HERO_FILL_WIDTH
	_cd_width = HERO_CD_WIDTH

	_place(cooldown_border, Vector2(-2, -2), Vector2(176, 14))
	_place(cooldown_bg, Vector2(0, 0), Vector2(172, 10))
	_place(cooldown_fill, Vector2(2, 2), Vector2(HERO_CD_WIDTH, 6))
	_place(health_border, Vector2(36, 16), Vector2(108, 36))
	_place(health_bg, Vector2(38, 18), Vector2(104, 32))
	_place(health_fill, Vector2(40, 20), Vector2(HERO_FILL_WIDTH, 28))
	_place(chip, Vector2(0, 16), Vector2(32, 32))
	_place(hp_text, Vector2(38, 16), Vector2(104, 36))
	_place(buff_shield, Vector2(146, 20), Vector2(26, 26))
	hp_text.add_theme_font_size_override("font_size", 18)
	chip_label.add_theme_font_size_override("font_size", 22)

	var stats := combatant.stats
	if stats != null:
		chip.color = stats.accent_color
		chip_label.text = stats.display_name.substr(0, 1).to_upper()
	chip.visible = true
	hp_text.visible = true

static func _place(node: Control, pos: Vector2, dims: Vector2) -> void:
	node.position = pos
	node.size = dims

func pop_in() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.6, 0.6)
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, Tuning.BARS_POP_IN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, Tuning.BARS_POP_IN_TIME)

func refresh() -> void:
	if combatant == null or not is_instance_valid(combatant):
		return
	if not _is_hero:
		cooldown_fill.size.x = _cd_width * combatant.cooldown_fraction()
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
	cooldown_fill.size.x = 0.0 if not alive else _cd_width * combatant.cooldown_fraction()
	hp_text.text = "DEAD" if not alive else "%d / %d" % [combatant.current_hp, combatant.max_hp]
	buff_shield.visible = alive and combatant.is_defending()

## A dead hero's bar stays in the party strip, greyed and reading DEAD, rather
## than vanishing: the roster is the only place the party's losses are shown.
func set_dead() -> void:
	_dead = true
	buff_shield.visible = false
	cooldown_border.visible = false
	cooldown_bg.visible = false
	cooldown_fill.visible = false
	set_health_fraction(0.0)
	modulate = Color(0.45, 0.45, 0.52)

func set_alive() -> void:
	_dead = false
	cooldown_border.visible = true
	cooldown_bg.visible = true
	cooldown_fill.visible = true
	modulate = Color.WHITE

## Snaps the health fill; the detached chunk carries the motion (spec 11.2).
func set_health_fraction(fraction: float) -> void:
	health_fill.size.x = _fill_width * clampf(fraction, 0.0, 1.0)

## Healing tweens up instead, and flashes green (spec 11.2). A polled party bar
## losing health tweens the same way but must not flash green about it.
func tween_health_fraction(fraction: float, heal_flash: bool = true) -> void:
	var tw := create_tween()
	tw.tween_property(health_fill, "size:x", _fill_width * clampf(fraction, 0.0, 1.0), 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if not heal_flash:
		return
	var flash := create_tween()
	flash.tween_property(health_fill, "color", Tuning.C_HEAL, 0.15)
	flash.tween_property(health_fill, "color", Tuning.C_DANGER, 0.15)

func flash_background() -> void:
	var tw := create_tween()
	tw.tween_property(health_bg, "color", Color.WHITE, 0.05)
	tw.tween_property(health_bg, "color", Tuning.C_CONSOLE_BG, 0.05)

## World-space rect of the segment that was just lost, in global 2D coords.
func lost_segment_rect(f_prev: float, f_new: float) -> Rect2:
	var x0 := _fill_width * clampf(f_new, 0.0, 1.0)
	var x1 := _fill_width * clampf(f_prev, 0.0, 1.0)
	var origin := health_fill.global_position + Vector2(x0, 0.0)
	return Rect2(origin, Vector2(maxf(x1 - x0, 1.0), health_fill.size.y))

func fade_and_free() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
