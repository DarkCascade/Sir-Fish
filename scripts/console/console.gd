extends Control
## The management console (spec 17). Owns the status panel, the slot machine, the
## fish tank, the party damage button, the slot counter and the upgrade tray.

@onready var status_panel = $StatusPanel
@onready var slot_machine = $SlotMachine
@onready var party_damage_button = $PartyDamageButton
@onready var sir_fish_tank = $SirFishTank
@onready var slot_counter = $SlotCounter
@onready var upgrade_tray = $UpgradeTray

## Called by RunController once the director exists.
func bind_director(director) -> void:
	slot_machine.director = director
	status_panel.director = director
	party_damage_button.director = director
