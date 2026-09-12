extends Control
## The item DETAIL view - one item, shown against whatever its class currently
## wears in the same slot. Every list in the game (shop Buy and Sell, the
## inventory, the forge, the blacksmith's Scrap and Sell tabs) opens this by
## tapping a strip; each host owns its own instance, added as its LAST child so
## unhandled input reaches this before the screen underneath it.
##
## A plain Control + scrim, not a PopupPanel/Window - with subwindows embedded
## (this project's setup), a Window-derived popup renders itself the instant
## it is added to the tree regardless of visible/popup() state and misbehaves
## on close. This mirrors ShopModal's own proven show()/hide() + scrim pattern.
##
## [ui-project-longshot] It reached full-dialog size when comparing stopped
## being a stray tap on a card and became a button press: a close button, the
## open/close animation ShopModal uses, and a change list that does the
## subtraction for the player rather than leaving two columns of stats as
## homework.
##
## [item-row] It is the detail half of the list now, so the two full item
## columns are gone. The candidate appeared in three places at once - its own
## well, the change list, and the card in the list behind the scrim - so the
## well pair was the copy to cut. What is left is the item once, in the header,
## and one row per stat that MOVES, with the verdict promoted to the title so
## the answer arrives before the arithmetic. The comparison itself lives in
## ItemCompare, shared with the list strip's badge, because a strip promising
## "+12" over a dialog that then says something else is worse than either alone.

const ItemCompare := preload("res://scripts/ui/item_compare.gd")
const CardActions := preload("res://scripts/ui/item_card_actions.gd")

## Named for the RivalLabel's "your weapon slot is empty" line. Lower case
## because it lands mid-sentence, unlike the inventory's own slot headings.
const SLOT_NAMES := {
	Item.Slot.WEAPON: "weapon",
	Item.Slot.ARMOR: "armor",
	Item.Slot.TRINKET: "trinket",
}

@onready var scrim: ColorRect = $Scrim
@onready var panel: PanelContainer = $Panel
## The crystal-corner overlay. A SIBLING of Panel, not a child: the panel's
## stylebox carries 72px content margins, so parenting the frame to it would
## inset every corner by that much instead of pinning it to the panel's edge.
## Sibling means it has to be told the panel's rect - see _sync_frame().
@onready var frame: Control = $Frame
@onready var verdict_label: Label = $Panel/Layout/Header/VerdictLabel
@onready var for_label: Label = $Panel/Layout/Header/ForLabel
@onready var close_button: Button = $Panel/Layout/Header/CloseButton

@onready var glyph = $Panel/Layout/Hero/Medallion/Glyph   # ItemGlyph (untyped: custom API)
## Full width, above the medallion row - the display font needs most of the
## panel to draw a generated name on one line. See the scene's own note.
@onready var name_label: Label = $Panel/Layout/NameLabel
@onready var meta_label: Label = $Panel/Layout/Hero/Identity/MetaLabel
@onready var rival_label: Label = $Panel/Layout/Hero/Identity/RivalLabel
@onready var headline_value: Label = $Panel/Layout/Hero/Headline/Value
@onready var headline_unit: Label = $Panel/Layout/Hero/Headline/Unit

@onready var change_header: Label = $Panel/Layout/ChangeHeader
@onready var change_list: VBoxContainer = $Panel/Layout/ChangeList
@onready var row_template: PanelContainer = $Panel/Layout/ChangeList/RowTemplate

func _ready() -> void:
	for_label.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	scrim.gui_input.connect(_on_scrim_input)
	close_button.pressed.connect(close)
	# item_rect_changed, not resized: the panel is re-CENTRED as it grows, and
	# resized fires only for the size half of that, which left the corners
	# correctly sized but parked at the old position.
	panel.item_rect_changed.connect(_sync_frame)
	hide()

## Pins the corner frame to the panel's ACTUAL rect. Both were authored at the
## same 940x900, but Panel is a PanelContainer and grows to whatever its content
## needs, while Frame is a plain Control that stays where it was authored - so
## the corners drifted off the panel edges as soon as the columns got tall.
##
## Re-centres the scale pivot on the same pass, which had the identical bug: a
## pivot baked at (470, 450) spins the open animation about a point that is no
## longer the panel's middle.
## `position`, NOT `global_position`: a Control's global position is taken from
## its transform, which folds in its own scale about its pivot - so while the
## open tween holds the panel at 0.9 it reports a point ~5% of the panel size
## off. Scale changes do not re-fire item_rect_changed, so that stale value
## would then stick for the life of the dialog. Both nodes are siblings, so the
## layout-space position compares directly and is scale-independent.
func _sync_frame() -> void:
	frame.size = panel.size
	frame.position = panel.position
	panel.pivot_offset = panel.size * 0.5
	frame.pivot_offset = panel.pivot_offset

