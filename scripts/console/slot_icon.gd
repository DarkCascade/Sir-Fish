class_name SlotIcon
extends RefCounted
## [slot phase 2] The slot's icon vocabulary, in one place.
##
## An "icon" is a plain Dictionary — { "id": StringName, "roll": int,
## "enhanced": bool } — so it round-trips through arrays, the reel strip and the
## party modal without a node behind it. Every other property (what it does, its
## element tint, its chip art) is DERIVED from `id` here, never stored twice.
##
## The id vocabulary IS Itemizer.MODIFIERS (one equipped modifier = one icon),
## plus two innate ids with no item behind them (§2) and a blank. `slot_purse`
## and any other unrecognised id resolve to NO icon and must not crash — callers
## filter on KNOWN_MODIFIER_IDS before building an icon (§5 migration rule).

## Innate icons: one per living hero, magnitude fixed in Tuning (§2).
const INNATE_DAMAGE := &"innate_dmg"
const INNATE_HEAL := &"innate_heal"
const BLANK := &""

## [levels] One base icon per equipment slot, contributed by EVERY equipped
## item regardless of rarity (levels & stats spec §4.3) - the fix for a Common
## putting zero icons in the bag (RARITY_MOD_COUNT[COMMON] == 0). Slot-flavoured
## rather than identical: a weapon strikes, armor wards (heals), a trinket
## carries the magic-flavoured strike, so the three slots still read
## differently on the board.
const BASE_WEAPON := &"base_weapon"
const BASE_ARMOR := &"base_armor"
const BASE_TRINKET := &"base_trinket"

## The equipped-modifier ids that map to a board icon. `dmg_pct` is here — it is
## the multiplier icon. `slot_purse` is deliberately absent (§5).
const KNOWN_MODIFIER_IDS: Array[StringName] = [
	&"dmg_flat", &"dmg_pct", &"elem_fire", &"elem_ice", &"elem_light",
	&"slot_bolt", &"slot_mend",
]

enum Kind { BLANK, DAMAGE, DAMAGE_ALL, HEAL, MULT }

## The reliquary chip art, one PNG per modifier id (already on disk, drawn by the
## compare flyout's stat chips). The two innate ids borrow the closest chip.
const _CHIP_DIR := "res://assets/ui/reliquary/"

static func kind_of(id: StringName) -> Kind:
	match id:
		&"dmg_flat", &"elem_fire", &"elem_ice", &"elem_light", INNATE_DAMAGE, \
		BASE_WEAPON, BASE_TRINKET:
			return Kind.DAMAGE
		&"slot_bolt":
			return Kind.DAMAGE_ALL
		&"slot_mend", INNATE_HEAL, BASE_ARMOR:
			return Kind.HEAL
		&"dmg_pct":
			return Kind.MULT
		_:
			return Kind.BLANK

## "" for a non-elemental icon, else "fire" / "ice" / "light" — the key
## GameState.element_color() and the battle overlay already speak.
static func element_of(id: StringName) -> StringName:
	match id:
		&"elem_fire": return &"fire"
		&"elem_ice": return &"ice"
		&"elem_light": return &"light"
	return &""

## The innate icon id a living hero of `hero_class` contributes (§2): the mage
## heals, everyone else deals damage. Unknown classes fall back to damage so the
## bag is never left without a floor.
static func innate_for(hero_class: StringName) -> StringName:
	return INNATE_HEAL if hero_class == &"mage" else INNATE_DAMAGE

static func is_innate(id: StringName) -> bool:
	return id == INNATE_DAMAGE or id == INNATE_HEAL

## [levels] The base icon id `slot` contributes (spec §4.3).
static func base_for(slot: Item.Slot) -> StringName:
	match slot:
		Item.Slot.ARMOR: return BASE_ARMOR
		Item.Slot.TRINKET: return BASE_TRINKET
		_: return BASE_WEAPON

static func is_base(id: StringName) -> bool:
	return id == BASE_WEAPON or id == BASE_ARMOR or id == BASE_TRINKET

## [levels] The item-level contribution to an icon of `kind`'s magnitude -
## three different units, never interchangeable. This is the one seam that
## dispatches on Kind so from_item_base() and from_modifier() below never have
## to.
##
## HEAL reads `roll` as a PERCENT OF MAX HP (slot_machine._heal_lowest());
## feeding base_power()'s unbounded, level-scaling flat value (up to 180 at
## level 30) into that field would mean a single mid-level armor piece
## instantly full-heals every time it resolves - see Item.base_heal_pct().
##
## MULT (dmg_pct) reads `roll` as a percent BOOST applied to every damage icon
## resolving this spin, item's own included. Adding this item's base_power()
## to it would compound multiplicatively on top of damage icons that are
## already scaled by their own item levels - dmg_pct stays exactly the
## modifier's own rolled percent, zero item-level contribution.
static func _item_level_contribution(item: Item, kind: Kind) -> int:
	match kind:
		Kind.HEAL: return item.base_heal_pct()
		Kind.MULT: return 0
		_: return item.base_power()

