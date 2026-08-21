extends ColorRect
## The signature effect: the lost segment of a health bar detaches and floats
## away while fading (spec 11.2).

func launch() -> void:
	pivot_offset = size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position",
			position + Vector2(RNG.randf_range(-Tuning.CHUNK_FLING_X, Tuning.CHUNK_FLING_X),
				-RNG.randf_range(Tuning.CHUNK_FLING_Y_MIN, Tuning.CHUNK_FLING_Y_MAX)),
			Tuning.CHUNK_FLIGHT_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation", RNG.randf_range(-Tuning.CHUNK_SPIN, Tuning.CHUNK_SPIN), Tuning.CHUNK_FLIGHT_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 0.0, Tuning.CHUNK_FLIGHT_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)
