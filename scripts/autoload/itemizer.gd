extends Node
## Itemizer — the only place items are created (spec 13).

## [town] Renamed from WEAPON_TYPES (spec 4.2) - it now names armor and trinket
## types too. Every entry carries a `slot` (Item.Slot); the five weapon rows are
## otherwise unchanged, base_values included (moving them would move
## test_economy.gd's affordability gate). Armor and trinkets list
## classes: [&"warrior"] rather than [] so usable_by() / weapon_types_for() /
## _maybe_auto_equip() keep working untouched; the mage and ranger get their own
## rows here when they return (spec 15).
const ITEM_TYPES := {
	# --- weapons (unchanged from WEAPON_TYPES) ---
	&"axe":    { "slot": Item.Slot.WEAPON,  "base_value": 20, "classes": [&"warrior"], "nouns": ["Axe", "Hatchet", "Cleaver", "Chopper"] },
	&"sword":  { "slot": Item.Slot.WEAPON,  "base_value": 22, "classes": [&"warrior"], "nouns": ["Sword", "Blade", "Saber", "Longsword"] },
	&"bow":    { "slot": Item.Slot.WEAPON,  "base_value": 20, "classes": [&"ranger"],  "nouns": ["Bow", "Longbow", "Shortbow", "Recurve"] },
	&"dagger": { "slot": Item.Slot.WEAPON,  "base_value": 18, "classes": [&"ranger"],  "nouns": ["Dagger", "Knife", "Dirk", "Shiv"] },
	&"staff":  { "slot": Item.Slot.WEAPON,  "base_value": 25, "classes": [&"mage"],    "nouns": ["Staff", "Rod", "Cane", "Scepter"] },
	# --- armor [town] ---
	&"helm":   { "slot": Item.Slot.ARMOR,   "base_value": 18, "classes": [&"warrior"], "nouns": ["Helm", "Casque", "Barbute", "Coif"] },
	&"mail":   { "slot": Item.Slot.ARMOR,   "base_value": 24, "classes": [&"warrior"], "nouns": ["Mail", "Hauberk", "Cuirass", "Plate"] },
	&"shield": { "slot": Item.Slot.ARMOR,   "base_value": 22, "classes": [&"warrior"], "nouns": ["Shield", "Buckler", "Targe", "Kite"] },
	# --- trinkets [town] ---
	&"ring":   { "slot": Item.Slot.TRINKET, "base_value": 19, "classes": [&"warrior"], "nouns": ["Ring", "Band", "Signet", "Loop"] },
	&"amulet": { "slot": Item.Slot.TRINKET, "base_value": 21, "classes": [&"warrior"], "nouns": ["Amulet", "Pendant", "Charm", "Talisman"] },
	&"idol":   { "slot": Item.Slot.TRINKET, "base_value": 23, "classes": [&"warrior"], "nouns": ["Idol", "Fetish", "Totem", "Effigy"] },
}

const ADJECTIVES := [
	"Fat", "Wimpy", "Rusty", "Gleaming", "Crooked", "Humble", "Brash", "Sullen",
	"Chipped", "Peculiar", "Stout", "Lucky", "Grumbling", "Nimble", "Battered",
	"Radiant", "Sodden", "Hasty", "Bold", "Weeping", "Jagged", "Plucky",
]

const MODIFIERS := [
	# Hero-damage modifiers
	{ "id": &"dmg_flat",   "label": "+%d Damage",        "roll": [2, 9],   "value_mult": [0.28, 0.55] },
	{ "id": &"dmg_pct",    "label": "+%d%% Damage",      "roll": [5, 18],  "value_mult": [0.30, 0.60] },
	{ "id": &"elem_fire",  "label": "+%d Fire Damage",   "roll": [3, 11],  "value_mult": [0.35, 0.70] },
	{ "id": &"elem_ice",   "label": "+%d Ice Damage",    "roll": [3, 11],  "value_mult": [0.35, 0.70] },
	{ "id": &"elem_light", "label": "+%d Lightning Dmg", "roll": [3, 11],  "value_mult": [0.35, 0.70] },
	# Slot modifiers [v2] - these are what make the initial vision's core loop
	# real: finding items in the world makes the slot machine pay bigger.
	{ "id": &"slot_bolt",  "label": "+%d Bolt Power",    "roll": [2, 8],   "value_mult": [0.40, 0.75] },
	{ "id": &"slot_purse", "label": "+%d Coin Yield",    "roll": [3, 10],  "value_mult": [0.38, 0.72] },
	{ "id": &"slot_mend",  "label": "+%d%% Mend Power",  "roll": [3, 9],   "value_mult": [0.40, 0.75] },
]

