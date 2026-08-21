class_name Item
extends Resource

enum Rarity { COMMON, UNCOMMON, MAGIC, RARE }
enum Kind { WEAPON, POTION, RELIC }

@export var display_name: String = ""         # generated, e.g. "Fat Knife"
@export var kind: Kind = Kind.WEAPON
@export var rarity: Rarity = Rarity.COMMON
@export var weapon_type: StringName = &""     # axe|sword|bow|dagger|staff ; empty if not a weapon
@export var modifiers: Array[Dictionary] = [] # [{ "id": &"dmg_flat", "label": "+4 Damage", "value_mult": 0.42 }, ...]
@export var value: int = 0                    # computed intrinsic gold value
@export var equipped: bool = false            # always false in the demo (spec 13.6)

func subtitle() -> String:
	# "Magic Sword", "Common Bow" - rarity + type, per the source doc
	return "%s %s" % [rarity_name(), type_name()]

func rarity_name() -> String:
	return ["Common", "Uncommon", "Magic", "Rare"][rarity]

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
