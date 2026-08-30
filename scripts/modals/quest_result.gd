extends Control
## [town] Quest / run result screen (spec 18, spec 8.5). Renamed from RunSummary
## at step 5 and reparented into Hud/ModalLayer so it can present over a town
## scene it was never a child of.
##
## Step 8 wired the quest flow. Three modes:
##   - RETRY    - endless / fixed dev path. One "RETRY" button; `dismissed` is
##                what RunController._on_retry binds.
##   - VICTORY  - a quest was completed. "Retire for the evening"; dismiss routes
##                to the inn (spec 8.5).
##   - FAILURE  - a quest was lost. Two recovery buttons (rest at the inn /
##                sleep in the street) instead of one dismiss; the flow has
##                already routed to the inn before this presents.
##
## The route + present is driven HERE, off EventBus.quest_finished, not from
## RunController: SceneRouter.go() frees main.tscn, and a coroutine that awaited
## it from RunController would resume on a freed node (spec 8.5).
##
## [move-elements-to-editor] The whole screen is authored in quest_result.tscn -
## Sir Fish at the top and one named row per statistic, each carrying its caption
## and a plausible dummy number. This script writes numbers into the rows it
## recognises, by node NAME, and leaves the rest alone.

signal dismissed()

enum Mode { RETRY, VICTORY, FAILURE }

@onready var scrim: ColorRect = $Scrim
@onready var panel: PanelContainer = $Panel
@onready var title: Label = $Panel/Layout/Title
@onready var subtitle: Label = $Panel/Layout/Subtitle
@onready var stat_rows: VBoxContainer = $Panel/Layout/Stats
@onready var primary_button: Button = $Panel/Layout/Buttons/PrimaryButton
@onready var secondary_button: Button = $Panel/Layout/Buttons/SecondaryButton

var _mode: Mode = Mode.RETRY
var _victory: bool = false
## Where _dismiss() routes after hiding, or -1 for none (spec 8.5: only the
## victory screen routes on dismiss; failure has already routed to the inn).
var _dismiss_route: int = -1

func _ready() -> void:
	primary_button.pressed.connect(_on_primary_pressed)
	secondary_button.pressed.connect(_on_secondary_pressed)
	# spec 8.5: the victory / failure flow lands here after RunController emits.
	EventBus.quest_finished.connect(_on_quest_finished)
	hide()

## spec 8.5 steps 3-5 for both endings: route home first, THEN present over it.
func _on_quest_finished(victory: bool) -> void:
	await SceneRouter.go(SceneRouter.Place.MAYOR if victory else SceneRouter.Place.INN)
	present(victory)

