extends Control
class_name BossNameplate
## The boss encounter's title card ("Black Glass Nameplate" - boss transition
## exploration). Played fire-and-forget by RunController._travel() over a boss
## encounter's own travel leg: letterbox bars close, the quest name fades in,
## then the boss's own name slams down. That landing beat is also the exact
## moment the console swaps to its Black Glass boss theme - see `impact`
## below - and RunController is what actually calls Console.apply_boss_theme()
## when it fires, never this scene; this scene only presents.
##
## Tuned to finish (~3.0s) well inside a boss encounter's 4.0s travel_duration
## (EncounterDef's own default ramp already gives the boss leg exactly that -
## see game_state.gd's _default_quest_travel()), so it never has to race
## RunController._arrive() to get off screen.
##
## A single persistent instance (authored in battle_overlay.tscn, like
## BarsLayer/FloatingLayer/VfxLayer beside it) rather than instanced per
## encounter - reset() at the top of every play() is what makes replaying it
## safe, including the pathological case of two boss encounters in a row.

signal impact()   ## The chrome-swap beat - see this file's own header.

const LEAD_DIM_TIME := 0.35
const LEAD_NAME_TIME := 0.3
const LEAD_RULE_TIME := 0.25
const HOLD_TIME := 1.7
const FADE_TIME := 0.4
const POP_TIME := 0.28
const TAG_DELAY := 0.15
const TAG_TIME := 0.2
const FLASH_IN_TIME := 0.08
const FLASH_OUT_TIME := 0.35
const SHAKE_PIXELS := 6.0

@onready var dim: ColorRect = $Dim
@onready var top_bar: ColorRect = $TopBar
@onready var bottom_bar: ColorRect = $BottomBar
@onready var card: VBoxContainer = $Card
@onready var quest_label: Label = $Card/QuestLabel
@onready var rule: ColorRect = $Card/Rule
@onready var name_label: Label = $Card/NameLabel
@onready var tag_label: Label = $Card/TagLabel
@onready var flash: ColorRect = $Flash

var _tween: Tween = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	rule.pivot_offset = rule.size * 0.5
	# name_label's size depends on the boss's own name (set fresh every play()),
	# so its pivot is re-centred on every resize rather than once here - the
	# same reason compare_flyout.gd re-syncs its own frame off item_rect_changed
	# instead of a one-shot pivot set.
	name_label.resized.connect(func() -> void: name_label.pivot_offset = name_label.size * 0.5)

## `quest_name` / `boss_name` are display strings, already resolved by the
## caller (RunController) - this scene has no opinion on where they come from.
func play(quest_name: String, boss_name: String) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	quest_label.text = quest_name
	name_label.text = boss_name
	_reset()
	visible = true

	_tween = create_tween()
	_tween.tween_property(dim, "modulate:a", 1.0, LEAD_DIM_TIME)
	_tween.parallel().tween_property(top_bar, "modulate:a", 1.0, LEAD_DIM_TIME)
	_tween.parallel().tween_property(bottom_bar, "modulate:a", 1.0, LEAD_DIM_TIME)
	_tween.tween_property(quest_label, "modulate:a", 1.0, LEAD_NAME_TIME)
	_tween.tween_property(rule, "scale:x", 1.0, LEAD_RULE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_land)
	_tween.tween_interval(HOLD_TIME)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	await _tween.finished
	visible = false

func _reset() -> void:
	modulate.a = 1.0
	position = Vector2.ZERO
	dim.modulate.a = 0.0
	top_bar.modulate.a = 0.0
	bottom_bar.modulate.a = 0.0

	quest_label.modulate.a = 0.0
	quest_label.add_theme_color_override("font_color", Tuning.C_GOLD_BRIGHT)
	rule.scale = Vector2(0.0, 1.0)
	rule.color = Tuning.C_GOLD

	name_label.modulate.a = 0.0
	name_label.scale = Vector2(1.4, 1.4)
	tag_label.modulate.a = 0.0
	flash.modulate.a = 0.0

## The name's landing beat: the flash, the shake, the pop-in, and the console
## chrome swap (via `impact`, which RunController listens for). Everything
## from here runs as its OWN tween(s), independent of the main sequence in
## play() above - the hold/fade-out keeps going underneath regardless.
func _land() -> void:
	impact.emit()
	quest_label.add_theme_color_override("font_color", Tuning.C_SEAM)
	rule.color = Tuning.C_SEAM
	name_label.add_theme_color_override("font_color", Tuning.C_SEAM_BRIGHT)

	var pop := create_tween().set_parallel(true)
	pop.tween_property(name_label, "modulate:a", 1.0, POP_TIME)
	pop.tween_property(name_label, "scale", Vector2.ONE, POP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(tag_label, "modulate:a", 1.0, TAG_TIME).set_delay(TAG_DELAY)

	var fl := create_tween()
	fl.tween_property(flash, "modulate:a", 0.85, FLASH_IN_TIME)
	fl.tween_property(flash, "modulate:a", 0.0, FLASH_OUT_TIME)

	var shake := create_tween()
	shake.tween_property(self, "position", Vector2(0, SHAKE_PIXELS), 0.05)
	shake.tween_property(self, "position", Vector2.ZERO, 0.08)
