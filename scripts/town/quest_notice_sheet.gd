class_name QuestNoticeSheet
extends Control
## [mayor notice board] The full notice, opened from a QuestNotice or a
## QuestPlaque: blurb, objectives, the labelled route, level band against the
## party's level, and the reward. "Take the notice" emits `accepted`;
## mayor_office.gd owns what happens next (start, save, route).
##
## Closes on "Put it back", a tap on the scrim, or ui_cancel (routed here by
## mayor_office.gd's _unhandled_input, so Android's back gesture closes the
## sheet before it leaves the office).

signal accepted(quest: QuestDef)

var _quest: QuestDef

@onready var _scrim: ColorRect = $Scrim
@onready var _kicker: Label = $Paper/Frame/Margin/V/Kicker
@onready var _name: Label = $Paper/Frame/Margin/V/Name
@onready var _blurb: Label = $Paper/Frame/Margin/V/Blurb
@onready var _objective_header: Label = $Paper/Frame/Margin/V/ObjectiveHeader
@onready var _objective: Label = $Paper/Frame/Margin/V/Objective
@onready var _route: QuestRouteStrip = $Paper/Frame/Margin/V/Route
@onready var _road_note: Label = $Paper/Frame/Margin/V/RoadNote
@onready var _level: Label = $Paper/Frame/Margin/V/Facts/LevelCol/Level
@onready var _level_note: Label = $Paper/Frame/Margin/V/Facts/LevelCol/LevelNote
@onready var _gold: Label = $Paper/Frame/Margin/V/Facts/RewardCol/GoldRow/Gold
@onready var _drop: Label = $Paper/Frame/Margin/V/Facts/RewardCol/Drop
@onready var _extras: Label = $Paper/Frame/Margin/V/Facts/RewardCol/Extras
@onready var _put_back: Button = $Paper/Frame/Margin/V/Buttons/PutBack
@onready var _take: Button = $Paper/Frame/Margin/V/Buttons/Take

func _ready() -> void:
	hide()
	_put_back.pressed.connect(close)
	_take.pressed.connect(_on_take)
	_scrim.gui_input.connect(_on_scrim_input)

## A quest is always available (mayor_office.gd's header), so the take button
## is never locked - underlevelled only tints the level note.
func open(q: QuestDef, standing: bool, hero_level: int) -> void:
	_quest = q
	_kicker.text = "Standing contract" if standing else "Today's posting"
	_name.text = q.display_name
	_blurb.text = q.blurb
	_blurb.visible = not q.blurb.is_empty()

	var goals: PackedStringArray = []
	for o: QuestObjective in q.objectives:
		if not o.description.is_empty():
			goals.append(o.description)
	_objective.text = "\n".join(goals)
	_objective.visible = not goals.is_empty()
	_objective_header.visible = _objective.visible

	_route.encounter_types = q.encounter_types.duplicate()
	# [content phase 1] The road strip alone reads as a guaranteed path - warn
	# here when an objective (SlayObjective today) can satisfy is_complete()
	# before the route's later stops, the boss included, ever happen.
	_road_note.visible = q.objectives.any(
		func(o: QuestObjective) -> bool: return o.can_end_early())

	_level.text = "%d – %d" % [q.level_range.x, q.level_range.y]
	if hero_level < q.level_range.x:
		_level_note.text = "you are Lv %d - underlevelled" % hero_level
		_level_note.add_theme_color_override("font_color", Tuning.C_DANGER_INK)
	else:
		_level_note.text = "you are Lv %d" % hero_level
		_level_note.add_theme_color_override("font_color", Tuning.C_INK_DIM)

	_gold.text = "%d gold" % q.gold_reward
	# Floor 0 (Common) guarantees nothing worth a line.
	_drop.visible = q.boss_drop_rarity_floor > 0
	_drop.text = "boss drops %s or better" % Item.rarity_name_for(q.boss_drop_rarity_floor)
	# [content phase 1] Reward extras (D2 / spec §3 Step 1b). Empty on every
	# quest this phase ships (QuestRewardExtra's header).
	var extra_bits: PackedStringArray = []
	for extra: QuestRewardExtra in q.reward_extras:
		var text := extra.describe()
		if not text.is_empty():
			extra_bits.append("+ " + text)
	_extras.text = "\n".join(extra_bits)
	_extras.visible = not extra_bits.is_empty()
	show()

func close() -> void:
	hide()
	_quest = null

func _on_take() -> void:
	if _quest != null:
		accepted.emit(_quest)

func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
		accept_event()
