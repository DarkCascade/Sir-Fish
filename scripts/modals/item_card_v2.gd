extends VBoxContainer
## The v2 item card layout - name full-width above the medallion row, stats
## split into two 2-tile rows (Attack/Magic, then Health/Defense) beside the
## medallion instead of one 4-tile row below it, and the modifier chips moved
## up into that same column as named text rows. Same public API as item_card.gd
## (setup/set_actions/etc.) so callers don't care which card they instanced -
## only the internal node paths differ, because item_card_v2.tscn's tree does.
##
## Kept as its own script rather than reworking item_card.gd in place so the
## original item_card.tscn (and every scene still using it) is untouched.

signal action_pressed(id: StringName)

const ItemCardStyle := preload("res://scripts/ui/item_card_style.gd")

## The four headline tiles, in [Attack, Magic, Health, Defense] order - see
## _fill_stats(), which reads TopStats' two children then BottomStats' two to
## land on that same order. Item carries no four-stat block - it carries
## `modifiers` - so each tile sums the rolls of the modifier ids named here.
##
## `dmg_pct` is deliberately in NO tile: it is a percentage and cannot be summed
## into the flat damage adds without lying about the unit. The chip row above
## the tiles lists it anyway.
##
## [armor items] Health also carries `armor_life` (a % of max hp), and Defense
## carries `armor_block` PLUS the item's passive armor_value() - added in
## _fill_stats since it is not a modifier roll. A weapon reads 0 on both armor
## tiles, an armor piece reads 0 on Attack / Magic.
const DEFENSE_TILE := 3
const STAT_TILES: Array[Dictionary] = [
	{ "ids": [&"dmg_flat", &"elem_fire", &"elem_ice", &"elem_light"], "pct": false },
	{ "ids": [&"slot_bolt"], "pct": false },
	{ "ids": [&"slot_mend", &"armor_life"], "pct": true },
	{ "ids": [&"armor_block"], "pct": false },
]

## Every button authored under Actions. The node name is the id capitalized.
const ACTION_IDS: Array[StringName] = [&"compare", &"equip", &"unequip", &"buy", &"sell", &"forge"]

## Shrink-to-fit bounds for the name, measured against the full Layout width
## now that NameLabel spans the card rather than sharing a column with the
## medallion. The display font is wide: the longest name Itemizer can
## generate - "Grumbling Longsword" (longest ADJECTIVE + longest noun, 19
## chars) - still needs shrinking on the narrower vertical card, so the floor
## is deliberately down at 28 and the longest names really do reach it. A name
## that STILL overruns at 28 gets an ellipsis (the label is single-line with
## clip_text on) rather than a second line.
const NAME_SIZE_MAX := 54
const NAME_SIZE_MIN := 28

## Resting colour for a modifier row's label. An enhanced roll overrides it with
## the ENHANCED rarity colour, so this cannot live in the scene alone - the
## non-enhanced branch needs something to put back.
const MOD_TEXT := Color(0.94902, 0.913725, 0.815686)

var item: Item = null

@onready var _backing: PanelContainer = $Card/Backing
@onready var _glyph = $Card/Content/Layout/TopRow/MedallionCol/Medallion/Glyph  # ItemGlyph (untyped: custom API)
@onready var _name_label: Label = $Card/Content/Layout/NameLabel
@onready var _subtitle_label: Label = $Card/Content/Layout/TopRow/MedallionCol/LevelPlate/SubtitleLabel
@onready var _mods: VBoxContainer = $Card/Content/Layout/TopRow/VBoxContainer/Mods
@onready var _no_mods: Label = $Card/Content/Layout/TopRow/VBoxContainer/NoneLabel
@onready var _top_stats: HBoxContainer = $Card/Content/Layout/TopRow/VBoxContainer/TopStats
@onready var _bottom_stats: HBoxContainer = $Card/Content/Layout/TopRow/VBoxContainer/BottomStats
@onready var _actions: HBoxContainer = $Actions
@onready var _card: Control = $Card
@onready var _content: MarginContainer = $Card/Content
@onready var _layout: VBoxContainer = $Card/Content/Layout
@onready var _rarity_flash: ColorRect = $Card/RarityFlash
@onready var _burst: GPUParticles2D = $Burst

func _ready() -> void:
	for id: StringName in ACTION_IDS:
		var b := _button(id)
		b.visible = false
		b.pressed.connect(func() -> void: action_pressed.emit(id))
	_actions.visible = false
	# The name is fitted against Layout's width, so a re-fit is owed whenever
	# that resizes - not whenever the LABEL does, which the font size override
	# changes and would feed back into itself.
	_layout.resized.connect(_fit_name)

