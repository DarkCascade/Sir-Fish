extends RefCounted
## [town] The rarity-tinted card frame shared by the shop's Buy card, the shop's
## Sell row and (spec 6.2) the inventory row. Lifted verbatim from the identical
## block setup() carried in BOTH shop_buy_card.gd and shop_sell_row.gd, so the
## third caller does not write a third copy - the same "don't copy it a third
## time" that produced currency_feedback.gd at step 5 (spec 5.3).
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

	# [reliquary] The teal card face becomes the plum-black reliquary stone; the
	# border and shadow stay the rarity tint (now a slightly stronger halo).
	var face_style: StyleBoxFlat = (face.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	face_style.bg_color = Tuning.C_RELIQUARY_STONE
	face_style.border_color = rarity_color
	face_style.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.32)
	face_style.shadow_size = 6
	face.add_theme_stylebox_override("panel", face_style)

	glyph.set("ring_color", rarity_color)
	glyph.set("weapon_type", item.weapon_type)
	glyph.set("kind", item.kind)

	if name_label != null:
		name_label.add_theme_color_override("font_color", rarity_color)
	if subtitle_label != null:
		subtitle_label.add_theme_color_override("font_color", Tuning.C_TEXT_DIM)
