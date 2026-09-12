extends VBoxContainer
## [item-row] The list entry. One strip renders an item everywhere a LIST of
## items is shown - the shop's Buy and Sell tabs, the inventory, the forge, the
## blacksmith's Scrap and Sell tabs - with the full card demoted to a detail
## view opened by tapping the strip.
##
## The card it replaces stood about 500px tall in a 1920px viewport, so three
## items shared a screen; the strip is about 230px including its action bar, so
## eight do. What buys that back is dropping the four fixed stat tiles: they
## were SUMS of the modifier rows printed directly beneath them, and an item
## only ever fills one or two of the four, so half the block was dimmed zeroes
## drawn at 52pt. The rolls survive as icon pips - their COUNT is the rarity -
## and the magnitudes are spelled out in the detail view.
##
## Public API is deliberately the universal card's, node for node and method for
## method, so a host swaps one preload constant and keeps its handlers:
## setup / set_actions / set_action_text / set_action_disabled / action_button,
## the `item` property, the juice (play_entrance, flash_rarity, spawn_burst,
## set_spent, play_departure) and the action_pressed signal.

signal action_pressed(id: StringName)

const ItemCardStyle := preload("res://scripts/ui/item_card_style.gd")
const ItemCompare := preload("res://scripts/ui/item_compare.gd")

## Every button authored under Actions. The node name is the id capitalized.
const ACTION_IDS: Array[StringName] = [&"compare", &"equip", &"unequip", &"buy", &"sell", &"forge"]

## Shrink-to-fit bounds for the name, against the Info column. The strip gives
## that column about 410px of an 816px-wide list, so the display font's longest
## generated name ("Grumbling Longsword") lands near the floor. A name that
## still overruns at the floor gets an ellipsis - the label is single-line with
## clip_text on and can never wrap, because a second line would change the
## strip's height and break the uniform list.
const NAME_SIZE_MAX := 38
const NAME_SIZE_MIN := 24

## The strip's floor. setup() raises it to whatever the content actually needs
## (Body is a plain Control and takes no minimum from its anchored children), so
## this only has to stop a hypothetically tiny item from collapsing the row.
const BODY_MIN_H := 150.0

var item: Item = null

@onready var _body: Control = $Body
@onready var _backing: PanelContainer = $Body/Backing
@onready var _content: MarginContainer = $Body/Content
@onready var _glyph = $Body/Content/Strip/Medallion/Glyph  # ItemGlyph (untyped: custom API)
@onready var _info: VBoxContainer = $Body/Content/Strip/Info
@onready var _name_label: Label = $Body/Content/Strip/Info/NameLabel
@onready var _meta_label: Label = $Body/Content/Strip/Info/MetaLabel
@onready var _pips: HBoxContainer = $Body/Content/Strip/Info/Pips
@onready var _value_label: Label = $Body/Content/Strip/Readout/Value
@onready var _unit_label: Label = $Body/Content/Strip/Readout/Unit
@onready var _badge_label: Label = $Body/Content/Strip/Readout/Badge
@onready var _actions: HBoxContainer = $Actions
@onready var _rarity_flash: ColorRect = $Body/RarityFlash
@onready var _burst: GPUParticles2D = $Burst

func _ready() -> void:
	for id: StringName in ACTION_IDS:
		var b := action_button(id)
		b.visible = false
		b.pressed.connect(func() -> void: action_pressed.emit(id))
	_actions.visible = false
	_body.gui_input.connect(_on_body_input)
	# The name is fitted against the Info column's width, so a re-fit is owed
	# whenever that column resizes - not whenever the LABEL does, which the font
	# size override changes and would feed back into itself.
	_info.resized.connect(_fit_name)

func setup(i: Item) -> void:
	item = i
	# The strip takes the card's rarity treatment wholesale - tinted border, dark
	# reliquary fill, coloured halo, ringed glyph - rather than inventing a
	# lighter one for lists. Two rarity looks would be two things to drift.
	ItemCardStyle.apply(_backing, _glyph, i, _name_label, _meta_label)
	_name_label.text = i.display_name
	_meta_label.text = ItemCompare.meta_line(i)
	_value_label.text = str(ItemCompare.headline_value(i))
	_unit_label.text = ItemCompare.headline_unit(i)
	_fill_pips(i)
	_fill_badge(i)
	# Body is a plain Control and every one of its children is anchored, so it
	# takes no minimum from them and has to be told. Hosts add_child() before
	# setup(), so the theme is resolved and this minimum is real.
	_body.custom_minimum_size.y = maxf(BODY_MIN_H, _content.get_combined_minimum_size().y)
	_fit_name()

## Which action buttons show, in the order given. Anything not listed is hidden.
func set_actions(ids: Array[StringName]) -> void:
	for id: StringName in ACTION_IDS:
		action_button(id).visible = ids.has(id)
	for idx: int in range(ids.size()):
		_actions.move_child(action_button(ids[idx]), idx)
	_actions.visible = not ids.is_empty()

func set_action_text(id: StringName, text: String) -> void:
	action_button(id).text = text

func set_action_disabled(id: StringName, disabled: bool) -> void:
	action_button(id).disabled = disabled

