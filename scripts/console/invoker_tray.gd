extends Control
## [backlog P7 / decision 7.4] The console's bottom band: one special invoker per
## hero, laid out like the party stands on the field - ranger left, warrior in the
## middle, mage right.
##
## The order is FIXED by class, not read from the party. Tuning.PARTY_FORMATION is
## indexed by position in active_party (which starts [warrior] and APPENDS
## recruits), so the field order changes with recruitment order; the tray is meant
## to read as a stable control surface, so each hero always has the same slot. A
## hero not in the party has no button - the slot stays empty rather than
## collapsing, so a recruit joining never shifts the buttons the player has
## learned.
##
## The buttons hold no rules (special_invoker.gd): they ask the director, which
## refuses and spends nothing when it cannot fire.

## Set by Console.bind_director(). Null out of combat.
var director = null:
	set(value):
		director = value
		for b: SpecialInvoker in _buttons():
			b.director = value
		_refresh_party()

func _ready() -> void:
	EventBus.run_started.connect(_refresh_party)
	_refresh_party()

func _buttons() -> Array[SpecialInvoker]:
	var out: Array[SpecialInvoker] = []
	for child: Node in get_children():
		if child is SpecialInvoker:
			out.append(child as SpecialInvoker)
	return out

## A hero who is not in the party has nothing to invoke.
func _refresh_party() -> void:
	for b: SpecialInvoker in _buttons():
		b.visible = GameState.active_party.has(b.hero_class)

## Called by the console once it knows how much room the band gets. The buttons
## keep their authored x and size; only their height in the band is imposed
## (centred, never above the band's own top on a squeezed viewport).
func apply_height(h: float) -> void:
	custom_minimum_size = Vector2(custom_minimum_size.x, h)
	size = Vector2(size.x, h)
	for b: SpecialInvoker in _buttons():
		b.position.y = maxf((h - b.size.y) * 0.5, 0.0)
