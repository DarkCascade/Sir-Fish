extends VBoxContainer
## The universal item card. ONE layout renders item info everywhere - the shop's
## Buy and Sell tabs, the inventory, the forge - instead of the four private
## card scenes that used to share only a border-tinting helper and had drifted
## apart in spacing, font size and which fields they showed at all.
##
## The framed card is fixed; only the row of action buttons BELOW it varies by
## caller (set_actions()). A shop card asks for [&"buy"], an inventory row for
## [&"compare", &"equip"] - nothing inside the frame changes between them.

signal action_pressed(id: StringName)

const ItemCardStyle := preload("res://scripts/ui/item_card_style.gd")

## The four headline tiles, in StatRow's child order (Attack, Magic, Health,
## Defense). Item carries no four-stat block - it carries `modifiers` - so each
## tile sums the rolls of the modifier ids named here.
##
## `dmg_pct` is deliberately in NO tile: it is a percentage and cannot be summed
## into the flat damage adds without lying about the unit. Nothing is hidden by
## leaving it out - the chip row above the tiles lists every modifier the item
## carries, `dmg_pct` included.
##
## Defense lists no ids because no armor modifier exists yet (Itemizer.MODIFIERS
## is five damage ids plus two slot ids). It reads 0 on every item until one is
## added, which is what the reference art itself shows.
const STAT_TILES: Array[Dictionary] = [
	{ "ids": [&"dmg_flat", &"elem_fire", &"elem_ice", &"elem_light"], "pct": false },
	{ "ids": [&"slot_bolt"], "pct": false },
	{ "ids": [&"slot_mend"], "pct": true },
	{ "ids": [], "pct": false },
]

## Every button authored under Actions. The node name is the id capitalized.
const ACTION_IDS: Array[StringName] = [&"compare", &"equip", &"unequip", &"buy", &"sell", &"forge"]

## Shrink-to-fit bounds for the name. The display font is wide: the longest name
## Itemizer can generate - "Grumbling Longsword" (longest ADJECTIVE + longest
## noun, 19 chars) - only fits the ~500px Info column on one line at about 30, so
## the floor is deliberately down at 28 and the longest names really do reach it.
## A name that STILL overruns at 28 gets an ellipsis (the label is single-line
## with clip_text on) rather than a second line.
const NAME_SIZE_MAX := 54
const NAME_SIZE_MIN := 28

var item: Item = null

@onready var _backing: PanelContainer = $Card/Backing
@onready var _glyph = $Card/Content/Layout/TopRow/MedallionCol/Medallion/Glyph  # ItemGlyph (untyped: custom API)
@onready var _name_label: Label = $Card/Content/Layout/TopRow/Info/NameLabel
@onready var _subtitle_label: Label = $Card/Content/Layout/TopRow/MedallionCol/LevelPlate/SubtitleLabel
@onready var _mod_row: HBoxContainer = $Card/Content/Layout/TopRow/Info/ModRow
@onready var _stat_row: HBoxContainer = $Card/Content/Layout/StatRow
@onready var _actions: HBoxContainer = $Actions
@onready var _info: VBoxContainer = $Card/Content/Layout/TopRow/Info
@onready var _rarity_flash: ColorRect = $Card/RarityFlash
@onready var _burst: GPUParticles2D = $Burst

func _ready() -> void:
	for id: StringName in ACTION_IDS:
		var b := _button(id)
		b.visible = false
		b.pressed.connect(func() -> void: action_pressed.emit(id))
	_actions.visible = false
	# The name is fitted against the Info column's width, so a re-fit is owed
	# whenever that column resizes - not whenever the LABEL does, which the font
	# size override changes and would feed back into itself.
	_info.resized.connect(_fit_name)

func setup(i: Item) -> void:
	item = i
	ItemCardStyle.apply(_backing, _glyph, i, _name_label, _subtitle_label)
	_name_label.text = i.display_name
	# [item power model] Weapons carry the number their swing is made of.
	_subtitle_label.text = "Lv %d  ·  %d dmg" % [i.level, i.power()] \
		if i.slot() == Item.Slot.WEAPON else "Lv %d" % i.level
	_fill_mods(i)
	_fill_stats(i)
	_fit_name()

## Which action buttons show, in the order given. Anything not listed is hidden.
func set_actions(ids: Array[StringName]) -> void:
	for id: StringName in ACTION_IDS:
		_button(id).visible = ids.has(id)
	for idx: int in range(ids.size()):
		_actions.move_child(_button(ids[idx]), idx)
	_actions.visible = not ids.is_empty()

func set_action_text(id: StringName, text: String) -> void:
	_button(id).text = text

func set_action_disabled(id: StringName, disabled: bool) -> void:
	_button(id).disabled = disabled

func _button(id: StringName) -> Button:
	return _actions.get_node(String(id).capitalize()) as Button

