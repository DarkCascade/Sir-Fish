extends CanvasLayer
## [town] The persistent overlay (spec 3.2). Autoload `Hud`, layer 10, above
## every routed scene. One node, three jobs: the inventory button that must
## exist in both town and forest, the modal layer that outlives a scene swap
## (QuestResult lives here - spec 8.5), and the Transition rect SceneRouter.go()
## fades through.
##
## test_autoload_safety.gd cannot see this scene autoload's _ready() (spec 13.3),
## so it stays free of sibling-autoload work on the honour system - CurrencyPlate
## binds its own EventBus signals in its own script, which is the right home for
## them anyway. A --headless --quit-after boot of boot.tscn is what actually
## covers this file's inertness.

@onready var inventory_button: Button = $InventoryButton
@onready var currency_plate: PanelContainer = $CurrencyPlate
@onready var modal_layer: Control = $ModalLayer
## spec 8.5 reaches the result modal as `Hud.quest_result`.
@onready var quest_result = $ModalLayer/QuestResult
@onready var transition: ColorRect = $Transition

func _process(_delta: float) -> void:
	# spec 3.2 / step-5 Q9: the button is disabled in COMBAT during a quest so
	# it can never be used to pause the fight for a free think or a heal-timing
	# tool. It is ALSO disabled everywhere else until step 6 gives it a modal to
	# open - step 6 drops the `or true` and adds the `pressed` handler, nothing
	# else. The COMBAT lock is live now so step 6 does not have to think about it.
	inventory_button.disabled = _combat_locked() or true

## True during a quest's COMBAT state. Reads SceneRouter.place (set by go(), and
## re-asserted by every routed scene's _ready() for direct launches - Q8) and
## RunController.state.
func _combat_locked() -> bool:
	if SceneRouter.place != SceneRouter.Place.QUEST:
		return false
	var rc := get_tree().root.find_child("RunController", true, false)
	return rc != null and int(rc.state) == rc.RunState.COMBAT
