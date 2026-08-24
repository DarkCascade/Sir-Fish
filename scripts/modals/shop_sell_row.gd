extends PanelContainer
## One inventory item with equip/sell actions underneath it (spec 15.3).
## 880 x 180. [equip] Tapping the row body opens the compare flyout;
## EquipButton and SellButton are separate hit targets that consume their own
## clicks first, same pattern as shop_buy_card's BuyButton.

signal sold(item: Item, row: Control)
signal compare_requested(item: Item)
## Bubbled to shop_modal after an equip/unequip - equipping this item may have
## just unequipped a DIFFERENT row's item for the same hero, so the whole
## Sell tab is rebuilt rather than each row trying to track its neighbours.
signal equip_changed()

var item: Item = null
var _hero_class: StringName = &""

@onready var edge: ColorRect = $Row/Edge
@onready var name_label: Label = $Row/Layout/Info/NameLabel
@onready var subtitle_label: Label = $Row/Layout/Info/SubtitleLabel
@onready var mods_label: Label = $Row/Layout/Info/ModsLabel
@onready var equip_button: Button = $Row/Layout/Actions/EquipButton
@onready var sell_button: Button = $Row/Layout/Actions/SellButton
@onready var sell_amount_label: Label = $Row/Layout/Actions/SellButton/Content/AmountLabel

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

	var classes := i.usable_by()
	_hero_class = classes[0] if not classes.is_empty() else &""
	equip_button.visible = _hero_class != &""
	if equip_button.visible:
		equip_button.pressed.connect(_on_equip_pressed)
	_refresh_equip_state()

	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND   # compare is always tappable
	gui_input.connect(_on_gui_input)

func _refresh_equip_state() -> void:
	if _hero_class == &"":
		return
	equip_button.text = "Unequip" if item.equipped_by == _hero_class else "Equip"

func _on_equip_pressed() -> void:
	if item.equipped_by == _hero_class:
		GameState.unequip_item(item)
	else:
		GameState.equip_item(item, _hero_class)
	equip_changed.emit()

## The row body (everything outside EquipButton/SellButton) opens the compare
## flyout - both buttons consume their own clicks before they reach here.
func _on_gui_input(event: InputEvent) -> void:
	# Excludes mouse-wheel scroll, which Godot also delivers as an
	# InputEventMouseButton press (on the wheel-up/down "buttons") - without
	# the button_index check, scrolling the sell list fired a compare_requested
	# on every notch.
	var tapped := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if not tapped:
		return
	compare_requested.emit(item)

func _on_sell() -> void:
	sell_button.disabled = true
	equip_button.disabled = true
	GameState.add_gold(item.sell_price())
	GameState.remove_item(item)
	GameState.run_stats["items_sold"] = int(GameState.run_stats["items_sold"]) + 1
	sold.emit(item, self)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "custom_minimum_size:y", 0.0, 0.25)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(queue_free)
