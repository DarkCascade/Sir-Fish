extends Control
## Read-only comparison of a candidate item against whatever its class currently
## has equipped. Shared by the shop's Buy and Sell tabs - shop_modal owns the one
## instance and every card/row's CompareButton asks it to show over itself.
##
## A plain Control + scrim, not a PopupPanel/Window - with subwindows embedded
## (this project's setup), a Window-derived popup renders itself the instant
## it is added to the tree regardless of visible/popup() state and misbehaves
## on close. This mirrors ShopModal's own proven show()/hide() + scrim pattern.
##
## [ui-project-longshot] It reached full-dialog size when comparing stopped
## being a stray tap on a card and became a button press. Three things came with
## that: a close button (the scrim tap still works, but a dialog the player
## opened on purpose has to have a visible way out), the open/close animation
## ShopModal uses, and the change list below - which is the part that actually
## answers the question the player pressed Compare to ask. Two columns of stats
## still leave "so is it better?" as homework; the change list does the
## subtraction.

@onready var scrim: ColorRect = $Scrim
@onready var panel: PanelContainer = $Panel
## The crystal-corner overlay. A SIBLING of Panel, not a child: the panel's
## stylebox carries 72px content margins, so parenting the frame to it would
## inset every corner by that much instead of pinning it to the panel's edge.
## Sibling means it has to be told the panel's rect - see _sync_frame().
@onready var frame: Control = $Frame
@onready var for_label: Label = $Panel/Layout/Header/ForLabel
@onready var close_button: Button = $Panel/Layout/Header/CloseButton

@onready var equipped_rule: ColorRect = $Panel/Layout/Columns/Equipped/Body/Rule
@onready var equipped_name: Label = $Panel/Layout/Columns/Equipped/Body/NameLabel
@onready var equipped_subtitle: Label = $Panel/Layout/Columns/Equipped/Body/SubtitleLabel
@onready var equipped_mods: HFlowContainer = $Panel/Layout/Columns/Equipped/Body/Mods
@onready var equipped_none: Label = $Panel/Layout/Columns/Equipped/Body/NoneLabel

@onready var candidate_rule: ColorRect = $Panel/Layout/Columns/Candidate/Body/Rule
@onready var candidate_name: Label = $Panel/Layout/Columns/Candidate/Body/NameLabel
@onready var candidate_subtitle: Label = $Panel/Layout/Columns/Candidate/Body/SubtitleLabel
@onready var candidate_mods: HFlowContainer = $Panel/Layout/Columns/Candidate/Body/Mods

@onready var change_list: VBoxContainer = $Panel/Layout/ChangeList

## [reliquary] Each modifier is now a chip tile rather than a text line.
const StatChipScene := preload("res://scenes/modals/stat_chip.tscn")

const MOD_FONT_SIZE := 30
## U+2212, not a hyphen: it matches the digit width of "+" so a column of gains
## and losses stays aligned.
const MINUS := "−"

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

## Shows `item` compared against whatever its (single, in practice) usable_by()
## class currently has equipped.
func show_for(item: Item) -> void:
	var classes := item.usable_by()
	var hero_class: StringName = classes[0] if not classes.is_empty() else &""
	for_label.visible = hero_class != &""
	for_label.text = "For %s" % String(hero_class).capitalize()

	# [town] spec 6.3: look up the equipped item BY SLOT, so a helm is compared
	# against the equipped helm and not against whatever the hero holds first.
	var equipped: Item = GameState.equipped_item(hero_class, item.slot()) if hero_class != &"" else null
	equipped_none.visible = equipped == null
	# The whole left column empties out when there is nothing equipped, down to
	# its rarity stripe - a stripe with no item over it reads as a colour the
	# comparison is making a claim about.
	equipped_rule.visible = equipped != null
	equipped_name.visible = equipped != null
	equipped_subtitle.visible = equipped != null
	equipped_mods.visible = equipped != null
	if equipped != null:
		equipped_rule.color = equipped.rarity_color()
		equipped_name.text = equipped.display_name
		equipped_name.add_theme_color_override("font_color", equipped.rarity_color())
		equipped_subtitle.text = equipped.subtitle()
		equipped_subtitle.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
		_fill_mods(equipped_mods, equipped)

	candidate_rule.color = item.rarity_color()
	candidate_name.text = item.display_name
	candidate_name.add_theme_color_override("font_color", item.rarity_color())
	candidate_subtitle.text = item.subtitle()
	candidate_subtitle.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	_fill_mods(candidate_mods, item)

	_fill_changes(equipped, item)

	show()
	# The columns have just changed height, so the panel is about to be re-laid
	# out; sync after that pass rather than against the previous item's rect.
	_sync_frame.call_deferred()
	_animate_in()

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

