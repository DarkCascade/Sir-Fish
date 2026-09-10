extends Control
## [meshy-shop-pass] Stage exists so ActionLayer and Face (shop_buy_card.tscn)
## can overlap, and so Face can be slid horizontally on drag, without a
## Container fighting either - a Container forces every child to its own
## fitted rect every sort pass, which would both un-overlap the two layers
## and snap Face back the instant it moved.
##
## The cost of a plain Control is that it does not relay a child's minimum
## size upward the way a Container would, so left alone this card would be
## clipped to its own custom_minimum_size no matter how much content Face's
## icon/modifiers/BUY bar actually need. This restores that one piece of
## Container behaviour for Face specifically - the only child whose content
## should ever grow the card; ActionLayer's "Compare" label never needs to.
##
## Height only, never width: every card/row in a list must stay the same
## width as its siblings. Relaying Face's full minimum size (width included)
## let a row whose buttons happened to need more horizontal room - e.g. the
## Sell tab's "Unequip" vs. "Equip" - balloon wider than the others and spill
## past the modal's edge.
##
## The other half of restoring Container behaviour: a Container re-sorts when a
## child's minimum changes, but a plain Control never hears about it. Face's
## content is filled in by setup() AFTER _ready (real name, modifier count,
## "Must Unequip to Sell"), so without this the card keeps the minimum it
## cached from the empty .tscn template - the last row in a list gets the
## fewest later layout passes to self-correct, so its Face renders past the
## card's own (too-short) rect and the rarity border encloses the overflow.
func _ready() -> void:
	var face := get_node_or_null("Face") as Control
	if face != null:
		face.minimum_size_changed.connect(update_minimum_size)

func _get_minimum_size() -> Vector2:
	var face := get_node_or_null("Face") as Control
	return Vector2(0.0, face.get_combined_minimum_size().y) if face != null else Vector2.ZERO
