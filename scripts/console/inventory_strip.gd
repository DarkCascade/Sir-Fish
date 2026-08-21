extends ScrollContainer
## Horizontal strip of 64x64 item chips (spec 17.2). Tapping a chip shows the
## item tooltip; tapping anywhere dismisses it.

const TOOLTIP_SCENE := preload("res://scenes/modals/item_tooltip.tscn")

@onready var row: HBoxContainer = $Row

var _tooltip = null               # ItemTooltip (untyped: custom API)

func _ready() -> void:
	EventBus.item_added.connect(_on_item_added)
	EventBus.item_removed.connect(_on_item_removed)
	# reset_run() empties the inventory array wholesale rather than removing
	# item by item, so a Retry emits no item_removed at all (spec 18.3).
	EventBus.run_started.connect(rebuild)
	rebuild()

func rebuild() -> void:
	for child: Node in row.get_children():
		child.queue_free()
	for item: Item in GameState.inventory:
		_add_chip(item, false)

func _on_item_added(item: Item) -> void:
	_add_chip(item, true)

func _on_item_removed(item: Item) -> void:
	for child: Node in row.get_children():
		if child.get_meta("item", null) == item:
			child.queue_free()
			return

func _add_chip(item: Item, animate: bool) -> void:
	# The slot is what the HBoxContainer positions; the chip inside it is what
	# the entry tween moves. Animating the container's own child would fight
	# the layout and leave every chip parked at x = 0, stacked on top of each
	# other.
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(64, 64)
	slot.set_meta("item", item)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.clip_contents = true
	row.add_child(slot)

	var chip := ColorRect.new()
	chip.color = item.rarity_color()
	chip.set_anchors_preset(Control.PRESET_FULL_RECT)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(chip)

	var label := Label.new()
	label.text = item.type_initial()
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Tuning.C_INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)

	slot.gui_input.connect(_on_chip_input.bind(slot, item))

	if animate:
		chip.modulate.a = 0.0
		chip.position.x = 60.0
		var tw: Tween = chip.create_tween().set_parallel(true)
		tw.tween_property(chip, "modulate:a", 1.0, 0.3)
		tw.tween_property(chip, "position:x", 0.0, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_chip_input(event: InputEvent, chip: Control, item: Item) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_show_tooltip(chip, item)
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_show_tooltip(chip, item)

func _show_tooltip(chip: Control, item: Item) -> void:
	_dismiss_tooltip()
	_tooltip = TOOLTIP_SCENE.instantiate()
	get_tree().root.add_child(_tooltip)
	_tooltip.show_item(item)
	await get_tree().process_frame
	if is_instance_valid(_tooltip):
		var anchor: Vector2 = chip.global_position + Vector2(chip.size.x * 0.5, 0.0)
		_tooltip.global_position = anchor - Vector2(_tooltip.size.x * 0.5,
			_tooltip.size.y + 12.0)

func _dismiss_tooltip() -> void:
	if _tooltip != null and is_instance_valid(_tooltip):
		_tooltip.queue_free()
	_tooltip = null

func _unhandled_input(event: InputEvent) -> void:
	if _tooltip == null:
		return
	if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
		_dismiss_tooltip()
