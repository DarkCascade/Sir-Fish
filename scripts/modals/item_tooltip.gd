extends PanelContainer
## Tapping an inventory chip shows this; tapping anywhere dismisses it
## (spec 17.2).

@onready var name_label: Label = $Layout/NameLabel
@onready var subtitle_label: Label = $Layout/SubtitleLabel
@onready var modifiers_box: VBoxContainer = $Layout/Modifiers
@onready var value_label: Label = $Layout/ValueLabel

func show_item(item: Item) -> void:
	name_label.text = item.display_name
	subtitle_label.text = item.subtitle()
	subtitle_label.add_theme_color_override("font_color", item.rarity_color())
	for child: Node in modifiers_box.get_children():
		child.queue_free()
	for mod: Dictionary in item.modifiers:
		var line := Label.new()
		line.text = String(mod["label"])
		line.add_theme_font_size_override("font_size", 28)
		line.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
		modifiers_box.add_child(line)
	value_label.text = "Value %d" % item.value
