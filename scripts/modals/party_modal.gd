extends Control
## [town] The party status modal (spec 3.2). Lives in Hud/ModalLayer, opened by
## the HUD's heal-glyph button that sits beside the backpack button. One row per
## active_party member: name, an HP bar, and the current/max HP readout, with a
## fallen hero greyed and marked.
##
## Read-only - there is no heal here (that is the inn, spec 7.2). Like the
## inventory modal it pauses the tree while open (ModalLayer is
## PROCESS_MODE_ALWAYS, so the modal keeps animating); in town nothing is
## running to pause, and the button is disabled in COMBAT so it can never freeze
## a fight for a heal-timing read.
##
## Rebuilt on every open() from GameState.party_status() - the town has no combat
## ticking HP down under it, so there is nothing to live-update against.

## [slot ui phase 3] The board's plum icon tile - town's default here, since
## this modal also opens in town, where the board itself is never visible to
## compare against.
const SLOT_TILE := preload("res://resources/ui/slot_tile.tres")
## [rootwood-canopy] The same tile, rootwood - what slot_symbol.tscn itself now
## uses permanently (the board only ever renders while questing). Picked over
## SLOT_TILE in _reel_chip() when this modal is opened mid-quest, so a reel icon
## reads as the same object here as it does on the board it was pulled from.
const SLOT_TILE_ROOTWOOD := preload("res://resources/ui/slot_tile_rootwood.tres")
## The glyph's inset inside its 72 px tile - the board draws glyphs at 74% of
## the tile (SlotSymbol.glyph_fraction), and 9 px either side is the same.
const GLYPH_INSET := 9.0

const BiomeTheme := preload("res://scripts/ui/biome_theme.gd")

@onready var scrim: ColorRect = $Scrim
@onready var panel: PanelContainer = $Panel
@onready var grain: TextureRect = $Panel/Grain
@onready var close_button: Button = $Panel/Layout/Header/CloseButton
@onready var members: VBoxContainer = $Panel/Layout/Members

func _ready() -> void:
	BiomeTheme.apply_panel_backdrop(panel, grain)
	close_button.pressed.connect(close)
	hide()

func open() -> void:
	if visible:
		return
	# [rootwood-canopy] Re-read the live biome on every open, not just _ready() -
	# this modal lives under the persistent Hud autoload (see hud.gd), whose
	# children only ever _ready() once, at boot, while SceneRouter.place is
	# still TOWN. Without this, the panel would keep whatever it was opened into
	# on its FIRST open for the rest of the session.
	BiomeTheme.apply_panel_backdrop(panel, grain)
	_rebuild()
	show()
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
	get_tree().paused = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "scale", Vector2(0.9, 0.9), 0.2)
	tw.tween_property(panel, "modulate:a", 0.0, 0.2)
	tw.tween_property(scrim, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(hide)

## Optional desktop / Android-back nicety; the red X stays the only required
## close path, same contract as inventory_modal.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# --- build ----------------------------------------------------------------

func _rebuild() -> void:
	for child: Node in members.get_children():
		child.queue_free()
	for h: Dictionary in GameState.party_status():
		members.add_child(_member_row(h))

func _member_row(h: Dictionary) -> Control:
	var alive: bool = h["alive"]
	var cur: int = h["current_hp"]
	var top: int = maxi(int(h["max_hp"]), 1)
	var ratio := clampf(float(cur) / float(top), 0.0, 1.0)

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if not alive:
		row.modulate = Color(1, 1, 1, 0.45)

	var top_line := HBoxContainer.new()
	top_line.add_theme_constant_override("separation", 16)
	row.add_child(top_line)

	var name_label := Label.new()
	name_label.theme_type_variation = &"DisplayLabel"
	name_label.add_theme_font_size_override("font_size", 46)
	name_label.add_theme_color_override("font_color", Tuning.C_TEXT)
	name_label.text = h["display_name"]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_line.add_child(name_label)

	var hp_text := Label.new()
	hp_text.add_theme_font_size_override("font_size", 46)
	hp_text.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	hp_text.text = "Fallen" if not alive else "%d / %d" % [cur, top]
	top_line.add_child(hp_text)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 30)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = float(top)
	bar.value = float(cur)
	bar.add_theme_stylebox_override("background", _bar_bg())
	bar.add_theme_stylebox_override("fill", _bar_fill(
		Tuning.C_DANGER.lerp(Tuning.C_HEAL, ratio) if alive else Tuning.C_DANGER))
	row.add_child(bar)

	# [slot phase 2] The third element: this hero's contribution to the slot bag,
	# directly under the health bar. Inherits the "the only place a player can
	# see what their inventory is doing" duty from the retired bonus strip
	# (§7.1). Composition only - what is in the bag and why - which is the
	# question asked between fights, not what fired on the board this spin.
	row.add_child(_reel_strip(h["stats_id"]))
	return row

