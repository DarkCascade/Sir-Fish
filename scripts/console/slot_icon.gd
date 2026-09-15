class_name SlotIcon
extends RefCounted
## [icons phase 2] The slot's icon vocabulary, in one place.
##
## An "icon" is a plain Dictionary — { "id": StringName, "roll": int,
## "enhanced": bool } — so it round-trips through arrays, the reel strip and the
## party modal without a node behind it. Every other property (what it does, its
## element tint, its chip art) is DERIVED from `id` here, never stored twice.
##
## The id vocabulary IS Itemizer.MODIFIERS (one equipped modifier = one icon),
## plus two innate ids with no item behind them (§2) and a blank. Any
## unrecognised id (a retired one from a pre-rework save) resolves to NO icon
## and must not crash — callers filter on KNOWN_MODIFIER_IDS before building an
## icon.

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

## [icons phase 2] The full rollable-modifier vocabulary. Warrior weapons roll
## the three elements plus bleed; ranger weapons roll bomb_arrow; mage weapons
## roll lightning_blast; armor rolls block/mend; trinkets roll crit plus one
## class-exclusive ultimate. See Itemizer.MODIFIERS for the pool/class filter.
const KNOWN_MODIFIER_IDS: Array[StringName] = [
	&"elem_fire", &"elem_ice", &"elem_light", &"bleed",
	&"bomb_arrow", &"lightning_blast",
	&"armor_block", &"slot_mend",
	&"crit", &"cleave", &"rain", &"thunderburst",
]

## [icons phase 2] BLOCK: an armor icon that grants the party a temporary flat
## damage reduction when it resolves (SlotMachine._grant_block). BLEED applies
## a damage-over-time debuff to one enemy rather than dealing damage itself.
## CLEAVE / RAIN set a pending "next attack" buff rather than resolving
## anything immediately (SlotMachine._pending_cleave / _pending_rain).
## BOMB_ARROW / THUNDERBURST are both hit-all-enemies AoEs, kept as separate
## Kinds (rather than one shared DAMAGE_ALL, which no icon uses any more) purely
## so each has its own single-class executor - see class_def.gd's `executes`.
## These are raw ints in every ClassDef.tres's `executes` array (Godot can't
## serialise a typed array of a nested enum) - re-point every .tres if this
## ordering ever changes.
enum Kind { BLANK, DAMAGE, HEAL, BLOCK, BLEED, CLEAVE, RAIN, BOMB_ARROW, THUNDERBURST }

## The reliquary chip art, one PNG per modifier id (already on disk, drawn by the
## compare flyout's stat chips). The two innate ids borrow the closest chip.
const _CHIP_DIR := "res://assets/ui/reliquary/"

static func kind_of(id: StringName) -> Kind:
	match id:
		&"elem_fire", &"elem_ice", &"elem_light", &"lightning_blast", &"crit", \
		INNATE_DAMAGE, BASE_WEAPON, BASE_TRINKET:
			return Kind.DAMAGE
		&"bleed":
			return Kind.BLEED
		&"cleave":
			return Kind.CLEAVE
		&"rain":
			return Kind.RAIN
		&"bomb_arrow":
			return Kind.BOMB_ARROW
		&"thunderburst":
			return Kind.THUNDERBURST
		&"slot_mend", INNATE_HEAL:
			return Kind.HEAL
		BASE_ARMOR, &"armor_block":
			return Kind.BLOCK
		_:
			return Kind.BLANK

## "" for a non-elemental icon, else "fire" / "ice" / "light" — the key
## GameState.element_color() and the battle overlay already speak.
## `lightning_blast` and `thunderburst` tint as lightning too - both are
## lightning-flavoured, stronger variants of elem_light.
static func element_of(id: StringName) -> StringName:
	match id:
		&"elem_fire": return &"fire"
		&"elem_ice": return &"ice"
		&"elem_light", &"lightning_blast", &"thunderburst": return &"light"
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
	# [armor items] No reliquary chip art for block yet - borrow the shield
	# glyph from the item card's stat-tile set.
	if id == BASE_ARMOR or id == &"armor_block":
		return "res://assets/icons/glyph_shield.png"
	var key := id
	# [icons phase 2] The generic attack icon (base weapon / the innate damage
	# floor) and the trinket's base strike still borrow the old dmg_flat /
	# elem_light chip art on disk - that art is orphaned as a MODIFIER id but
	# the files themselves are harmless to keep pointing at for a plain
	# "damage" and "magic strike" look until the new icons get their own art.
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

## [slot ui phase 3] The board's own glyph art (assets/ui/slot/glyph_*.png):
## transparent gold emblems that SlotSymbol draws on a procedural tile. Kept
## apart from chip_path() on purpose - the item cards, compare flyout and item
## rows still draw the reliquary chips (the party modal and the board use these).
## An id with no glyph on disk
## yet returns null, and SlotSymbol falls back to its chip, so the set can land
## one file at a time. Innate and base ids share their nearest glyph, as chips do;
## BASE_TRINKET gets its own key, since borrowing the lightning art made a
## trinket indistinguishable from elem_light on the board.
const _GLYPH_DIR := "res://assets/ui/slot/"

static func board_glyph_path(id: StringName) -> String:
	var key := id
	match id:
		INNATE_DAMAGE, BASE_WEAPON: key = &"dmg_flat"
		INNATE_HEAL: key = &"slot_mend"
		BASE_ARMOR: key = &"armor_block"
	if key == BLANK:
		return ""
	return "%sglyph_%s.png" % [_GLYPH_DIR, key]

static func board_glyph_texture(id: StringName) -> Texture2D:
	var path := board_glyph_path(id)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## Short label for the win banner / readouts.
static func short_label(id: StringName) -> String:
	match id:
		INNATE_DAMAGE: return "Damage"
		&"elem_fire": return "Fire"
		&"elem_ice": return "Ice"
		&"elem_light": return "Lightning"
		&"bleed": return "Bleed"
		&"bomb_arrow": return "Bomb Arrow"
		&"lightning_blast": return "Lightning Blast"
		&"slot_mend", INNATE_HEAL: return "Mend"
		BASE_WEAPON: return "Strike"
		BASE_ARMOR, &"armor_block": return "Block"
		BASE_TRINKET: return "Focus"
		&"crit": return "Crit"
		&"cleave": return "Cleave"
		&"rain": return "Rain of Arrows"
		&"thunderburst": return "Thunderburst"
	return ""

## Percent-magnitude icons render their roll as "+N%"; the rest as "+N".
## [icons phase 2] slot_mend is the only remaining percent icon - everything
## else (damage, block, bleed, the trinket ultimates) is a flat magnitude.
static func is_percent(id: StringName) -> bool:
	return id == &"slot_mend" or id == INNATE_HEAL
