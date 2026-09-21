extends Button
class_name SpecialInvoker
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

## Which hero this button invokes, and the render that carries their glyph and
## label. Authored per instance in the editor - the tray's three buttons differ by
## these two fields and nothing else. hero_class also points the Meter child at
## the same hero, so there is one field to set, not two that can disagree.
##
## Every render shares the cleave's frame, so TAB_* and ART_ASPECT hold for all of
## them (the ranger and mage renders were measured against it: same tab, to a
## pixel at button size).
@export var hero_class: StringName = &"":
	set(value):
		hero_class = value
		if is_node_ready():
			_meter.hero_class = value
			_refresh()

@export var art: Texture2D:
	set(value):
		art = value
		if is_node_ready() and value != null:
			_art.texture = value

## Set by the tray, which gets it from Console.bind_director(). Null out of
## combat, which is also when the button correctly reads as unavailable.
var director = null:
	set(value):
		director = value
		if is_node_ready():
			_refresh()

@onready var _meter: ChargeMeter = $Meter
@onready var _art: TextureRect = $Art

## How far the button dims while its meter is still filling. Not disabled: a
## greyed-out control reads as broken, where a dim one reads as "not yet".
const DIM := Color(0.62, 0.62, 0.66)

func _ready() -> void:
	pressed.connect(_on_pressed)
	EventBus.special_charges_changed.connect(_on_charges_changed)
	EventBus.combat_started.connect(_on_combat_changed)
	EventBus.combat_ended.connect(_on_combat_changed)
	_meter.hero_class = hero_class
	if art != null:
		_art.texture = art
	_refresh()

## Polled, not event-driven: whether a press would fire also depends on things no
## single signal covers - the mage's heal wants somebody wounded, and anyone's
## HP can change under her. Three buttons; the comparison is a bool.
func _process(_delta: float) -> void:
	_refresh()

func _on_combat_changed(_a: Variant = null, _b: Variant = null) -> void:
	_refresh()

func _on_charges_changed(changed_class: StringName, _charges: int, _cost: int) -> void:
	if changed_class == hero_class:
		_refresh()

## Lit only when the press would actually do something. With a director that is
## its own guard chain (can_invoke_hero_special), so a full mage meter at full
## party HP reads as "not yet" rather than as a button that does nothing. Without
## one - out of combat, in town - it falls back to the meter alone, which is all
## there is to ask and still reads honestly. It never asks the director about a
## mid-action hero (ignore_busy), or the button would blink dark on every press.
func _refresh() -> void:
	var lit := _is_lit()
	if lit != _lit:
		_lit = lit
		modulate = Color.WHITE if lit else DIM

var _lit := true

func _is_lit() -> bool:
	if hero_class == &"":
		return false
	if director != null and director.has_method("can_invoke_hero_special"):
		return director.can_invoke_hero_special(_hero(), true)
	return GameState.special_ready(hero_class)

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
