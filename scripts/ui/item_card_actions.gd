extends RefCounted
## [item-card] What the universal card's action buttons DO. Static and
## stateless, the same shape as item_card_style.gd beside it.
##
## The shop modal and the blacksmith both build Buy, Sell and Scrap lists out
## of the same ItemCard, so without this they would carry two copies of every
## transaction - which is exactly the split that let shop_buy_card.gd and
## shop_sell_row.gd drift apart in the first place. Each caller keeps only its
## own action handler; the money changing hands lives here once.

enum Mode { SELL, SCRAP }

## The Buy label carries the price, so the card needs no separate price bar the
## way the old buy card did.
static func buy_label(item: Item) -> String:
	return "Buy  ·  %d G" % item.buy_price()

static func sell_label(item: Item, mode: int) -> String:
	if mode == Mode.SCRAP:
		return "Scrap  ·  %d S" % item.scrap_value()
	return "Sell  ·  %d G" % item.sell_price()

## The first active_party member who can wield `item`. An "Anyone" item (empty
## usable_by()) goes to the field leader; an item restricted to classes none of
## whom are on the field returns &"", and the caller then offers no equip
## control rather than one that silently fails.
##
## The old Sell row took usable_by()[0] WITHOUT checking the field, so it could
## offer an Equip that did nothing; the inventory row checked. Unifying the card
## unified this too, on the inventory row's stricter reading.
static func equip_hero(item: Item) -> StringName:
	var usable := item.usable_by()
	if usable.is_empty():
		return GameState.active_party[0] if not GameState.active_party.is_empty() else &""
	for c: StringName in usable:
		if c in GameState.active_party:
			return c
	return &""

## Which equip action id `item` should offer, or &"" for none.
static func equip_action(item: Item) -> StringName:
	var hero := equip_hero(item)
	if hero == &"":
		return &""
	return &"unequip" if item.equipped_by == hero else &"equip"

## A card whose item has already been bought. Tracked as metadata rather than
## read back off the button text, so a label change can never silently reopen
## a sold card to a second purchase.
static func is_spent(card: Control) -> bool:
	return bool(card.get_meta("spent", false))

## Re-run whenever gold changes: a purchase, a sale, or a slot payout can all
## move a card across the affordability line.
static func refresh_buy_state(card: Control, item: Item) -> void:
	if is_spent(card):
		return
	card.set_action_disabled(&"buy", GameState.gold < item.buy_price())

## An equipped item cannot be sold or scrapped out from under its hero: the
## button disables and says why, rather than staying enabled and doing nothing.
static func refresh_sell_state(card: Control, item: Item, mode: int) -> void:
	var locked := item.equipped_by != &""
	card.set_action_disabled(&"sell", locked)
	if locked:
		card.set_action_text(&"sell",
			"Unequip to %s" % ("scrap" if mode == Mode.SCRAP else "sell"))
	else:
		card.set_action_text(&"sell", sell_label(item, mode))

## Spends the gold and hands the item over, then plays the purchase juice.
## Returns false and changes nothing if the player cannot afford it - the
## button reads disabled, but a purchase must never half-complete.
static func do_buy(card: Control, item: Item) -> bool:
	if is_spent(card) or not GameState.spend_gold(item.buy_price()):
		return false
	GameState.add_item(item)
	GameState.run_stats["items_found"] = int(GameState.run_stats["items_found"]) + 1
	card.set_meta("spent", true)
	card.set_spent(true)
	card.set_action_disabled(&"buy", true)
	card.set_action_text(&"buy", "Sold")
	card.spawn_burst(card.get_node("Actions/Buy"))
	# A Common buy stays quiet: the wash is the shop's only cue that a
	# Magic-or-better purchase was a bigger deal than an ordinary one.
	if item.rarity >= Item.Rarity.MAGIC:
		card.flash_rarity()
	return true

## Pays out, removes the item, and collapses the card out of its list.
static func do_sell(card: Control, item: Item, mode: int) -> bool:
	if item.equipped_by != &"":
		return false   # the button reads disabled, but guard anyway
	card.set_action_disabled(&"sell", true)
	if mode == Mode.SCRAP:
		GameState.add_scrap(item.scrap_value())
	else:
		GameState.add_gold(item.sell_price())
		GameState.run_stats["items_sold"] = int(GameState.run_stats["items_sold"]) + 1
	GameState.remove_item(item)
	card.play_departure()
	return true

## Equip or unequip, whichever the card offered. The caller rebuilds its list
## afterwards: equipping can displace a DIFFERENT card's item in the same slot,
## so no card can be patched in isolation.
static func do_equip(item: Item, equipping: bool) -> void:
	if equipping:
		GameState.equip_item(item, equip_hero(item))
	else:
		GameState.unequip_item(item)
