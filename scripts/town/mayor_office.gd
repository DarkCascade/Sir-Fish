extends Control
## [town] The mayor's office (spec 7.5). One button per QuestDef in
## res://resources/quests/, in easy -> hard order, each showing name, blurb,
## encounter count and gold reward. Pressing one calls
## GameState.start_expedition(quest), saves the profile (spec 2.4's "When to
## save" names this caller), and routes to Place.QUEST.
##
## A quest is always available - no cooldown, no lockout, no prerequisite.
## Difficulty is the gate (spec 7.5).
##
## The background (assets/mayor-bg.png) and its darkening Vignette scrim are
## authored in mayor_office.tscn - the Meshy art pass, spec 12.1 (step 11).

const QUEST_DIR := "res://resources/quests/"
## Authored order rather than DirAccess iteration order, so easy always sits top.
const QUEST_ORDER: Array[StringName] = [&"easy", &"medium", &"hard"]

@onready var _quest_list: VBoxContainer = $Layout/QuestList
@onready var _back_button: Button = $Layout/BackButton
@onready var _fed_line: Label = $Layout/FedLine

func _ready() -> void:
	# spec 3.1: re-assert our own place for direct launches (F5, play_scene).
	SceneRouter.place = SceneRouter.Place.MAYOR
	_back_button.pressed.connect(SceneRouter.go.bind(SceneRouter.Place.TOWN))
	_populate()
	# [day-night] §9.6.2: the meal is bought before the quest choice and spent
	# after it - this line is the only thing joining those two moments, so it is
	# part of the pass, not a nice-to-have. Hidden entirely when meal_pct == 0.
	_fed_line.visible = GameState.meal_pct > 0
	if _fed_line.visible:
		_fed_line.text = "The party is well fed. +%d%% damage." % GameState.meal_pct
	# [day-night] §2.3: grey the quest buttons while a night is owed, on the same
	# affordability pattern inn.gd uses. _accept()'s guard is the real lock; this
	# is so a locked button reads as locked rather than silently inert.
	if GameState.day_phase != GameState.DayPhase.DAY:
		for b: Button in _quest_list.get_children():
			b.disabled = true
			b.modulate = Color(0.68, 0.65, 0.6, 1.0)

## ui_cancel (and therefore Android's back gesture) routes home (spec 7.1).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneRouter.go(SceneRouter.Place.TOWN)
		get_viewport().set_input_as_handled()

func _populate() -> void:
	for q: QuestDef in _load_quests():
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 210)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 45)
		button.text = "%s\n%s\n%d encounters   ·   %d gold" % [
			q.display_name, q.blurb, q.encounter_types.size(), q.gold_reward,
		]
		button.pressed.connect(_accept.bind(q))
		_quest_list.add_child(button)

func _accept(q: QuestDef) -> void:
	# [day-night] §2.3: one quest per day. Unreachable through the UI (§9.6's
	# disabled state covers that); this guards a corrupt save and a debug command
	# that reach _accept() while a night is still owed.
	if GameState.day_phase != GameState.DayPhase.DAY:
		return
	GameState.start_expedition(q)
	SaveGame.save_profile()
	SceneRouter.go(SceneRouter.Place.QUEST)

func _load_quests() -> Array[QuestDef]:
	var out: Array[QuestDef] = []
	for id: StringName in QUEST_ORDER:
		var res := load(QUEST_DIR + String(id) + ".tres")
		if res is QuestDef:
			out.append(res)
	return out