## Escape closes the compare window before it closes the shop underneath it -
## this node is added as ShopModal's last child, so unhandled input reaches it
## first, and marking the event handled stops ShopModal from also acting on it.
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

func _fill_mods(container: HFlowContainer, item: Item) -> void:
	for child: Node in container.get_children():
		child.queue_free()
	if item.modifiers.is_empty():
		container.add_child(_line("No modifiers", Tuning.C_TEXT_DIM))
		return
	for mod: Dictionary in item.modifiers:
		# [town] spec 10.3: an Enhanced modifier (last forge rung, doubled roll)
		# tints the whole chip in the ENHANCED rarity colour so it reads as its
		# own thing rather than as a lucky roll of the normal range; every other
		# modifier's chip takes the item's own rarity colour.
		var tint: Color = Tuning.RARITY_COLORS[Item.Rarity.ENHANCED] \
			if mod.get("enhanced", false) else item.rarity_color()
		var chip := StatChipScene.instantiate()
		container.add_child(chip)
		chip.setup(mod, tint)

# --- the change list --------------------------------------------------------

## One line per modifier whose value actually MOVES, as a single net figure -
## "−5 Damage", not "+9 Damage → +4 Damage". The player pressed Compare to
## ask "is this better", and a before/after pair leaves them to do the
## subtraction; this does it for them.
##
## Walked in Itemizer.MODIFIERS order rather than either item's own order, so
## the same two items always produce the same list and a modifier cannot jump
## rows depending on which side happens to carry it. `caption` and `pct` are
## read off the DEFINITION rather than the rolled dict, because a modifier
## loaded from an older save may predate either key.
func _fill_changes(equipped: Item, candidate: Item) -> void:
	for child: Node in change_list.get_children():
		child.queue_free()

	var before := _mods_by_id(equipped)
	var after := _mods_by_id(candidate)
	var moved := false
	for def: Dictionary in Itemizer.MODIFIERS:
		var id: StringName = def["id"]
		var delta: int = (int(after[id]["roll"]) if after.has(id) else 0) 			- (int(before[id]["roll"]) if before.has(id) else 0)
		if delta == 0:
			continue          # unchanged modifiers are not news
		moved = true
		var text := "%s%d%s %s" % [
			"+" if delta > 0 else MINUS,
			absi(delta),
			"%" if bool(def["pct"]) else "",
			def["caption"],
		]
		change_list.add_child(_line(text, Tuning.C_HEAL if delta > 0 else Tuning.C_DANGER))

	if not moved:
		# Either two plain Commons, or two items that happen to roll identically.
		# Saying so beats an empty panel that looks broken.
		change_list.add_child(_line("No change to any stat.", Tuning.C_TEXT_DIM))

## Modifier dictionaries keyed by id, for a null-safe item. Rolls are compared
## rather than the formatted labels because the label is a display string with
## the number already baked into it (see Itemizer.MODIFIERS) - the magnitude is
## only recoverable from "roll".
func _mods_by_id(item: Item) -> Dictionary:
	var out: Dictionary = {}
	if item == null:
		return out
	for mod: Dictionary in item.modifiers:
		out[mod["id"]] = mod
	return out

func _line(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", MOD_FONT_SIZE)
	l.add_theme_color_override("font_color", color)
	return l
