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
##
## [party-wipe-consequences] BOTH reveals gained a beat before the heading: four
## spoils reels (one per Spoils.Category) that decide what the run actually
## brings home. THIS SCREEN IS WHERE THE RUN IS SETTLED now - RunController hands
## over an ending with its XP still banked and its loose loot still in the
## inventory, and GameState.apply_spoils() resolves both here, once the reels
## land.
##
## Which is also why the heading is no longer a fixed word on either path. Each
## LOSE is -1 and each DOUBLE +1, and that sum alone picks the word and its
## colour - red at <= -1, yellow at 0, green at >= 1. Winning or wiping adds
## nothing of its own to the total because the two POOLS already carry it (see
## _verdict_points()), so the word rates what the party walked away with rather
## than restating an outcome the player just watched.

signal dismissed()

enum Mode { RETRY, VICTORY, FAILURE }

@onready var scrim: ColorRect = $Scrim
@onready var panel: PanelContainer = $Panel
@onready var fish: Control = $Panel/Layout/SummaryFish
@onready var spoils_reels: HBoxContainer = $Panel/Layout/SpoilsReels
@onready var title: Label = $Panel/Layout/Title
@onready var subtitle: Label = $Panel/Layout/Subtitle
@onready var divider: HBoxContainer = $Panel/Layout/Divider
@onready var stat_rows: VBoxContainer = $Panel/Layout/Stats
@onready var primary_button: Button = $Panel/Layout/Buttons/PrimaryButton
@onready var secondary_button: Button = $Panel/Layout/Buttons/SecondaryButton

var _mode: Mode = Mode.RETRY
var _victory: bool = false

## [party-wipe-consequences] The verdict, by rating. What used to be one bank of
## punch words for every defeat is three, because a wipe that held on to
## everything is not an "oof" - see _verdict_points().
const VERDICT_BAD := ["oof", "whomp whomp", "ouch"]
const VERDICT_NEUTRAL := ["ok", "welp", "...cool"]
const VERDICT_GOOD := ["nice", "way to go", "smooth"]

## [victory-failure-stat-parity] The shared stat row set, in the exact order it
## should read - reordered into place every present() regardless of how
## quest_result.tscn happens to author them. Originally the failure reveal's
## own shorter set; the victory reveal now uses the same rows and order so the
## two screens read as one format, with QuestReward (and its extras) leading
## on a win since a loss has no reward to show.
const _STAT_ROW_ORDER: Array[StringName] = [
	&"NetGold", &"ExpeditionScrap", &"ItemsFound", &"EncountersCleared",
	&"RunTime", &"DamageDealt", &"DamageTaken", &"IconsSpins",
]
## [victory-failure-stat-parity] Superseded by _STAT_ROW_ORDER - these used to
## be the victory reveal's own, larger row set. Kept as authored chrome in
## quest_result.tscn (see _row_values(), which still fills them) but never
## shown on either screen any more.
const _RETIRED_ROWS: Array[StringName] = [
	&"ExpeditionGold", &"GoldEarned", &"GoldSpent",
	&"GoldOnHand", &"SlotSpins", &"SlotWins", &"ItemsSold",
]

const _BLANK_HOLD := 0.35         # beat before Sir Fish fades in
const _FISH_FADE_TIME := 0.4
const _FISH_HOLD := 0.5           # lets the slump/death pose read before the text pops
const _TEXT_POP_TIME := 0.4
const _BUTTON_FADE_TIME := 0.25
const _ROW_FADE_TIME := 0.22
const _ROW_OVERLAP := 0.75        # next row starts once the current one is this fraction opaque

const _SPOILS_FADE_TIME := 0.3
const _SPOILS_SPIN_TIME := 1.1    # all four free-spinning before the first stops
const _SPOILS_STAGGER := 0.45     # between one reel landing and the next stopping
const _SPOILS_HOLD := 0.6         # the four words read together before the verdict

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
	_apply_subtitle(is_quest)
	_configure_buttons()

	if victory:
		_present_victory()
	else:
		_present_failure()

## The verdict, on BOTH paths - neither heading is known until the reels have
## rolled, because the roll is what the word is rating (_verdict_points()).
func _apply_verdict(points: int) -> void:
	var bank: Array = VERDICT_NEUTRAL
	var color: Color = Tuning.C_GOLD
	if points <= -1:
		bank = VERDICT_BAD
		color = Tuning.C_DANGER
	elif points >= 1:
		bank = VERDICT_GOOD
		color = Tuning.C_HEAL
	title.text = bank[RNG.randi_range(0, bank.size() - 1)]
	# The longest words ("whomp whomp", "way to go") run edge to edge at 96 in a
	# panel this wide, and Title cannot wrap - one size down clears them.
	title.add_theme_font_size_override("font_size", 96 if title.text.length() <= 8 else 78)
	title.add_theme_color_override("font_color", color)

