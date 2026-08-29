extends PanelContainer
## One item for sale (Buy tab). ~880 wide, height grows with modifier count.
##
## [meshy-shop-pass] Full mobile-first rebuild, scoped to the Buy tab only.
## The card is two layers under Stage (see shop_buy_card.tscn's header):
## ActionLayer, a "Compare" lane pinned behind the right edge, and Face, the
## visible card (icon + info + a full-width BUY bar) - Face's own script
## (swipeable_face.gd, shared with the Sell tab's row) handles sliding it on
## drag and emits action_triggered() when Compare is tapped. Buying stays a
## single deliberate tap on BUY - never a drag - an accidental spend is the
## worst failure mode a shop can have. Compare is also always one plain tap
## away via CompareHint regardless of the swipe: discoverability first, the
## shortcut second.

signal purchased(item: Item, card: Control)
signal compare_requested(item: Item)

const ItemCardStyle := preload("res://scripts/ui/item_card_style.gd")

var item: Item = null
var sold: bool = false

@onready var face = $Stage/Face   # SwipeableFace (untyped: custom API)
@onready var glyph = $Stage/Face/FaceLayout/TopRow/Glyph   # ItemGlyph (untyped: custom API)
@onready var name_label: Label = $Stage/Face/FaceLayout/TopRow/Info/NameLabel
@onready var subtitle_label: Label = $Stage/Face/FaceLayout/TopRow/Info/SubtitleLabel
@onready var modifiers_box: VBoxContainer = $Stage/Face/FaceLayout/TopRow/Info/Modifiers
@onready var compare_hint: Button = $Stage/Face/FaceLayout/TopRow/Info/CompareHint
@onready var buy_bar: Button = $Stage/Face/FaceLayout/BuyBar
@onready var buy_label: Label = $Stage/Face/FaceLayout/BuyBar/Content/BuyLabel
@onready var divider: ColorRect = $Stage/Face/FaceLayout/BuyBar/Content/Divider
@onready var coin_glyph: Control = $Stage/Face/FaceLayout/BuyBar/Content/CoinGlyph
@onready var price_label: Label = $Stage/Face/FaceLayout/BuyBar/Content/PriceLabel
@onready var sold_label: Label = $Stage/Face/FaceLayout/BuyBar/Content/SoldLabel
@onready var burst: GPUParticles2D = $Burst
@onready var rarity_flash: ColorRect = $Stage/Face/RarityFlash

var _pulse: Tween = null

## Shared across every card instance for the life of the process, so the
## teach swipe (see play_entrance()) fires once per session, not once per
## shop visit.
static var _taught_this_run: bool = false

func _ready() -> void:
	face.action_triggered.connect(func() -> void: compare_requested.emit(item))

func setup(i: Item) -> void:
	item = i
	ItemCardStyle.apply(face, glyph, i)

	name_label.text = i.display_name
	subtitle_label.text = i.subtitle()
	subtitle_label.add_theme_color_override("font_color", i.rarity_color())
	for child: Node in modifiers_box.get_children():
		child.queue_free()
	for mod: Dictionary in i.modifiers:
		var line := Label.new()
		line.text = String(mod["label"])
		line.add_theme_font_size_override("font_size", 26)
		line.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
		modifiers_box.add_child(line)

	price_label.text = str(i.buy_price())
	buy_bar.pressed.connect(_on_buy_pressed)
	buy_bar.button_down.connect(_on_buy_button_down)
	buy_bar.button_up.connect(_on_buy_button_up)
	compare_hint.pressed.connect(func() -> void: compare_requested.emit(item))

	await get_tree().process_frame
	buy_bar.pivot_offset = buy_bar.size * 0.5
	price_label.pivot_offset = price_label.size * 0.5

# --- entrance -----------------------------------------------------------

