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
## plus one innate id with no item behind it (§2) and a blank. Any
## unrecognised id (a retired one from a pre-rework save) resolves to NO icon
## and must not crash — callers filter on KNOWN_MODIFIER_IDS before building an
## icon.

## Innate icons: one per living hero, magnitude fixed in Tuning (§2).
## [backlog P7] Every hero's innate icon is damage now. The mage's used to be a
## percent heal ("Mend"); healing is her invokable Healing Aura special, and the
## slot no longer heals at all (see HEAL's removal from Kind).
const INNATE_DAMAGE := &"innate_dmg"
const BLANK := &""

## [levels] One base icon per equipment slot, contributed by EVERY equipped
## item regardless of rarity (levels & stats spec §4.3) - the fix for a Common
## putting zero icons in the bag (RARITY_MOD_COUNT[COMMON] == 0). Slot-flavoured
## rather than identical: a weapon strikes, armor wards (blocks), a trinket
## carries the magic-flavoured strike, so the three slots still read
## differently on the board.
const BASE_WEAPON := &"base_weapon"
const BASE_ARMOR := &"base_armor"
const BASE_TRINKET := &"base_trinket"

## [icons phase 2] The modifier ids that put an icon on the board. Warrior
## weapons roll the three elements; ranger weapons roll bomb_arrow; mage
## weapons roll lightning_blast; armor rolls block; each trinket rolls its
## class's special charge. See Itemizer.MODIFIERS for the pool/class filter.
##
## [slot vocabulary] bleed and crit are item modifiers but NOT board icons any
## more - they are wearer stats (STAT_MODIFIER_IDS below), so from_modifier()
## drops them and they never reach the bag.
const KNOWN_MODIFIER_IDS: Array[StringName] = [
	&"elem_fire", &"elem_ice", &"elem_light",
	&"bomb_arrow", &"lightning_blast",
	&"armor_block",
	&"cleave", &"rain", &"thunderburst",
]

## [slot vocabulary] Modifiers that change the wearer rather than the board:
## `bleed` is a chance for the wearer's swings to open a bleed
## (GameState.hero_bleed), `crit` a percent chance for all of the wearer's
## attacks to deal double (GameState.hero_crit_chance).
const STAT_MODIFIER_IDS: Array[StringName] = [&"bleed", &"crit"]

## [slot vocabulary] The board speaks six categories, and only six: a weapon
## strike (drawn as the owner's weapon), the three elements, block, and a
## special charge (drawn as the owner's profile on a gold coin). Every icon id
## maps onto one of them, and the payline matches on the CATEGORY, not the id -
## a sword strike, a bow strike and a staff strike are three of a kind.
const CAT_DAMAGE := &"damage"
const CAT_FIRE := &"fire"
const CAT_ICE := &"ice"
const CAT_LIGHTNING := &"lightning"
const CAT_BLOCK := &"block"
const CAT_CHARGE := &"charge"

## [slot vocabulary] Four kinds now, from eight. BLEED is a wearer stat, and
## CLEAVE / RAIN / BOMB_ARROW / THUNDERBURST all became CHARGE: landing one only
## fills its owner's special meter (Tuning.SLOT_CHARGE_ICON_CHARGE), and the
## special itself is the payoff. The enum was RENUMBERED again - these are raw
## ints in every ClassDef.tres `executes` array (Godot can't serialise a typed
## array of a nested enum), and all three were re-pointed with it.
enum Kind { BLANK, DAMAGE, BLOCK, CHARGE }

## The reliquary chip art, one PNG per modifier id (already on disk, drawn by the
## compare flyout's stat chips). The two innate ids borrow the closest chip.
const _CHIP_DIR := "res://assets/ui/reliquary/"

static func kind_of(id: StringName) -> Kind:
	match id:
		&"elem_fire", &"elem_ice", &"elem_light", &"lightning_blast", \
		INNATE_DAMAGE, BASE_WEAPON, BASE_TRINKET:
			return Kind.DAMAGE
		&"cleave", &"rain", &"bomb_arrow", &"thunderburst":
			return Kind.CHARGE
		BASE_ARMOR, &"armor_block":
			return Kind.BLOCK
		_:
			return Kind.BLANK

## "" for a non-elemental icon, else "fire" / "ice" / "light" — the key
## GameState.element_color() and the battle overlay already speak.
## `lightning_blast` tints as lightning too - a lightning-flavoured, stronger
## variant of elem_light.
static func element_of(id: StringName) -> StringName:
	match id:
		&"elem_fire": return &"fire"
		&"elem_ice": return &"ice"
		&"elem_light", &"lightning_blast": return &"light"
	return &""

