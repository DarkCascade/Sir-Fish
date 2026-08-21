extends Control
## Live slot wins / spins with a five-spin streak strip (spec 17.8 / Q24).
##
## No percentage anywhere a small sample can be read as a verdict. An observed
## defeat run reported 7 wins / 21 spins = 33.3% on the summary; at 21 spins one
## sigma is about 11 points, so that is ordinary variance - but a player reading
## "33%" concludes the machine is rigged, which is the opposite of the reassurance
## putting it there was meant to give. The raw counts read as texture rather than
## as a claim; the 50% sanity check lives in test_slot_odds, where the sample size
## makes it meaningful.

## slot_machine.gd has no class_name, so the win rule is reached through the
## script resource rather than duplicated here - there is one definition of a win.
const SlotMachineScript := preload("res://scripts/console/slot_machine.gd")

const PIP := 12.0
const PIP_GAP := 6.0
const STREAK_LEN := 5

var _streak: Array[bool] = []

var _wins: Label
var _spins: Label
var _pips: Control

func _ready() -> void:
	custom_minimum_size = Vector2(172, 164)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	EventBus.slot_spin_stopped.connect(_on_spin_stopped)
	EventBus.run_started.connect(_on_run_started)
	refresh()

func _build() -> void:
	var caption := Label.new()
	caption.text = "SLOT"
	caption.position = Vector2(0, 8)
	caption.size = Vector2(172, 24)
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)

	_wins = Label.new()
	_wins.theme_type_variation = &"DisplayLabel"
	_wins.position = Vector2(0, 34)
	_wins.size = Vector2(172, 56)
	_wins.add_theme_font_size_override("font_size", 52)
	_wins.add_theme_color_override("font_color", Tuning.C_GOLD)
	_wins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wins)

	var divider := ColorRect.new()
	divider.position = Vector2(36, 92)
	divider.size = Vector2(100, 2)
	divider.color = Tuning.C_PANEL_BORDER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)

	_spins = Label.new()
	_spins.position = Vector2(0, 104)
	_spins.size = Vector2(172, 28)
	_spins.add_theme_font_size_override("font_size", 24)
	_spins.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	_spins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_spins)

	_pips = Control.new()
	_pips.position = Vector2(0, 138)
	_pips.size = Vector2(172, PIP)
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.draw.connect(_draw_pips)
	add_child(_pips)

## Newest on the right (spec 17.8).
func _draw_pips() -> void:
	var total := PIP * float(STREAK_LEN) + PIP_GAP * float(STREAK_LEN - 1)
	var x := (_pips.size.x - total) * 0.5
	for i: int in range(STREAK_LEN):
		# Pad on the left so an early run fills from the right as spins arrive.
		var index := i - (STREAK_LEN - _streak.size())
		var won := index >= 0 and _streak[index]
		var r := Rect2(Vector2(x + float(i) * (PIP + PIP_GAP), 0.0), Vector2(PIP, PIP))
		_pips.draw_rect(r, Tuning.C_GOLD if won else Tuning.C_PANEL_BORDER)

func _on_spin_stopped(symbols: Array) -> void:
	var won := int(SlotMachineScript.evaluate(symbols)["count"]) >= 2
	_streak.append(won)
	while _streak.size() > STREAK_LEN:
		_streak.pop_front()
	if won:
		_punch()
	refresh()

func _on_run_started() -> void:
	_streak.clear()
	refresh()

func refresh() -> void:
	_wins.text = str(int(GameState.run_stats["slot_wins"]))
	_spins.text = "%d spins" % int(GameState.run_stats["slot_spins"])
	_pips.queue_redraw()

func _punch() -> void:
	_wins.pivot_offset = _wins.size * 0.5
	var tw := create_tween()
	tw.tween_property(_wins, "scale", Vector2(1.18, 1.18), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_wins, "scale", Vector2.ONE, 0.13)