## Called once per card right after shop_modal adds it to the tree. `index`
## staggers the pop-in so the shop feels alive rather than dumping all three
## cards on screen at once; the FIRST card only also plays a one-time swipe
## peek once it has settled, teaching the gesture without a word of text.
##
## [width-overflow fix] `size` is read only after the card's own layout pass
## has actually run - for index > 0 the stagger's own timer wait is plenty of
## time for that; index 0 has no such wait, so without an explicit frame here
## `size`/pivot_offset would be read as the pre-layout, pre-Stage-fill value,
## silently wrong once the parent VBoxContainer stretches the card wider than
## its authored custom_minimum_size (see shop_buy_stage.gd). Scale is split
## per-axis for the same reason: TRANS_BACK's overshoot is harmless on the
## Y axis, but this card is already near the modal's full width, so letting
## X overshoot past 1.0 pushed it past the modal's edge during the bounce.
func play_entrance(index: int) -> void:
	modulate.a = 0.0
	scale = Vector2(0.85, 0.85)
	if index > 0:
		await get_tree().create_timer(index * 0.08).timeout
	else:
		await get_tree().process_frame
	pivot_offset = size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.22)
	tw.tween_property(self, "scale:y", 1.0, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale:x", 1.0, 0.24) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if index == 0 and not _taught_this_run:
		await get_tree().create_timer(0.9).timeout
		if is_inside_tree() and not sold:
			_taught_this_run = true
			face.peek()

# --- buy --------------------------------------------------------------------

## Re-run whenever gold changes: on purchase, on sale, on slot gold payouts.
func refresh_affordability() -> void:
	if sold:
		return
	var affordable := GameState.gold >= item.buy_price()
	buy_bar.disabled = not affordable
	buy_bar.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if affordable \
		else Control.CURSOR_ARROW
	if affordable and _pulse == null:
		_pulse = create_tween().set_loops()
		_pulse.tween_property(price_label, "scale", Vector2(1.05, 1.05), 0.8) \
			.set_trans(Tween.TRANS_SINE)
		_pulse.tween_property(price_label, "scale", Vector2.ONE, 0.8) \
			.set_trans(Tween.TRANS_SINE)
	elif not affordable and _pulse != null:
		_pulse.kill()
		_pulse = null
		price_label.scale = Vector2.ONE

func _on_buy_button_down() -> void:
	if buy_bar.disabled or sold:
		return
	var t := create_tween()
	t.tween_property(buy_bar, "scale", Vector2(0.97, 0.93), 0.05)

func _on_buy_button_up() -> void:
	var t := create_tween()
	t.tween_property(buy_bar, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_buy_pressed() -> void:
	if sold or GameState.gold < item.buy_price():
		return
	_buy()

func _buy() -> void:
	if not GameState.spend_gold(item.buy_price()):
		return
	sold = true
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	GameState.add_item(item)

	buy_label.visible = false
	divider.visible = false
	coin_glyph.visible = false
	price_label.visible = false
	sold_label.visible = true
	sold_label.pivot_offset = sold_label.size * 0.5
	sold_label.rotation = deg_to_rad(-9.0)
	sold_label.scale = Vector2(1.8, 1.8)
	var stamp := create_tween()
	stamp.tween_property(sold_label, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	buy_bar.disabled = true
	face.modulate = Color(0.55, 0.55, 0.6, 1.0)

	_spawn_burst()
	if item.rarity >= Item.Rarity.MAGIC:
		_flash_rarity()

	purchased.emit(item, self)

func _spawn_burst() -> void:
	burst.position = buy_bar.get_global_rect().position + buy_bar.size * 0.5 - global_position
	burst.amount = 30 if item.rarity >= Item.Rarity.MAGIC else 20
	burst.restart()
	burst.emitting = true

func _flash_rarity() -> void:
	var c := item.rarity_color()
	rarity_flash.color = Color(c.r, c.g, c.b, 0.0)
	var t := create_tween()
	t.tween_property(rarity_flash, "color:a", 0.4, 0.12)
	t.tween_property(rarity_flash, "color:a", 0.0, 0.5)
