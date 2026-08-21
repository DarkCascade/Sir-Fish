extends PanelContainer
## One inventory item with a sell button underneath it (spec 15.3). 880 x 180.

signal sold(item: Item, row: Control)

var item: Item = null

@onready var edge: ColorRect = $Row/Edge
@onready var name_label: Label = $Row/Layout/Info/NameLabel
@onready var subtitle_label: Label = $Row/Layout/Info/SubtitleLabel
@onready var mods_label: Label = $Row/Layout/Info/ModsLabel
@onready var sell_button: Button = $Row/Layout/SellButton
@onready var sell_amount_label: Label = $Row/Layout/SellButton/Content/AmountLabel

func setup(i: Item) -> void:
	item = i
	edge.color = i.rarity_color()
	name_label.text = i.display_name
	subtitle_label.text = i.subtitle()
	subtitle_label.add_theme_color_override("font_color", i.rarity_color())
	mods_label.text = "%d modifier%s" % [i.modifiers.size(),
		"" if i.modifiers.size() == 1 else "s"]
	# [v3.5 F4] Coin glyph + amount live in Content, not the button's own text
	# (spec 15.3); the button stays clickable and empty.
	sell_button.text = ""
	sell_amount_label.text = "Sell for %d" % i.sell_price()
	sell_button.pressed.connect(_on_sell)

func _on_sell() -> void:
	sell_button.disabled = true
	GameState.add_gold(item.sell_price())
	GameState.remove_item(item)
	GameState.run_stats["items_sold"] = int(GameState.run_stats["items_sold"]) + 1
	sold.emit(item, self)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "custom_minimum_size:y", 0.0, 0.25)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(queue_free)
