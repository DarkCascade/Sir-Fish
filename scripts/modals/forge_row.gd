extends PanelContainer
## [town] One equipped item on the blacksmith's Forge tab (spec 7.3). Shows the
## shared rarity-tinted card (icon medallion + name + modifier lines, via
## ItemCardStyle) and a single FORGE button that walks the item one rarity step
## up the ladder. At ENHANCED the button is replaced by a static "Fully forged"
## plate; an empty slot is a different node entirely (see blacksmith.gd).
##
## The row does NOT forge or save itself: it emits forge_pressed(item) and the
## blacksmith runs Itemizer.forge() + SaveGame.save_profile() + a rebuild, then
## calls flash_new_modifier() on the rebuilt row - spec 7.3's "rarity-coloured
## flash on the new modifier line".

signal forge_pressed(item: Item)

const ItemCardStyle := preload("res://scripts/ui/item_card_style.gd")

var item: Item = null

@onready var glyph = $VBox/TopRow/Glyph   # ItemGlyph (untyped: custom API)
@onready var name_label: Label = $VBox/TopRow/Info/NameLabel
@onready var subtitle_label: Label = $VBox/TopRow/Info/SubtitleLabel
@onready var modifiers_box: VBoxContainer = $VBox/Modifiers
@onready var forge_button: Button = $VBox/ForgeButton
@onready var fully_forged: Label = $VBox/FullyForged

func setup(i: Item) -> void:
	item = i
	ItemCardStyle.apply(self, glyph, i)
	name_label.text = i.display_name
	subtitle_label.text = i.subtitle()
	subtitle_label.add_theme_color_override("font_color", i.rarity_color())
	_fill_modifiers()

	var maxed := i.rarity >= Item.Rarity.ENHANCED
	forge_button.visible = not maxed
	fully_forged.visible = maxed
	if not maxed:
		forge_button.pressed.connect(func() -> void: forge_pressed.emit(item))
		refresh_affordability()

func _fill_modifiers() -> void:
	for child: Node in modifiers_box.get_children():
		child.queue_free()
	for mod: Dictionary in item.modifiers:
		var line := Label.new()
		line.text = String(mod["label"])
		line.add_theme_font_size_override("font_size", 26)
		# spec 10.3: a forged (doubled) modifier tints to the ENHANCED colour.
		line.add_theme_color_override("font_color",
			Tuning.RARITY_COLORS[Item.Rarity.ENHANCED] if mod.get("enhanced", false)
			else Tuning.C_TEXT_DIM)
		modifiers_box.add_child(line)

## Re-run whenever gold or scrap changes: forging one slot can drop another
## below affordable, and a Buy-tab purchase spends gold. Disabled with the
## shortfall spelled out when the player cannot afford the next step (spec 7.3).
func refresh_affordability() -> void:
	if item == null or item.rarity >= Item.Rarity.ENHANCED:
		return
	var cost: Array = Tuning.FORGE_COSTS[item.rarity]
	var need_scrap := int(cost[0])
	var need_gold := int(cost[1])
	var to_name: String = Item.rarity_name_for(item.rarity + 1)
	var short_scrap: int = maxi(0, need_scrap - GameState.scrap)
	var short_gold: int = maxi(0, need_gold - GameState.gold)
	if short_scrap == 0 and short_gold == 0:
		forge_button.disabled = false
		forge_button.text = "FORGE  →  %s        %d scrap  ·  %d gold" % [to_name, need_scrap, need_gold]
	else:
		forge_button.disabled = true
		var parts: PackedStringArray = []
		if short_scrap > 0:
			parts.append("%d more scrap" % short_scrap)
		if short_gold > 0:
			parts.append("%d more gold" % short_gold)
		forge_button.text = "FORGE  →  %s   (need %s)" % [to_name, " and ".join(parts)]

## Fades the newest modifier line - the one forge() just appended - from the new
## rarity colour down to its settled colour (spec 7.3). Colour-only, so it does
## not depend on the row's layout pass having run.
func flash_new_modifier() -> void:
	if modifiers_box.get_child_count() == 0:
		return
	var line: Label = modifiers_box.get_child(modifiers_box.get_child_count() - 1)
	var settled: Color = line.get_theme_color("font_color")
	var hot: Color = item.rarity_color()
	line.add_theme_color_override("font_color", hot)
	create_tween().tween_method(
		func(t: float) -> void: line.add_theme_color_override("font_color", hot.lerp(settled, t)),
		0.0, 1.0, 0.6).set_trans(Tween.TRANS_QUAD)