# 13.2 Rarity: weight, modifier count, value multiplier range.
#
# [town] Every array here is indexed by Item.Rarity and carries an ENHANCED slot
# (spec 10.1). ENHANCED's weight is 0: RNG.weighted_index() sums the weights and
# rolls randi_range(1, total), so a trailing 0 contributes nothing to the total
# and its index is unreachable - ENHANCED can never be rolled into a chest or
# shop. It is reached only by Itemizer.forge() walking an item up the ladder
# (spec 10.2, lands with scrap). RARITY_VALUE_MULT's ENHANCED row is never read
# (forging adds gold to value directly, spec 10.5) but the array has to match
# the others in length or an index goes stale.
const RARITY_WEIGHTS := [50, 30, 15, 5, 0]
const RARITY_MOD_COUNT := [0, 1, 2, 3, 4]
const RARITY_VALUE_MULT := [
	[1.0, 1.0],
	[1.6, 2.2],
	[2.8, 3.6],
	[4.5, 6.0],
	[6.5, 8.0],   # ENHANCED - never read, present for length parity
]

# TODO (post-demo): replace the random multiplier ranges with a designed curve -
# rarity multipliers should be authored per-rarity constants, and each modifier's
# value contribution should scale with the magnitude actually rolled rather than
# being independently random.

func generate_items(count: int) -> Array[Item]:
	var out: Array[Item] = []
	for i: int in range(count):
		out.append(generate_item())
	return out

func generate_item() -> Item:
	return generate_item_with_rarity(RNG.weighted_index(RARITY_WEIGHTS))

## Shop stock and the Debug harness need a specific rarity; everything else
## should go through generate_item() and take the weighted roll.
##
## [town] Rolls the SLOT first, then a type within it (spec 4.4) - the number of
## types a slot happens to have must not decide how often that slot is served.
## Passes the active party, so with a solo warrior staves and bows stop
## appearing in chests and shop stock entirely (the spec 1.6 fix).
func generate_item_with_rarity(rarity_index: int) -> Item:
	# Clamp to RARE, never ENHANCED (spec 10.1): the guard now says what it means.
	rarity_index = clampi(rarity_index, 0, Item.Rarity.RARE)
	return _roll_typed(GameState.active_party, rarity_index)

## The whole of the old generate_item_with_rarity() body from `item.weapon_type`
## onward, with the type handed in. Nothing else moves.
func _generate_typed(wtype: StringName, rarity_index: int) -> Item:
	var item := Item.new()
	item.kind = Item.Kind.WEAPON      # the only kind generated in the demo (spec 13.7)
	item.weapon_type = wtype

	item.rarity = rarity_index as Item.Rarity

	var nouns: Array = ITEM_TYPES[wtype]["nouns"]
	var adjective: String = ADJECTIVES[RNG.randi_range(0, ADJECTIVES.size() - 1)]
	var noun: String = nouns[RNG.randi_range(0, nouns.size() - 1)]
	item.display_name = "%s %s" % [adjective, noun]

	var mods: Array[Dictionary] = []
	var mod_sum: float = 0.0
	var pool: Array = MODIFIERS.duplicate()
	for i: int in range(RARITY_MOD_COUNT[rarity_index]):
		if pool.is_empty():
			break
		var pick_index: int = RNG.randi_range(0, pool.size() - 1)
		var def: Dictionary = pool[pick_index]
		pool.remove_at(pick_index)          # never roll the same modifier twice on one item
		var roll: int = RNG.randi_range(int(def["roll"][0]), int(def["roll"][1]))
		var vm: float = RNG.randf_range(float(def["value_mult"][0]), float(def["value_mult"][1]))
		mod_sum += vm
		mods.append({
			"id": def["id"],
			"label": (def["label"] as String) % roll,
			# The raw roll is stored alongside the formatted label: v2 modifiers have
			# gameplay effects (spec 13.5), so the magnitude must be recoverable, and
			# a formatted string alone does not allow that.
			"roll": roll,
			"value_mult": vm,
		})
	item.modifiers = mods

	var base_value: int = int(ITEM_TYPES[wtype]["base_value"])
	var rarity_mult: float = RNG.randf_range(
		RARITY_VALUE_MULT[rarity_index][0], RARITY_VALUE_MULT[rarity_index][1])
	item.value = int(round(float(base_value) * rarity_mult * (1.0 + mod_sum)))
	return item

# --- the forge (spec 10.2) ------------------------------------------------------

