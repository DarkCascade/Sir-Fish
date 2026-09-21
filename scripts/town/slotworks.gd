extends Control
## [backlog P7 / decision 7.5] The Slotworks: the town area where the slot
## cabinet is tuned. Phase 0 of a larger effort - today it holds one tab, the three
## permanent slot upgrades (quick_reels, overcharge, polish), moved wholesale from
## the blacksmith. The TabContainer is deliberate: more tabs are expected, and each
## is just another child of Layout/Tabs (the tab title is the node's name).
##
## The cards are the console tray's own scene (upgrade_tray.gd pairs them with
## Upgrades.ORDER); they save the profile themselves on a purchase
## (upgrade_button.gd). Gold reads off the HUD's CurrencyPlate, which stays up
## everywhere but a quest, so this scene keeps no readout of its own.

@onready var _back_button: Button = $Layout/BackButton

func _ready() -> void:
	# spec 3.1: every routed scene re-asserts its own place, so a direct launch
	# (F5, MCP play_scene) that never went through go() still reads true.
	SceneRouter.place = SceneRouter.Place.SLOTWORKS
	_back_button.pressed.connect(SceneRouter.go.bind(SceneRouter.Place.TOWN))

## ui_cancel (and Android's back gesture) routes home, like every town interior.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneRouter.go(SceneRouter.Place.TOWN)
		get_viewport().set_input_as_handled()
