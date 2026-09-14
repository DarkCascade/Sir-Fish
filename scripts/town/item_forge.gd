extends Control
## [dev] Item Forge - a throwaway test screen, not shippable content. One
## button rolls a random item through Itemizer.generate_item() and appends it
## to a growing list, so item generation and its modifier rolls can be
## eyeballed in bulk (rarity spread, pip counts, glyphs) without grinding
## drops in a real run. The ItemForgeButton on town.tscn that reaches this
## screen must be removed or gated before ship.

const ItemRow := preload("res://scenes/modals/item_row.tscn")

@onready var _forge_button: Button = $Layout/Button
@onready var _back_button: Button = $Layout/BackButton
@onready var _list: VBoxContainer = $Layout/ItemScroll/ForgedItemsList

func _ready() -> void:
	SceneRouter.place = SceneRouter.Place.ITEM_FORGE
	_forge_button.pressed.connect(_on_forge_pressed)
	_back_button.pressed.connect(SceneRouter.go.bind(SceneRouter.Place.TOWN))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneRouter.go(SceneRouter.Place.TOWN)
		get_viewport().set_input_as_handled()

func _on_forge_pressed() -> void:
	var item := Itemizer.generate_item()
	var row := ItemRow.instantiate()
	_list.add_child(row)
	row.setup(item)
	row.play_entrance(_list.get_child_count() - 1)
