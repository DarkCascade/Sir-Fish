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
##
## [presentation redesign S6] Gold and depth are now OrnateFrame-backed plates
## (GoldPlate/DepthPlate) rather than bare labels sitting directly in
## ResourceRow, and depth is two labels (caption + numeral) instead of one
## string, so the two can carry different font sizes.

const NUMBER_SCENE := preload("res://scenes/overlay/damage_number.tscn")

@onready var gold_label: Label = $Layout/ResourceRow/GoldPlate/GoldLabel
@onready var depth_caption: Label = $Layout/ResourceRow/DepthPlate/DepthCaption
@onready var depth_numeral: Label = $Layout/ResourceRow/DepthPlate/DepthNumeral

func _ready() -> void:
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.run_started.connect(_update_depth)
	EventBus.encounter_started.connect(func(_index: int, _def: EncounterDef) -> void: _update_depth())
	_update_gold()
	_update_depth()

## [layout experiment] Depth is hidden unconditionally for now - was
## `plate.visible = GameState.endless_mode`. The title row's "Bioluminescent
## Forest" is standing in for that readout. Restore the endless_mode line to
## bring it back; depth_numeral's text is still kept current underneath so
## nothing has to be re-derived if it does.
func _update_depth() -> void:
	var plate := depth_caption.get_parent() as Control
	plate.visible = false
	if GameState.endless_mode:
		depth_numeral.text = str(GameState.endless_level_number)

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

## The number pops as a child of StatusPanel itself, not of GoldPlate, so
## converting through global_position (S6's GoldPlate nesting moved GoldLabel
## one level deeper than when this read gold_label.position directly).
func _float_delta(delta: int) -> void:
	var label = NUMBER_SCENE.instantiate()
	add_child(label)
	var local_pos: Vector2 = gold_label.global_position - global_position
	label.position = local_pos + Vector2(gold_label.size.x + 20.0, 10.0)
	var color := Tuning.C_GOLD if delta > 0 else Tuning.C_DANGER
	label.show_number("%s%d" % ["+" if delta > 0 else "", delta], color, 38, 60.0, 0.8)