## [levels] Every equipped item's guaranteed slot icon (spec §4.3) - a Common
## with zero modifiers still puts exactly one icon in the bag, which is the
## whole fix for a Common contributing nothing.
static func from_item_base(item: Item) -> Dictionary:
	var id := base_for(item.slot())
	return { "id": id, "roll": _item_level_contribution(item, kind_of(id)), "enhanced": false }

## An icon dict from an equipped modifier entry (see Itemizer.MODIFIERS).
## Returns an empty dict for an id with no board icon — callers skip those.
##
## [levels] `item` is required now: every icon's resolved magnitude is the
## item's own level contribution PLUS the modifier's own rolled value (spec
## §4.4), so even a modifier icon carries its item's level - `slot_mend` is
## HEAL-kind, so it takes base_heal_pct(), same unit rule as the armor base
## icon. The raw modifier roll survives separately as `mod_roll`, for the party
## modal's per-item readout ("+4 Damage" on the card) to stay truthfully
## sourced from what the item itself rolled, distinct from what resolves on
## the board.
static func from_modifier(mod: Dictionary, item: Item) -> Dictionary:
	var id := StringName(mod.get("id", &""))
	if not KNOWN_MODIFIER_IDS.has(id):
		return {}
	var mod_roll := int(mod.get("roll", 0))
	return {
		"id": id,
		"roll": _item_level_contribution(item, kind_of(id)) + mod_roll,
		"mod_roll": mod_roll,
		"enhanced": bool(mod.get("enhanced", false)),
	}

## An innate icon dict for a hero class. Magnitude is the fixed Tuning constant —
## damage as a flat value, heal as a percent of max hp.
## [levels] `weapon_power` is the hero's own RAW Weapon Power at their current
## level (GameState.hero_weapon_power(hero_class)) - precomputed by the caller
## rather than looked up here, since a caller mid-combat and one in town
## resolve "the hero's level" from different places (spec §4.4). Only the
## DAMAGE branch (a non-mage hero) uses it; the mage's heal keeps its flat
## SLOT_INNATE_HEAL_PCT, unrelated to weapon power.
static func innate(hero_class: StringName, weapon_power: int = 0) -> Dictionary:
	var id := innate_for(hero_class)
	var roll: int
	if id == INNATE_DAMAGE:
		roll = int(round(float(weapon_power) * Tuning.SLOT_INNATE_POWER_FRACTION))
	else:
		roll = Tuning.SLOT_INNATE_HEAL_PCT
	return { "id": id, "roll": roll, "enhanced": false, "innate": true }

static func blank() -> Dictionary:
	return { "id": BLANK, "roll": 0, "enhanced": false }

static func is_blank(icon: Dictionary) -> bool:
	return kind_of(StringName(icon.get("id", &""))) == Kind.BLANK

## The chip texture path for an icon id, or "" if none applies (blank). Innate
## ids borrow the nearest modifier chip.
static func chip_path(id: StringName) -> String:
	var key := id
	if id == INNATE_DAMAGE or id == BASE_WEAPON:
		key = &"dmg_flat"
	elif id == INNATE_HEAL or id == BASE_ARMOR:
		key = &"slot_mend"
	elif id == BASE_TRINKET:
		key = &"elem_light"
	if key == BLANK:
		return ""
	return "%schip_%s.png" % [_CHIP_DIR, key]

static func chip_texture(id: StringName) -> Texture2D:
	var path := chip_path(id)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## Short label for the win banner / readouts. "Sword", "Fire", "Chain", "Mend",
## "Boost", "Heal".
static func short_label(id: StringName) -> String:
	match id:
		&"dmg_flat", INNATE_DAMAGE: return "Damage"
		&"dmg_pct": return "Boost"
		&"elem_fire": return "Fire"
		&"elem_ice": return "Ice"
		&"elem_light": return "Lightning"
		&"slot_bolt": return "Chain"
		&"slot_mend", INNATE_HEAL: return "Mend"
		BASE_WEAPON: return "Strike"
		BASE_ARMOR: return "Ward"
		BASE_TRINKET: return "Focus"
	return ""

## Percent-magnitude icons render their roll as "+N%"; the rest as "+N".
## [levels] BASE_ARMOR heals a percent of max hp, same shape as slot_mend /
## INNATE_HEAL (spec §4.3).
static func is_percent(id: StringName) -> bool:
	return id == &"dmg_pct" or id == &"slot_mend" or id == INNATE_HEAL or id == BASE_ARMOR
