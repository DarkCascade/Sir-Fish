class_name CollectObjective
extends QuestObjective
## "Bring back a specific item" (content phase 1 spec §3 Step 1a's
## CollectObjective) - narrowed from the spec's (slot, rarity, count) to an
## exact weapon_type match. The Recruitment Quest Acceptance Test Outline
## (§5.1) flags why: a loose slot/rarity match would let ANY trinket of that
## rarity satisfy a quest that is really asking for one specific, hand-
## authored relic (a chest or an unrelated boss drop landing on the same slot/
## rarity would falsely complete it). weapon_type is unique per authored relic
## (see Itemizer.ITEM_TYPES' "authored relics" rows), so this cannot happen.
##
## Reads EventBus's existing item_added, no new signal needed.

@export var target_weapon_type: StringName = &""
@export var count: int = 1

var _collected: int = 0

func on_event(evt: StringName, payload: Dictionary) -> void:
	if evt != &"item_added":
		return
	var item: Item = payload.get("item")
	if item == null or item.weapon_type != target_weapon_type:
		return
	_collected += 1

func progress() -> Vector2i:
	return Vector2i(mini(_collected, count), count)

func is_complete() -> bool:
	return _collected >= count

func kind() -> StringName:
	return &"collect"

func _to_dict_extra() -> Dictionary:
	return { "target_weapon_type": target_weapon_type, "count": count }

func _from_dict_extra(data: Dictionary) -> void:
	target_weapon_type = StringName(data.get("target_weapon_type", &""))
	count = int(data.get("count", 1))