## The hero's reel icons as a headed, wrapping strip of chips, each labelled with
## its rolled magnitude. Duplicates show as separate chips; the innate icon is
## marked. [slot ui phase 3] Drawn exactly as the board draws them: the board
## glyph (SlotIcon.board_glyph_texture) on the shared tile - plum or rootwood,
## matching whichever this modal was opened into (see SLOT_TILE_ROOTWOOD above).
func _reel_strip(hero_class: StringName) -> Control:
	var data: Dictionary = GameState.hero_reel_icons(hero_class)
	var icons: Array = data["icons"]

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var head := Label.new()
	head.add_theme_font_size_override("font_size", 40)
	head.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
	head.text = "Reel icons (%d)" % int(data["count"])
	box.add_child(head)

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	for ic: Dictionary in icons:
		flow.add_child(_reel_chip(ic))
	return box

func _reel_chip(ic: Dictionary) -> Control:
	var id: StringName = StringName(ic.get("id", &""))
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	# [slot ui phase 3] Top-aligned, not centred: the flow row is as tall as its
	# tallest cell, and an innate/forged chip's extra tag line made a centred
	# cell float its tile above the rest of the row.
	cell.alignment = BoxContainer.ALIGNMENT_BEGIN

	var tile := Panel.new()
	tile.custom_minimum_size = Vector2(72, 72)
	# Stay 72 wide even when the roll label under it is wider.
	tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_theme_stylebox_override("panel",
		SLOT_TILE_ROOTWOOD if BiomeTheme.biome() == &"expedition" else SLOT_TILE)
	cell.add_child(tile)

	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = GLYPH_INSET
	icon.offset_top = GLYPH_INSET
	icon.offset_right = -GLYPH_INSET
	icon.offset_bottom = -GLYPH_INSET
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# expand_mode defaults to EXPAND_KEEP_SIZE, which makes the control's
	# MINIMUM size the texture's own native resolution (the reliquary chips
	# are all 1024x1024) - Godot then takes the max of that and
	# custom_minimum_size, so the 72x72 floor above is silently overridden and
	# the chip renders at ~1024px instead. IGNORE_SIZE is what actually lets
	# the tile's size govern.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph := SlotIcon.board_glyph_texture(id)
	if glyph != null:
		# Board glyphs carry their own colour - never element-tinted.
		icon.texture = glyph
	else:
		# No board glyph for this id: its reliquary chip, tinted as before.
		icon.texture = SlotIcon.chip_texture(id)
		match SlotIcon.element_of(id):
			&"fire": icon.modulate = Tuning.C_FIRE
			&"ice": icon.modulate = Tuning.C_ICE
			&"light": icon.modulate = Tuning.C_LIGHTNING
	tile.add_child(icon)

	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", Tuning.C_TEXT)
	lbl.text = String(ic.get("label", ""))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(lbl)

	var tag_text := ""
	var tag_color := Tuning.C_GOLD_BRIGHT
	if bool(ic.get("innate", false)):
		tag_text = "innate"
	elif bool(ic.get("enhanced", false)):
		tag_text = "forged"
		tag_color = Tuning.RARITY_COLORS[Item.Rarity.ENHANCED]
	if tag_text != "":
		var tag := Label.new()
		tag.add_theme_font_size_override("font_size", 40)
		tag.add_theme_color_override("font_color", tag_color)
		tag.text = tag_text
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(tag)
	return cell

func _bar_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.043, 0.086, 1.0)
	sb.border_color = Color(0.227, 0.227, 0.282, 1.0)
	sb.set_border_width_all(7)
	sb.set_corner_radius_all(8)
	return sb

func _bar_fill(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(8)
	return sb
