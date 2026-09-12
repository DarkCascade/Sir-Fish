extends RefCounted
## [item-row] The comparison math behind BOTH the list row's delta badge and the
## item detail overlay's change rows. One owner, because the two have to agree:
## a row that promises "+12" over a detail panel that then spells out a
## different set of numbers is worse than either screen alone.
##
## Static and stateless, the same shape as item_card_style.gd and
## item_card_actions.gd beside it.

const CardActions := preload("res://scripts/ui/item_card_actions.gd")

## What the detail overlay stamps across its header. WORN is "this IS the item
## you are wearing" and NEW is "nothing is equipped in this slot to compare
## against" - neither claims an improvement that has no referent.
enum Verdict { WORN, NEW, UPGRADE, MIXED, WORSE, SAME }

## U+2212, not a hyphen: it matches the digit width of "+" so a column of gains
## and losses stays aligned. Same reasoning the compare flyout already used.
const MINUS := "−"
const UP := "▲"
const DOWN := "▼"

## The item's characteristic magnitude - the value of the base slot icon that
## EVERY equipped item contributes (SlotIcon.from_item_base): Power for a weapon
## or trinket, flat damage reduction for armor.
##
## Deliberately NOT "power plus the modifier rolls". A modifier is its own icon
## in the bag with its own roll (SlotIcon.KNOWN_MODIFIER_IDS), and it does not
## add to the base icon - so a headline that summed the two would be a number
## the game never computes anywhere.
static func headline_value(item: Item) -> int:
	return item.armor_value() if item.slot() == Item.Slot.ARMOR else item.power()

## The unit under that headline, in the row and the overlay alike.
static func headline_unit(item: Item) -> String:
	match item.slot():
		Item.Slot.ARMOR:
			return "ARMOR"
		Item.Slot.TRINKET:
			return "POWER"
		_:
			return "DAMAGE"

## The same figure's caption when it appears as the first CHANGE row rather than
## as the headline - spelled out, because there it sits in a list beside
## "Fire Damage" and "Bolt Power" and has to name itself as fully as they do.
static func base_caption(item: Item) -> String:
	match item.slot():
		Item.Slot.ARMOR:
			return "Armor"
		Item.Slot.TRINKET:
			return "Focus Power"
		_:
			return "Weapon Damage"

## "Rare Sword · Lv 7 · Warrior" - the one-line identity both surfaces print
## under the name. Item.subtitle() is not reused: it bakes the damage figure
## into the same string, which would print the headline number twice.
static func meta_line(item: Item) -> String:
	return "%s %s  ·  Lv %d  ·  %s" % [
		item.rarity_name(), item.type_name(), item.level, item.class_label(),
	]

## What `item` would be REPLACING: whatever is worn in its slot by the hero who
## could actually wield it. Null when nobody on the field can use it, when the
## slot is empty, or when `item` is itself the worn one - an item is not an
## upgrade over itself.
static func rival(item: Item) -> Item:
	var hero := CardActions.equip_hero(item)
	if hero == &"":
		return null
	var worn := GameState.equipped_item(hero, item.slot())
	return null if worn == item else worn

## One line per stat that either side puts on the board, in a FIXED order - the
## base slot icon first, then Itemizer.MODIFIERS order - so the same two items
## always produce the same list and a stat cannot jump rows depending on which
## side happens to carry it. A stat neither item touches is not news and is
## skipped. Walking the definitions rather than either item's own array is the
## rule compare_flyout's change list already followed.
##
## Each entry is { "id", "caption", "pct", "value", "delta" }: `value` is the
## CANDIDATE's magnitude and `delta` is candidate minus worn, so a caller can
## render the absolute number, the change, or both. `worn` may be null, which
## makes every delta equal to the candidate's own value.
static func rows(candidate: Item, worn: Item) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if candidate == null:
		return out

	var base_now := headline_value(candidate)
	var base_was := headline_value(worn) if worn != null else 0
	if base_now != 0 or base_was != 0:
		out.append({
			"id": SlotIcon.base_for(candidate.slot()),
			"caption": base_caption(candidate),
			"pct": false,
			"value": base_now,
			"delta": base_now - base_was,
		})

	var mine := _rolls_by_id(candidate)
	var theirs := _rolls_by_id(worn)
	for def: Dictionary in Itemizer.MODIFIERS:
		var id: StringName = def["id"]
		var now: int = int(mine.get(id, 0))
		var was: int = int(theirs.get(id, 0))
		if now == 0 and was == 0:
			continue
		out.append({
			"id": id,
			"caption": def["caption"],
			"pct": bool(def["pct"]),
			"value": now,
			"delta": now - was,
		})
	return out

