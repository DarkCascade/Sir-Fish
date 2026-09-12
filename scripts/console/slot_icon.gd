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
## the multiplier icon. `slot_purse` is deliberately absent (§5). [armor items]
## `armor_block` is here (a BLOCK icon); `armor_life` is NOT - it is a passive
## max-hp boost read straight off item.modifiers, never a board icon.
const KNOWN_MODIFIER_IDS: Array[StringName] = [
	&"dmg_flat", &"dmg_pct", &"elem_fire", &"elem_ice", &"elem_light",
	&"slot_bolt", &"slot_mend", &"armor_block",
]

## [armor items] BLOCK: an armor icon that grants the party a temporary flat
## damage reduction when it resolves (SlotMachine._grant_block).
enum Kind { BLANK, DAMAGE, DAMAGE_ALL, HEAL, MULT, BLOCK }

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
		&"slot_mend", INNATE_HEAL:
			return Kind.HEAL
		BASE_ARMOR, &"armor_block":
			return Kind.BLOCK
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

## The base slot icon's magnitude - 100% of the item's characteristic value:
## Power for a DAMAGE icon (weapon, trinket), armor_value for a BLOCK icon
## (armor). [armor items] Armor's base icon used to be a percent-of-max-hp
## heal; it is a flat block now.
static func _base_icon_roll(item: Item, kind: Kind) -> int:
	if kind == Kind.BLOCK:
		return item.armor_value()
	return item.power()

## [levels] Every equipped item's guaranteed slot icon (spec §4.3) - a Common
## with zero modifiers still puts exactly one icon in the bag, which is the
## whole fix for a Common contributing nothing.
static func from_item_base(item: Item) -> Dictionary:
	var id := base_for(item.slot())
	return { "id": id, "roll": _base_icon_roll(item, kind_of(id)), "enhanced": false }

## An icon dict from an equipped modifier entry (see Itemizer.MODIFIERS).
## Returns an empty dict for an id with no board icon — callers skip those.
##
## [item power model] The modifier's `roll` is already the final resolved
## magnitude - Itemizer._roll_icon_magnitude() baked it at generation / forge
## time (125-175% of the item's Power for a DAMAGE / DAMAGE_ALL icon, its own
## percent for HEAL / MULT). `_item` is no longer read; the signature stays
## two-arg for the call sites and for the day a per-icon recompute returns.
static func from_modifier(mod: Dictionary, _item: Item = null) -> Dictionary:
	var id := StringName(mod.get("id", &""))
	if not KNOWN_MODIFIER_IDS.has(id):
		return {}
	return {
		"id": id,
		"roll": int(mod.get("roll", 0)),
		"enhanced": bool(mod.get("enhanced", false)),
	}

## An innate icon dict for a hero class: one per living hero, the floor that
## keeps the bag from ever being empty of icons. [content phase 1] The icon id
## comes from GameState.get_class_def(hero_class).innate_icon now - replaces
## the mage/damage ternary SlotIcon.innate_for() used to hardcode (spec §3
## Step 2). A class with no ClassDef (should not happen for a real hero) falls
## back to damage, same floor the old ternary's default arm gave.
## [item power model] `weapon_power` is 100% of the hero's EQUIPPED weapon
## Power (GameState.hero_weapon_power(hero_class)), precomputed by the caller -
## the hero's own stats no longer feed combat. 0 when the hero is unarmed
## (handled later). Only the DAMAGE branch uses it; a HEAL innate keeps its
## flat SLOT_INNATE_HEAL_PCT.
static func innate(hero_class: StringName, weapon_power: int = 0) -> Dictionary:
	var cdef := GameState.get_class_def(hero_class)
	var id: StringName = cdef.innate_icon if cdef != null and cdef.innate_icon != &"" else INNATE_DAMAGE
	var roll: int = weapon_power if id == INNATE_DAMAGE else Tuning.SLOT_INNATE_HEAL_PCT
	return { "id": id, "roll": roll, "enhanced": false, "innate": true }

static func blank() -> Dictionary:
	return { "id": BLANK, "roll": 0, "enhanced": false }

static func is_blank(icon: Dictionary) -> bool:
	return kind_of(StringName(icon.get("id", &""))) == Kind.BLANK

## The chip texture path for an icon id, or "" if none applies (blank). Innate
## ids borrow the nearest modifier chip.
static func chip_path(id: StringName) -> String:
	# [armor items] No reliquary chip art for block / life yet - borrow the
	# shield and heart glyphs from the item card's stat-tile set.
	if id == BASE_ARMOR or id == &"armor_block":
		return "res://assets/icons/glyph_shield.png"
	if id == &"armor_life":
		return "res://assets/icons/glyph_heal.png"
	var key := id
	if id == INNATE_DAMAGE or id == BASE_WEAPON:
		key = &"dmg_flat"
	elif id == INNATE_HEAL:
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
		BASE_ARMOR, &"armor_block": return "Block"
		&"armor_life": return "Life"
		BASE_TRINKET: return "Focus"
	return ""

## Percent-magnitude icons render their roll as "+N%"; the rest as "+N".
## [armor items] BASE_ARMOR / armor_block are flat now (a block amount, not a
## percent); armor_life IS a percent (of max hp).
static func is_percent(id: StringName) -> bool:
	return id == &"dmg_pct" or id == &"slot_mend" or id == INNATE_HEAL or id == &"armor_life"
