class_name EncounterDef
extends Resource

enum Type { COMBAT, LOOT, SHOP }

@export var type: Type = Type.COMBAT
@export var is_boss: bool = false
@export var enemy_stat_ids: Array[StringName] = []  # COMBAT only, 1-3 entries
@export var loot_item_count: int = 0                # LOOT only
@export var shop_item_count: int = 3                # SHOP only
@export var travel_duration: float = 2.5            # seconds of scrolling before this encounter

## Shop stock is generated once per encounter and cached here, so reopening a
## tab never rerolls (spec 21-D11). Not exported - it is runtime-only state.
var cached_shop_items: Array = []
