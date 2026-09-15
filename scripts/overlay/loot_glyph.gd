extends Control
## Floating loot-glyph popup (spec 14.2 / P5) - the chest/drop-loot
## counterpart to damage_number.gd's rising numbers. Shows only the item's
## type glyph inside its rarity ring: no name, no class target, just the icon
## - the same reliquary medallion (item_glyph.gd) every item card already
## uses, reused here rather than drawing a second icon system.

@onready var _glyph: Control = $Glyph

func show_glyph(item: Item, rise: float = 120.0, duration: float = 1.2) -> void:
	_glyph.set("ring_color", item.rarity_color())
	_glyph.set("weapon_type", item.weapon_type)
	_glyph.set("kind", item.kind)

	pivot_offset = size * 0.5
	scale = Vector2(0.6, 0.6)

	var punch := create_tween()
	punch.tween_property(self, "scale", Vector2(1.2, 1.2), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	punch.tween_property(self, "scale", Vector2.ONE, 0.06)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position:y", position.y - rise, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)
