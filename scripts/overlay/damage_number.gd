extends Label
## Floating damage / heal / gold number (spec 11.4).

func show_number(value: String, color: Color, font_size: int = 42,
		rise: float = 80.0, duration: float = 0.85) -> void:
	text = value
	add_theme_font_size_override("font_size", font_size)
	add_theme_color_override("font_color", color)
	add_theme_color_override("font_outline_color", Tuning.C_INK)
	add_theme_constant_override("outline_size", 6)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	await get_tree().process_frame
	pivot_offset = size * 0.5
	scale = Vector2(0.6, 0.6)

	var punch := create_tween()
	punch.tween_property(self, "scale", Vector2(1.25, 1.25), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	punch.tween_property(self, "scale", Vector2.ONE, 0.06)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position:y", position.y - rise, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)