func _apply_subtitle(is_quest: bool) -> void:
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

## The all-at-once reveal (spec 8.5): scrim wash, everything already on the page,
## title overshoot. Explicitly resets every alpha this screen touches to 1.0
## first, since the SAME long-lived instance may have just run
## _present_failure(), which leaves several of them at 0.
func _present_victory() -> void:
	# Up front, opaque, and filled with what the run banked - a win shows its
	# stats THROUGH the spin rather than after it (_show_victory_rows).
	_show_victory_rows()

	scrim.modulate.a = 0.0
	var s := create_tween()
	s.tween_property(scrim, "modulate:a", 1.0, 0.5)

	fish.modulate.a = 1.0
	subtitle.modulate.a = 1.0
	divider.modulate.a = 1.0
	primary_button.modulate.a = 1.0

	spoils_reels.visible = true
	spoils_reels.modulate.a = 0.0
	title.modulate.a = 0.0
	# See _present_failure(): a Button that has not faded in still takes clicks,
	# and dismissing before the roll lands would skip the settlement.
	primary_button.disabled = true

	# [party-wipe-consequences] A win rolls too, on its own pool - one that can
	# only hold or improve what the run banked (Spoils.POOL_VICTORY). Only the
	# verdict waits for it; the rows are already up, and just take their new
	# numbers in place.
	var outcomes := await _spin_spoils(true)
	_settle_spoils(outcomes)
	primary_button.disabled = false
	_fill_row_values()

	_apply_verdict(_verdict_points(outcomes))
	title.modulate.a = 1.0
	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(1.6, 1.6)
	var t := create_tween()
	t.tween_property(title, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	spoils_reels.visible = true
	spoils_reels.modulate.a = 0.0
	# A transparent Button still takes clicks, and the spoils roll is what
	# SETTLES the run - dismissing mid-spin would strand the XP and the loot and
	# skip the save. Re-enabled with the fade-in below, once the roll has landed.
	primary_button.disabled = true
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

	# [party-wipe-consequences] What the run brings home is decided here, before
	# the verdict can be worded - the reels ARE the suspense beat.
	var outcomes := await _spin_spoils(false)
	_settle_spoils(outcomes)
	_apply_verdict(_verdict_points(outcomes))
	_fill_row_values()

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

	primary_button.disabled = false
	var button_tw := create_tween().set_parallel(true)
	button_tw.tween_property(primary_button, "modulate:a", 1.0, _BUTTON_FADE_TIME)
	button_tw.tween_property(divider, "modulate:a", 1.0, _BUTTON_FADE_TIME)
	await button_tw.finished

	_reveal_rows_overlapped(_STAT_ROW_ORDER)

## Hides QuestReward and every retired row, and reorders the shared set into
## _STAT_ROW_ORDER. [party-wipe-consequences] Does NOT fill the values any
## more - the spoils roll rewrites what the run brought home, so the fill waits
## until it has settled (_present_failure).
func _prepare_failure_rows() -> void:
	_rebuild_reward_extra_rows(false)
	_row_visible(&"QuestReward", false)
	for row_name: StringName in _RETIRED_ROWS:
		_row_visible(row_name, false)
	for row_name: StringName in _STAT_ROW_ORDER:
		_row_visible(row_name, true)
	for i: int in range(_STAT_ROW_ORDER.size()):
		var row := stat_rows.get_node_or_null(NodePath(_STAT_ROW_ORDER[i]))
		if row != null:
			stat_rows.move_child(row, i)

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

# --- [party-wipe-consequences] the spoils machine ----------------------------

## Fades the four reels in, spins them together, then lands them left to right
## with a beat between each. Returns the roll as
## { Spoils.Category: Spoils.Outcome }.
##
## Walks the authored children in order and pairs them with
## Spoils.CATEGORY_ORDER, so the reels read left to right in whatever order
## quest_result.tscn happens to author them.
func _spin_spoils(victory: bool) -> Dictionary:
	var reels: Array[Node] = spoils_reels.get_children()
	var count: int = mini(reels.size(), Spoils.CATEGORY_ORDER.size())
	for i: int in range(count):
		(reels[i] as SpoilsReel).setup(Spoils.CATEGORY_ORDER[i] as Spoils.Category, victory)

	await create_tween().tween_property(
		spoils_reels, "modulate:a", 1.0, _SPOILS_FADE_TIME).finished
	for i: int in range(count):
		(reels[i] as SpoilsReel).start_spin()
	await get_tree().create_timer(_SPOILS_SPIN_TIME).timeout

	var outcomes: Dictionary = {}
	for i: int in range(count):
		var reel := reels[i] as SpoilsReel
		var outcome := Spoils.roll(victory)
		outcomes[Spoils.CATEGORY_ORDER[i]] = outcome
		if i == count - 1:
			# The last one is awaited in full, so the hold below starts once its
			# word has actually popped rather than once its reel stopped moving.
			await reel.stop_on(outcome)
		else:
			reel.stop_on(outcome)
			await get_tree().create_timer(_SPOILS_STAGGER).timeout

	await get_tree().create_timer(_SPOILS_HOLD).timeout
	return outcomes

## Hands the roll to GameState, then re-saves. The quest path already saved in
## RunController, but that save predates everything the roll just changed - the
## XP it applied, the loot it kept or dropped, the gold and scrap it moved.
func _settle_spoils(outcomes: Dictionary) -> void:
	GameState.apply_spoils(outcomes)
	if GameState.completed_quest != null:
		SaveGame.save_profile()

## The run's rating, from the reels ALONE. <= -1 reads red, 0 yellow, >= 1 green
## (_apply_verdict).
##
## Winning or wiping deliberately adds nothing of its own. It does not need to:
## the two pools already carry it, since a wipe can only draw LOSE/KEEP/KEEP_HALF
## and a win only KEEP/KEEP_HALF/DOUBLE. So a wipe rates between red and yellow
## and a win between yellow and green, and the word ends up rating what the run
## WALKED AWAY WITH rather than restating an outcome the player just watched. A
## wipe that held on to everything is a "welp", not an "oof"; a win that doubled
## nothing is the same "welp", not a "nice".
func _verdict_points(outcomes: Dictionary) -> int:
	var points: int = 0
	for outcome: int in outcomes.values():
		points += Spoils.points(outcome as Spoils.Outcome)
	return points

## Puts the victory row set up, filled and fully opaque, BEFORE anything spins.
## [victory-failure-stat-parity] Same row set and order as the failure reveal
## (_STAT_ROW_ORDER) - only QuestReward, and any QuestRewardExtra rows, lead
## the list, and only on a quest win, since a loss has no reward to show.
##
## [party-wipe-consequences] These used to slide in one at a time after the
## heading. A win now reads its stats while the reels are still turning, and the
## numbers the reels touch change in place when the roll lands (_present_victory
## re-fills them) - so the player watches "Gold brought home" double rather than
## being told about it afterwards. Nothing animates them in a second time.
##
## The alphas have to be asserted rather than assumed: the SAME long-lived
## instance may have just run _present_failure(), which leaves every row at 0.
func _show_victory_rows() -> void:
	var is_quest: bool = GameState.completed_quest != null
	var show_reward: bool = is_quest and _victory
	_row_visible(&"QuestReward", show_reward)
	for row_name: StringName in _RETIRED_ROWS:
		_row_visible(row_name, false)
	for row_name: StringName in _STAT_ROW_ORDER:
		_row_visible(row_name, true)
	_rebuild_reward_extra_rows(show_reward)

	var insert_index := 0
	if show_reward:
		var quest_reward_row := stat_rows.get_node_or_null(NodePath(&"QuestReward"))
		if quest_reward_row != null:
			stat_rows.move_child(quest_reward_row, insert_index)
			insert_index += 1
		for row: Node in stat_rows.get_children():
			if row.is_in_group(_REWARD_EXTRA_GROUP):
				stat_rows.move_child(row, insert_index)
				insert_index += 1
	for row_name: StringName in _STAT_ROW_ORDER:
		var row := stat_rows.get_node_or_null(NodePath(row_name))
		if row != null:
			stat_rows.move_child(row, insert_index)
			insert_index += 1

	_fill_row_values()

	for row: Control in stat_rows.get_children():
		row.modulate.a = 1.0

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
		# [party-wipe-consequences] What came home, not what was found - the ITEMS
		# reel can halve or drop the haul, and "Items found 4" beside a LOSE is a
		# straight contradiction. run_stats["items_found"] is left as the true
		# find count for anything else that wants it.
		&"ItemsFound": str(GameState.expedition_items_held()),
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