func present(victory: bool) -> void:
	_victory = victory
	var is_quest: bool = GameState.completed_quest != null
	if is_quest:
		_mode = Mode.VICTORY if victory else Mode.FAILURE
	else:
		_mode = Mode.RETRY

	show()
	_apply_heading(is_quest)
	_configure_buttons()

	scrim.modulate.a = 0.0
	var s := create_tween()
	s.tween_property(scrim, "modulate:a", 1.0, 0.5)

	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(1.6, 1.6)
	var t := create_tween()
	t.tween_property(title, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_build_stats()

func _apply_heading(is_quest: bool) -> void:
	if is_quest:
		title.text = "QUEST COMPLETE" if _victory else "DEFEATED"
	else:
		title.text = "LEVEL CLEARED" if _victory else "DEFEATED"
	title.add_theme_font_size_override("font_size", 76 if _victory else 84)
	title.add_theme_color_override("font_color",
		Tuning.C_GOLD if _victory else Tuning.C_DANGER)

	if is_quest:
		var qname: String = GameState.completed_quest.display_name
		subtitle.text = ("%s — the road home" % qname) if _victory \
			else ("The %s expedition is lost" % qname)
		return

	if _victory:
		subtitle.text = "Cleared all %d encounters" % GameState.level.encounters.size()
	else:
		var shown_index: int = clampi(GameState.current_encounter_index + 1, 1,
			GameState.level.encounters.size())
		if GameState.endless_mode:
			subtitle.text = "Reached Depth %d, encounter %d of %d" % \
				[GameState.endless_level_number, shown_index, GameState.level.encounters.size()]
		else:
			subtitle.text = "Reached encounter %d of %d" % \
				[shown_index, GameState.level.encounters.size()]

## RETRY / VICTORY use PrimaryButton alone; FAILURE shows both recovery buttons
## with the affordability gates spec 8.5 spells out.
func _configure_buttons() -> void:
	_dismiss_route = -1
	secondary_button.visible = false
	secondary_button.disabled = false
	primary_button.disabled = false
	primary_button.modulate = Color.WHITE
	secondary_button.modulate = Color.WHITE

	match _mode:
		Mode.RETRY:
			primary_button.text = "RETRY"
		Mode.VICTORY:
			primary_button.text = "Retire for the evening"
			_dismiss_route = SceneRouter.Place.INN
		Mode.FAILURE:
			var cost: int = _inn_cost()
			primary_button.text = "Rest at the Inn  —  %d G" % cost
			var can_rest: bool = GameState.gold >= cost
			primary_button.disabled = not can_rest
			if not can_rest:
				primary_button.modulate = Color(0.68, 0.65, 0.6, 1.0)

			secondary_button.visible = true
			secondary_button.text = "Sleep in the street  —  free"
			var slept: bool = GameState.street_sleep_used
			secondary_button.disabled = slept
			if slept:
				secondary_button.modulate = Color(0.68, 0.65, 0.6, 1.0)

func _inn_cost() -> int:
	return Tuning.INN_REST_COST_PER_HERO * maxi(GameState.active_party.size(), 1)

func _on_primary_pressed() -> void:
	if _mode == Mode.FAILURE:
		# Rest at the inn: spend, full heal, save, then close.
		if not GameState.spend_gold(_inn_cost()):
			return
		GameState.heal_party()
		SaveGame.save_profile()
	_dismiss()

func _on_secondary_pressed() -> void:
	# FAILURE only: the free half-heal (spec 8.5 / 1.9).
	GameState.street_sleep_recover()
	SaveGame.save_profile()
	_dismiss()

func _dismiss() -> void:
	hide()
	dismissed.emit()
	if _dismiss_route != -1:
		var to: int = _dismiss_route
		_dismiss_route = -1
		SceneRouter.go(to)

## Fills in the authored rows and plays them in one at a time. The three quest
## rows (QuestReward / ExpeditionGold / ExpeditionScrap) are shown only on a
## quest ending, and QuestReward only on a win.
##
## The slot-win PERCENTAGE stays deliberately absent (spec 18.2 / 17.8 / Q24):
## at ~20 spins one sigma is ~11 points, so a healthy machine can print "33%"
## and read as rigged. Raw count here; the 50% check lives in test_slot_odds.
func _build_stats() -> void:
	var is_quest: bool = GameState.completed_quest != null
	_row_visible(&"QuestReward", is_quest and _victory)
	_row_visible(&"ExpeditionGold", is_quest)
	_row_visible(&"ExpeditionScrap", is_quest)

	var stats: Dictionary = GameState.run_stats
	var values := {
		&"QuestReward": str(GameState.completed_quest.gold_reward) if is_quest and _victory else "",
		&"ExpeditionGold": str(GameState.expedition_gold),
		&"ExpeditionScrap": str(GameState.expedition_scrap),
		&"EncountersCleared": str(int(stats["encounters_cleared"])),
		&"RunTime": _format_time(float(stats["run_time"])),
		&"GoldEarned": str(int(stats["gold_earned"])),
		&"GoldSpent": str(int(stats["gold_spent"])),
		&"GoldOnHand": str(GameState.gold),
		&"DamageDealt": str(int(stats["damage_dealt"])),
		&"DamageTaken": str(int(stats["damage_taken"])),
		&"SlotSpins": str(int(stats["slot_spins"])),
		&"SlotWins": str(int(stats["slot_wins"])),
		&"UpgradesBought": str(int(stats["upgrades_bought"])),
		&"ItemsFound": str(int(stats["items_found"])),
		&"ItemsSold": str(int(stats["items_sold"])),
	}

	var i := 0
	for row: Control in stat_rows.get_children():
		if not row.visible:
			continue
		var value_label := row.get_node_or_null("Value") as Label
		if value_label != null and values.has(row.name):
			value_label.text = String(values[row.name])

		# Reveal one at a time, 0.08s apart, sliding in from the left.
		row.modulate.a = 0.0
		row.position.x = -60.0
		var tw: Tween = row.create_tween().set_parallel(true)
		tw.tween_property(row, "modulate:a", 1.0, 0.2).set_delay(0.08 * float(i))
		tw.tween_property(row, "position:x", 0.0, 0.25).set_delay(0.08 * float(i)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		i += 1

func _row_visible(row_name: StringName, visible_now: bool) -> void:
	var row := stat_rows.get_node_or_null(NodePath(row_name)) as Control
	if row != null:
		row.visible = visible_now

static func _format_time(seconds: float) -> String:
	var total := int(round(seconds))
	@warning_ignore("integer_division")
	var minutes := total / 60
	return "%d:%02d" % [minutes, total % 60]
