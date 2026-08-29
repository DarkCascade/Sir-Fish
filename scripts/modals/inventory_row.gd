extends PanelContainer
## [town] One inventory item with Compare + Equip/Unequip actions (spec 6.2).
##
## A NEW scene, not a trimmed shop_sell_row: that row hangs its whole layout off
## a full-width primary Sell bar, and this row has no sell action at all -
## selling stays in the shop where a merchant is standing (spec 6.4). What it
## DOES reuse verbatim is swipeable_face, item_glyph and the rarity-tinted card
## frame (via ItemCardStyle, spec 6.2).
##
## The action area is two equal-width buttons side by side. Compare is ALSO
## reachable by the same swipe-to-reveal gesture the shop cards use (Face's
## ActionLayer), so the row keeps the Stage/ActionLayer/Face structure
## swipeable_face.gd expects.

signal compare_requested(item: Item)
## Bubbled to the modal after an equip/unequip: equipping this item may have
## displaced a DIFFERENT row's item in the same slot, so the modal rebuilds
## both sections rather than each row tracking its neighbours - the reason
## shop_modal already documents for its Sell tab.
signal equip_changed()

const ItemCardStyle := preload("res://scripts/ui/item_card_style.gd")

var item: Item = null
## The active-party hero this row's Equip button acts for, or &"" when nobody on
## the field can wield the item (spec 6.2 - then the button is hidden, not shown
## as a control that silently fails).
var _hero_class: StringName = &""

@onready var face = $Stage/Face   # SwipeableFace (untyped: custom API)
@onready var glyph = $Stage/Face/FaceLayout/TopRow/Glyph   # ItemGlyph (untyped: custom API)
@onready var name_label: Label = $Stage/Face/FaceLayout/TopRow/Info/NameLabel
@onready var subtitle_label: Label = $Stage/Face/FaceLayout/TopRow/Info/SubtitleLabel
@onready var mods_label: Label = $Stage/Face/FaceLayout/TopRow/Info/ModsLabel
@onready var compare_button: Button = $Stage/Face/FaceLayout/Actions/CompareButton
@onready var equip_button: Button = $Stage/Face/FaceLayout/Actions/EquipButton

func _ready() -> void:
	face.action_triggered.connect(func() -> void: compare_requested.emit(item))

func setup(i: Item) -> void:
	item = i
	ItemCardStyle.apply(face, glyph, i)

	name_label.text = i.display_name
	subtitle_label.text = i.subtitle()
	subtitle_label.add_theme_color_override("font_color", i.rarity_color())
	mods_label.text = "%d modifier%s" % [i.modifiers.size(),
		"" if i.modifiers.size() == 1 else "s"]

	compare_button.pressed.connect(func() -> void: compare_requested.emit(item))

	_hero_class = _eligible_class(i)
	equip_button.visible = _hero_class != &""
	if equip_button.visible:
		equip_button.pressed.connect(_on_equip_pressed)
		_refresh_equip_label()

## The first member of active_party that can wield `i`. An "Anyone" item
## (empty usable_by() - spec 4.2's deferred universal path) goes to the field
## leader; an item restricted to classes none of whom are on the field returns
## &"", which hides the Equip button.
func _eligible_class(i: Item) -> StringName:
	var usable := i.usable_by()
	if usable.is_empty():
		return GameState.active_party[0] if not GameState.active_party.is_empty() else &""
	for c: StringName in usable:
		if c in GameState.active_party:
			return c
	return &""

func _refresh_equip_label() -> void:
	equip_button.text = "Unequip" if item.equipped_by == _hero_class else "Equip"

func _on_equip_pressed() -> void:
	if item.equipped_by == _hero_class:
		GameState.unequip_item(item)
	else:
		GameState.equip_item(item, _hero_class)
	equip_changed.emit()
