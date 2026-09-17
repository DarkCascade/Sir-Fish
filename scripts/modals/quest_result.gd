extends Control
## [town] Quest / run result screen (spec 18, spec 8.5). Renamed from RunSummary
## at step 5 and reparented into Hud/ModalLayer so it can present over a town
## scene it was never a child of.
##
## Three modes:
##   - RETRY   - endless / fixed dev path. One "RETRY" button; `dismissed` is
##               what RunController._on_retry binds. Covers BOTH outcomes on
##               that path (see _victory below) - RunController.run() also
##               calls present(true) on a non-quest win.
##   - VICTORY / FAILURE - a quest ended, won or lost. They differ only in
##               heading, subtitle and stat rows - both show one "Return to
##               Town" button that routes home. RunController has already
##               applied the party's recovery (GameState.recover_after_expedition())
##               and saved by the time this screen appears, so dismissing it
##               only moves the player.
##
## present() is driven HERE, off EventBus.quest_finished, not from RunController,
## because it must outlive main.tscn (spec 8.5): the stats show over the
## battlefield tableau, and the route home happens on dismiss.
##
## [move-elements-to-editor] The whole screen is authored in quest_result.tscn -
## Sir Fish at the top and one named row per statistic, each carrying its caption
## and a plausible dummy number. This script writes numbers into the rows it
## recognises, by node NAME, and leaves the rest alone.
##
## [run-summary-modal] `_victory == false` - a quest FAILURE or a RETRY-mode
## wipe, the only way _game_over() is ever reached (battle_director.gd:539) -
## gets its own choreographed reveal (_present_failure): blank, then Sir
## Fish's tank fades in over his already-triggered `slump` clip (EventBus.
## game_over, fired at the top of RunController._play_wipe_cinematic so it
## plays in sync with the battlefield's own slow-motion beat), then the
## verdict pops in, then Return to Town, then a shorter row set fades in fast
## and overlapped. `_victory == true` keeps the original all-at-once reveal.

signal dismissed()

enum Mode { RETRY, VICTORY, FAILURE }

@onready var scrim: ColorRect = $Scrim
@onready var panel: PanelContainer = $Panel
@onready var fish: Control = $Panel/Layout/SummaryFish
@onready var title: Label = $Panel/Layout/Title
@onready var subtitle: Label = $Panel/Layout/Subtitle
@onready var divider: HBoxContainer = $Panel/Layout/Divider
@onready var stat_rows: VBoxContainer = $Panel/Layout/Stats
@onready var primary_button: Button = $Panel/Layout/Buttons/PrimaryButton
@onready var secondary_button: Button = $Panel/Layout/Buttons/SecondaryButton

var _mode: Mode = Mode.RETRY
var _victory: bool = false

## Short, punchy stand-ins for "DEFEATED" on any failure (spec: PDR
## party-wipe-cinematic) - picked once per present(), not per branch below.
const PUNCH_WORDS := ["ouch", "oof", "nope"]

## [run-summary-modal] The failure reveal's own, shorter row set, in the exact
## order it should read - reordered into place every present() regardless of
## how quest_result.tscn happens to author them, since the authored order
## interleaves victory-only rows this case hides.
const _FAILURE_ROW_ORDER: Array[StringName] = [
	&"NetGold", &"ExpeditionScrap", &"ItemsFound", &"EncountersCleared",
	&"RunTime", &"DamageDealt", &"DamageTaken", &"IconsSpins",
]
const _VICTORY_ONLY_ROWS: Array[StringName] = [
	&"QuestReward", &"ExpeditionGold", &"GoldEarned", &"GoldSpent",
	&"GoldOnHand", &"SlotSpins", &"SlotWins", &"UpgradesBought", &"ItemsSold",
]

const _BLANK_HOLD := 0.35         # beat before Sir Fish fades in
const _FISH_FADE_TIME := 0.4
const _FISH_HOLD := 0.5           # lets the slump/death pose read before the text pops
const _TEXT_POP_TIME := 0.4
const _BUTTON_FADE_TIME := 0.25
const _ROW_FADE_TIME := 0.22
const _ROW_OVERLAP := 0.75        # next row starts once the current one is this fraction opaque