## [slot vocabulary] Which of the six board categories `id` shows as, or "" for
## a blank. What the payline matches on.
static func category_of(id: StringName) -> StringName:
	match element_of(id):
		&"fire": return CAT_FIRE
		&"ice": return CAT_ICE
		&"light": return CAT_LIGHTNING
	match kind_of(id):
		Kind.DAMAGE: return CAT_DAMAGE
		Kind.BLOCK: return CAT_BLOCK
		Kind.CHARGE: return CAT_CHARGE
	return &""

## [slot vocabulary] The weapon-glyph key for an item type: the authored relic
## bow draws as a bow.
## [backlog P3, issue #74] The roster's new weapons have no board glyph yet, so
## each borrows its nearest relative's until real glyphs are generated (#188).
## Without this they fell back to the generic gold sword (glyph_dmg_flat).
const _BORROWED_WEAPON_GLYPHS := {
	&"warbow": &"bow",
	&"greatsword": &"sword",
	&"crossbow": &"bow",
	&"heavy_crossbow": &"bow",
	&"wand": &"staff",
}

static func weapon_glyph_key(weapon_type: StringName) -> StringName:
	return _BORROWED_WEAPON_GLYPHS.get(weapon_type, weapon_type)

static func is_innate(id: StringName) -> bool:
	return id == INNATE_DAMAGE

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
	return _with_weapon({ "id": id, "roll": _base_icon_roll(item, kind_of(id)), "enhanced": false },
		item.equipped_by)

## An icon dict from an equipped modifier entry (see Itemizer.MODIFIERS).
## Returns an empty dict for an id with no board icon — callers skip those.
##
## [item power model] The modifier's `roll` is already the final resolved
## magnitude - Itemizer._roll_icon_magnitude() baked it at generation / forge
## time (125-175% of the item's Power for a DAMAGE / DAMAGE_ALL icon, its own
## magnitude for a BLOCK icon). `item` is read only for who wears it, which
## decides the weapon a strike draws as ([slot vocabulary] _with_weapon).
## A stat modifier (bleed, crit) returns an empty dict too: it is not a board icon.
static func from_modifier(mod: Dictionary, item: Item = null) -> Dictionary:
	var id := StringName(mod.get("id", &""))
	if not KNOWN_MODIFIER_IDS.has(id):
		return {}
	return _with_weapon({
		"id": id,
		"roll": int(mod.get("roll", 0)),
		"enhanced": bool(mod.get("enhanced", false)),
	}, item.equipped_by if item != null else &"")

## [slot vocabulary] Stamps `weapon` - the wearer's equipped weapon type - onto
## a plain strike, so the board can draw it as that weapon. Elements, block and
## charge draw the same whoever owns them and are left alone.
static func _with_weapon(icon: Dictionary, wearer: StringName) -> Dictionary:
	if wearer != &"" and category_of(StringName(icon.get("id", &""))) == CAT_DAMAGE:
		icon["weapon"] = GameState.hero_weapon_type(wearer)
	return icon

## An innate icon dict for a hero class: one per living hero, the floor that
## keeps the bag from ever being empty of icons. [content phase 1] The icon id
## comes from GameState.get_class_def(hero_class).innate_icon now - replaces
## the mage/damage ternary SlotIcon.innate_for() used to hardcode (spec §3
## Step 2). A class with no ClassDef (should not happen for a real hero) falls
## back to damage, same floor the old ternary's default arm gave.
## [item power model] `weapon_power` is 100% of the hero's EQUIPPED weapon
## Power (GameState.hero_weapon_power(hero_class)), precomputed by the caller -
## the hero's own stats no longer feed combat. 0 when the hero is unarmed
## (handled later).
## [owner swings] `owner` is the hero whose action this icon becomes when it
## resolves - SlotMachine sums each owner's DAMAGE icons into that hero's OWN
## swing, so a ranger's bow icons are swung by the ranger. Every icon in the bag
## carries one (SlotMachine._rebuild_bag() stamps the item icons from
## Item.equipped_by); an icon built without one - a rigged test board, a legacy
## caller - resolves through the DAMAGE executor, exactly as before.
static func innate(hero_class: StringName, weapon_power: int = 0) -> Dictionary:
	var cdef := GameState.get_class_def(hero_class)
	var id: StringName = cdef.innate_icon if cdef != null and cdef.innate_icon != &"" else INNATE_DAMAGE
	return _with_weapon({ "id": id, "roll": weapon_power, "enhanced": false, "innate": true,
		"owner": hero_class }, hero_class)

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
		BASE_ARMOR: key = &"armor_block"
	if key == BLANK:
		return ""
	return "%sglyph_%s.png" % [_GLYPH_DIR, key]

