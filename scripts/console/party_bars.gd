extends Control
## The party roster in the console's resource strip (spec 17.2): one bar per
## hero, stacked vertically in the party-status column to the right of Sir
## Fish and the gold.
##
## These are the same CombatantBars the enemies wear over their heads, in their
## hero layout and with poll_health on - the party's health is stated once, and
## the one statement is the one that holds still. Bars over the heroes drifted
## with the characters, overlapped each other when the party bunched up during
## travel, and had to be clamped away from the viewport edges.

const BARS_SCENE := preload("res://scenes/overlay/hero_bars.tscn")

## Gap between stacked hero bars.
const GAP := 8.0

var director = null               # BattleDirector (untyped: custom API)

var _bars: Array = []

## [UI pass] The party column: three 46-tall hero bars stacked with GAP
## between them (see _layout()), centred in whatever width the resource
## strip's 40% party-status cell actually gives this column.
func _ready() -> void:
	custom_minimum_size = Vector2(340, 154)
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

## Stacks the bars vertically, centred as a block in whatever height this
## column gets, and centred horizontally too (in case the column ends up
## wider than a single bar).
func _layout() -> void:
	if _bars.is_empty():
		return
	var bar_size: Vector2 = _bars[0].size
	var total_h := bar_size.y * float(_bars.size()) + GAP * float(_bars.size() - 1)
	var start_y := (size.y - total_h) * 0.5
	var x := (size.x - bar_size.x) * 0.5
	for i: int in range(_bars.size()):
		_bars[i].position = Vector2(x, start_y + float(i) * (bar_size.y + GAP))
