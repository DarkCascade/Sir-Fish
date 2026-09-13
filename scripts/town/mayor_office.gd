extends Control
## [town] The mayor's office (spec 7.5). One button per QuestDef - the three
## hand-authored quests in res://resources/quests/, ordered by level_range.x
## rather than a hardcoded id list, followed by the generated board
## (GameState.quest_board_offers(), content phase 1 spec §3 Step 3) - each
## showing name, blurb, encounter count and gold reward. Pressing one calls
## GameState.start_expedition(quest), saves the profile (spec 2.4's "When to
## save" names this caller), and routes to Place.QUEST.
##
## A quest is always available - no cooldown, no lockout, no prerequisite.
## Difficulty is the gate (spec 7.5). A generated quest follows the same rule
## for as long as it is offered: taking or finishing it does not remove it.
## The generated board as a whole rerolls each new day (GameState.resolve_night(),
## content-phase-1 questions doc Q7); the three authored quests never change.
##
## The background (assets/mayor-bg.png) and its darkening Vignette scrim are
## authored in mayor_office.tscn - the Meshy art pass, spec 12.1 (step 11).

const QUEST_DIR := "res://resources/quests/"

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
		# [phase 0] type ramp M step; the levels readout below adds a third and
		# sometimes fourth line, so this button is the one most at risk of
		# overflowing its 210px floor - see the Phase 0 verification handoff.
		button.add_theme_font_size_override("font_size", 54)
		# [levels] spec §2.6: name the band so a player can read difficulty off
		# the number, not just the tier label. Underlevelled is a warning, never
		# a lock - difficulty is the gate (this file's own header), so the
		# button stays enabled and only tints.
		var underlevelled: bool = GameState.hero_level() < q.level_range.x
		# [content phase 1] Reward extras (D2 / spec §3 Step 1b) render as an
		# extra "+ ..." clause after the gold figure. Empty on every quest this
		# phase ships (QuestRewardExtra's header), so this is normally a no-op.
		var extra_bits: PackedStringArray = []
		for extra: QuestRewardExtra in q.reward_extras:
			var text := extra.describe()
			if not text.is_empty():
				extra_bits.append(text)
		var extras_suffix := ("  ·  +" + " +".join(extra_bits)) if not extra_bits.is_empty() else ""
		button.text = "%s\n%s\nLv. %d–%d  ·  %d encounters  ·  %d gold%s%s" % [
			q.display_name, q.blurb, q.level_range.x, q.level_range.y,
			q.encounter_types.size(), q.gold_reward, extras_suffix,
			"\n— you are underlevelled" if underlevelled else "",
		]
		if underlevelled:
			button.add_theme_color_override("font_color", Tuning.C_DANGER)
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
	var out: Array[QuestDef] = _load_authored_quests()
	out.append_array(GameState.quest_board_offers())
	return out

## Every QuestDef in res://resources/quests/, sorted by level_range.x - the
## data that already exists to express "easy comes before hard", rather than
## a second, hardcoded ordering (QUEST_ORDER is gone, spec §3 exit criteria).
func _load_authored_quests() -> Array[QuestDef]:
	var out: Array[QuestDef] = []
	var dir := DirAccess.open(QUEST_DIR)
	if dir == null:
		return out
	for file_name: String in dir.get_files():
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var res := load(QUEST_DIR + clean)
		if res is QuestDef:
			out.append(res)
	out.sort_custom(func(a: QuestDef, b: QuestDef) -> bool: return a.level_range.x < b.level_range.x)
	return out
