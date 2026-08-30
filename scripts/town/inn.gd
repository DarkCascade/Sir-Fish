extends Control
## [town] The inn (spec 7.2). Two actions:
##   - Rest for the night: INN_REST_COST_PER_HERO x party size, every hero to
##     full HP (the dead among them revived).
##   - Sit by the fire: free, a flavour beat only. It must NOT heal, or the paid
##     rest has no reason to exist.
##
## Hero HP is profile-scoped (spec 2.1), so the heal itself is GameState's
## (heal_party()); this scene only gates it on gold and spends. Resting saves
## the profile (spec 2.4). Back / ui_cancel route home.

@onready var _rest_button: Button = $Layout/RestButton
@onready var _fire_button: Button = $Layout/FireButton
@onready var _back_button: Button = $Layout/BackButton
@onready var _flavour: Label = $Layout/Flavour

func _ready() -> void:
	# spec 3.1: re-assert our own place for direct launches (F5, play_scene).
	SceneRouter.place = SceneRouter.Place.INN
	_rest_button.pressed.connect(_on_rest)
	_fire_button.pressed.connect(_on_fire)
	_back_button.pressed.connect(SceneRouter.go.bind(SceneRouter.Place.TOWN))
	EventBus.gold_changed.connect(_on_gold_changed)
	_refresh_rest_button()

## ui_cancel (and therefore Android's back gesture) also routes home (spec 7.1).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneRouter.go(SceneRouter.Place.TOWN)
		get_viewport().set_input_as_handled()

func _rest_cost() -> int:
	return Tuning.INN_REST_COST_PER_HERO * maxi(GameState.active_party.size(), 1)

## Disabled and greyed when the player cannot afford it, re-evaluated on
## gold_changed - upgrade_button.gd's affordability pattern, not a new one
## (spec 7.2).
func _refresh_rest_button() -> void:
	var cost := _rest_cost()
	_rest_button.text = "Rest for the night  —  %d G" % cost
	var affordable := GameState.gold >= cost
	_rest_button.disabled = not affordable
	_rest_button.modulate = Color.WHITE if affordable else Color(0.68, 0.65, 0.6, 1.0)

func _on_rest() -> void:
	if not GameState.spend_gold(_rest_cost()):
		return
	GameState.heal_party()
	SaveGame.save_profile()
	_flavour.text = "You wake with the dawn, every wound closed."
	_refresh_rest_button()

func _on_fire() -> void:
	# Flavour only. No heal (spec 7.2).
	_flavour.text = "You sit a while by the fire. The forest feels far away."

func _on_gold_changed(_total: int, _delta: int) -> void:
	_refresh_rest_button()
