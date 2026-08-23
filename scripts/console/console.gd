extends Control
## The management console (spec 17). Three bands, one verb each: the resource
## strip you read, the slot machine you watch, the upgrade tray you spend at.
##
## Sir Fish and the slot counter live inside the status panel's strip; the party
## damage button is gone, and with it the console's only mid-combat button.
##
## The bands are laid out from the console's own height rather than from baked
## offsets, so the battle / console split can be moved (see main_layout.gd) without
## re-authoring every scene underneath.

## [presentation redesign S6, then the title-row experiment] Was 130, then
## 160 for the gold/depth plates' bigger numerals and OrnateFrame chrome; now
## 300 to also fit the "Bioluminescent Forest" title row and the party bars'
## own dedicated row below it. Pure 2D: does not touch battle_height or
## Tuning.RUN_DIR, unlike the full S4 screen-budget resize.
const STRIP_HEIGHT := 300.0
const TRAY_HEIGHT := 262.0
const MIN_SLOT_HEIGHT := 320.0

@onready var status_panel = $StatusPanel
@onready var slot_machine = $SlotMachine
@onready var sir_fish_tank = $StatusPanel/Layout/ResourceRow/SirFishTank
## [layout experiment] Moved out of ResourceRow to its own full-width row
## below the title (status_panel.tscn), so PartyBars is now a direct child
## of Layout instead of nested under ResourceRow.
@onready var party_bars = $StatusPanel/Layout/PartyBars
@onready var upgrade_tray = $UpgradeTray

func apply_height(h: float) -> void:
	custom_minimum_size = Vector2(1080, h)
	size = Vector2(1080, h)

	var tray_h := TRAY_HEIGHT
	var slot_h := h - STRIP_HEIGHT - tray_h
	# A very tall battle view eats the slot first and the tray second - the tray
	# is three fixed-size cards, the cabinet stretches.
	if slot_h < MIN_SLOT_HEIGHT:
		slot_h = MIN_SLOT_HEIGHT
		tray_h = maxf(h - STRIP_HEIGHT - slot_h, 120.0)

	status_panel.position = Vector2.ZERO
	status_panel.size = Vector2(1080, STRIP_HEIGHT)

	slot_machine.position = Vector2(0, STRIP_HEIGHT)
	slot_machine.apply_height(slot_h)

	upgrade_tray.position = Vector2(0, STRIP_HEIGHT + slot_h)
	upgrade_tray.apply_height(tray_h)

## Called by RunController once the director exists.
func bind_director(director) -> void:
	slot_machine.director = director
	party_bars.director = director
