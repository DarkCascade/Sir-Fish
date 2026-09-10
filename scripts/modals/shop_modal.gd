extends Control
## The shop (spec 15). The encounter resolves only when the red X is pressed.
##
## [move-elements-to-editor] The bonus strip and the compare flyout are authored
## children in shop_modal.tscn now, in the positions their code comments used to
## assert: the strip directly under the header (spec 15.1 - it is what makes
## selling a real decision instead of free money, because the player can see
## exactly what leaves the party with the item), and the flyout last, so Escape
## reaches it before this modal. The buy cards and sell rows stay code-built -
## one per item in stock and one per inventory item, so there is no fixed set of
## them to author.
## Bonus strip removed after the other bonus strip was moved to the upper-right
## corner.

signal closed()

const ITEM_CARD := preload("res://scenes/modals/item_card.tscn")
const CardActions := preload("res://scripts/ui/item_card_actions.gd")
const NUMBER_SCENE := preload("res://scenes/overlay/damage_number.tscn")

var _encounter: EncounterDef = null
var _cards: Array = []

@onready var _compare_flyout = $CompareFlyout   # CompareFlyout (untyped: custom API)

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
	EventBus.gold_changed.connect(_on_gold_changed)
	hide()

func open(encounter: EncounterDef) -> void:
	_encounter = encounter
	# Generated once per shop encounter and cached; reopening a tab never
	# rerolls (spec 21-D11).
	if encounter.cached_shop_items.is_empty():
		# A guaranteed rarity spread rather than an all-random roll, so at least one
		# card is affordable and one is a teaser (spec 13.6 / Q14).
		encounter.cached_shop_items = Itemizer.generate_shop_stock(encounter.level)
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
	# ...and a paused world has no reason to keep being redrawn behind the
	# scrim. See MainLayout.set_world_rendering().
	_set_world_rendering(false)
	EventBus.shop_visibility_changed.emit(true)

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
	_set_world_rendering(true)
	EventBus.shop_visibility_changed.emit(false)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2(0.9, 0.9), 0.2)
	tw.tween_property(panel, "modulate:a", 0.0, 0.2)
	tw.tween_property(scrim, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(func() -> void:
		hide()
		closed.emit())

## `owner` rather than a node path: this modal is instanced in main.tscn, so its
## owner IS MainLayout, and nothing here has to know where in that scene it
## sits. Guarded because the shop is also opened standalone by the tests, where
## there is no MainLayout above it.
func _set_world_rendering(enabled: bool) -> void:
	if owner != null and owner.has_method("set_world_rendering"):
		owner.call("set_world_rendering", enabled)

## Optional desktop nicety; the red X remains the only required path (spec 15.4).
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# --- buy --------------------------------------------------------------------

func _build_buy() -> void:
	for child: Node in buy_list.get_children():
		child.queue_free()
	_cards.clear()
	var index := 0
	for item: Item in _encounter.cached_shop_items:
		var card := ITEM_CARD.instantiate()
		buy_list.add_child(card)
		card.setup(item)
		var acts: Array[StringName] = [&"compare", &"buy"]
		card.set_actions(acts)
		card.set_action_text(&"buy", CardActions.buy_label(item))
		card.action_pressed.connect(_on_buy_action.bind(card, item))
		# Staggered pop-in. The one-time swipe teach went with the swipe layer:
		# the card puts Compare on a button now, so there is no hidden gesture
		# left to teach.
		card.play_entrance(index)
		_cards.append(card)
		index += 1
	await get_tree().process_frame
	_refresh_cards()

func _on_compare_requested(item: Item) -> void:
	_compare_flyout.show_for(item)

func _refresh_cards() -> void:
	for card: Variant in _cards:
		if is_instance_valid(card):
			CardActions.refresh_buy_state(card, card.item)

func _on_buy_action(id: StringName, card: Control, item: Item) -> void:
	if id == &"compare":
		_on_compare_requested(item)
	elif id == &"buy" and CardActions.do_buy(card, item):
		# The bought item lands in the inventory, so the Sell tab is stale, and
		# the spend moves every other card across the affordability line.
		_build_sell()
		_float_gold(-item.buy_price())
		_refresh_cards()

# --- sell -------------------------------------------------------------------

## [equip] Lists the whole inventory now, not just GameState.sellable_items() -
## equipping and comparing both need equipped items to show up here too, and
## every item is sellable (selling an equipped item just drops it out of
## inventory, which is what unequips it; see GameState.party_bonuses()).
func _build_sell() -> void:
	for child: Node in sell_list.get_children():
		child.queue_free()
	var items := GameState.inventory
	sell_empty.visible = items.is_empty()
	var index := 0
	for item: Item in items:
		var card := ITEM_CARD.instantiate()
		sell_list.add_child(card)
		card.setup(item)
		var acts: Array[StringName] = [&"compare"]
		var eq := CardActions.equip_action(item)
		if eq != &"":
			acts.append(eq)
		acts.append(&"sell")
		card.set_actions(acts)
		CardActions.refresh_sell_state(card, item, CardActions.Mode.SELL)
		card.action_pressed.connect(_on_sell_action.bind(card, item))
		card.play_entrance(index)
		index += 1

## An equip/unequip may have unequipped a DIFFERENT card's item for the same
## hero, so the whole tab is rebuilt rather than patching one card.
func _on_sell_action(id: StringName, card: Control, item: Item) -> void:
	match id:
		&"compare":
			_on_compare_requested(item)
		&"equip", &"unequip":
			CardActions.do_equip(item, id == &"equip")
			_build_sell()
		&"sell":
			if CardActions.do_sell(card, item, CardActions.Mode.SELL):
				_float_gold(item.sell_price())
				# Selling changes the party bonuses AND every card affordability.
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
	label.show_number("%s%d" % ["+" if delta > 0 else "", delta], color, 46, 70.0, 0.9)
