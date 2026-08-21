extends Node
## Itemizer — the only place items are created (spec 13).

const WEAPON_TYPES := {
	&"axe":    { "base_value": 20, "nouns": ["Axe", "Hatchet", "Cleaver", "Chopper"] },
	&"sword":  { "base_value": 22, "nouns": ["Sword", "Blade", "Saber", "Longsword"] },
	&"bow":    { "base_value": 20, "nouns": ["Bow", "Longbow", "Shortbow", "Recurve"] },
	&"dagger": { "base_value": 18, "nouns": ["Dagger", "Knife", "Dirk", "Shiv"] },
	&"staff":  { "base_value": 25, "nouns": ["Staff", "Rod", "Cane", "Scepter"] },
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
const RARITY_WEIGHTS := [50, 30, 15, 5]
const RARITY_MOD_COUNT := [0, 1, 2, 3]
const RARITY_VALUE_MULT := [
	[1.0, 1.0],
	[1.6, 2.2],
	[2.8, 3.6],
	[4.5, 6.0],
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
func generate_item_with_rarity(rarity_index: int) -> Item:
	rarity_index = clampi(rarity_index, 0, 3)
	var item := Item.new()
	item.kind = Item.Kind.WEAPON      # the only kind generated in the demo (spec 13.7)

	var types: Array = WEAPON_TYPES.keys()
	var wtype: StringName = types[RNG.randi_range(0, types.size() - 1)]
	item.weapon_type = wtype

	item.rarity = rarity_index as Item.Rarity

	var nouns: Array = WEAPON_TYPES[wtype]["nouns"]
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

	var base_value: int = int(WEAPON_TYPES[wtype]["base_value"])
	var rarity_mult: float = RNG.randf_range(
		RARITY_VALUE_MULT[rarity_index][0], RARITY_VALUE_MULT[rarity_index][1])
	item.value = int(round(float(base_value) * rarity_mult * (1.0 + mod_sum)))
	return item

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
