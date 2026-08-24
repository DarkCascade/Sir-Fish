extends Control
## Small read-only comparison of a candidate item against whatever its class
## currently has equipped. Shared by the shop's Buy and Sell tabs - shop_modal
## owns the one instance and every card/row asks it to show over itself.
##
## A plain Control + scrim, not a PopupPanel/Window - with subwindows embedded
## (this project's setup), a Window-derived popup renders itself the instant
## it is added to the tree regardless of visible/popup() state and misbehaves
## on close. This mirrors ShopModal's own proven show()/hide() + scrim pattern.

@onready var scrim: ColorRect = $Scrim
@onready var for_label: Label = $Panel/Margin/VBox/ForLabel
@onready var equipped_header: Label = $Panel/Margin/VBox/EquippedHeader
@onready var equipped_name: Label = $Panel/Margin/VBox/EquippedName
@onready var equipped_subtitle: Label = $Panel/Margin/VBox/EquippedSubtitle
@onready var equipped_mods: VBoxContainer = $Panel/Margin/VBox/EquippedMods
@onready var equipped_none: Label = $Panel/Margin/VBox/EquippedNone
@onready var candidate_header: Label = $Panel/Margin/VBox/CandidateHeader
@onready var candidate_name: Label = $Panel/Margin/VBox/CandidateName
@onready var candidate_subtitle: Label = $Panel/Margin/VBox/CandidateSubtitle
@onready var candidate_mods: VBoxContainer = $Panel/Margin/VBox/CandidateMods

func _ready() -> void:
	for_label.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	equipped_header.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	equipped_none.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	candidate_header.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	scrim.gui_input.connect(_on_scrim_input)
	hide()

## Shows `item` compared against whatever its (single, in practice) usable_by()
## class currently has equipped.
func show_for(item: Item) -> void:
	var classes := item.usable_by()
	var hero_class: StringName = classes[0] if not classes.is_empty() else &""
	for_label.visible = hero_class != &""
	for_label.text = "For %s" % String(hero_class).capitalize()

	var equipped: Item = GameState.equipped_item(hero_class) if hero_class != &"" else null
	equipped_none.visible = equipped == null
	equipped_name.visible = equipped != null
	equipped_subtitle.visible = equipped != null
	equipped_mods.visible = equipped != null
	if equipped != null:
		equipped_name.text = equipped.display_name
		equipped_subtitle.text = equipped.subtitle()
		equipped_subtitle.add_theme_color_override("font_color", equipped.rarity_color())
		_fill_mods(equipped_mods, equipped)

	candidate_name.text = item.display_name
	candidate_subtitle.text = item.subtitle()
	candidate_subtitle.add_theme_color_override("font_color", item.rarity_color())
	_fill_mods(candidate_mods, item)

	show()

## Tapping outside the panel (anywhere the scrim is visible) dismisses it -
## the panel itself has its own mouse_filter (STOP, PanelContainer's default)
## so a tap on the panel never reaches the scrim underneath it.
func _on_scrim_input(event: InputEvent) -> void:
	# Excludes mouse-wheel scroll (also delivered as an InputEventMouseButton
	# press, on the wheel-up/down "buttons") - see the same guard in
	# shop_buy_card.gd / shop_sell_row.gd.
	var tapped := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if tapped:
		hide()

func _fill_mods(container: VBoxContainer, item: Item) -> void:
	for child: Node in container.get_children():
		child.queue_free()
	if item.modifiers.is_empty():
		var l := Label.new()
		l.text = "No modifiers"
		l.add_theme_font_size_override("font_size", 26)
		l.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
		container.add_child(l)
		return
	for mod: Dictionary in item.modifiers:
		var l := Label.new()
		l.text = String(mod["label"])
		l.add_theme_font_size_override("font_size", 26)
		l.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
		container.add_child(l)
