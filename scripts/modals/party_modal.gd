extends Control
## [town] The party status modal (spec 3.2). Lives in Hud/ModalLayer, opened by
## the HUD's heal-glyph button that sits beside the backpack button. One row per
## active_party member: name, an HP bar, and the current/max HP readout, with a
## fallen hero greyed and marked.
##
## Read-only - there is no heal here (that is the inn, spec 7.2). Like the
## inventory modal it pauses the tree while open (ModalLayer is
## PROCESS_MODE_ALWAYS, so the modal keeps animating); in town nothing is
## running to pause, and the button is disabled in COMBAT so it can never freeze
## a fight for a heal-timing read.
##
## Rebuilt on every open() from GameState.party_status() - the town has no combat
## ticking HP down under it, so there is nothing to live-update against.

@onready var scrim: ColorRect = $Scrim
@onready var panel: PanelContainer = $Panel
@onready var close_button: Button = $Panel/Layout/Header/CloseButton
@onready var members: VBoxContainer = $Panel/Layout/Members

func _ready() -> void:
	close_button.pressed.connect(close)
	hide()

func open() -> void:
	if visible:
		return
	_rebuild()
	show()
	get_tree().paused = true

	scrim.modulate.a = 0.0
	create_tween().tween_property(scrim, "modulate:a", 1.0, 0.2)

	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.85, 0.85)
	panel.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)

func close() -> void:
	get_tree().paused = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2(0.9, 0.9), 0.2)
	tw.tween_property(panel, "modulate:a", 0.0, 0.2)
	tw.tween_property(scrim, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(hide)

## Optional desktop / Android-back nicety; the red X stays the only required
## close path, same contract as inventory_modal.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# --- build ----------------------------------------------------------------

func _rebuild() -> void:
	for child: Node in members.get_children():
		child.queue_free()
	for h: Dictionary in GameState.party_status():
		members.add_child(_member_row(h))

func _member_row(h: Dictionary) -> Control:
	var alive: bool = h["alive"]
	var cur: int = h["current_hp"]
	var top: int = maxi(int(h["max_hp"]), 1)
	var ratio := clampf(float(cur) / float(top), 0.0, 1.0)

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if not alive:
		row.modulate = Color(1, 1, 1, 0.45)

	var top_line := HBoxContainer.new()
	top_line.add_theme_constant_override("separation", 16)
	row.add_child(top_line)

	var name_label := Label.new()
	name_label.theme_type_variation = &"DisplayLabel"
	name_label.add_theme_font_size_override("font_size", 36)
	name_label.add_theme_color_override("font_color", Tuning.C_TEXT)
	name_label.text = h["display_name"]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_line.add_child(name_label)

	var hp_text := Label.new()
	hp_text.add_theme_font_size_override("font_size", 32)
	hp_text.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	hp_text.text = "Fallen" if not alive else "%d / %d" % [cur, top]
	top_line.add_child(hp_text)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 30)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = float(top)
	bar.value = float(cur)
	bar.add_theme_stylebox_override("background", _bar_bg())
	bar.add_theme_stylebox_override("fill", _bar_fill(
		Tuning.C_DANGER.lerp(Tuning.C_HEAL, ratio) if alive else Tuning.C_DANGER))
	row.add_child(bar)
	return row

func _bar_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.043, 0.086, 1.0)
	sb.border_color = Color(0.227, 0.227, 0.282, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	return sb

func _bar_fill(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(8)
	return sb