## Total roll per modifier id, for a null-safe item. Summed rather than assigned
## because a single dictionary per id is only guaranteed by Itemizer's
## "never roll the same modifier twice" rule, and an item loaded from an older
## save predates that guarantee.
static func _rolls_by_id(item: Item) -> Dictionary:
	var out: Dictionary = {}
	if item == null:
		return out
	for mod: Dictionary in item.modifiers:
		var id: StringName = StringName(mod.get("id", &""))
		out[id] = int(out.get(id, 0)) + int(mod.get("roll", 0))
	return out

## Sign-only, never a weighted score. Adding up damage, mend percent and block
## into one "item score" would mean inventing a weighting the combat model does
## not have; counting which way each row moved does not.
static func verdict(candidate: Item) -> Verdict:
	if candidate == null:
		return Verdict.NEW
	if candidate.equipped_by != &"":
		return Verdict.WORN
	var worn := rival(candidate)
	if worn == null:
		return Verdict.NEW
	var up := false
	var down := false
	for row: Dictionary in rows(candidate, worn):
		if int(row["delta"]) > 0:
			up = true
		elif int(row["delta"]) < 0:
			down = true
	if up and down:
		return Verdict.MIXED
	if up:
		return Verdict.UPGRADE
	if down:
		return Verdict.WORSE
	return Verdict.SAME

static func verdict_text(v: Verdict) -> String:
	match v:
		Verdict.WORN:
			return "EQUIPPED"
		Verdict.UPGRADE:
			return "UPGRADE"
		Verdict.MIXED:
			return "MIXED"
		Verdict.WORSE:
			return "WORSE"
		Verdict.SAME:
			return "NO CHANGE"
		_:
			return "NEW"

static func verdict_color(v: Verdict) -> Color:
	match v:
		Verdict.UPGRADE:
			return Tuning.C_HEAL
		Verdict.WORSE:
			return Tuning.C_DANGER
		Verdict.MIXED, Verdict.NEW:
			return Tuning.C_GOLD
		_:
			return Tuning.C_TEXT_DIM

## The list row's one-line verdict, which has a narrower column than the overlay
## header and so prefers a NUMBER when there is a meaningful one to show: the
## base-stat swing is the figure a player scanning a list is actually sorting
## on. Falls back to the verdict word when the headline stat is unchanged but
## the modifiers moved, so a row never goes silent about a real difference.
static func badge(item: Item) -> Dictionary:
	var v := verdict(item)
	if v == Verdict.WORN or v == Verdict.NEW:
		return { "text": verdict_text(v), "color": verdict_color(v) }
	var worn := rival(item)
	var delta: int = headline_value(item) - (headline_value(worn) if worn != null else 0)
	if delta == 0:
		return { "text": verdict_text(v), "color": verdict_color(v) }
	return {
		"text": "%s %d" % [UP if delta > 0 else DOWN, absi(delta)],
		"color": Tuning.C_HEAL if delta > 0 else Tuning.C_DANGER,
	}

## "+12", "−4", "+9%" - the change column's text for one row() entry.
static func delta_text(row: Dictionary) -> String:
	var delta := int(row["delta"])
	if delta == 0:
		return "—"
	return "%s%d%s" % [
		"+" if delta > 0 else MINUS,
		absi(delta),
		"%" if bool(row["pct"]) else "",
	]

static func delta_color(row: Dictionary) -> Color:
	var delta := int(row["delta"])
	if delta > 0:
		return Tuning.C_HEAL
	if delta < 0:
		return Tuning.C_DANGER
	return Tuning.C_TEXT_DIM

## "58", or "9%" for a percent stat - the absolute column beside the change.
static func value_text(row: Dictionary) -> String:
	return "%d%s" % [int(row["value"]), "%" if bool(row["pct"]) else ""]
