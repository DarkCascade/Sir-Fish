extends Control
## [town] Quest / run result screen with the full run stats and a dismiss
## button (spec 18, spec 8.5). Renamed from RunSummary at step 5 and reparented
## into Hud/ModalLayer so it can present over a town scene it was never a child
## of; the victory/failure flow rewiring (Quest Reward row, expedition
## gold/scrap rows, the two recovery buttons) is spec 8.5 at step 8. At step 5
## present(victory: bool) keeps its exact prior behaviour and RunController
## still drives it.
##
## [move-elements-to-editor] The whole screen is authored in quest_result.tscn -
## Sir Fish at the top (he is the first thing the player sees on this screen,
## spec 18.2) and one named row per statistic, each carrying its caption and a
## plausible dummy number. This script writes numbers into the rows it
## recognises, by node NAME, and leaves everything else alone: reordering,
## restyling or deleting a row is editor work and needs no change here.

signal dismissed()

@onready var scrim: ColorRect = $Scrim
@onready var panel: PanelContainer = $Panel
@onready var title: Label = $Panel/Layout/Title
@onready var subtitle: Label = $Panel/Layout/Subtitle
@onready var stat_rows: VBoxContainer = $Panel/Layout/Stats
@onready var retry_button: Button = $Panel/Layout/RetryButton

func _ready() -> void:
	retry_button.pressed.connect(func() -> void:
		hide()
		dismissed.emit())
	hide()

func present(victory: bool) -> void:
	show()
	title.text = "LEVEL CLEARED" if victory else "DEFEATED"
	title.add_theme_font_size_override("font_size", 76 if victory else 84)
	title.add_theme_color_override("font_color",
		Tuning.C_GOLD if victory else Tuning.C_DANGER)
	if victory:
		subtitle.text = "Cleared all %d encounters" % GameState.level.encounters.size()
	else:
		var shown_index: int = clampi(GameState.current_encounter_index + 1, 1, GameState.level.encounters.size())
		if GameState.endless_mode:
			# "encounter 3 of 6" on its own reads as barely any progress even
			# after clearing four full levels first - the wipe only ever
			# happens partway through the CURRENT level, so depth has to be
			# named too or the four levels before it vanish from the summary.
			subtitle.text = "Reached Depth %d, encounter %d of %d" % \
				[GameState.endless_level_number, shown_index, GameState.level.encounters.size()]
		else:
			subtitle.text = "Reached encounter %d of %d" % [shown_index, GameState.level.encounters.size()]

	scrim.modulate.a = 0.0
	var s := create_tween()
	s.tween_property(scrim, "modulate:a", 1.0, 0.5)

	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(1.6, 1.6)
	var t := create_tween()
	t.tween_property(title, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_build_stats()

## Fills in the authored rows and plays them in one at a time.
##
## The slot-win PERCENTAGE is deliberately absent (spec 18.2 / 17.8 / Q24). At
## the ~20 spins of a short run, one sigma is about 11 points, so a perfectly
## healthy machine can print "33%" - and a player reading that concludes it is
## rigged against them. The raw count goes here; the live counter lives in the
## console; the 50% check lives in test_slot_odds, where the sample makes it mean
## something.
func _build_stats() -> void:
	var stats: Dictionary = GameState.run_stats
	var values := {
		&"EncountersCleared": str(int(stats["encounters_cleared"])),
		&"RunTime": _format_time(float(stats["run_time"])),
		&"GoldEarned": str(int(stats["gold_earned"])),
		&"GoldSpent": str(int(stats["gold_spent"])),
		&"GoldOnHand": str(GameState.gold),
		&"DamageDealt": str(int(stats["damage_dealt"])),
		&"DamageTaken": str(int(stats["damage_taken"])),
		&"SlotSpins": str(int(stats["slot_spins"])),
		&"SlotWins": str(int(stats["slot_wins"])),
		&"UpgradesBought": str(int(stats["upgrades_bought"])),
		&"ItemsFound": str(int(stats["items_found"])),
		&"ItemsSold": str(int(stats["items_sold"])),
	}

	var i := 0
	for row: Control in stat_rows.get_children():
		var value_label := row.get_node_or_null("Value") as Label
		if value_label != null and values.has(row.name):
			value_label.text = String(values[row.name])

		# Reveal one at a time, 0.08s apart, sliding in from the left.
		row.modulate.a = 0.0
		row.position.x = -60.0
		var tw: Tween = row.create_tween().set_parallel(true)
		tw.tween_property(row, "modulate:a", 1.0, 0.2).set_delay(0.08 * float(i))
		tw.tween_property(row, "position:x", 0.0, 0.25).set_delay(0.08 * float(i)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		i += 1

static func _format_time(seconds: float) -> String:
	var total := int(round(seconds))
	@warning_ignore("integer_division")
	var minutes := total / 60
	return "%d:%02d" % [minutes, total % 60]
