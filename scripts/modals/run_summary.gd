extends Control
## Defeat / victory screen with the full run stats and a Retry (spec 18).

signal retry_pressed()

const FISH_TANK_SCENE := preload("res://scenes/console/sir_fish_tank.tscn")

@onready var scrim: ColorRect = $Scrim
@onready var panel: PanelContainer = $Panel
@onready var title: Label = $Panel/Layout/Title
@onready var subtitle: Label = $Panel/Layout/Subtitle
@onready var stat_rows: VBoxContainer = $Panel/Layout/Stats
@onready var retry_button: Button = $Panel/Layout/RetryButton

func _ready() -> void:
	_add_fish_tank()
	retry_button.pressed.connect(func() -> void:
		hide()
		retry_pressed.emit())
	hide()

## Sir Fish at 2x scale at the top of the panel, already holding slump or
## triumph. He is the first thing the player sees on this screen (spec 18.2).
func _add_fish_tank() -> void:
	var layout := $Panel/Layout as VBoxContainer
	var tank = FISH_TANK_SCENE.instantiate()
	tank.name = "SummaryFish"
	tank.custom_minimum_size = Vector2(328, 328)
	tank.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	layout.add_child(tank)
	layout.move_child(tank, 0)

func present(victory: bool) -> void:
	show()
	title.text = "LEVEL CLEARED" if victory else "DEFEATED"
	title.add_theme_font_size_override("font_size", 76 if victory else 84)
	title.add_theme_color_override("font_color",
		Tuning.C_GOLD if victory else Tuning.C_DANGER)
	if victory:
		subtitle.text = "Cleared all %d encounters" % GameState.level.encounters.size()
	else:
		var shown_index: int = clampi(GameState.current_encounter_index + 1, 1, GameState.level.encounters.size())
		subtitle.text = "Reached encounter %d of %d" % [shown_index, GameState.level.encounters.size()]

	scrim.modulate.a = 0.0
	var s := create_tween()
	s.tween_property(scrim, "modulate:a", 1.0, 0.5)

	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(1.6, 1.6)
	var t := create_tween()
	t.tween_property(title, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_build_stats()

func _build_stats() -> void:
	for child: Node in stat_rows.get_children():
		child.queue_free()
	var stats: Dictionary = GameState.run_stats
	var spins := int(stats["slot_spins"])
	var wins := int(stats["slot_wins"])

	# The slot-win PERCENTAGE is deliberately absent (spec 18.2 / 17.8 / Q24). At
	# the ~20 spins of a short run, one sigma is about 11 points, so a perfectly
	# healthy machine can print "33%" - and a player reading that concludes it is
	# rigged against them. The raw count goes here; the live counter lives in the
	# console; the 50% check lives in test_slot_odds, where the sample makes it mean
	# something.
	var rows: Array = [
		["Encounters cleared", str(int(stats["encounters_cleared"]))],
		["Run time", _format_time(float(stats["run_time"]))],
		["Gold earned", str(int(stats["gold_earned"]))],
		["Gold spent", str(int(stats["gold_spent"]))],
		["Gold on hand", str(GameState.gold)],
		["Damage dealt", str(int(stats["damage_dealt"]))],
		["Damage taken", str(int(stats["damage_taken"]))],
		["Slot spins", str(spins)],
		["Slot wins", str(wins)],
		["Upgrades bought", str(int(stats["upgrades_bought"]))],
		["Items found", str(int(stats["items_found"]))],
		["Items sold", str(int(stats["items_sold"]))],
	]

	for i: int in range(rows.size()):
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 54)
		stat_rows.add_child(row)

		var label := Label.new()
		label.text = String(rows[i][0])
		label.add_theme_font_size_override("font_size", 38)
		label.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var value := Label.new()
		value.text = String(rows[i][1])
		value.add_theme_font_size_override("font_size", 38)
		value.add_theme_color_override("font_color", Tuning.C_TEXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)

		# Reveal one at a time, 0.08s apart, sliding in from the left.
		row.modulate.a = 0.0
		row.position.x = -60.0
		var tw: Tween = row.create_tween().set_parallel(true)
		tw.tween_property(row, "modulate:a", 1.0, 0.2).set_delay(0.08 * float(i))
		tw.tween_property(row, "position:x", 0.0, 0.25).set_delay(0.08 * float(i)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

static func _format_time(seconds: float) -> String:
	var total := int(round(seconds))
	@warning_ignore("integer_division")
	var minutes := total / 60
	return "%d:%02d" % [minutes, total % 60]
