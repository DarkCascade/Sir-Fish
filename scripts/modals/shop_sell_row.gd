extends PanelContainer
## One inventory item with equip/sell actions underneath it (Sell tab).
##
## [meshy-experiment] Same card frame as the Buy tab's shop_buy_card.gd - see
## its header. Equip stays a small, always-visible button (a real gameplay
## action players reach for often, not just information), Compare moves
## behind the same swipe-to-reveal gesture Face already provides
## (swipeable_face.gd, shared with the Buy card), and Sell becomes the one
## full-width primary bar.

signal sold(item: Item, row: Control)
signal compare_requested(item: Item)
## Bubbled to shop_modal after an equip/unequip - equipping this item may have
## just unequipped a DIFFERENT row's item for the same hero, so the whole
## Sell tab is rebuilt rather than each row trying to track its neighbours.
signal equip_changed()

const ItemCardStyle := preload("res://scripts/ui/item_card_style.gd")

var item: Item = null
var _hero_class: StringName = &""

@onready var face = $Stage/Face   # SwipeableFace (untyped: custom API)
@onready var glyph = $Stage/Face/FaceLayout/TopRow/Glyph   # ItemGlyph (untyped: custom API)
@onready var name_label: Label = $Stage/Face/FaceLayout/TopRow/Info/NameLabel
@onready var subtitle_label: Label = $Stage/Face/FaceLayout/TopRow/Info/SubtitleLabel
@onready var mods_label: Label = $Stage/Face/FaceLayout/TopRow/Info/ModsLabel
@onready var equip_button: Button = $Stage/Face/FaceLayout/TopRow/Info/SecondaryRow/EquipButton
@onready var compare_hint: Button = $Stage/Face/FaceLayout/TopRow/Info/SecondaryRow/CompareHint
@onready var sell_bar: Button = $Stage/Face/FaceLayout/SellBar
@onready var sell_label: Label = $Stage/Face/FaceLayout/SellBar/Content/SellLabel
@onready var divider: ColorRect = $Stage/Face/FaceLayout/SellBar/Content/Divider
@onready var coin_glyph: Control = $Stage/Face/FaceLayout/SellBar/Content/CoinGlyph
@onready var amount_label: Label = $Stage/Face/FaceLayout/SellBar/Content/AmountLabel
@onready var locked_label: Label = $Stage/Face/FaceLayout/SellBar/Content/LockedLabel

## Shared across every row instance for the life of the process, so the teach
## swipe (see play_entrance()) fires once per session, not once per shop
## visit - and independently of the Buy tab's own equivalent flag.
static var _taught_this_run: bool = false

func _ready() -> void:
	face.action_triggered.connect(func() -> void: compare_requested.emit(item))

func setup(i: Item) -> void:
	item = i
	ItemCardStyle.apply(face, glyph, i, name_label, subtitle_label)

	name_label.text = i.display_name
	subtitle_label.text = i.subtitle()
	mods_label.text = "%d modifier%s" % [i.modifiers.size(),
		"" if i.modifiers.size() == 1 else "s"]

	amount_label.text = str(i.sell_price())
	sell_bar.pressed.connect(_on_sell)
	sell_bar.button_down.connect(_on_sell_button_down)
	sell_bar.button_up.connect(_on_sell_button_up)
	compare_hint.pressed.connect(func() -> void: compare_requested.emit(item))

	var classes := i.usable_by()
	_hero_class = classes[0] if not classes.is_empty() else &""
	equip_button.visible = _hero_class != &""
	if equip_button.visible:
		equip_button.pressed.connect(_on_equip_pressed)
	_refresh_equip_state()
	_refresh_sell_state()

	await get_tree().process_frame
	sell_bar.pivot_offset = sell_bar.size * 0.5

# --- entrance -----------------------------------------------------------

## Called once per row right after shop_modal adds it to the tree - see
## shop_buy_card.gd's play_entrance() for the full reasoning, including why
## `size` is read after an explicit frame wait for index 0 and why scale is
## split per-axis. Staggered a touch faster than the Buy tab's (0.05 vs 0.08)
## since the Sell list can run to many more rows.
func play_entrance(index: int) -> void:
	modulate.a = 0.0
	scale = Vector2(0.85, 0.85)
	if index > 0:
		await get_tree().create_timer(index * 0.05).timeout
	else:
		await get_tree().process_frame
	pivot_offset = size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
	tw.tween_property(self, "scale:y", 1.0, 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale:x", 1.0, 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if index == 0 and not _taught_this_run:
		await get_tree().create_timer(0.9).timeout
		if is_inside_tree():
			_taught_this_run = true
			face.peek()

# --- equip ----------------------------------------------------------------

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

# --- sell -------------------------------------------------------------------

## An equipped item can't be sold out from under its hero - the bar disables
## and swaps its content for a plain status message rather than staying an
## enabled "Sell" that would just silently do nothing (or worse, unequip and
## sell in the same breath). Re-run from setup() only: equipping ANY item
## rebuilds the whole Sell tab (see equip_changed above), so a row's equip
## state can never change without also being fully re-set-up.
func _is_equipped() -> bool:
	return _hero_class != &"" and item.equipped_by == _hero_class

func _refresh_sell_state() -> void:
	var locked := _is_equipped()
	sell_bar.disabled = locked
	sell_label.visible = not locked
	divider.visible = not locked
	coin_glyph.visible = not locked
	amount_label.visible = not locked
	locked_label.visible = locked

func _on_sell_button_down() -> void:
	if sell_bar.disabled:
		return
	var t := create_tween()
	t.tween_property(sell_bar, "scale", Vector2(0.97, 0.93), 0.05)

func _on_sell_button_up() -> void:
	var t := create_tween()
	t.tween_property(sell_bar, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_sell() -> void:
	if _is_equipped():
		return   # the bar reads disabled, but guard anyway - see _refresh_sell_state()
	sell_bar.disabled = true
	equip_button.disabled = true
	compare_hint.disabled = true
	# Fading the whole row via `modulate` below reduces every layer's alpha
	# together, so Face - fully opaque only at alpha 1 - would otherwise stop
	# occluding the ActionLayer behind it partway through and let "Compare"
	# bleed through. Locking it closed hides that layer outright.
	face.lock_closed()
	GameState.add_gold(item.sell_price())
	GameState.remove_item(item)
	GameState.run_stats["items_sold"] = int(GameState.run_stats["items_sold"]) + 1
	sold.emit(item, self)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "custom_minimum_size:y", 0.0, 0.25)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(queue_free)