## ModRow authors four chips - RARITY_MOD_COUNT tops out at 4 - and this shows
## the first `modifiers.size()` of them rather than building nodes at runtime,
## so the chip plate stays inspector-authored (CLAUDE.md best practice 1).
func _fill_mods(i: Item) -> void:
	var chips := _mod_row.get_children()
	for idx: int in range(chips.size()):
		var chip := chips[idx] as PanelContainer
		chip.visible = idx < i.modifiers.size()
		if not chip.visible:
			continue
		var mod: Dictionary = i.modifiers[idx]
		var path := "res://assets/ui/reliquary/chip_%s.png" % String(mod.get("id", &""))
		var icon := chip.get_node("Icon") as TextureRect
		icon.texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
		chip.tooltip_text = String(mod.get("label", ""))
		var tint: Color = Tuning.RARITY_COLORS[Item.Rarity.ENHANCED] \
			if mod.get("enhanced", false) else i.rarity_color()
		var sb := (chip.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
		sb.border_color = tint
		chip.add_theme_stylebox_override("panel", sb)

func _fill_stats(i: Item) -> void:
	for idx: int in range(STAT_TILES.size()):
		var spec: Dictionary = STAT_TILES[idx]
		var ids: Array = spec["ids"]
		var total := 0
		for mod: Dictionary in i.modifiers:
			if ids.has(mod.get("id", &"")):
				total += int(mod.get("roll", 0))
		var value := _stat_row.get_child(idx).get_node("Box/Value") as Label
		value.text = ("%d%%" % total) if bool(spec["pct"]) and total > 0 else str(total)
		# A zero tile is dimmed rather than hidden: the four tiles are a fixed
		# readout, and holes opening in the row would cost more than the noise.
		value.modulate.a = 1.0 if total > 0 else 0.4

## Picks the largest font size (NAME_SIZE_MAX down to NAME_SIZE_MIN) at which the
## name fits the Info column on one line, measured against the font directly
## rather than the rendered label. The label is single-line with clip_text on, so
## a name that still overruns at the floor gets an ellipsis - it can never wrap.
##
## `setup()` calls this before the card has laid out, when `_info.size.x` is
## still 0, so it waits a frame for a real width and then re-checks until the
## width holds steady (different hosts - the shop's VBox, the inventory grid, the
## forge - settle the column in a different number of passes). `_fitting`
## collapses the `setup()` call and the `resized` emits it races into one fit.
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

# --- juice, ported from the old shop cards ----------------------------------

## Staggered pop-in. `index` is the card position in its list, so a rebuilt
## shop or inventory feels alive rather than dumping every card at once.
##
## `size` is read only after a layout pass has actually run: index > 0 gets one
## free from its stagger timer, index 0 has no such wait and needs the explicit
## frame, or pivot_offset is baked from the pre-layout size and the card scales
## about the wrong point. This is the width-overflow fix the old buy card
## documented, kept because the cause has not changed.
func play_entrance(index: int) -> void:
	modulate.a = 0.0
	scale = Vector2(0.85, 0.85)
	if index > 0:
		await get_tree().create_timer(index * 0.08).timeout
	else:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	pivot_offset = size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.22)
	tw.tween_property(self, "scale:y", 1.0, 0.28) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# X is eased without overshoot: the card sits near the modal full width, so
	# a TRANS_BACK bounce on X pushes it past the modal edge mid-tween.
	tw.tween_property(self, "scale:x", 1.0, 0.24) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## A rarity-coloured wash over the whole card. The old buy card gated this on
## rarity >= MAGIC internally; the gate now belongs to the CALLER, so the forge
## can flash a step of any rarity while a Common purchase still stays quiet.
func flash_rarity() -> void:
	if item == null:
		return
	var c := item.rarity_color()
	_rarity_flash.color = Color(c.r, c.g, c.b, 0.0)
	var t := create_tween()
	t.tween_property(_rarity_flash, "color:a", 0.4, 0.12)
	t.tween_property(_rarity_flash, "color:a", 0.0, 0.5)

## Coin spray centred on `at`, which callers pass as the button that was
## pressed so the burst leaves the tap rather than the middle of the card.
func spawn_burst(at: Control = null) -> void:
	var target: Control = at if at != null else _actions
	_burst.position = target.get_global_rect().position 		+ target.size * 0.5 - global_position
	_burst.amount = 30 if item != null and item.rarity >= Item.Rarity.MAGIC else 20
	_burst.restart()
	_burst.emitting = true

## Greys the card once its item is gone. Which BUTTONS a spent card should
## disable is left to the caller - a sold shop card disables Buy, a scrapped
## inventory card hides everything - so this only touches the card face.
func set_spent(spent: bool) -> void:
	($Card as Control).modulate = Color(0.55, 0.55, 0.6, 1.0) if spent else Color.WHITE

## Collapses the card out of its list and frees it - the sold/scrapped exit.
## The CARD child carries the height, so that is what shrinks; fading the root
## alone would leave a card-sized hole in the list until the next rebuild.
func play_departure() -> void:
	var card := $Card as Control
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_property(card, "custom_minimum_size:y", 0.0, 0.25)
	tw.chain().tween_callback(queue_free)
