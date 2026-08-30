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

## Tints `face`'s panel stylebox border + shadow to the item's rarity colour and
## points `glyph`'s three properties at the item. `face` is the SwipeableFace
## PanelContainer; `glyph` is an ItemGlyph (both untyped here - leaf @tool /
## custom-API scripts with no class_name).
static func apply(face: PanelContainer, glyph: Control, item: Item) -> void:
	var rarity_color := item.rarity_color()

	var face_style: StyleBoxFlat = (face.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	face_style.border_color = rarity_color
	face_style.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.45)
	face_style.shadow_size = 8
	face.add_theme_stylebox_override("panel", face_style)

	glyph.set("ring_color", rarity_color)
	glyph.set("weapon_type", item.weapon_type)
	glyph.set("kind", item.kind)