func _ready() -> void:
	primary_button.pressed.connect(_on_primary_pressed)
	secondary_button.pressed.connect(_on_secondary_pressed)
	# spec 8.5: the victory / failure flow lands here after RunController emits.
	EventBus.quest_finished.connect(_on_quest_finished)
	hide()

## Present over the battlefield tableau - NO route first. _dismiss() routes home.
func _on_quest_finished(victory: bool) -> void:
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

	if victory:
		_present_victory()
	else:
		_present_failure()

func _apply_heading(is_quest: bool) -> void:
	var punch_word: String = PUNCH_WORDS[RNG.randi_range(0, PUNCH_WORDS.size() - 1)]
	if is_quest:
		title.text = "QUEST COMPLETE" if _victory else punch_word
	else:
		title.text = "LEVEL CLEARED" if _victory else punch_word
	title.add_theme_font_size_override("font_size", 78 if _victory else 96)
	title.add_theme_color_override("font_color",
		Tuning.C_GOLD if _victory else Tuning.C_DANGER)

	if is_quest:
		# Quest names already lead with "The" ("The Shallow Wood"), so the
		# failure line takes the same "%s — ..." shape as the victory one rather
		# than prefixing a second article.
		var qname: String = GameState.completed_quest.display_name
		# [inn & recovery] A win's free night at the inn (GameState.
		# recover_after_expedition()) is named here, or the full heal on the
		# way home reads as a bug.
		subtitle.text = ("%s — the town stands you a night at the inn" % qname) if _victory \
			else ("%s — the expedition is lost" % qname)
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

## RETRY -> "RETRY"; VICTORY and FAILURE -> "Return to Town". SecondaryButton is
## hidden in all three modes - it stays in the scene as authored chrome for the
## next two-button modal.
func _configure_buttons() -> void:
	secondary_button.visible = false
	primary_button.disabled = false
	primary_button.modulate = Color.WHITE

	match _mode:
		Mode.RETRY:
			primary_button.text = "RETRY"
		Mode.VICTORY, Mode.FAILURE:
			primary_button.text = "Return to Town"

func _on_primary_pressed() -> void:
	_dismiss()

func _on_secondary_pressed() -> void:
	pass   # SecondaryButton is hidden in every mode; kept for the future.

## A quest ending routes home; RETRY stays on the battlefield for
## RunController._on_retry, which listens to `dismissed`.
func _dismiss() -> void:
	hide()
	dismissed.emit()
	if _mode != Mode.RETRY:
		SceneRouter.go(SceneRouter.Place.TOWN)

