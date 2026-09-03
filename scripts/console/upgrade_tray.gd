extends Control
## The upgrade tray (spec 17.6). Always visible and always interactive, in combat
## and out - out-of-combat time is when the player spends, which is half of why
## the slot's attract mode (16.6) exists.
##
## [move-elements-to-editor] The cards are authored instances in
## upgrade_tray.tscn, not spawned here: their X positions, their top margin and
## their width are all editor work now. This script only pairs each card with an
## entry in Upgrades.ORDER (in child order) and re-heights them when the console
## hands the tray a new height.
##
## Three upgrades at three levels is a vertical slice, not the system. The seam
## for a fourth is Upgrades.DEFS plus one more card duplicated in the .tscn
## (spec 22).

const NUMBER_SCENE := preload("res://scenes/overlay/damage_number.tscn")

## How much shorter than the tray a card is: the authored top margin plus a
## matching hair of room under the price plate. Read off the first card rather
## than hardcoded, so nudging the cards down in the editor keeps working.
const BUTTON_BOTTOM_MARGIN := 8.0

var _buttons: Array[Control] = []

## [slot phase 2] The bonus strip that used to sit here is gone - item effects
## are slot icons now, read per-hero in the party modal (party_modal.gd).
func _ready() -> void:
	for child: Node in get_children():
		if child is Control:
			_buttons.append(child as Control)
	for i: int in range(mini(_buttons.size(), Upgrades.ORDER.size())):
		_buttons[i].setup(Upgrades.ORDER[i])
	# More cards authored than upgrades defined: hide the spares rather than
	# leave a blank parchment tablet sitting in the tray.
	for i: int in range(Upgrades.ORDER.size(), _buttons.size()):
		_buttons[i].hide()

	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)

## Called by the console once it knows how much room the tray gets. Only the
## HEIGHT is imposed - each card keeps the x/width/top it was authored with.
func apply_height(h: float) -> void:
	custom_minimum_size = Vector2(custom_minimum_size.x, h)
	size = Vector2(size.x, h)
	for button: Control in _buttons:
		button.size = Vector2(button.size.x, h - button.position.y - BUTTON_BOTTOM_MARGIN)

## Floats a -N from the card that was just bought, mirroring the shop's
## feedback (spec 17.6).
func _on_upgrade_purchased(id: StringName, _level: int) -> void:
	var index := Upgrades.ORDER.find(id)
	if index < 0 or index >= _buttons.size():
		return
	var label = NUMBER_SCENE.instantiate()
	add_child(label)
	label.position = Vector2(_buttons[index].position.x + 40.0, size.y * 0.5)
	# The level has already advanced, so the price paid was the previous cost.
	var paid := int(round(float(Upgrades.DEFS[id]["base"])
		* pow(Tuning.UPGRADE_COST_GROWTH, float(Upgrades.level(id) - 1))))
	label.show_number("-%d" % paid, Tuning.C_GOLD, 34, 70.0, 0.9)
