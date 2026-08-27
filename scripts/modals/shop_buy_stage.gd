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
func _get_minimum_size() -> Vector2:
	var face := get_node_or_null("Face") as Control
	return Vector2(0.0, face.get_combined_minimum_size().y) if face != null else Vector2.ZERO
