extends VBoxContainer
## The party roster in the console's resource strip (spec 17.2): one bar per
## hero, stacked vertically in the party-status column to the right of Sir
## Fish and the gold.
##
## These are the same CombatantBars the enemies wear over their heads, in their
## hero layout and with poll_health on - the party's health is stated once, and
## the one statement is the one that holds still. Bars over the heroes drifted
## with the characters, overlapped each other when the party bunched up during
## travel, and had to be clamped away from the viewport edges.
##
## [move-elements-to-editor] The bars are authored instances in
## party_bars.tscn, stacked by this VBoxContainer. The gap between them is the
## container's `separation` constant and the block is centred by its
## `alignment` - both inspector properties now, where they used to be a GAP
## constant and a hand-rolled _layout(). This script only binds each authored
## bar to a live hero and hides the ones a smaller party does not need.

var director = null               # BattleDirector (untyped: custom API)

var _bars: Array = []

func _ready() -> void:
	for child: Node in get_children():
		_bars.append(child)

func _process(_delta: float) -> void:
	if director == null:
		return
	var hero_count: int = director.heroes.size()
	for i: int in range(_bars.size()):
		var bars = _bars[i]
		# A party smaller than the authored roster leaves spare bars; hiding
		# them beats leaving an empty card in the column, and the VBox closes
		# the gap for free.
		var should_show: bool = i < hero_count
		if bars.visible != should_show:
			bars.visible = should_show
		if not should_show:
			continue
		# A retry frees the old party and spawns a new one; the bar has to follow
		# the live Combatant, not the one it was set up with (spec 18.3).
		if bars.combatant != director.heroes[i]:
			bars.setup(director.heroes[i])
			bars.poll_health = true
			bars.set_health_fraction(director.heroes[i].hp_fraction())
		bars.refresh()
