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
		&"dmg_flat", &"elem_fire", &"elem_ice", &"elem_light", INNATE_DAMAGE:
			return Kind.DAMAGE
		&"slot_bolt":
			return Kind.DAMAGE_ALL
		&"slot_mend", INNATE_HEAL:
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

## An icon dict from an equipped modifier entry (see Itemizer.MODIFIERS). Returns
## an empty dict for an id with no board icon — callers skip those.
static func from_modifier(mod: Dictionary) -> Dictionary:
	var id := StringName(mod.get("id", &""))
	if not KNOWN_MODIFIER_IDS.has(id):
		return {}
	return {
		"id": id,
		"roll": int(mod.get("roll", 0)),
		"enhanced": bool(mod.get("enhanced", false)),
	}

## An innate icon dict for a hero class. Magnitude is the fixed Tuning constant —
## damage as a flat value, heal as a percent of max hp.
static func innate(hero_class: StringName) -> Dictionary:
	var id := innate_for(hero_class)
	var roll := Tuning.SLOT_INNATE_DAMAGE if id == INNATE_DAMAGE else Tuning.SLOT_INNATE_HEAL_PCT
	return { "id": id, "roll": roll, "enhanced": false, "innate": true }

static func blank() -> Dictionary:
	return { "id": BLANK, "roll": 0, "enhanced": false }

static func is_blank(icon: Dictionary) -> bool:
	return kind_of(StringName(icon.get("id", &""))) == Kind.BLANK

## The chip texture path for an icon id, or "" if none applies (blank). Innate
## ids borrow the nearest modifier chip.
static func chip_path(id: StringName) -> String:
	var key := id
	if id == INNATE_DAMAGE:
		key = &"dmg_flat"
	elif id == INNATE_HEAL:
		key = &"slot_mend"
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
	return ""

## Percent-magnitude icons render their roll as "+N%"; the rest as "+N".
static func is_percent(id: StringName) -> bool:
	return id == &"dmg_pct" or id == &"slot_mend" or id == INNATE_HEAL
