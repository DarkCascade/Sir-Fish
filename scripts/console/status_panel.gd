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
##
## [slot phase 2] The bonus row is gone. Item effects are slot icons now, and
## each hero's reel-icon contribution is shown in the party modal
## (party_modal.gd), under that hero's health bar.

## [town] spec 5.3: the pop-and-float treatment lives in one shared place now,
## lifted out of this file so CurrencyPlate (and step 9's forge) reuse it rather
## than carrying a second and third copy.
const CurrencyFeedback := preload("res://scripts/ui/currency_feedback.gd")

@onready var gold_label: Label = $Layout/ResourceRow/GoldPlate/GoldLabel

func _ready() -> void:
	EventBus.gold_changed.connect(_on_gold_changed)
	#EventBus.run_started.connect(_update_depth)
	#EventBus.encounter_started.connect(func(_index: int, _def: EncounterDef) -> void: _update_depth())
	_update_gold()
	#_update_depth()

func _update_gold() -> void:
	gold_label.text = str(GameState.gold)

func _on_gold_changed(_new_total: int, delta: int) -> void:
	_update_gold()
	CurrencyFeedback.pop(gold_label)
	# The number pops as a child of StatusPanel itself, not of GoldPlate, so the
	# helper converts through global_position (S6's GoldPlate nesting moved
	# GoldLabel a level deeper than when this read gold_label.position directly).
	CurrencyFeedback.float_delta(self, gold_label, delta, Tuning.C_GOLD)
