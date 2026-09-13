extends Control
## [town] The inn. Open any time the party is in town - there is no day/night
## cycle to wait on:
##   - Rest: a flat Tuning.INN_NIGHT_COST night. Full heal, the downed revived,
##     and the mayor's quest board refreshes (GameState.rest_at_inn()).
##   - Order a meal: +MEAL_DAMAGE_PCT damage for the next expedition, one per
##     quest (GameState.buy_meal()).
##
## "Sit by the fire" is free, flavour only. Back / ui_cancel route home. Hero HP
## and the meal both live on GameState; this scene only spends the gold and saves.

## The greyed-out modulate for a button that cannot be used right now -
## upgrade_button.gd's affordability pattern.
const GREYED := Color(0.68, 0.65, 0.6, 1.0)

@onready var _rest_button: Button = $Layout/RestButton
@onready var _meal_button: Button = $Layout/MealButton
@onready var _fire_button: Button = $Layout/FireButton
@onready var _back_button: Button = $Layout/BackButton
@onready var _flavour: Label = $Layout/Flavour

func _ready() -> void:
	# spec 3.1: re-assert our own place for direct launches (F5, play_scene).
	SceneRouter.place = SceneRouter.Place.INN
	_rest_button.pressed.connect(_on_rest)
	_meal_button.pressed.connect(_on_meal)
	_fire_button.pressed.connect(_on_fire)
	_back_button.pressed.connect(SceneRouter.go.bind(SceneRouter.Place.TOWN))
	EventBus.gold_changed.connect(_on_gold_changed)
	_refresh_buttons()

## ui_cancel (and therefore Android's back gesture) also routes home (spec 7.1).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneRouter.go(SceneRouter.Place.TOWN)
		get_viewport().set_input_as_handled()

## Each button greys out when it cannot be used, and its label says why - a
## grey button with no reason reads as broken.
func _refresh_buttons() -> void:
	_rest_button.text = "Rest — %d G" % Tuning.INN_NIGHT_COST
	_set_live(_rest_button, GameState.gold >= Tuning.INN_NIGHT_COST)

	var cost := GameState.meal_cost()
	var fed := GameState.meal_pct > 0
	_meal_button.text = "Already fed" if fed else "Order a meal — %d G" % cost
	_set_live(_meal_button, not fed and GameState.gold >= cost)

func _set_live(button: Button, live: bool) -> void:
	button.disabled = not live
	button.modulate = Color.WHITE if live else GREYED

func _on_rest() -> void:
	if not GameState.rest_at_inn():
		return
	SaveGame.save_profile()
	# The flavour label carries the confirmation.
	_flavour.text = "You sleep the night through and wake with every wound closed."
	_refresh_buttons()

func _on_meal() -> void:
	if not GameState.buy_meal():
		return
	SaveGame.save_profile()
	_flavour.text = "A ribeye off the bone, bread to mop the plate, and a " \
		+ "second helping. You'll fight better for it."
	_refresh_buttons()

func _on_fire() -> void:
	# Flavour only. No heal (spec 7.2).
	_flavour.text = "You sit a while by the fire. The forest feels far away."

func _on_gold_changed(_total: int, _delta: int) -> void:
	_refresh_buttons()