## The original all-at-once reveal (spec 8.5): scrim wash, title overshoot,
## stat rows sliding in staggered. Explicitly resets every alpha this screen
## touches to 1.0 first, since the SAME long-lived instance may have just run
## _present_failure(), which leaves several of them at 0.
func _present_victory() -> void:
	scrim.modulate.a = 0.0
	var s := create_tween()
	s.tween_property(scrim, "modulate:a", 1.0, 0.5)

	fish.modulate.a = 1.0
	title.modulate.a = 1.0
	subtitle.modulate.a = 1.0
	divider.modulate.a = 1.0
	primary_button.modulate.a = 1.0

	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(1.6, 1.6)
	var t := create_tween()
	t.tween_property(title, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_build_stats()

## [run-summary-modal] Any defeat (spec: PDR party-wipe-cinematic /
## run-summary-modal): blank, Sir Fish's tank fades in over his own
## already-playing `slump` clip, the verdict explodes onto the page, Return to
## Town fades in so a player who wants out isn't gated behind the rows, then
## the failure row set cascades in fast and overlapped.
func _present_failure() -> void:
	_prepare_failure_rows()

	scrim.modulate.a = 0.0
	create_tween().tween_property(scrim, "modulate:a", 1.0, 0.5)

	fish.modulate.a = 0.0
	title.modulate.a = 0.0
	subtitle.modulate.a = 0.0
	divider.modulate.a = 0.0
	primary_button.modulate.a = 0.0
	for row: Control in stat_rows.get_children():
		if row.visible:
			row.modulate.a = 0.0

	await get_tree().create_timer(_BLANK_HOLD).timeout

	await create_tween().tween_property(fish, "modulate:a", 1.0, _FISH_FADE_TIME).finished
	await get_tree().create_timer(_FISH_HOLD).timeout

	# The verdict explodes in - an exaggerated version of the victory title's
	# own overshoot, big enough to read as impact rather than a heading.
	title.modulate.a = 1.0
	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(2.2, 2.2)
	var text_tw := create_tween().set_parallel(true)
	text_tw.tween_property(title, "scale", Vector2.ONE, _TEXT_POP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	text_tw.tween_property(subtitle, "modulate:a", 1.0, _TEXT_POP_TIME)
	await text_tw.finished

	var button_tw := create_tween().set_parallel(true)
	button_tw.tween_property(primary_button, "modulate:a", 1.0, _BUTTON_FADE_TIME)
	button_tw.tween_property(divider, "modulate:a", 1.0, _BUTTON_FADE_TIME)
	await button_tw.finished

	_reveal_rows_overlapped(_FAILURE_ROW_ORDER)

## Hides every victory-only row, shows and reorders the failure set into
## _FAILURE_ROW_ORDER, and fills every visible row's Value label.
func _prepare_failure_rows() -> void:
	_rebuild_reward_extra_rows(false)
	for row_name: StringName in _VICTORY_ONLY_ROWS:
		_row_visible(row_name, false)
	for row_name: StringName in _FAILURE_ROW_ORDER:
		_row_visible(row_name, true)
	for i: int in range(_FAILURE_ROW_ORDER.size()):
		var row := stat_rows.get_node_or_null(NodePath(_FAILURE_ROW_ORDER[i]))
		if row != null:
			stat_rows.move_child(row, i)
	_fill_row_values()

## Fades each row in fully, starting the next once the current one is
## _ROW_OVERLAP (75%) opaque - a linear fade reaches that fraction of its
## final alpha at that same fraction of its duration, so this is timed
## mathematically rather than polled.
func _reveal_rows_overlapped(order: Array[StringName]) -> void:
	var delay := 0.0
	for row_name: StringName in order:
		var row := stat_rows.get_node_or_null(NodePath(row_name)) as Control
		if row == null or not row.visible:
			continue
		create_tween().tween_property(row, "modulate:a", 1.0, _ROW_FADE_TIME).set_delay(delay)
		delay += _ROW_FADE_TIME * _ROW_OVERLAP

## Fills in the authored rows and plays them in one at a time. The three quest
## rows (QuestReward / ExpeditionGold / ExpeditionScrap) are shown only on a
## quest ending, and QuestReward only on a win. Victory-only - see
## _prepare_failure_rows() for the failure reveal's own, shorter row set.
##
## The slot-win PERCENTAGE stays deliberately absent (spec 18.2 / 17.8 / Q24):
## at ~20 spins one sigma is ~11 points, so a healthy machine can print "33%"
## and read as rigged. Raw count here; the 50% check lives in test_slot_odds.
func _build_stats() -> void:
	var is_quest: bool = GameState.completed_quest != null
	_row_visible(&"QuestReward", is_quest and _victory)
	_row_visible(&"ExpeditionGold", is_quest)
	_row_visible(&"ExpeditionScrap", is_quest)
	_row_visible(&"NetGold", false)
	_row_visible(&"IconsSpins", false)
	_rebuild_reward_extra_rows(is_quest and _victory)
	_fill_row_values()

	var i := 0
	for row: Control in stat_rows.get_children():
		if not row.visible:
			continue
		# Reveal one at a time, 0.08s apart, sliding in from the left.
		row.modulate.a = 0.0
		row.position.x = -60.0
		var tw: Tween = row.create_tween().set_parallel(true)
		tw.tween_property(row, "modulate:a", 1.0, 0.2).set_delay(0.08 * float(i))
		tw.tween_property(row, "position:x", 0.0, 0.25).set_delay(0.08 * float(i)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		i += 1

## Every row this screen can show, keyed by node NAME - both present() paths
## call this and let it just leave stale text sitting under a hidden row.
func _row_values() -> Dictionary:
	var stats: Dictionary = GameState.run_stats
	var is_quest: bool = GameState.completed_quest != null
	return {
		&"QuestReward": str(GameState.completed_quest.gold_reward) if is_quest and _victory else "",
		&"ExpeditionGold": str(GameState.expedition_gold),
		&"ExpeditionScrap": str(GameState.expedition_scrap),
		# [run-summary-modal] Net for the run, not a running total - can go
		# negative, unlike every other row here.
		&"NetGold": str(int(stats["gold_earned"]) - int(stats["gold_spent"])),
		&"EncountersCleared": str(int(stats["encounters_cleared"])),
		&"RunTime": _format_time(float(stats["run_time"])),
		&"GoldEarned": str(int(stats["gold_earned"])),
		&"GoldSpent": str(int(stats["gold_spent"])),
		&"GoldOnHand": str(GameState.gold),
		&"DamageDealt": str(int(stats["damage_dealt"])),
		&"DamageTaken": str(int(stats["damage_taken"])),
		&"SlotSpins": str(int(stats["slot_spins"])),
		&"SlotWins": str(int(stats["slot_wins"])),
		# [run-summary-modal] X = every icon resolution this expedition (a
		# payline triple's centre row counts twice - see slot_machine.gd);
		# Y = only spins that actually resolved at least one, so a spin still
		# spinning when the party wiped doesn't count.
		&"IconsSpins": "%d icons hit in %d spins" % \
			[int(stats["slot_icons_hit"]), int(stats["slot_spins_resolved"])],
		&"UpgradesBought": str(int(stats["upgrades_bought"])),
		&"ItemsFound": str(int(stats["items_found"])),
		&"ItemsSold": str(int(stats["items_sold"])),
	}

func _fill_row_values() -> void:
	var values := _row_values()
	for row: Control in stat_rows.get_children():
		var value_label := row.get_node_or_null("Value") as Label
		if value_label != null and values.has(row.name):
			value_label.text = String(values[row.name])

## [content phase 1] One extra Caption/Value row per QuestRewardExtra with
## non-empty describe(), inserted right after the authored QuestReward row -
## same HBoxContainer/Caption/Value shape as every authored row, since there
## is no scene node to fill in for these (the list is empty on every shipped
## quest; see content-phase-1 questions doc Q6). Rebuilt from scratch each
## present() so a re-presented modal never doubles the rows up.
const _REWARD_EXTRA_GROUP := "quest_reward_extra_row"

func _rebuild_reward_extra_rows(show_rows: bool) -> void:
	for row: Node in get_tree().get_nodes_in_group(_REWARD_EXTRA_GROUP):
		if row.get_parent() == stat_rows:
			row.queue_free()
	if not show_rows or GameState.completed_quest == null:
		return
	var quest_reward_row := stat_rows.get_node_or_null(NodePath(&"QuestReward"))
	var insert_index: int = quest_reward_row.get_index() + 1 if quest_reward_row != null else 0
	for extra: QuestRewardExtra in GameState.completed_quest.reward_extras:
		var text := extra.describe()
		if text.is_empty():
			continue
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 54)
		row.add_to_group(_REWARD_EXTRA_GROUP)
		var caption := Label.new()
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.add_theme_color_override("font_color", Tuning.C_GOLD)
		caption.add_theme_font_size_override("font_size", 46)
		caption.text = text
		row.add_child(caption)
		stat_rows.add_child(row)
		stat_rows.move_child(row, insert_index)
		insert_index += 1

func _row_visible(row_name: StringName, visible_now: bool) -> void:
	var row := stat_rows.get_node_or_null(NodePath(row_name)) as Control
	if row != null:
		row.visible = visible_now

static func _format_time(seconds: float) -> String:
	var total := int(round(seconds))
	@warning_ignore("integer_division")
	var minutes := total / 60
	return "%d:%02d" % [minutes, total % 60]
