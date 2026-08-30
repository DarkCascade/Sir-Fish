extends Control
## [town] The inventory modal (spec 6). Lives in Hud/ModalLayer, opened by the
## HUD's backpack button, usable in town and - outside COMBAT - in the forest
## (spec 3.2's disable rule lives on the button, not here).
##
## Two sections, both rebuilt on ANY equip change: equipping one item can
## displace another in the same slot, so patching a single row is not enough
## (the reason shop_modal already documents for its Sell tab).
##   - Equipped: one row per Item.Slot in enum order, an item row or an
##     empty-slot placeholder naming the slot (spec 6.1).
##   - Carried: every unequipped inventory item.
##
## No sell action - selling stays in the shop, where a merchant is standing
## (spec 6.4). An always-available sell button in a modal reachable mid-quest is
## an always-available gold faucet.
##
## Its own CompareFlyout instance, a child of THIS modal (see the step-6
## questions doc): the flyout must be the last child of whatever opened it for
## the Escape ordering to work, and the shop's instance lives under a different
## modal in a different scene. The slot-aware lookup (spec 6.3) is in
## compare_flyout.gd itself, so both instances get it for free.

const INVENTORY_ROW := preload("res://scenes/modals/inventory_row.tscn")

const SLOT_NAMES := {
	Item.Slot.WEAPON: "Weapon",
	Item.Slot.ARMOR: "Armor",
	Item.Slot.TRINKET: "Trinket",
}

@onready var scrim: ColorRect = $Scrim
@onready var panel: PanelContainer = $Panel
@onready var gold_label: Label = $Panel/Layout/Header/Currency/GoldLabel
@onready var scrap_label: Label = $Panel/Layout/Header/Currency/ScrapLabel
@onready var close_button: Button = $Panel/Layout/Header/CloseButton
@onready var equipped_list: VBoxContainer = $Panel/Layout/Scroll/Body/Equipped
@onready var carried_list: VBoxContainer = $Panel/Layout/Scroll/Body/Carried
@onready var carried_empty: Label = $Panel/Layout/Scroll/Body/CarriedEmpty
@onready var compare_flyout = $CompareFlyout   # CompareFlyout (untyped: custom API)

func _ready() -> void:
	close_button.pressed.connect(close)
	EventBus.gold_changed.connect(_on_currency_changed)
	EventBus.scrap_changed.connect(_on_currency_changed)
	hide()

func open() -> void:
	if visible:
		return
	_rebuild()
	_update_currency()
	show()
	# Same as shop_modal: an open inventory pauses the world. ModalLayer is
	# PROCESS_MODE_ALWAYS, so this modal keeps animating. In town nothing is
	# running to pause; in the forest it freezes the fight (the button is
	# already disabled in COMBAT, so this only ever pauses travel/loot/shop).
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
	# Unpause first, on every exit path, so a modal torn down unexpectedly can
	# never strand the tree paused (shop_modal's own rule).
	get_tree().paused = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2(0.9, 0.9), 0.2)
	tw.tween_property(panel, "modulate:a", 0.0, 0.2)
	tw.tween_property(scrim, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(hide)

## Optional desktop / Android-back nicety; the red X stays the only required
## close path (demo spec 15.4), same contract as shop_modal.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# --- build ----------------------------------------------------------------

func _rebuild() -> void:
	var hero: StringName = GameState.active_party[0] if not GameState.active_party.is_empty() else &"warrior"

	for child: Node in equipped_list.get_children():
		child.queue_free()
	for s: Item.Slot in [Item.Slot.WEAPON, Item.Slot.ARMOR, Item.Slot.TRINKET]:
		var worn := GameState.equipped_item(hero, s)
		if worn != null:
			_add_row(equipped_list, worn)
		else:
			equipped_list.add_child(_empty_slot_row(s))

	for child: Node in carried_list.get_children():
		child.queue_free()
	var carried := GameState.inventory.filter(func(i: Item) -> bool: return i.equipped_by == &"")
	carried_empty.visible = carried.is_empty()
	for i: Item in carried:
		_add_row(carried_list, i)

func _add_row(into: VBoxContainer, i: Item) -> void:
	var row := INVENTORY_ROW.instantiate()
	into.add_child(row)
	row.setup(i)
	row.compare_requested.connect(func(it: Item) -> void: compare_flyout.show_for(it))
	row.equip_changed.connect(_rebuild)

func _empty_slot_row(s: Item.Slot) -> Label:
	var l := Label.new()
	l.text = "%s slot — empty" % SLOT_NAMES[s]
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	return l

# --- currency -----------------------------------------------------------

func _on_currency_changed(_total: int, _delta: int) -> void:
	if visible:
		_update_currency()

func _update_currency() -> void:
	gold_label.text = "%d G" % GameState.gold
	scrap_label.text = "%d S" % GameState.scrap
