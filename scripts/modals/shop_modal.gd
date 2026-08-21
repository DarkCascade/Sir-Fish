extends Control
## The shop (spec 15). The encounter resolves only when the red X is pressed.

signal closed()

const BUY_CARD := preload("res://scenes/modals/shop_buy_card.tscn")
const SELL_ROW := preload("res://scenes/modals/shop_sell_row.tscn")
const NUMBER_SCENE := preload("res://scenes/overlay/damage_number.tscn")
const BONUS_STRIP_SCENE := preload("res://scenes/console/bonus_strip.tscn")

var _encounter: EncounterDef = null
var _cards: Array = []

@onready var scrim: ColorRect = $Scrim
@onready var panel: PanelContainer = $Panel
@onready var gold_label: Label = $Panel/Layout/Header/GoldBox/GoldLabel
@onready var close_button: Button = $Panel/Layout/Header/CloseButton
@onready var buy_list: VBoxContainer = $Panel/Layout/Tabs/Buy/BuyList
@onready var sell_list: VBoxContainer = $Panel/Layout/Tabs/Sell/Scroll/SellList
@onready var sell_empty: Label = $Panel/Layout/Tabs/Sell/EmptyLabel
@onready var tabs: TabContainer = $Panel/Layout/Tabs

func _ready() -> void:
	close_button.pressed.connect(close)
	_add_bonus_strip()
	EventBus.gold_changed.connect(_on_gold_changed)
	hide()

func open(encounter: EncounterDef) -> void:
	_encounter = encounter
	# Generated once per shop encounter and cached; reopening a tab never
	# rerolls (spec 21-D11).
	if encounter.cached_shop_items.is_empty():
		# A guaranteed rarity spread rather than an all-random roll, so at least one
		# card is affordable and one is a teaser (spec 13.6 / Q14).
		encounter.cached_shop_items = Itemizer.generate_shop_stock()
		Debug.apply_shop_override(encounter.cached_shop_items)
	_build_buy()
	_build_sell()
	_update_gold()
	tabs.current_tab = 0
	show()
	# [v3.5 D1] An open shop pauses the game. ModalLayer is PROCESS_MODE_ALWAYS,
	# so this modal (and every child - scrim, panel, price pulse, X button)
	# keeps processing while everything under Console/BattleView freezes.
	get_tree().paused = true

	scrim.modulate.a = 0.0
	var s := create_tween()
	s.tween_property(scrim, "modulate:a", 1.0, 0.2)

	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.85, 0.85)
	panel.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)

func close() -> void:
	# [v3.5 D1] Unpause before anything else, on every exit path, so a modal
	# torn down unexpectedly can never strand the tree paused.
	get_tree().paused = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2(0.9, 0.9), 0.2)
	tw.tween_property(panel, "modulate:a", 0.0, 0.2)
	tw.tween_property(scrim, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(func() -> void:
		hide()
		closed.emit())

## Optional desktop nicety; the red X remains the only required path (spec 15.4).
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

## Spec 15.1. The strip under the gold readout is what makes selling a real
## decision instead of free money: the player can see exactly what leaves the
## party with the item.
func _add_bonus_strip() -> void:
	var layout := $Panel/Layout as VBoxContainer
	var strip = BONUS_STRIP_SCENE.instantiate()
	strip.name = "BonusStrip"
	strip.custom_minimum_size = Vector2(880, 34)
	layout.add_child(strip)
	# Directly under the header, above the tabs.
	layout.move_child(strip, 1)

# --- buy --------------------------------------------------------------------

func _build_buy() -> void:
	for child: Node in buy_list.get_children():
		child.queue_free()
	_cards.clear()
	for item: Item in _encounter.cached_shop_items:
		var card = BUY_CARD.instantiate()
		buy_list.add_child(card)
		card.setup(item)
		card.purchased.connect(_on_purchased)
		_cards.append(card)
	await get_tree().process_frame
	_refresh_cards()

func _refresh_cards() -> void:
	for card: Variant in _cards:
		if is_instance_valid(card):
			card.refresh_affordability()

func _on_purchased(item: Item, _card: Control) -> void:
	GameState.run_stats["items_found"] = int(GameState.run_stats["items_found"]) + 1
	_build_sell()
	_float_gold(-item.buy_price())

# --- sell -------------------------------------------------------------------

func _build_sell() -> void:
	for child: Node in sell_list.get_children():
		child.queue_free()
	var items := GameState.sellable_items()
	sell_empty.visible = items.is_empty()
	for item: Item in items:
		var row = SELL_ROW.instantiate()
		sell_list.add_child(row)
		row.setup(item)
		row.sold.connect(_on_sold)

func _on_sold(item: Item, _row: Control) -> void:
	_float_gold(item.sell_price())
	# Selling changes the party bonuses AND every card's affordability.
	_refresh_cards()

# --- gold -------------------------------------------------------------------

func _on_gold_changed(_total: int, _delta: int) -> void:
	if not visible:
		return
	_update_gold()
	_refresh_cards()

func _update_gold() -> void:
	gold_label.text = str(GameState.gold)

func _float_gold(delta: int) -> void:
	var label = NUMBER_SCENE.instantiate()
	panel.add_child(label)
	label.position = gold_label.global_position - panel.global_position + Vector2(0, -10)
	var color := Tuning.C_GOLD if delta > 0 else Tuning.C_DANGER
	label.show_number("%s%d" % ["+" if delta > 0 else "", delta], color, 38, 70.0, 0.9)