func setup(i: Item) -> void:
	item = i
	ItemCardStyle.apply(_backing, _glyph, i, _name_label, _subtitle_label)
	_name_label.text = i.display_name
	# [item power model] Weapons carry the number their swing is made of.
	_subtitle_label.text = "Lv %d  ·  %d dmg" % [i.level, i.power()] \
		if i.slot() == Item.Slot.WEAPON else "Lv %d" % i.level
	_fill_mods(i)
	_fill_stats(i)
	# Card carries the height for the whole instance, and every one of its
	# children is anchored, so it takes no minimum from them - it has to be told.
	# The number is per-ITEM now that the modifier list is 0-3 rows: one authored
	# height would mean a Common kept all the slack a three-roll Epic needs.
	# Callers add_child() before setup(), so the theme is resolved and these
	# minimums are real. NameLabel's height is pinned in the scene, or _fit_name
	# would move this number a frame later.
	_card.custom_minimum_size.y = _content.get_combined_minimum_size().y
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
	return action_button(id)

## Public because ItemCardActions needs somewhere to aim the purchase burst, and
## the list strip that shares that helper keeps its buttons at a different depth
## - so neither tree may be hard-coded into the helper.
func action_button(id: StringName) -> Button:
	return _actions.get_node(String(id).capitalize()) as Button

## Mods authors three rows - RARITY_MOD_COUNT tops out at 3 - and this shows the
## first `modifiers.size()` of them rather than building nodes at runtime, so the
## list stays inspector-authored (CLAUDE.md best practice 1).
##
## Itemizer already formats each roll into `label` ("+8 Damage", "+6% Mend
## Power"), so the row only has to show it. That string used to be the chip's
## tooltip_text and nothing else, which on a touch build meant the shop could
## not tell you what an item did.
func _fill_mods(i: Item) -> void:
	var rows := _mods.get_children()
	for idx: int in range(rows.size()):
		var row := rows[idx] as HBoxContainer
		row.visible = idx < i.modifiers.size()
		if not row.visible:
			continue
		var mod: Dictionary = i.modifiers[idx]
		# [armor items] SlotIcon.chip_path resolves the reliquary chips AND the
		# glyph fallbacks for block / life, so no id is left with a blank icon.
		var path := SlotIcon.chip_path(StringName(mod.get("id", &"")))
		var icon := row.get_node("Icon") as TextureRect
		icon.texture = load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
		# The enhanced colour is the one thing the chips carried that the label
		# has to keep: it is how a forged roll reads as forged.
		var label := row.get_node("Label") as Label
		label.text = String(mod.get("label", ""))
		label.add_theme_color_override("font_color",
			Tuning.RARITY_COLORS[Item.Rarity.ENHANCED] if mod.get("enhanced", false) else MOD_TEXT)
	_mods.visible = not i.modifiers.is_empty()
	_no_mods.visible = i.modifiers.is_empty()

## TopStats holds Attack then Magic, BottomStats holds Health then Defense -
## concatenating them lands on STAT_TILES' [Attack, Magic, Health, Defense]
## order without needing a single combined row node.
func _fill_stats(i: Item) -> void:
	var tiles := _top_stats.get_children() + _bottom_stats.get_children()
	for idx: int in range(STAT_TILES.size()):
		var spec: Dictionary = STAT_TILES[idx]
		var ids: Array = spec["ids"]
		var total := 0
		for mod: Dictionary in i.modifiers:
			if ids.has(mod.get("id", &"")):
				total += int(mod.get("roll", 0))
		# [armor items] the Defense tile also shows the passive flat DR.
		if idx == DEFENSE_TILE:
			total += i.armor_value()
		var value := (tiles[idx] as PanelContainer).get_node("Box/Value") as Label
		value.text = ("%d%%" % total) if bool(spec["pct"]) and total > 0 else str(total)
		# A zero tile is dimmed rather than hidden: the four tiles are a fixed
		# readout, and holes opening in the row would cost more than the noise.
		value.modulate.a = 1.0 if total > 0 else 0.4

## Picks the largest font size (NAME_SIZE_MAX down to NAME_SIZE_MIN) at which the
## name fits Layout's width on one line, measured against the font directly
## rather than the rendered label. The label is single-line with clip_text on, so
## a name that still overruns at the floor gets an ellipsis - it can never wrap.
##
## `setup()` calls this before the card has laid out, when `_layout.size.x` is
## still 0, so it waits a frame for a real width and then re-checks until the
## width holds steady (different hosts - the shop's VBox, the inventory grid, the
## forge - settle the column in a different number of passes). `_fitting`
## collapses the `setup()` call and the `resized` emits it races into one fit.
var _fitting := false

func _fit_name() -> void:
	if _fitting or _name_label.text.is_empty():
		return
	_fitting = true
	var avail := _layout.size.x
	for _i: int in range(8):
		await get_tree().process_frame
		if not is_inside_tree():
			_fitting = false
			return
		if is_equal_approx(avail, _layout.size.x):
			break
		avail = _layout.size.x
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
	tw.tween_property(self, "scale:y", 1.0, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# X is eased without overshoot: the card sits near the modal full width, so
	# a TRANS_BACK bounce on X pushes it past the modal edge mid-tween.
	tw.tween_property(self, "scale:x", 1.0, 0.24) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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
	_burst.position = target.get_global_rect().position \
		+ target.size * 0.5 - global_position
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
