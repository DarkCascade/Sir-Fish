class_name EncounterDef
extends Resource

enum Type { COMBAT, LOOT, SHOP }

@export var type: Type = Type.COMBAT
@export var is_boss: bool = false
@export var enemy_stat_ids: Array[StringName] = []  # COMBAT only, 1-3 entries
@export var loot_item_count: int = 0                # LOOT only
@export var shop_item_count: int = 3                # SHOP only
@export var travel_duration: float = 2.5            # seconds of scrolling before this encounter

## [town] Lowest rarity this encounter's boss drop may roll, as an Item.Rarity
## index. Only read when is_boss (battle_director.start_combat()), and defaults
## to 1 so the endless / fixed bosses keep their "never Common" floor untouched;
## _build_quest_level() raises it to the quest's boss_drop_rarity_floor (spec
## 8.2 / 8.3), which is how hard guarantees a Rare base item.
@export_range(0, 4, 1) var boss_drop_rarity_floor: int = 1

## Shop stock is generated once per encounter and cached here, so reopening a
## tab never rerolls (spec 21-D11). Not exported - it is runtime-only state.
var cached_shop_items: Array = []
