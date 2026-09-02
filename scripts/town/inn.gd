extends Control
## [town] The inn (day/night spec §9). The bed moved out to the post-quest night
## modal (§2.2), so the room's job changed: it is where you go BEFORE a quest,
## not after one. Two things now:
##   - PriceBoard: a non-interactive label stating what tonight's bed will cost,
##     so a player who spends their last gold at the forge has been told (§9.2).
##   - Order a meal: INN_REST_COST replacement trade. Once per day, pay per
##     hero, +MEAL_DAMAGE_PCT damage for the next expedition (§9.3).
##
## "Sit by the fire" is unchanged - free, flavour only. Back / ui_cancel route
## home. Hero HP is profile-scoped (spec 2.1); the meal likewise lives on
## GameState (buy_meal()), and this scene only spends the gold and saves.

@onready var _price_board: Label = $Layout/PriceBoard
@onready var _meal_button: Button = $Layout/MealButton
@onready var _fire_button: Button = $Layout/FireButton
@onready var _back_button: Button = $Layout/BackButton
@onready var _flavour: Label = $Layout/Flavour

func _ready() -> void:
	# spec 3.1: re-assert our own place for direct launches (F5, play_scene).
	SceneRouter.place = SceneRouter.Place.INN
	_price_board.text = "A bed for the night — %d G, payable at nightfall." \
		% GameState.night_inn_cost()
	_meal_button.pressed.connect(_on_meal)
	_fire_button.pressed.connect(_on_fire)
	_back_button.pressed.connect(SceneRouter.go.bind(SceneRouter.Place.TOWN))
	EventBus.gold_changed.connect(_on_gold_changed)
	_refresh_meal_button()

## ui_cancel (and therefore Android's back gesture) also routes home (spec 7.1).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneRouter.go(SceneRouter.Place.TOWN)
		get_viewport().set_input_as_handled()

## Disabled and greyed when the meal cannot be ordered, with the label saying
## WHICH - a grey button with no reason is the failure mode _refresh_rest_button()
## was written to avoid (§9.3). upgrade_button.gd's affordability pattern.
func _refresh_meal_button() -> void:
	var cost := GameState.meal_cost()
	var can_buy := GameState.day_phase == GameState.DayPhase.DAY \
		and not GameState.meal_eaten_today and GameState.gold >= cost
	if GameState.meal_eaten_today:
		_meal_button.text = "Order a meal — eaten today"
	elif GameState.day_phase != GameState.DayPhase.DAY:
		_meal_button.text = "Order a meal — not now"
	else:
		_meal_button.text = "Order a meal — %d G" % cost
	_meal_button.disabled = not can_buy
	_meal_button.modulate = Color.WHITE if can_buy else Color(0.68, 0.65, 0.6, 1.0)

func _on_meal() -> void:
	if not GameState.buy_meal():
		return
	SaveGame.save_profile()
	# [day-night] §9.3 / §9.6.3: the flavour label carries the confirmation.
	_flavour.text = "A ribeye off the bone, bread to mop the plate, and a " \
		+ "second helping. You'll fight better for it."
	_refresh_meal_button()

func _on_fire() -> void:
	# Flavour only. No heal (spec 7.2).
	_flavour.text = "You sit a while by the fire. The forest feels far away."

func _on_gold_changed(_total: int, _delta: int) -> void:
	_refresh_meal_button()
