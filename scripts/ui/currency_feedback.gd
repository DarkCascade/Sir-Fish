extends RefCounted
## [town] Shared "pop the number, float the delta" feedback for a currency
## label (spec 5.3). Lifted verbatim from status_panel.gd's _on_gold_changed /
## _float_delta so the HUD's CurrencyPlate, the console's GoldPlate and (step 9)
## the forge do not each carry their own copy.

const NUMBER_SCENE := preload("res://scenes/overlay/damage_number.tscn")

## The scale-punch on the label itself.
static func pop(label: Label) -> void:
	label.pivot_offset = label.size * 0.5
	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector2(1.22, 1.22), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "scale", Vector2.ONE, 0.13)

## A "+N" / "-N" number that floats up and fades. Spawned as a child of `host`
## at `label`'s screen position (converted through global_position, since the
## label is usually nested a level or two below `host`). No-op for a zero delta.
static func float_delta(host: Control, label: Label, delta: int, positive_color: Color) -> void:
	if delta == 0:
		return
	var number := NUMBER_SCENE.instantiate()
	host.add_child(number)
	var local_pos: Vector2 = label.global_position - host.global_position
	number.position = local_pos + Vector2(label.size.x + 20.0, 10.0)
	var color: Color = positive_color if delta > 0 else Tuning.C_DANGER
	number.show_number("%s%d" % ["+" if delta > 0 else "", delta], color, 38, 60.0, 0.8)
