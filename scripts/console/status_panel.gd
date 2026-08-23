extends PanelContainer
## The console's resource strip (spec 17.2): Sir Fish, the gold, and the party
## roster (party_bars.gd) filling the room to their right.
##
## Per-hero health is stated exactly once, here. It used to be drawn twice - three
## 70 px rows in this panel AND a bar over every hero's head - which is what this
## strip exists to fix.
##
## The item chips and the slot wins/spins counter were here too, and are gone:
## items still work and their effects still land, and the run summary still
## reports the slot's record at the end (spec 18.2) - neither needed a live
## readout competing with the cabinet.

const NUMBER_SCENE := preload("res://scenes/overlay/damage_number.tscn")

@onready var gold_label: Label = $Layout/ResourceRow/GoldLabel
@onready var depth_label: Label = $Layout/ResourceRow/DepthLabel

func _ready() -> void:
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.run_started.connect(_update_depth)
	EventBus.encounter_started.connect(func(_index: int, _def: EncounterDef) -> void: _update_depth())
	_update_gold()
	_update_depth()

## Endless-only (spec: Endless Mode) - the fixed level has no "depth" to
## report, so the label just disappears rather than showing a meaningless
## "Depth 1" forever. Recomputed on every encounter, not just level
## transitions - cheap, and it means there's no second place that has to
## remember when the depth last changed.
func _update_depth() -> void:
	depth_label.visible = GameState.endless_mode
	if GameState.endless_mode:
		depth_label.text = "DEPTH %d" % GameState.endless_level_number

func _update_gold() -> void:
	gold_label.text = str(GameState.gold)

func _on_gold_changed(_new_total: int, delta: int) -> void:
	_update_gold()
	gold_label.pivot_offset = gold_label.size * 0.5
	var tw := create_tween()
	tw.tween_property(gold_label, "scale", Vector2(1.22, 1.22), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(gold_label, "scale", Vector2.ONE, 0.13)
	if delta != 0:
		_float_delta(delta)

func _float_delta(delta: int) -> void:
	var label = NUMBER_SCENE.instantiate()
	add_child(label)
	label.position = gold_label.position + Vector2(gold_label.size.x + 20.0, 10.0)
	var color := Tuning.C_GOLD if delta > 0 else Tuning.C_DANGER
	label.show_number("%s%d" % ["+" if delta > 0 else "", delta], color, 38, 60.0, 0.8)
