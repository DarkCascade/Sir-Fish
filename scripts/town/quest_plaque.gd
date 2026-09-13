class_name QuestPlaque
extends Button
## [mayor notice board] One hand-authored quest from res://resources/quests/,
## shown under Standing Contracts as a slim plaque: name, a level / encounter
## line, and gold. These never change, so they get a plainer, denser row than
## the day's parchment notices. Pressing it opens the QuestNoticeSheet.

signal chosen(quest: QuestDef)

var quest: QuestDef

@onready var _name: Label = $Row/Text/Name
@onready var _sub: Label = $Row/Text/Sub
@onready var _gold: Label = $Row/Gold

func _ready() -> void:
	pressed.connect(func() -> void: chosen.emit(quest))

## Call once the plaque is in the tree. [levels] spec §2.6: underlevelled is a
## warning, never a lock - the sub line swaps its encounter count for the
## party's level, in C_DANGER, and the plaque stays enabled.
func setup(q: QuestDef, hero_level: int) -> void:
	quest = q
	_name.text = q.display_name
	_gold.text = str(q.gold_reward)
	if hero_level < q.level_range.x:
		_sub.text = "Lv %d–%d  ·  you are Lv %d" % [q.level_range.x, q.level_range.y, hero_level]
		_sub.add_theme_color_override("font_color", Tuning.C_DANGER)
	else:
		_sub.text = "Lv %d–%d  ·  %d encounters" % [
			q.level_range.x, q.level_range.y, q.encounter_types.size()]
