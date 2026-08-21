extends Control
## The upgrade tray (spec 17.6). Always visible and always interactive, in combat
## and out - out-of-combat time is when the player spends, which is half of why
## the slot's attract mode (16.6) exists.
##
## Three upgrades at three levels is a vertical slice, not the system. The seam
## for a fourth is Upgrades.DEFS plus one more button here (spec 22).

const BUTTON_SCENE := preload("res://scenes/console/upgrade_button.tscn")
const BONUS_STRIP_SCENE := preload("res://scenes/console/bonus_strip.tscn")
const NUMBER_SCENE := preload("res://scenes/overlay/damage_number.tscn")

const BUTTON_X: Array[float] = [12.0, 370.0, 728.0]
const BUTTON_Y := 34.0
const BUTTON_SIZE := Vector2(340, 178)

var _buttons: Array = []

func _ready() -> void:
	var strip = BONUS_STRIP_SCENE.instantiate()
	strip.name = "BonusStrip"
	strip.position = Vector2.ZERO
	strip.size = Vector2(1080, 30)
	add_child(strip)

	for i: int in range(Upgrades.ORDER.size()):
		var button = BUTTON_SCENE.instantiate()
		button.name = "UpgradeButton%d" % i
		add_child(button)
		button.position = Vector2(BUTTON_X[i], BUTTON_Y)
		button.size = BUTTON_SIZE
		button.setup(Upgrades.ORDER[i])
		_buttons.append(button)

	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)

## Floats a -N from the button that was just bought, mirroring the shop's
## feedback (spec 17.6).
func _on_upgrade_purchased(id: StringName, _level: int) -> void:
	var index := Upgrades.ORDER.find(id)
	if index < 0:
		return
	var label = NUMBER_SCENE.instantiate()
	add_child(label)
	label.position = Vector2(BUTTON_X[index] + 40.0, BUTTON_Y + 110.0)
	# The level has already advanced, so the price paid was the previous cost.
	var paid := int(round(float(Upgrades.DEFS[id]["base"])
		* pow(Tuning.UPGRADE_COST_GROWTH, float(Upgrades.level(id) - 1))))
	label.show_number("-%d" % paid, Tuning.C_GOLD, 34, 70.0, 0.9)
