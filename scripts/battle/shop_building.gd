extends Node3D
## The shop encounter's building (spec 14.3). Same pop-in tween as the chest.
##
## [refinement-pass-3] The building is a Meshy model now (Model, instancing
## assets/meshes/shop_building.glb) with WindowGlow as its one authored light -
## see shop_building.tscn's header. This script only ever animated the whole
## node's scale, so the art swap left it untouched.

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
