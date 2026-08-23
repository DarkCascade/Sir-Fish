extends Control
## Standalone preview for the console's resource strip - Sir Fish, gold, and
## the three hero party bars (status_panel.tscn) - so the bars can be tuned
## without booting a battle. Run this scene directly (F6 / "Run Current
## Scene") to see it.
##
## Spawns real Combatant instances from the hero stats and feeds them to
## PartyBars through a stand-in for BattleDirector, so the bars behave
## exactly as they do in-game - no separate mock data path to keep in sync.

const WARRIOR := preload("res://resources/stats/warrior.tres")
const RANGER := preload("res://resources/stats/ranger.tres")
const PRIEST := preload("res://resources/stats/priest.tres")

## party_bars.gd only ever reads director.heroes, so this is the entire
## surface a stand-in needs.
class MockDirector:
	var heroes: Array = []

@onready var status_panel: PanelContainer = $StatusPanel
@onready var heroes_root: Node3D = $Heroes

func _ready() -> void:
	var mock := MockDirector.new()
	# Uneven HP on purpose - a full bar doesn't show you whether the fill,
	# color and "x/y" text are lining up right.
	mock.heroes = [
		_spawn(PRIEST, 45),
		_spawn(RANGER, 80),
		_spawn(WARRIOR, 60),
	]
	# [UI pass] PartyBars moved back into ResourceRow as the party-status column.
	var party_bars := status_panel.get_node("Layout/ResourceRow/PartyBars")
	party_bars.director = mock

func _spawn(stats: CombatantStats, starting_hp: int) -> Combatant:
	var packed: PackedScene = load(stats.scene_path)
	var c := packed.instantiate() as Combatant
	heroes_root.add_child(c)
	c.setup(stats, starting_hp)
	return c
