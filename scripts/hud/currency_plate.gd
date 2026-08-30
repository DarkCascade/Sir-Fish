extends PanelContainer
## [town] The HUD's shared gold + scrap readout (spec 3.3, 5.3). This is the
## PROFILE's currency plate; status_panel's GoldPlate is the EXPEDITION's, and
## during a quest they show the same number because banked gold lands straight
## on the profile (spec 8.4). Do not add a second scrap label to status_panel -
## this one is already on screen there.
##
## Reads GameState directly for the first paint (autoloads _ready() before the
## first scene, so this runs before boot.gd's load_profile()), then trusts
## gold_changed / scrap_changed. boot.gd re-emits both with a zero delta once
## the profile is settled so this repaints (spec 3.1 / step-5 Q5).
##
## Both halves are live: combat pickups feed scrap_changed via
## GameState.add_scrap (spec 9, step 9) and the forge spends it (spec 10.2).

const CurrencyFeedback := preload("res://scripts/ui/currency_feedback.gd")

## Scrap's float colour. A UI tint, not a gameplay number, so it lives here
## rather than in Tuning.
const SCRAP_COLOR := Color("9FB2BE")

@onready var gold_label: Label = $Row/Gold/Value
@onready var scrap_label: Label = $Row/Scrap/Value

func _ready() -> void:
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.scrap_changed.connect(_on_scrap_changed)
	gold_label.text = str(GameState.gold)
	scrap_label.text = str(GameState.scrap)

func _on_gold_changed(new_total: int, delta: int) -> void:
	gold_label.text = str(new_total)
	CurrencyFeedback.pop(gold_label)
	CurrencyFeedback.float_delta(self, gold_label, delta, Tuning.C_GOLD)

func _on_scrap_changed(new_total: int, delta: int) -> void:
	scrap_label.text = str(new_total)
	CurrencyFeedback.pop(scrap_label)
	CurrencyFeedback.float_delta(self, scrap_label, delta, SCRAP_COLOR)
