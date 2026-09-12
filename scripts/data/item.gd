class_name Item
extends Resource

## COMMON..RARE are the rolled rarities (Itemizer.RARITY_WEIGHTS). ENHANCED is
## [town]: forge-only, never generated (its weight is 0), reached only by walking
## an item up the full ladder (spec 10.1 / 10.2). Four index-addressed arrays
## are keyed by this enum and must all carry an ENHANCED slot -
## Item.rarity_name(), Tuning.RARITY_COLORS, and Itemizer's RARITY_WEIGHTS /
## RARITY_MOD_COUNT / RARITY_VALUE_MULT.
##
## [item power model] The UNCOMMON tier was removed - the forge ladder is three
## rungs now (Common -> Magic -> Rare -> Enhanced), each adding one slot icon.
## A saved item stores rarity as a raw int, so this reindex is a save-breaking
## change: SaveGame.VERSION was bumped and pre-existing saves are rejected.
enum Rarity { COMMON, MAGIC, RARE, ENHANCED }
enum Kind { WEAPON, POTION, RELIC }

## [town] Which of the hero's three equipment slots this item occupies (spec
## 4.1). A separate axis from `kind` (WEAPON/POTION/RELIC), which is left alone -
## overloading `kind` to carry a slot would break item_glyph.gd's kind-based
## fallback. DERIVED from weapon_type via Itemizer.ITEM_TYPES (slot()), never
## stored, for the reason usable_by() derives its classes the same way: a second
## copy of the mapping is a second thing to drift.
enum Slot { WEAPON, ARMOR, TRINKET }

@export var display_name: String = ""         # generated, e.g. "Fat Knife"
## Every generated item - armor and trinkets included - keeps Kind.WEAPON
## (spec 4.1, step-4 Q7). Three derivations read it: usable_by() early-returns
## empty unless kind == WEAPON, type_name()'s "Helm" comes off the same branch,
## and the shop rows feed it to the glyph. Until POTION / RELIC generation
## exists (spec 15) `kind` effectively means "was generated" and slot() carries
## the real classification.
@export var kind: Kind = Kind.WEAPON
@export var rarity: Rarity = Rarity.COMMON
## The item's type id, keying Itemizer.ITEM_TYPES. Named `weapon_type` for
## history; since [town] it also names armor and trinket types. The table it
## keys is what decides which slot the item fills (slot()). Empty if not a
## generated item.
@export var weapon_type: StringName = &""
@export var modifiers: Array[Dictionary] = [] # [{ "id": &"dmg_flat", "label": "+4 Damage", "value_mult": 0.42 }, ...]
@export var value: int = 0                    # computed intrinsic gold value
## Which hero currently has this equipped, or &"" if none. A StringName rather
## than a bool because equipping is per-hero - a shared-usable_by() type still
## needs to say WHICH of its eligible classes actually holds it, not just that
## it is held.
##
## [town] A hero now wears one item per Item.Slot (spec 4.3), not one item
## total. This field deliberately does NOT record the slot: it is recoverable
## from the item's own type via slot(), so an item can never be ambiguous about
## which slot it fills - which is why three slots needed no new field here.
@export var equipped_by: StringName = &""

## [town] How many times this item has been through the forge (spec 10.2, 10.4).
## Not derivable: rarity alone cannot say whether a Rare was found or forged up
## from Common. Part of the save format (spec 2.4). The forge that increments it
## lands with spec 7.3 - declared now, at 0, so to_dict()/from_dict() can cover
## the whole item this step (spec 14 step 2).
@export var forge_count: int = 0

## [levels] The level this item was made at - the encounter that dropped it, or
## the shop tier that stocked it (Itemizer's five generators). NEVER changes
## after generation: the forge raises rarity and adds modifiers, it does not
## re-date an item (levels & stats spec §4.1 / §5.3). This is what lets a
## Common from deep content out-damage an Enhanced forged in the shallows.
@export var level: int = 1

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
		"level": level,
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
	item.level = int(data.get("level", 1))
	return item