static func board_glyph_texture(id: StringName) -> Texture2D:
	var path := board_glyph_path(id)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## [slot vocabulary] The glyph a DEALT icon draws, which depends on more than
## its id: a strike draws its owner's weapon (`weapon`, stamped by
## SlotMachine._stamp_board_fields), an element its element, block the shield.
## A charge icon has no glyph - SlotSymbol draws it as a gold coin carrying
## charge_portrait_path() - so this returns "" for it. A strike whose owner
## holds no weapon (or whose weapon has no glyph yet) falls back to the generic
## gold sword.
static func board_glyph_path_for(icon: Dictionary) -> String:
	var id := StringName(icon.get("id", &""))
	match category_of(id):
		CAT_DAMAGE:
			var weapon := weapon_glyph_key(StringName(icon.get("weapon", &"")))
			var path := "%sglyph_weapon_%s.png" % [_GLYPH_DIR, weapon]
			if weapon != &"" and ResourceLoader.exists(path):
				return path
			return "%sglyph_dmg_flat.png" % _GLYPH_DIR
		CAT_FIRE: return "%sglyph_elem_fire.png" % _GLYPH_DIR
		CAT_ICE: return "%sglyph_elem_ice.png" % _GLYPH_DIR
		CAT_LIGHTNING: return "%sglyph_elem_light.png" % _GLYPH_DIR
		CAT_BLOCK: return "%sglyph_armor_block.png" % _GLYPH_DIR
	return ""

static func board_glyph_texture_for(icon: Dictionary) -> Texture2D:
	var path := board_glyph_path_for(icon)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## [slot vocabulary] The owner's side-on profile a charge coin carries, or "" if
## the icon has no owner (a rigged test board) or the portrait is not on disk.
static func charge_portrait_path(icon: Dictionary) -> String:
	var owner_class := StringName(icon.get("owner", &""))
	if owner_class == &"":
		return ""
	var path := "%sportrait_%s.png" % [_GLYPH_DIR, owner_class]
	return path if ResourceLoader.exists(path) else ""

## [slot vocabulary] The number printed on a dealt icon's tile: what it will
## actually add when it resolves. A strike or an element shows its share of
## the swing (roll, Overcharge, plus the per-icon floor - the same sum
## SlotMachine._resolve_board banks), block its flat reduction. A charge icon
## prints nothing (-1): its owner's portrait already says what it does.
static func board_value(icon: Dictionary, mult: float = 1.0) -> int:
	var id := StringName(icon.get("id", &""))
	var roll := int(icon.get("roll", 0))
	match kind_of(id):
		Kind.DAMAGE:
			return maxi(1, int(round(float(roll) * mult))) + Tuning.SLOT_ATTACK_ICON_FLOOR
		Kind.BLOCK:
			return maxi(1, roll)
	return -1

## [slot vocabulary] The jackpot banner's word for a category.
static func category_label(category: StringName) -> String:
	match category:
		CAT_DAMAGE: return "Strike"
		CAT_FIRE: return "Fire"
		CAT_ICE: return "Ice"
		CAT_LIGHTNING: return "Lightning"
		CAT_BLOCK: return "Block"
		CAT_CHARGE: return "Charge"
	return ""

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
		BASE_WEAPON: return "Strike"
		BASE_ARMOR, &"armor_block": return "Block"
		BASE_TRINKET: return "Focus"
		&"crit": return "Crit"
		&"cleave": return "Cleave"
		&"rain": return "Rain of Arrows"
		&"thunderburst": return "Thunderburst"
	return ""

## Percent-magnitude icons render their roll as "+N%"; the rest as "+N".
## [backlog P7] slot_mend was the last percent icon and is gone - every icon
## (damage, block, bleed, the trinket ultimates) is a flat magnitude now. Kept as a
## function so the callers that format a roll (GameState.icon_roll_text) need no
## special case the day a percent icon returns.
static func is_percent(_id: StringName) -> bool:
	return false
