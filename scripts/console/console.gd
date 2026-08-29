extends Control
## The management console (spec 17). Three bands, one verb each: the resource
## strip you read, the slot machine you watch, the upgrade tray you spend at.
##
## [ui-project-longshot] Sir Fish's tank has left the status strip - the
## concept board puts DEPTH where the tank was, and there is no fish anywhere
## on it. The tank scene is untouched and the quest result screen still shows
## him (quest_result.gd), so this is a relocation, not a deletion.
##
## The bands are laid out from the console's own height rather than from baked
## offsets, so the battle / console split can be moved (see main_layout.gd) without
## re-authoring every scene underneath.

## [presentation redesign S6, then the title-row experiment] Was 130, then 160
## for the gold/depth plates' bigger numerals and OrnateFrame chrome, then 300
## once the title row and the party bars got their own dedicated rows. [UI
## pass] Now 320: the party-status column moved into ResourceRow (stacked
## vertically instead of its own full-width row) and the bonus strip took over
## that vacated row instead, and the taller stacked column needs a bit more
## room than the row it replaced. Pure 2D: does not touch battle_height or
## Tuning.RUN_DIR, unlike the full S4 screen-budget resize.
## [ui-project-longshot] Re-proportioned against the concept board, which
## divides its console almost exactly 21 / 40 / 31 / 8 between strip, cabinet,
## card tray and bottom margin. Two of those moved a long way: the strip is
## SHORTER (the title band and the always-on bonus row are gone - the board has
## neither) and the tray much TALLER (the board's cards carry an icon, a title,
## a description, a level pip row and a price plate, which 262 px could not
## hold without the title overflowing its own card).
const STRIP_HEIGHT := 244.0
const TRAY_HEIGHT := 358.0
const MIN_SLOT_HEIGHT := 400.0
## [UI pass] The tray used to sit flush against the console's own bottom edge,
## which put the upgrade cards' price plates right at the screen's bottom -
## the first thing clipped on a shorter-than-designed viewport. This holds
## the tray up off that edge instead.
const BOTTOM_MARGIN := 90.0

@onready var status_panel = $StatusPanel
@onready var slot_machine = $SlotMachine
## [UI pass] Back in ResourceRow (it left for its own full-width row during
## the title-row experiment, then moved back in as the party-status column
## when the resource strip was split into gold/Sir Fish/party thirds).
@onready var party_bars = $StatusPanel/Layout/ResourceRow/PartyBars
@onready var upgrade_tray = $UpgradeTray

func apply_height(h: float) -> void:
	custom_minimum_size = Vector2(1080, h)
	size = Vector2(1080, h)

	var usable := h - BOTTOM_MARGIN
	var tray_h := TRAY_HEIGHT
	var slot_h := usable - STRIP_HEIGHT - tray_h
	# A very tall battle view eats the slot first and the tray second - the tray
	# is three fixed-size cards, the cabinet stretches.
	if slot_h < MIN_SLOT_HEIGHT:
		slot_h = MIN_SLOT_HEIGHT
		tray_h = maxf(usable - STRIP_HEIGHT - slot_h, 120.0)

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
