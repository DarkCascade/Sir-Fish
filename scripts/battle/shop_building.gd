extends Node3D
## The shop encounter's building (spec 14.3). Same pop-in tween as the chest.
##
## [move-elements-to-editor] Walls / Roof / Door / Sign / WindowGlow are
## authored in shop_building.tscn, not built in _ready(). Their meshes, cel
## materials and offsets are all inspector-editable there - the code that
## remains only animates the whole building.

func pop_in() -> void:
	scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 1.15, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3.ONE, 0.15)
	BattleVfx.dust_puff_at(global_position, 14)

func fade_out() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
