class_name QuestNotice
extends Control
## [mayor notice board] One of today's generated quests
## (GameState.quest_board_offers()), pinned to the mayor's board as a
## parchment notice: name, level band, gold, and the encounter route. Pressing
## it opens the QuestNoticeSheet - the blurb and objective live there, not on
## the card.
##
## The root is a plain Control on purpose: GridContainer.fit_child_in_rect()
## resets a direct child's rotation to 0 on every layout pass, so the tilt goes
## on Card one level down, which the container never touches.

signal chosen(quest: QuestDef)

## Degrees, applied about the card's centre.
@export var tilt_degrees: float = 0.0:
	set(v):
		tilt_degrees = v
		if is_node_ready():
			_card.rotation_degrees = v

var quest: QuestDef

@onready var _card: Button = $Card
@onready var _name: Label = $Card/Margin/V/Name
@onready var _lv_chip: PanelContainer = $Card/Margin/V/Meta/LvChip
@onready var _lv: Label = $Card/Margin/V/Meta/LvChip/Lv
@onready var _gold: Label = $Card/Margin/V/Meta/Gold
@onready var _route: QuestRouteStrip = $Card/Margin/V/Route

func _ready() -> void:
	_card.resized.connect(_recentre_pivot)
	_recentre_pivot()
	_card.rotation_degrees = tilt_degrees
	_card.pressed.connect(func() -> void: chosen.emit(quest))

func _recentre_pivot() -> void:
	_card.pivot_offset = _card.size * 0.5

## Call once the notice is in the tree. `underlevelled` inks the level chip red -
## a warning, never a lock (mayor_office.gd's header: difficulty is the gate).
func setup(q: QuestDef, underlevelled: bool) -> void:
	quest = q
	_name.text = q.display_name
	_lv.text = "Lv %d–%d" % [q.level_range.x, q.level_range.y]
	_gold.text = str(q.gold_reward)
	_route.encounter_types = q.encounter_types.duplicate()
	if underlevelled:
		_lv.add_theme_color_override("font_color", Tuning.C_DANGER_INK)
		var chip := _lv_chip.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		chip.border_color = Tuning.C_DANGER_INK
		_lv_chip.add_theme_stylebox_override("panel", chip)