## [town] Raises `item` one rarity step, adding one modifier. The ONLY way an
## item's rarity ever changes after generation (spec 10.2).
##
## The new modifier is drawn from the same MODIFIERS pool, excluding ids the
## item already carries - _generate_typed()'s "never roll the same modifier
## twice on one item" rule has to survive forging, or a player ends up with two
## "+N Damage" lines that party_bonuses() happily sums.
##
## spend_scrap() and spend_gold() are two separate transactions and the
## affordability check above them is not atomic with them; the refund branch is
## what stops a half-charged forge, the worst possible bug on a screen that
## spends the player's savings.
func forge(item: Item) -> bool:
	if item == null or item.rarity >= Item.Rarity.ENHANCED:
		return false
	var cost: Array = Tuning.FORGE_COSTS[item.rarity]
	if GameState.scrap < int(cost[0]) or GameState.gold < int(cost[1]):
		return false
	var pool := _modifier_pool_excluding(item)
	if pool.is_empty():
		return false                       # unreachable: 8 modifiers, 4 slots
	if not GameState.spend_scrap(int(cost[0])):
		return false
	if not GameState.spend_gold(int(cost[1])):
		GameState.add_scrap(int(cost[0]))  # refund - never half-charge
		return false
	var enhanced: bool = item.rarity == Item.Rarity.RARE
	item.modifiers.append(_roll_modifier(pool, enhanced))
	item.rarity = (item.rarity + 1) as Item.Rarity
	item.forge_count += 1
	item.value += int(cost[1])             # spec 10.5 - the gold half only
	GameState.run_stats["items_forged"] = int(GameState.run_stats["items_forged"]) + 1
	EventBus.item_forged.emit(item, item.rarity)
	return true

## The MODIFIERS entries whose id `item` does not already carry.
func _modifier_pool_excluding(item: Item) -> Array:
	var have: Dictionary = {}
	for m: Dictionary in item.modifiers:
		have[m["id"]] = true
	var pool: Array = []
	for def: Dictionary in MODIFIERS:
		if not have.has(def["id"]):
			pool.append(def)
	return pool

## [town] spec 10.3: Enhanced modifiers are the SAME ids as the normal pool,
## with the roll doubled and an `enhanced: true` marker - not a second table.
## party_bonuses() and compare_flyout read `id` / `roll` and need no edit; the
## marker is only what the UI tints.
func _roll_modifier(pool: Array, enhanced: bool) -> Dictionary:
	var def: Dictionary = pool[RNG.randi_range(0, pool.size() - 1)]
	var roll: int = RNG.randi_range(int(def["roll"][0]), int(def["roll"][1]))
	if enhanced:
		roll *= Tuning.FORGE_ENHANCED_MULT
	return {
		"id": def["id"],
		"label": (def["label"] as String) % roll,
		"roll": roll,
		"value_mult": RNG.randf_range(float(def["value_mult"][0]), float(def["value_mult"][1])),
		"enhanced": enhanced,
	}

# --- class-first generation (enemy drops) -----------------------------------

