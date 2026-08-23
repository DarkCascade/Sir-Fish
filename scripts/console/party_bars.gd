extends Control
## The party roster in the console's resource strip (spec 17.2): one bar per hero,
## in the space to the right of Sir Fish and the gold.
##
## These are the same CombatantBars the enemies wear over their heads, in their
## hero layout and with poll_health on - the party's health is stated once, and
## the one statement is the one that holds still. Bars over the heroes drifted
## with the characters, overlapped each other when the party bunched up during
## travel, and had to be clamped away from the viewport edges.

const BARS_SCENE := preload("res://scenes/overlay/hero_bars.tscn")

var director = null               # BattleDirector (untyped: custom API)

var _bars: Array = []

## [presentation redesign] Was 560, then 480 once the gold/depth plates ate
## into ResourceRow's shared width. Now a full-width row of its own (see
## status_panel.tscn's PartyBars, moved out of ResourceRow), so this claims
## the whole 1080 - _layout() below already adapts to whatever width it
## actually receives, so this only needs to fit the budget, not match a bar
## count.
func _ready() -> void:
	custom_minimum_size = Vector2(1080, 84)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)

func _process(_delta: float) -> void:
	if director == null:
		return
	if _bars.size() != director.heroes.size():
		_rebuild()
	for i: int in range(mini(_bars.size(), director.heroes.size())):
		var bars = _bars[i]
		# A retry frees the old party and spawns a new one; the bar has to follow
		# the live Combatant, not the one it was set up with (spec 18.3).
		if bars.combatant != director.heroes[i]:
			bars.setup(director.heroes[i])
			bars.poll_health = true
		bars.refresh()

func _rebuild() -> void:
	for bars: Variant in _bars:
		if is_instance_valid(bars):
			(bars as Node).queue_free()
	_bars.clear()
	for hero: Combatant in director.heroes:
		var bars = BARS_SCENE.instantiate()
		add_child(bars)
		bars.setup(hero)
		bars.poll_health = true
		bars.set_health_fraction(hero.hp_fraction())
		_bars.append(bars)
	_layout()

## Keeps the last bar off the panel's right edge, where it read as clipped.
const RIGHT_PAD := 16.0

## Spread evenly across whatever width the strip's HBoxContainer hands us.
func _layout() -> void:
	if _bars.is_empty():
		return
	var bar_size: Vector2 = _bars[0].size
	var span := maxf(size.x - bar_size.x - RIGHT_PAD, 0.0)
	var step := span / float(maxi(_bars.size() - 1, 1))
	var y := (size.y - bar_size.y) * 0.5
	for i: int in range(_bars.size()):
		_bars[i].position = Vector2(step * float(i), y)
