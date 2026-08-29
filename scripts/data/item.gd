class_name Item
extends Resource

## COMMON..RARE are the rolled rarities (Itemizer.RARITY_WEIGHTS). ENHANCED is
## [town]: forge-only, never generated (its weight is 0), reached only by walking
## an item up the full ladder (spec 10.1 / 10.2). Five index-addressed arrays
## are keyed by this enum and must all carry an ENHANCED slot -
## Item.rarity_name(), Tuning.RARITY_COLORS, and Itemizer's RARITY_WEIGHTS /
## RARITY_MOD_COUNT / RARITY_VALUE_MULT.
enum Rarity { COMMON, UNCOMMON, MAGIC, RARE, ENHANCED }
enum Kind { WEAPON, POTION, RELIC }

@export var display_name: String = ""         # generated, e.g. "Fat Knife"
@export var kind: Kind = Kind.WEAPON
@export var rarity: Rarity = Rarity.COMMON
@export var weapon_type: StringName = &""     # axe|sword|bow|dagger|staff ; empty if not a weapon
@export var modifiers: Array[Dictionary] = [] # [{ "id": &"dmg_flat", "label": "+4 Damage", "value_mult": 0.42 }, ...]
@export var value: int = 0                    # computed intrinsic gold value
## Which hero currently has this equipped, or &"" if none. A StringName rather
## than a bool because equipping is per-hero (one item per hero, GameState.
## equip_item()) - a shared-usable_by() type still needs to say WHICH of its
## eligible classes actually holds it, not just that it is held.
@export var equipped_by: StringName = &""

## [town] How many times this item has been through the forge (spec 10.2, 10.4).
## Not derivable: rarity alone cannot say whether a Rare was found or forged up
## from Common. Part of the save format (spec 2.4). The forge that increments it
## lands with spec 7.3 - declared now, at 0, so to_dict()/from_dict() can cover
## the whole item this step (spec 14 step 2).
@export var forge_count: int = 0

## [town] A flat dictionary of primitives for the profile save (spec 2.4).
## Explicit rather than ResourceSaver on the resource: a saved .tres embeds this
## script's path, so moving item.gd a year from now would silently invalidate
## every player's save. Covers exactly the @exported fields; usable_by(),
## prices and (later) slot() are all recomputed on load, never stored.
func to_dict() -> Dictionary:
	var mods: Array[Dictionary] = []
	for m: Dictionary in modifiers:
		mods.append(m.duplicate(true))
	return {
		"display_name": display_name,
		"kind": int(kind),
		"rarity": int(rarity),
		"weapon_type": weapon_type,
		"modifiers": mods,
		"value": value,
		"equipped_by": equipped_by,
		"forge_count": forge_count,
	}

## Rebuilds an Item from to_dict()'s output. `modifiers` is copied with
## duplicate(true) so a loaded item never aliases the dictionary literals in
## Itemizer.MODIFIERS (spec 2.4). Unknown / missing keys fall back to a fresh
## Item's defaults rather than crashing - a partially-readable save is still
## rejected wholesale by SaveGame.load_profile()'s version gate, so this only
## has to be total, not strict.
static func from_dict(data: Dictionary) -> Item:
	var item := Item.new()
	item.display_name = String(data.get("display_name", ""))
	item.kind = int(data.get("kind", Kind.WEAPON)) as Kind
	item.rarity = int(data.get("rarity", Rarity.COMMON)) as Rarity
	item.weapon_type = StringName(data.get("weapon_type", &""))
	var mods: Array[Dictionary] = []
	for m: Dictionary in data.get("modifiers", []):
		mods.append((m as Dictionary).duplicate(true))
	item.modifiers = mods
	item.value = int(data.get("value", 0))
	item.equipped_by = StringName(data.get("equipped_by", &""))
	item.forge_count = int(data.get("forge_count", 0))
	return item

func subtitle() -> String:
	# "Magic Sword - Warrior". The class half is what makes an item legible as
	# "this one is for someone" while equipping does not exist to enforce it.
	return "%s %s - %s" % [rarity_name(), type_name(), class_label()]

## Which hero classes can wield this item. DERIVED from the weapon type rather
## than stored on the resource, for the reason CombatantStats.required_anims()
## gives: a second copy of the mapping is a second thing to drift. Empty for a
## kind with no weapon type, so potions and relics answer sensibly the day they
## exist.
##
## Built by iteration rather than returned straight from the table because
## WEAPON_TYPES' inline arrays are untyped Array, which GDScript will not
## assign to an Array[StringName] return.
func usable_by() -> Array[StringName]:
	var out: Array[StringName] = []
	if kind != Kind.WEAPON or weapon_type == &"":
		return out
	var entry: Dictionary = Itemizer.WEAPON_TYPES.get(weapon_type, {})
	for c: StringName in entry.get("classes", []):
		out.append(c)
	return out

## "Warrior", or "Warrior / Ranger" for a shared type. "Anyone" when nothing
## restricts the item - which is what an unrestricted kind should read as, not
## an empty string that renders as a gap in the shop card.
func class_label() -> String:
	var classes := usable_by()
	if classes.is_empty():
		return "Anyone"
	var names: PackedStringArray = []
	for c: StringName in classes:
		names.append(String(c).capitalize())
	return " / ".join(names)

func rarity_name() -> String:
	return ["Common", "Uncommon", "Magic", "Rare", "Enhanced"][rarity]

func type_name() -> String:
	# Weapons read as their weapon type ("Sword"); the deferred kinds fall back
	# to the kind name, so "Magic Potion" / "Rare Relic" work the day they exist.
	if kind == Kind.WEAPON and weapon_type != &"":
		return String(weapon_type).capitalize()
	return ["Weapon", "Potion", "Relic"][kind]

func rarity_color() -> Color:
	return Tuning.RARITY_COLORS[rarity]

func buy_price() -> int:
	return int(round(float(value) * Tuning.SHOP_BUY_MARKUP))

func sell_price() -> int:
	return int(round(float(value) * Tuning.SHOP_SELL_RATE))

## Single letter used by the inventory chip (spec 17.2).
func type_initial() -> String:
	if weapon_type == &"":
		return "?"
	if weapon_type == &"staff":
		return "T"
	return String(weapon_type).substr(0, 1).to_upper()
