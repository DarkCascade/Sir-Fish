extends PanelContainer
## One item for sale (spec 15.2). 880 x 260.

signal purchased(item: Item, card: Control)

var item: Item = null
var sold: bool = false

@onready var edge: ColorRect = $Row/Edge
@onready var name_label: Label = $Row/Layout/Info/NameLabel
@onready var subtitle_label: Label = $Row/Layout/Info/SubtitleLabel
@onready var modifiers_box: VBoxContainer = $Row/Layout/Info/Modifiers
@onready var price_label: Label = $Row/Layout/PriceBox/PriceRow/PriceLabel

var _pulse: Tween = null

func setup(i: Item) -> void:
	item = i
	edge.color = i.rarity_color()
	name_label.text = i.display_name
	subtitle_label.text = i.subtitle()
	subtitle_label.add_theme_color_override("font_color", i.rarity_color())
	for child: Node in modifiers_box.get_children():
		child.queue_free()
	for mod: Dictionary in i.modifiers:
		var line := Label.new()
		line.text = String(mod["label"])
		line.add_theme_font_size_override("font_size", 28)
		line.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
		modifiers_box.add_child(line)
	price_label.text = str(i.buy_price())
	gui_input.connect(_on_gui_input)

## Re-run whenever gold changes: on purchase, on sale, on slot gold payouts
## (spec 15.2).
func refresh_affordability() -> void:
	if sold:
		return
	var affordable := GameState.gold >= item.buy_price()
	modulate = Color.WHITE if affordable else Color(0.45, 0.45, 0.5, 1.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if affordable \
		else Control.CURSOR_ARROW
	if affordable and _pulse == null:
		price_label.pivot_offset = price_label.size * 0.5
		_pulse = create_tween().set_loops()
		_pulse.tween_property(price_label, "scale", Vector2(1.04, 1.04), 0.8) \
			.set_trans(Tween.TRANS_SINE)
		_pulse.tween_property(price_label, "scale", Vector2.ONE, 0.8) \
			.set_trans(Tween.TRANS_SINE)
	elif not affordable and _pulse != null:
		_pulse.kill()
		_pulse = null
		price_label.scale = Vector2.ONE

func _on_gui_input(event: InputEvent) -> void:
	if sold:
		return
	var tapped := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if not tapped:
		return
	if GameState.gold < item.buy_price():
		return
	_buy()

func _buy() -> void:
	if not GameState.spend_gold(item.buy_price()):
		return
	sold = true
	GameState.add_item(item)
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	price_label.text = "SOLD!"
	price_label.add_theme_color_override("font_color", Tuning.C_DANGER)
	modulate = Color(0.45, 0.45, 0.5, 1.0)
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	purchased.emit(item, self)
