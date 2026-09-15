extends Control
## [town] The mayor's office (spec 7.5), laid out as a notice board (mayor
## notice board redesign). Two sections, both inside one ScrollContainer so a
## bigger board scrolls instead of pushing the title under the HUD:
##   - Today's Postings: GameState.quest_board_offers() (content phase 1 spec
##     §3 Step 3) as parchment QuestNotices in a two-column grid. The DawnSlip
##     fills the odd cell and says when the board turns over.
##   - Standing Contracts: every QuestDef in res://resources/quests/, ordered by
##     level_range.x rather than a hardcoded id list, as QuestPlaques.
## Pressing either opens the NoticeSheet (quest_notice_sheet.gd). Its "Take the
## notice" calls GameState.start_expedition(quest), saves the profile (spec
## 2.4's "When to save" names this caller), and routes to Place.QUEST.
##
## A quest is always available - no cooldown, no lockout, no prerequisite.
## Difficulty is the gate (spec 7.5). A generated quest follows the same rule
## for as long as it is offered: taking or finishing it does not remove it.
## The generated board as a whole refreshes after every finished quest and every
## inn night (GameState.refresh_quest_board()); the authored quests never change.
##
## The background (assets/mayor-bg.png) and its darkening Vignette scrim are
## authored in mayor_office.tscn - the Meshy art pass, spec 12.1 (step 11).

const QUEST_DIR := "res://resources/quests/"
const NOTICE_SCENE := preload("res://scenes/town/quest_notice.tscn")
const PLAQUE_SCENE := preload("res://scenes/town/quest_plaque.tscn")
## Hand-picked tilts, cycled by grid position. Fixed rather than rolled, so the
## board does not rearrange itself on every visit.
const NOTICE_TILTS: Array[float] = [-1.4, 1.1, 0.8, -0.9]

@onready var _today_grid: GridContainer = $Layout/Scroll/Body/Board/Inner/TodayGrid
@onready var _dawn_slip: PanelContainer = $Layout/Scroll/Body/Board/Inner/TodayGrid/DawnSlip
@onready var _dawn_label: Label = $Layout/Scroll/Body/Board/Inner/TodayGrid/DawnSlip/Label
@onready var _standing_list: VBoxContainer = $Layout/Scroll/Body/StandingList
@onready var _back_button: Button = $Layout/BackButton
@onready var _fed_line: Label = $Layout/FedLine
@onready var _sheet: QuestNoticeSheet = $NoticeSheet

func _ready() -> void:
	# spec 3.1: re-assert our own place for direct launches (F5, play_scene).
	SceneRouter.place = SceneRouter.Place.MAYOR
	_back_button.pressed.connect(SceneRouter.go.bind(SceneRouter.Place.TOWN))
	_sheet.accepted.connect(_accept)
	_populate()
	# [day-night] §9.6.2: the meal is bought before the quest choice and spent
	# after it - this line is the only thing joining those two moments, so it is
	# part of the pass, not a nice-to-have. Hidden entirely when meal_pct == 0.
	_fed_line.visible = GameState.meal_pct > 0
	if _fed_line.visible:
		_fed_line.text = "The party is well fed. +%d%% damage." % GameState.meal_pct

## ui_cancel (and therefore Android's back gesture) closes an open notice
## first, and otherwise routes home (spec 7.1).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _sheet.visible:
			_sheet.close()
		else:
			SceneRouter.go(SceneRouter.Place.TOWN)
		get_viewport().set_input_as_handled()

func _populate() -> void:
	# [levels] spec §2.6: underlevelled is read off the band here, once, and
	# only ever tints - difficulty is the gate (this file's own header).
	var hero := GameState.hero_level()
	var offers := GameState.quest_board_offers()
	for i: int in range(offers.size()):
		var q: QuestDef = offers[i]
		var notice: QuestNotice = NOTICE_SCENE.instantiate()
		_today_grid.add_child(notice)
		_today_grid.move_child(notice, _dawn_slip.get_index())
		notice.tilt_degrees = NOTICE_TILTS[i % NOTICE_TILTS.size()]
		notice.setup(q, hero < q.level_range.x)
		notice.chosen.connect(_open_sheet.bind(false))
	# The slip only ever fills a gap: the odd cell, or the whole board when
	# QuestGenerator found no template (generate_board()'s empty return).
	_dawn_slip.visible = offers.is_empty() or offers.size() % 2 == 1
	if offers.is_empty():
		_dawn_label.text = "No notices today. Fresh ones go up at dawn."

	for q: QuestDef in _load_authored_quests():
		var plaque: QuestPlaque = PLAQUE_SCENE.instantiate()
		_standing_list.add_child(plaque)
		plaque.setup(q, hero)
		plaque.chosen.connect(_open_sheet.bind(true))

func _open_sheet(q: QuestDef, standing: bool) -> void:
	_sheet.open(q, standing, GameState.hero_level())

func _accept(q: QuestDef) -> void:
	GameState.start_expedition(q)
	SaveGame.save_profile()
	SceneRouter.go(SceneRouter.Place.QUEST)

## Every QuestDef in res://resources/quests/, sorted by level_range.x - the
## data that already exists to express "easy comes before hard", rather than
## a second, hardcoded ordering (QUEST_ORDER is gone, spec §3 exit criteria).
##
## [recruitment] A recruitment quest is the one standing contract that DOES
## stop being offered once done - it has already been won in the way this
## header describes ("taking or finishing it does not remove it") for every
## other quest, but re-offering "recruit the mage" after she has already
## joined would be a lie the board tells. Filtered by outcome (the class is
## already in active_party), not by quest id, so a future second recruitment
## quest needs no edit here.
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
		if res is QuestDef and not _already_recruited(res):
			out.append(res)
	out.sort_custom(func(a: QuestDef, b: QuestDef) -> bool: return a.level_range.x < b.level_range.x)
	return out

func _already_recruited(q: QuestDef) -> bool:
	for extra: QuestRewardExtra in q.reward_extras:
		if extra is RecruitRewardExtra and GameState.active_party.has((extra as RecruitRewardExtra).hero_class):
			return true
	return false
