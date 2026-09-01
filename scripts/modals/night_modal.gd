extends Control
## [day-night] The two night modals (day/night spec §5). One scene, one script,
## two sibling panels separated by a scene change:
##   - ChoicePanel  - party health, and the inn / street choice (§5.1).
##   - ResultPanel  - the same bars as they WERE, then filling to their new
##                    values, shown after the fade home (§5.2, §4.3).
##
## Lives under Hud/ModalLayer, sibling to QuestResult. Driven off
## QuestResult.dismissed for the normal path and EventBus.profile_ready for the
## §8.2 resume. The night is already applied and saved by the time ResultPanel
## opens - it is a pure replay of GameState.last_night_report.

const HERO_BARS := preload("res://scenes/overlay/hero_bars.tscn")

@onready var scrim: ColorRect = $Scrim
@onready var choice_panel: PanelContainer = $ChoicePanel
@onready var result_panel: PanelContainer = $ResultPanel
@onready var _day_line: Label = $ChoicePanel/V/DayLine
@onready var _choice_rows: VBoxContainer = $ChoicePanel/V/Rows
@onready var _inn_button: Button = $ChoicePanel/V/PrimaryButton
@onready var _street_button: Button = $ChoicePanel/V/SecondaryButton
@onready var _result_title: Label = $ResultPanel/V/Title
@onready var _result_subtitle: Label = $ResultPanel/V/Subtitle
@onready var _result_rows: VBoxContainer = $ResultPanel/V/Rows
@onready var _morning_button: Button = $ResultPanel/V/PrimaryButton

func _ready() -> void:
	_inn_button.pressed.connect(_on_inn_pressed)
	_street_button.pressed.connect(_on_street_pressed)
	_morning_button.pressed.connect(_dismiss_result)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.profile_ready.connect(_on_profile_ready)
	# Sibling under ModalLayer. NOT Hud.quest_result: that @onready resolves in
	# Hud._ready(), which runs AFTER this child's _ready().
	var qr := get_node_or_null("../QuestResult")
	if qr != null:
		qr.dismissed.connect(_on_result_dismissed)
	scrim.modulate.a = 0.0
	choice_panel.hide()
	result_panel.hide()
	hide()

## [day-night] §0.4.1 / §5.1: there is no way out of the choice but a button.
func _unhandled_input(event: InputEvent) -> void:
	if choice_panel.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()

## §8.2 resume: boot.gd emits profile_ready after loading the profile. A night
## owed presents the choice directly over the town screen - no stats screen
## (run_stats was expedition-scoped and never saved).
func _on_profile_ready() -> void:
	if GameState.day_phase == GameState.DayPhase.NIGHT_PENDING:
		_show_choice()

## The normal path: QuestResult's "Make camp" dismisses into here.
func _on_result_dismissed() -> void:
	if GameState.day_phase != GameState.DayPhase.NIGHT_PENDING:
		return   # RETRY / dev path - no night (§10.4)
	_show_choice()

func _on_gold_changed(_total: int, _delta: int) -> void:
	if choice_panel.visible:
		_refresh_inn_button()

# --- the choice -----------------------------------------------------------

func _show_choice() -> void:
	show()
	result_panel.hide()
	_day_line.text = "Day %d" % GameState.day_number
	_seed_rows(_choice_rows, _runtime_rows())
	_refresh_inn_button()

	choice_panel.modulate.a = 1.0
	choice_panel.show()
	scrim.modulate.a = 0.0
	create_tween().tween_property(scrim, "modulate:a", 1.0, 0.5)
	choice_panel.pivot_offset = choice_panel.size * 0.5
	choice_panel.scale = Vector2(0.9, 0.9)
	create_tween().tween_property(choice_panel, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _refresh_inn_button() -> void:
	var cost := GameState.night_inn_cost()
	_inn_button.text = "Stay at the Inn  —  %d G" % cost
	var can := GameState.gold >= cost
	_inn_button.disabled = not can
	_inn_button.modulate = Color.WHITE if can else Color(0.68, 0.65, 0.6, 1.0)

func _on_inn_pressed() -> void:
	_resolve(GameState.NightChoice.INN)

func _on_street_pressed() -> void:
	_resolve(GameState.NightChoice.STREET)

func _resolve(choice: int) -> void:
	# resolve_night() applies and returns the report atomically, or [] if a
	# night is not owed / the inn is unaffordable - leave the buttons live.
	var report: Array = GameState.resolve_night(choice)
	if report.is_empty():
		return
	SaveGame.save_profile()
	_inn_button.disabled = true
	_street_button.disabled = true
	choice_panel.hide()
	# [day-night] §4.2 / §6.3: the 1.5 s fade IS the route home. `force` because
	# the resume path is already routed to TOWN and would otherwise drop it.
	await SceneRouter.go(SceneRouter.Place.TOWN,
		Tuning.NIGHT_FADE_OUT, Tuning.NIGHT_FADE_IN, true)
	_inn_button.disabled = false
	_street_button.disabled = false
	_show_result(choice, report)

# --- the result ---------------------------------------------------------

func _show_result(choice: int, report: Array) -> void:
	var inn := choice == GameState.NightChoice.INN
	_result_title.text = "MORNING" if inn else "A COLD MORNING"
	_result_subtitle.text = "You wake with the dawn, every wound closed." if inn \
		else "The cold got into your bones, but the bleeding stopped."
	result_panel.modulate.a = 1.0
	result_panel.show()
	_build_result_rows(report)

func _build_result_rows(report: Array) -> void:
	for c: Node in _result_rows.get_children():
		c.queue_free()
	var rows: Array = []
	for e: Dictionary in report:
		var row := HERO_BARS.instantiate()
		_result_rows.add_child(row)
		row.setup_detached(GameState.get_stats(e["stats_id"]))
		row.show_hp(int(e["before_hp"]), int(e["max_hp"]))   # the "before" picture
		rows.append(row)

	# Hold so the player reads the damage, then fill, staggered per hero (§5.2).
	await get_tree().process_frame
	await get_tree().create_timer(Tuning.NIGHT_BAR_HOLD).timeout
	for i: int in range(rows.size()):
		if i > 0:
			await get_tree().create_timer(Tuning.NIGHT_BAR_STAGGER).timeout
		var e: Dictionary = report[i]
		rows[i].tween_hp(int(e["after_hp"]), int(e["max_hp"]), Tuning.NIGHT_BAR_FILL)

func _dismiss_result() -> void:
	_morning_button.disabled = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(scrim, "modulate:a", 0.0, 0.3)
	tw.tween_property(result_panel, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(func() -> void:
		result_panel.hide()
		result_panel.modulate.a = 1.0
		_morning_button.disabled = false
		hide())

# --- rows --------------------------------------------------------------

## One {stats_id, hp, max} per hero_runtime entry - the "before" picture the
## brief asks for, and the seed for both modals.
func _runtime_rows() -> Array:
	var out: Array = []
	for e: Dictionary in GameState.hero_runtime:
		out.append({
			"stats_id": e["stats_id"],
			"hp": int(e["current_hp"]),
			"max": int(e["max_hp"]),
		})
	return out

func _seed_rows(into: VBoxContainer, data: Array) -> void:
	for c: Node in into.get_children():
		c.queue_free()
	for d: Dictionary in data:
		var row := HERO_BARS.instantiate()
		into.add_child(row)
		row.setup_detached(GameState.get_stats(d["stats_id"]))
		row.show_hp(int(d["hp"]), int(d["max"]))
