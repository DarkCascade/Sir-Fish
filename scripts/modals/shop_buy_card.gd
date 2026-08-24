extends PanelContainer
## One item for sale (spec 15.2). 880 x 260.
##
## [equip] Buying used to be "tap anywhere on the card"; the coin/price plate is
## its own Button (see shop_buy_card.tscn's BuyButton) so purchasing is a
## deliberate hit target.
##
## [ui-project-longshot] Comparing used to be the other half of that split - a
## tap on the card body outside BuyButton. It is CompareButton now. A whole-card
## tap target that nothing on the card advertises is not a feature the player
## can find, and it cost real code to defend: the body tap had to be told apart
## from a mouse-wheel notch and from a touch drag that was really a list scroll.
##
## [mobile-scroll] The card root and both buttons are mouse_filter = PASS so a
## touch drag reaches the enclosing ScrollContainer instead of being swallowed -
## see shop_sell_row.gd's header for the full reasoning. Three cards at 260 px
## do not overflow the ~955 px tab body, so the Buy tab does not actually scroll
## today; this is here so it behaves the moment SHOP_ITEMS_FOR_SALE grows.

signal purchased(item: Item, card: Control)
signal compare_requested(item: Item)

var item: Item = null
var sold: bool = false

@onready var edge: ColorRect = $Row/Edge
@onready var name_label: Label = $Row/Layout/Info/NameLabel
@onready var subtitle_label: Label = $Row/Layout/Info/SubtitleLabel
@onready var modifiers_box: VBoxContainer = $Row/Layout/Info/Modifiers
@onready var buy_button: Button = $Row/Layout/PriceBox/BuyButton
@onready var compare_button: Button = $Row/Layout/PriceBox/CompareButton
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
	buy_button.pressed.connect(_on_buy_pressed)
	compare_button.pressed.connect(func() -> void: compare_requested.emit(item))

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
