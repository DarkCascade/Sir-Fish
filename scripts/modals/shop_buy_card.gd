extends PanelContainer
## One item for sale (spec 15.2). 880 x 260.
##
## [equip] Buying used to be "tap anywhere on the card"; that tap now opens the
## compare flyout instead, and the coin/price plate is its own Button (see
## shop_buy_card.tscn's BuyButton) so purchasing is a separate, deliberate hit
## target from comparing.

signal purchased(item: Item, card: Control)
signal compare_requested(item: Item)

var item: Item = null
var sold: bool = false

@onready var edge: ColorRect = $Row/Edge
@onready var name_label: Label = $Row/Layout/Info/NameLabel
@onready var subtitle_label: Label = $Row/Layout/Info/SubtitleLabel
@onready var modifiers_box: VBoxContainer = $Row/Layout/Info/Modifiers
@onready var buy_button: Button = $Row/Layout/PriceBox/BuyButton
@onready var price_label: Label = $Row/Layout/PriceBox/BuyButton/Content/PriceLabel

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
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND   # compare is always tappable
	buy_button.pressed.connect(_on_buy_pressed)
	gui_input.connect(_on_gui_input)

## Re-run whenever gold changes: on purchase, on sale, on slot gold payouts
## (spec 15.2).
func refresh_affordability() -> void:
	if sold:
		return
	var affordable := GameState.gold >= item.buy_price()
	buy_button.disabled = not affordable
	buy_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if affordable \
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

## The card body (everything outside BuyButton) opens the compare flyout - a
## Button's own input consumes its clicks before they reach here, so this
## never fires for a tap on BuyButton itself.
func _on_gui_input(event: InputEvent) -> void:
	if sold:
		return
	# Excludes mouse-wheel scroll, which Godot also delivers as an
	# InputEventMouseButton press (on the wheel-up/down "buttons") - without
	# the button_index check, scrolling the shop list fired a compare_requested
	# on every notch.
	var tapped := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if not tapped:
		return
	compare_requested.emit(item)

func _on_buy_pressed() -> void:
	if sold or GameState.gold < item.buy_price():
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
	buy_button.disabled = true
	modulate = Color(0.45, 0.45, 0.5, 1.0)
	purchased.emit(item, self)
