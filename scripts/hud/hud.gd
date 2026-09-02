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
## spec 3.2: the heal-glyph button beside the backpack, same visibility rule.
@onready var party_button: Button = $PartyButton
@onready var currency_plate: PanelContainer = $CurrencyPlate
@onready var modal_layer: Control = $ModalLayer
## spec 6: opened by the backpack button, in town and (outside COMBAT) the forest.
@onready var inventory_modal = $ModalLayer/InventoryModal   # InventoryModal (untyped: custom API)
## spec 3.2: party HP readout, opened by the heal-glyph button.
@onready var party_modal = $ModalLayer/PartyModal   # PartyModal (untyped: custom API)
## [day-night] the post-quest night choice + result (day/night spec §5). Binds
## its own hooks in its own _ready() (QuestResult.dismissed, profile_ready).
@onready var night_modal = $ModalLayer/NightModal   # NightModal (untyped: custom API)
## spec 8.5 reaches the result modal as `Hud.quest_result`.
@onready var quest_result = $ModalLayer/QuestResult
@onready var transition: ColorRect = $Transition

## The running quest's RunController, registered from its own _ready() rather
## than found by a recursive whole-tree search every frame (D1). SceneRouter.go()
## frees main.tscn and the RunController in it (step-8 N2), so _combat_locked()
## guards this with is_instance_valid() and drops it when `place` leaves QUEST.
var _run_controller: Node = null

func register_run_controller(rc: Node) -> void:
	_run_controller = rc

func _ready() -> void:
	# spec 6 / step-5 Q9: the one line step 5 deliberately left out. Everything
	# about when the button is USABLE was already wired at step 5 (see _process).
	inventory_button.pressed.connect(inventory_modal.open)
	party_button.pressed.connect(party_modal.open)

func _process(_delta: float) -> void:
	# spec 3.2 / step-5 Q9: the button is disabled in COMBAT during a quest so it
	# can never be used to pause the fight for a free think or a heal-timing
	# tool. Everywhere else it is live from step 6 on (step 5 shipped this line
	# as `_combat_locked() or true`, the `or true` being the token this step
	# removes now that there is a modal to open).
	var locked := _combat_locked()
	inventory_button.disabled = locked
	# spec 3.2: the party panel pauses the tree exactly like the inventory modal,
	# so it carries the same COMBAT lock - no peeking at HP to time a heal.
	party_button.disabled = locked

## True during a quest's COMBAT state. Reads SceneRouter.place (set by go(), and
## re-asserted by every routed scene's _ready() for direct launches - Q8) and
## RunController.state.
func _combat_locked() -> bool:
	if SceneRouter.place != SceneRouter.Place.QUEST:
		_run_controller = null
		return false
	if not is_instance_valid(_run_controller):
		return false
	return int(_run_controller.state) == _run_controller.RunState.COMBAT