## Public because ItemCardActions needs somewhere to aim the purchase burst, and
## reaching for it by node path from outside would hard-code this scene's tree
## into a helper shared with the card.
func action_button(id: StringName) -> Button:
	return _actions.get_node(String(id).capitalize()) as Button

## A tap anywhere on the strip that a button did not take opens the detail view.
## It reports itself as the `compare` action rather than as a signal of its own,
## because "show me this item against what I am wearing" is exactly what the
## Compare button used to ask for - so every host's existing handler already
## knows what to do with it, and the button itself can retire from the lists.
func _on_body_input(event: InputEvent) -> void:
	var tapped := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if tapped:
		action_pressed.emit(&"compare")
		_body.accept_event()

## Pips authors three slots - RARITY_MOD_COUNT tops out at 3 - and this shows
## the first `modifiers.size()` of them rather than building nodes at runtime,
## so the strip stays inspector-authored (CLAUDE.md best practice 1).
##
## Icon only, no magnitude: at this size a number would be unreadable, and the
## COUNT is the information a scanning eye wants (three pips is a Rare). The
## numbers live one tap away in the detail view.
func _fill_pips(i: Item) -> void:
	var slots := _pips.get_children()
	for idx: int in range(slots.size()):
		var pip := slots[idx] as TextureRect
		pip.visible = idx < i.modifiers.size()
		if not pip.visible:
			continue
		var mod: Dictionary = i.modifiers[idx]
		pip.texture = SlotIcon.chip_texture(StringName(mod.get("id", &"")))
		# The enhanced colour is the one thing a pip has to carry beyond its
		# shape: it is how a forged roll reads as forged at a glance.
		pip.modulate = Tuning.RARITY_COLORS[Item.Rarity.ENHANCED] \
			if mod.get("enhanced", false) else Color.WHITE

func _fill_badge(i: Item) -> void:
	var badge := ItemCompare.badge(i)
	_badge_label.text = String(badge["text"])
	_badge_label.add_theme_color_override("font_color", badge["color"] as Color)

## Picks the largest font size at which the name fits the Info column on one
## line, measured against the font directly rather than the rendered label.
##
## `setup()` calls this before the strip has laid out, when `_info.size.x` is
## still 0, so it waits a frame for a real width and then re-checks until the
## width holds steady - different hosts settle the column in a different number
## of passes. `_fitting` collapses the `setup()` call and the `resized` emits it
## races into one fit. Lifted wholesale from the card, whose problem was
## identical.
var _fitting := false

func _fit_name() -> void:
	if _fitting or _name_label.text.is_empty():
		return
	_fitting = true
	var avail := _info.size.x
	for _i: int in range(8):
		await get_tree().process_frame
		if not is_inside_tree():
			_fitting = false
			return
		if is_equal_approx(avail, _info.size.x):
			break
		avail = _info.size.x
	_fitting = false
	if avail <= 1.0:
		return
	var font := _name_label.get_theme_font("font")
	var s := NAME_SIZE_MAX
	while s > NAME_SIZE_MIN and font.get_string_size(
			_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > avail - 2.0:
		s -= 2
	_name_label.add_theme_font_size_override("font_size", s)

# --- juice, the card's contract ---------------------------------------------

## Staggered pop-in. `index` is the entry's position in its list, so a rebuilt
## shop or inventory feels alive rather than dumping every row at once. The
## stagger is tighter than the card's 0.08 because there are three times as many
## rows on screen and the old spacing would take most of a second to finish.
func play_entrance(index: int) -> void:
	modulate.a = 0.0
	scale = Vector2(0.97, 0.97)
	if index > 0:
		await get_tree().create_timer(index * 0.035).timeout
	else:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	pivot_offset = size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	tw.tween_property(self, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## A rarity-coloured wash over the whole strip - the forge's "it changed" cue.
func flash_rarity() -> void:
	if item == null:
		return
	var c := item.rarity_color()
	_rarity_flash.color = Color(c.r, c.g, c.b, 0.0)
	var t := create_tween()
	t.tween_property(_rarity_flash, "color:a", 0.4, 0.12)
	t.tween_property(_rarity_flash, "color:a", 0.0, 0.5)

## Coin spray centred on `at`, which callers pass as the button that was pressed
## so the burst leaves the tap rather than the middle of the strip.
func spawn_burst(at: Control = null) -> void:
	var target: Control = at if at != null else _actions
	_burst.position = target.get_global_rect().position \
		+ target.size * 0.5 - global_position
	_burst.amount = 30 if item != null and item.rarity >= Item.Rarity.MAGIC else 20
	_burst.restart()
	_burst.emitting = true

## Greys the strip once its item is gone. Which BUTTONS a spent row should
## disable is left to the caller - a sold shop row disables Buy, a scrapped
## inventory row hides everything - so this only touches the face.
func set_spent(spent: bool) -> void:
	_body.modulate = Color(0.55, 0.55, 0.6, 1.0) if spent else Color.WHITE

## Collapses the row out of its list and frees it - the sold/scrapped exit. Body
## carries the height, so that is what shrinks; fading the root alone would
## leave a row-sized hole in the list until the next rebuild.
func play_departure() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_property(_body, "custom_minimum_size:y", 0.0, 0.25)
	tw.chain().tween_callback(queue_free)
