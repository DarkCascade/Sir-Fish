extends RefCounted
## [item-card] The rarity tinting for the universal ItemCard - its one caller
## now that the shop's Buy card, the shop's Sell row, the inventory row and the
## forge row have all collapsed into that single scene. Kept as a separate file
## rather than folded into item_card.gd because it is the RARITY half of the
## card's look, and the compare flyout is the obvious next thing to want it.
##
## Static, no state: it only ever reads the item and pushes onto two nodes the
## caller already holds. Lives in scripts/ui/ alongside currency_feedback.gd
## rather than scripts/modals/ because "shared UI helper" is the bucket, not
## "modal".

## Tints `face`'s panel stylebox to the item's rarity colour, points `glyph`'s
## three properties at the item, and (when passed) colours the name label to the
## rarity and dims the subtitle. `face` is the SwipeableFace PanelContainer;
## `glyph` is an ItemGlyph (both untyped here - leaf @tool / custom-API scripts
## with no class_name). `name_label` / `subtitle_label` are optional so a caller
## that still does its own label colouring keeps working.
static func apply(face: PanelContainer, glyph: Control, item: Item,
		name_label: Label = null, subtitle_label: Label = null) -> void:
	var rarity_color := item.rarity_color()

	# [reliquary] The card face is the near-black reliquary underside now, not the
	# lit plum: every card is identified purely by its rarity-tinted border + halo.
	# The border is widened to the spec's 7px floor (0.1) so it actually carries
	# that job against a dark fill, and the halo is pushed a little stronger.
	var face_style: StyleBoxFlat = (face.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	face_style.bg_color = Tuning.C_RELIQUARY_STONE_DARK
	face_style.border_color = rarity_color
	face_style.set_border_width_all(7)
	face_style.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.38)
	face_style.shadow_size = 8
	face.add_theme_stylebox_override("panel", face_style)

	glyph.set("ring_color", rarity_color)
	glyph.set("weapon_type", item.weapon_type)
	glyph.set("kind", item.kind)

	if name_label != null:
		name_label.add_theme_color_override("font_color", rarity_color)
	if subtitle_label != null:
		subtitle_label.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
