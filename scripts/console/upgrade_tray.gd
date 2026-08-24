extends Control
## The upgrade tray (spec 17.6). Always visible and always interactive, in combat
## and out - out-of-combat time is when the player spends, which is half of why
## the slot's attract mode (16.6) exists.
##
## Three upgrades at three levels is a vertical slice, not the system. The seam
## for a fourth is Upgrades.DEFS plus one more button here (spec 22).

const BUTTON_SCENE := preload("res://scenes/console/upgrade_button.tscn")
const NUMBER_SCENE := preload("res://scenes/overlay/damage_number.tscn")

## [ui-project-longshot] Three 340-wide cards with 16 between them and 14 either
## side is exactly 1080 - the board's cards run edge to edge with only a hair
## of console showing between, not the 12/358 grid that left a visible gutter.
const BUTTON_X: Array[float] = [14.0, 370.0, 726.0]
const BUTTON_Y := 24.0
const BUTTON_WIDTH := 340.0
const BUTTON_BOTTOM_MARGIN := 8.0
const DEFAULT_HEIGHT := 358.0

var _buttons: Array = []

## [presentation redesign] The bonus strip moved to status_panel.tscn's
## ResourceRow - enlarged, in the space the hidden depth plate freed up -
## instead of living here in miniature. See bonus_strip.gd's own header for
## what it shows.
func _ready() -> void:
	for i: int in range(Upgrades.ORDER.size()):
		var button = BUTTON_SCENE.instantiate()
		button.name = "UpgradeButton%d" % i
		add_child(button)
		button.position = Vector2(BUTTON_X[i], BUTTON_Y)
		button.size = Vector2(BUTTON_WIDTH, DEFAULT_HEIGHT - BUTTON_Y - BUTTON_BOTTOM_MARGIN)
		button.setup(Upgrades.ORDER[i])
		_buttons.append(button)

	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)

## Called by the console once it knows how much room the tray gets.
func apply_height(h: float) -> void:
	custom_minimum_size = Vector2(1080, h)
	size = Vector2(1080, h)
	for button: Control in _buttons:
		button.size = Vector2(BUTTON_WIDTH, h - BUTTON_Y - BUTTON_BOTTOM_MARGIN)

## Floats a -N from the button that was just bought, mirroring the shop's
## feedback (spec 17.6).
func _on_upgrade_purchased(id: StringName, _level: int) -> void:
	var index := Upgrades.ORDER.find(id)
	if index < 0:
		return
	var label = NUMBER_SCENE.instantiate()
	add_child(label)
	label.position = Vector2(BUTTON_X[index] + 40.0, size.y * 0.5)
	# The level has already advanced, so the price paid was the previous cost.
	var paid := int(round(float(Upgrades.DEFS[id]["base"])
		* pow(Tuning.UPGRADE_COST_GROWTH, float(Upgrades.level(id) - 1))))
	label.show_number("-%d" % paid, Tuning.C_GOLD, 34, 70.0, 0.9)