## Shows `item` against whatever its (single, in practice) usable_by() class
## currently has equipped in the same slot.
func show_for(item: Item) -> void:
	var hero := CardActions.equip_hero(item)
	for_label.visible = hero != &""
	for_label.text = "For %s" % String(hero).capitalize()

	# [town] spec 6.3: the lookup is BY SLOT, so a helm is compared against the
	# equipped helm and not against whatever the hero holds first. Null when the
	# slot is empty, when nobody on the field can wield the item, or when `item`
	# IS the equipped one - see ItemCompare.rival.
	var worn := ItemCompare.rival(item)
	var verdict := ItemCompare.verdict(item)
	verdict_label.text = ItemCompare.verdict_text(verdict)
	verdict_label.add_theme_color_override("font_color", ItemCompare.verdict_color(verdict))

	# The glyph half of ItemCardStyle.apply(), inlined: that helper also tints a
	# card FACE, and this dialog's face is the reliquary panel, whose chrome is
	# deliberately not rarity-coloured.
	glyph.set("ring_color", item.rarity_color())
	glyph.set("weapon_type", item.weapon_type)
	glyph.set("kind", item.kind)

	name_label.text = item.display_name
	name_label.add_theme_color_override("font_color", item.rarity_color())
	meta_label.text = ItemCompare.meta_line(item)
	rival_label.text = _rival_line(item, worn, hero)

	headline_value.text = str(ItemCompare.headline_value(item))
	headline_unit.text = ItemCompare.headline_unit(item)

	_fill_changes(item, worn)

	show()
	# The rows have just changed height, so the panel is about to be re-laid
	# out; sync after that pass rather than against the previous item's rect.
	_sync_frame.call_deferred()
	_animate_in()

## What the comparison's other half is, in words. Each branch answers a
## different "compared with what?", and saying so beats a dialog that quietly
## shows absolute numbers and lets the player assume they are deltas.
func _rival_line(item: Item, worn: Item, hero: StringName) -> String:
	if item.equipped_by != &"":
		return "worn by %s" % String(item.equipped_by).capitalize()
	if worn != null:
		return "replacing %s (Lv %d)" % [worn.display_name, worn.level]
	if hero == &"":
		return "no one in your party can wield this"
	return "your %s slot is empty" % SLOT_NAMES[item.slot()]

func close() -> void:
	# The frame is a sibling, so it has to be flown with the panel by hand or the
	# corners hang in place while the panel shrinks away underneath them.
	var tw := create_tween().set_parallel(true)
	for n: Control in [panel, frame]:
		tw.tween_property(n, "scale", Vector2(0.92, 0.92), 0.15)
		tw.tween_property(n, "modulate:a", 0.0, 0.15)
	tw.tween_property(scrim, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(hide)

## Same beat as ShopModal.open(), a touch quicker - this sits on top of a modal
## that already did the slow version, and repeating it at full length makes the
## second layer feel like it is lagging behind the press.
func _animate_in() -> void:
	scrim.modulate.a = 0.0
	panel.scale = Vector2(0.9, 0.9)
	panel.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(scrim, "modulate:a", 1.0, 0.15)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)

## Escape closes the detail view before it closes the screen underneath it -
## this node is added as its host's last child, so unhandled input reaches it
## first, and marking the event handled stops the host from also acting on it.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

## Tapping outside the panel (anywhere the scrim is visible) dismisses it -
## the panel itself has its own mouse_filter (STOP, PanelContainer's default)
## so a tap on the panel never reaches the scrim underneath it.
func _on_scrim_input(event: InputEvent) -> void:
	# Excludes mouse-wheel scroll (also delivered as an InputEventMouseButton
	# press, on the wheel-up/down "buttons").
	var tapped := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if tapped:
		close()

# --- the change list --------------------------------------------------------

## One well per stat either item puts on the board, carrying the candidate's own
## magnitude AND the net change - "58   +12", not "+9 Damage → +4 Damage". The
## pair is the point: a delta alone cannot say how big the thing is, and an
## absolute alone cannot say whether it is an improvement.
##
## Ordering, which stats qualify and the arithmetic all belong to
## ItemCompare.rows(), shared with the list strip's badge.
##
## With nothing equipped to compare against, the change column is HIDDEN rather
## than filled with deltas equal to the values beside them - a row reading
## "58   +58" states the same number twice and implies a comparison that was
## never made.
func _fill_changes(item: Item, worn: Item) -> void:
	for child: Node in change_list.get_children():
		if child != row_template:
			child.queue_free()

	var rows := ItemCompare.rows(item, worn)
	change_header.text = "IF YOU EQUIP THIS" if worn != null else "WHAT THIS CONTRIBUTES"
	if rows.is_empty():
		change_list.add_child(_plain_line("This item does nothing at all."))
		return

	for row: Dictionary in rows:
		var well := row_template.duplicate() as PanelContainer
		well.visible = true
		change_list.add_child(well)
		(well.get_node("Box/Icon") as TextureRect).texture = \
			SlotIcon.chip_texture(StringName(row["id"]))
		(well.get_node("Box/Caption") as Label).text = String(row["caption"])
		(well.get_node("Box/Value") as Label).text = ItemCompare.value_text(row)
		var delta := well.get_node("Box/Delta") as Label
		delta.visible = worn != null
		delta.text = ItemCompare.delta_text(row)
		delta.add_theme_color_override("font_color", ItemCompare.delta_color(row))

func _plain_line(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	return l
