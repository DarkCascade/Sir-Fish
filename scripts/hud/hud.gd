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
## spec 6: opened by the backpack button, in town and (outside COMBAT) the forest.
@onready var inventory_modal = $ModalLayer/InventoryModal   # InventoryModal (untyped: custom API)
## spec 8.5 reaches the result modal as `Hud.quest_result`.
@onready var quest_result = $ModalLayer/QuestResult
@onready var transition: ColorRect = $Transition

func _ready() -> void:
	# spec 6 / step-5 Q9: the one line step 5 deliberately left out. Everything
	# about when the button is USABLE was already wired at step 5 (see _process).
	inventory_button.pressed.connect(inventory_modal.open)

func _process(_delta: float) -> void:
	# spec 3.2 / step-5 Q9: the button is disabled in COMBAT during a quest so it
	# can never be used to pause the fight for a free think or a heal-timing
	# tool. Everywhere else it is live from step 6 on (step 5 shipped this line
	# as `_combat_locked() or true`, the `or true` being the token this step
	# removes now that there is a modal to open).
	inventory_button.disabled = _combat_locked()

## True during a quest's COMBAT state. Reads SceneRouter.place (set by go(), and
## re-asserted by every routed scene's _ready() for direct launches - Q8) and
## RunController.state.
func _combat_locked() -> bool:
	if SceneRouter.place != SceneRouter.Place.QUEST:
		return false
	var rc := get_tree().root.find_child("RunController", true, false)
	return rc != null and int(rc.state) == rc.RunState.COMBAT
