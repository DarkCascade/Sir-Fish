extends Button
## [specials] One hero's special invoker: the prototype button art with that
## hero's live charge meter drawn into its empty tab (P7).
##
## The art (assets/ui/invoker/invoker_*.png) is a Meshy render - gold rim, glass
## dome, neon glyph, label - regenerated deliberately WITHOUT pips so the meter
## below owns that space. Anything baked into the texture cannot light up, which
## is the whole reason the pip row is drawn rather than part of the image.
##
## The button is otherwise a plain Button: pressing it asks the director to fire
## the hero's special, and the director refuses if it cannot happen
## (BattleDirector.invoke_hero_special), so no rule lives twice.

## Where the empty tab sits inside the art, measured off the render itself:
## x 0.219-0.781, y 0.810-0.897 of the image. The Meter child is anchored to
## exactly these in the scene - they are recorded here because they are a
## property of the ARTWORK, and a re-render that moves the tab has to move the
## anchors with it.
const TAB_LEFT := 0.219
const TAB_RIGHT := 0.781
const TAB_TOP := 0.810
const TAB_BOTTOM := 0.897

## The art's own aspect (1201x1309). The tab anchors only line up while the
## button keeps it, so a layout that stretches this button will slide the pips
## off their recess.
const ART_ASPECT := 1201.0 / 1309.0

## Which hero this button invokes. Authored per instance in the editor, the same
## way ChargeMeter.hero_class is - the tray's three buttons differ by this field
## and their texture, nothing else.
@export var hero_class: StringName = &"":
	set(value):
		hero_class = value
		if is_node_ready():
			_meter.hero_class = value
			_refresh()

## Set by the tray, which gets it from Console.bind_director(). Null out of
## combat, which is also when the button correctly reads as unavailable.
var director = null:
	set(value):
		director = value
		if is_node_ready():
			_refresh()

@onready var _meter: ChargeMeter = $Meter

## How far the button dims while its meter is still filling. Not disabled: a
## greyed-out control reads as broken, where a dim one reads as "not yet".
const DIM := Color(0.62, 0.62, 0.66)

func _ready() -> void:
	pressed.connect(_on_pressed)
	EventBus.special_charges_changed.connect(_on_charges_changed)
	EventBus.combat_started.connect(_on_combat_changed)
	EventBus.combat_ended.connect(_on_combat_changed)
	_meter.hero_class = hero_class
	_refresh()

func _on_combat_changed(_a: Variant = null, _b: Variant = null) -> void:
	_refresh()

func _on_charges_changed(changed_class: StringName, _charges: int, _cost: int) -> void:
	if changed_class == hero_class:
		_refresh()

## Lit only when the press would actually do something. GameState.special_ready()
## rather than asking the director: this runs out of combat too, where there is
## no director and no hero to ask, and the meter should still read honestly.
func _refresh() -> void:
	var ready_now: bool = hero_class != &"" and GameState.special_ready(hero_class)
	modulate = Color.WHITE if ready_now else DIM

func _on_pressed() -> void:
	if director == null:
		return
	var hero := _hero()
	if hero == null:
		return
	# The director owns every rule about whether this can fire (dead, mid-action,
	# meter short, no target, nobody wounded for the mage) and spends nothing
	# when it refuses - so a rejected press is simply a press that did nothing.
	if director.invoke_hero_special(hero):
		_refresh()

func _hero() -> Combatant:
	if director == null or hero_class == &"":
		return null
	for h: Combatant in director.living_heroes():
		if h.stats != null and h.stats.id == hero_class:
			return h
	return null