func subtitle() -> String:
	# "Lv 5 Magic Sword - Warrior". The class half is what makes an item legible
	# as "this one is for someone" while equipping does not exist to enforce it.
	# Weapons carry the swing number, armor carries its flat damage reduction.
	var head := "Lv %d %s %s" % [level, rarity_name(), type_name()]
	if slot() == Slot.WEAPON:
		head += "  ·  %d dmg" % power()
	elif slot() == Slot.ARMOR:
		head += "  ·  %d armor" % armor_value()
	return "%s - %s" % [head, class_label()]

## [item power model] A weapon / trinket's Power at its level: the type's
## authored base (ITEM_TYPES[type].power) times item level. The base slot icon
## is worth 100% of this; each rarity icon rolls 125-175% of it. Weapons
## display it as "Weapon Damage" and it is the entire magnitude of a hero's
## swing. 0 for armor (which has no `power` row - see armor_value()).
func power() -> int:
	var entry: Dictionary = Itemizer.ITEM_TYPES.get(weapon_type, {})
	return int(entry.get("power", 0)) * maxi(level, 1)

## [armor items] An armor piece's flat damage reduction at its level -
## ITEM_TYPES[type].armor times item level. Applied to the wearer while
## equipped (Combatant.armor) and read as 100% by the base BLOCK icon; a block
## modifier rolls 125-175% of it. 0 for weapons / trinkets.
func armor_value() -> int:
	var entry: Dictionary = Itemizer.ITEM_TYPES.get(weapon_type, {})
	return int(entry.get("armor", 0)) * maxi(level, 1)

## [armor items] Percent added to the wearer's max hp by this item's `armor_life`
## modifiers (never a board icon - read straight off the modifier list).
func life_bonus_pct() -> int:
	var total := 0
	for m: Dictionary in modifiers:
		if StringName(m.get("id", &"")) == &"armor_life":
			total += int(m.get("roll", 0))
	return total

## Which hero classes can wield this item. DERIVED from the weapon type rather
## than stored on the resource, for the reason CombatantStats.required_anims()
## gives: a second copy of the mapping is a second thing to drift. Empty for a
## kind with no weapon type, so potions and relics answer sensibly the day they
## exist.
##
## [content phase 1] Reads Itemizer.classes_for_type() now, not an
## ITEM_TYPES[...]["classes"] entry - the mapping moved onto each class's own
## ClassDef.item_types (spec §3 Step 2b).
func usable_by() -> Array[StringName]:
	if kind != Kind.WEAPON or weapon_type == &"":
		return []
	return Itemizer.classes_for_type(weapon_type)

## [town] Which equipment slot this item fills, from its type's ITEM_TYPES
## entry (spec 4.1). Defaults to WEAPON for an unknown / empty type so a
## malformed item still answers sensibly rather than erroring.
func slot() -> Slot:
	var entry: Dictionary = Itemizer.ITEM_TYPES.get(weapon_type, {})
	return entry.get("slot", Slot.WEAPON) as Slot

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

## The name of an arbitrary rarity index - so a caller that needs the name of a
## rarity OTHER than this item's own (e.g. blacksmith.gd's _refresh_forge_card()
## naming the step's destination, rarity + 1) has one owner for the array
## instead of a copy (D4).
static func rarity_name_for(r: int) -> String:
	return ["Common", "Magic", "Rare", "Enhanced"][r]

func rarity_name() -> String:
	return rarity_name_for(rarity)

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

## [town] What scrapping this item at the blacksmith yields, in scrap. A quarter
## of its gold sell price (Tuning.SCRAP_RECLAIM_RATE) - a 100 G item becomes 25
## scrap.
func scrap_value() -> int:
	return int(round(float(sell_price()) * Tuning.SCRAP_RECLAIM_RATE))