## Every type `hero_class` can wield, in ANY slot. Stays the "all types for a
## class" accessor the slot-aware helpers below are built on (spec 4.4).
func weapon_types_for(hero_class: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for wtype: StringName in ITEM_TYPES:
		if (ITEM_TYPES[wtype]["classes"] as Array).has(hero_class):
			out.append(wtype)
	return out

## [town] The types in `slot` wieldable by some class in `classes`. Built on
## weapon_types_for(), then filtered to the one slot (spec 4.4 helper table).
func types_for_slot(slot: Item.Slot, classes: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for c: StringName in classes:
		for wtype: StringName in weapon_types_for(c):
			if int(ITEM_TYPES[wtype].get("slot", Item.Slot.WEAPON)) == int(slot) and not out.has(wtype):
				out.append(wtype)
	return out

## [town] The equipment slots at least one class in `classes` can fill. Rolling
## the slot over THIS (not all three) is what lets one helper serve both
## generators: the solo warrior gets [WEAPON, ARMOR, TRINKET]; a single-class
## generate_drop(&"mage") gets [WEAPON] and can never land on a slot the mage
## has no type for (spec 4.4, step-4 Q4). Replaces the earlier draft's bare
## _random_equippable_slot().
func _equippable_slots_for(classes: Array[StringName]) -> Array[Item.Slot]:
	var out: Array[Item.Slot] = []
	for s: Item.Slot in [Item.Slot.WEAPON, Item.Slot.ARMOR, Item.Slot.TRINKET]:
		if not types_for_slot(s, classes).is_empty():
			out.append(s)
	return out

## [town] Slot first, then a type within it - the shared body of both
## generators (spec 4.4). Keeping this one function is what stops the two
## generation paths drifting apart again.
func _roll_typed(classes: Array[StringName], rarity_index: int) -> Item:
	var slots := _equippable_slots_for(classes)
	if slots.is_empty():
		# Unreachable while some class in `classes` can wield something. A
		# generated item still beats a crash - the guard generate_drop() has
		# always carried, re-aimed: with no party-derived answer left, fall back
		# to a uniform draw over every type.
		var all: Array = ITEM_TYPES.keys()
		return _generate_typed(all[RNG.randi_range(0, all.size() - 1)], rarity_index)
	var slot: Item.Slot = slots[RNG.randi_range(0, slots.size() - 1)]
	var types := types_for_slot(slot, classes)
	return _generate_typed(types[RNG.randi_range(0, types.size() - 1)], rarity_index)

## The classes a drop can be aimed at, in active_party order (spec 4.5 - was
## PARTY_ORDER). Derived from the type table rather than listed, so a class with
## no wieldable type is excluded automatically instead of silently receiving
## items it cannot use.
func droppable_classes() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in GameState.active_party:
		if not weapon_types_for(id).is_empty():
			out.append(id)
	return out

## One item aimed at `hero_class`. Rarity is the normal §13.2 weighted roll
## raised to `rarity_floor`; the type is drawn slot-first from THAT class's
## fillable slots (spec 4.4). THE ONLY generator that picks a class first - see
## §0.3. Its guarantee is unchanged and now unconditional: a drop is always
## something the target class can wield.
func generate_drop(hero_class: StringName, rarity_floor: int = 0) -> Item:
	# Same RARE ceiling as generate_item_with_rarity() - a drop is never ENHANCED
	# (spec 10.1). Stated as the enum value now that RARITY_WEIGHTS has a fifth,
	# zero-weight entry.
	var rarity: int = maxi(RNG.weighted_index(RARITY_WEIGHTS), clampi(rarity_floor, 0, Item.Rarity.RARE))
	return _roll_typed([hero_class] as Array[StringName], rarity)

# --- shop stock (spec 13.6 / Q14) -------------------------------------------

## The 27-731 gold price spread stays: an unaffordable Rare is a teaser that
## makes the rarity ladder legible. But an all-random roll can put every card
## out of reach, and a dead shop encounter is worse than a predictable one. So
## the stock guarantees a spread rather than price-checking against live gold,
## which would make the shop feel like it was reading the player's wallet.
func generate_shop_stock() -> Array[Item]:
	var stock: Array[Item] = [
		_generate_in_bucket([Item.Rarity.COMMON, Item.Rarity.UNCOMMON]),   # affordable
		generate_item(),                                                    # free roll
		_generate_in_bucket([Item.Rarity.MAGIC, Item.Rarity.RARE]),         # teaser
	]
	# SHOP_ITEMS_FOR_SALE governs the count; the two forced buckets come first and
	# any remainder is free-rolled.
	while stock.size() < Tuning.SHOP_ITEMS_FOR_SALE:
		stock.append(generate_item())
	while stock.size() > Tuning.SHOP_ITEMS_FOR_SALE:
		stock.pop_back()
	stock.shuffle()          # so the expensive card is not always in the same slot
	return stock

## Picks within the bucket using the 13.2 weights renormalised across it.
func _generate_in_bucket(bucket: Array) -> Item:
	var weights: Array[int] = []
	for r: int in bucket:
		weights.append(int(RARITY_WEIGHTS[r]))
	return generate_item_with_rarity(int(bucket[RNG.weighted_index(weights)]))

# --- the blacksmith's expanded shop (spec 7.4) --------------------------------

## [town] The blacksmith's six-card stock: two cheap, two average, two dear.
## Same bucket technique as generate_shop_stock() at twice the width - a SEPARATE
## function rather than a parameter on that one, because test_economy.gd pins
## generate_shop_stock()'s shape (always SHOP_ITEMS_FOR_SALE items, a fixed
## bucket spread) and this stock has different guarantees. ENHANCED never appears
## here - it is forge-only (weight 0, spec 10.1). The result count is
## Tuning.FORGE_SHOP_SLOTS (2 per bucket x 3 buckets).
func generate_forge_stock() -> Array[Item]:
	var stock: Array[Item] = []
	for bucket: Array in [
		[Item.Rarity.COMMON,   Item.Rarity.UNCOMMON],   # cheap
		[Item.Rarity.UNCOMMON, Item.Rarity.MAGIC],      # average
		[Item.Rarity.MAGIC,    Item.Rarity.RARE],       # dear
	]:
		stock.append(_generate_in_bucket(bucket))
		stock.append(_generate_in_bucket(bucket))
	stock.shuffle()
	return stock
