class_name SlayObjective
extends QuestObjective
## "Kill N of something" (content phase 1 spec §3 Step 1a) - the second
## objective kind, and the one that can end a quest before its encounter list
## runs out (content-phase-1 questions doc Q1). Reads EventBus's existing
## combatant_died, no new signal needed.
##
## Matches on `target_id` (an exact CombatantStats.id, e.g. &"skeleton_warrior")
## when set, else on `target_tag` (a CombatantStats.tags entry, e.g. &"undead")
## when set, else any enemy death counts. At least one of the two should be
## set by whoever authors this - an objective with neither is "kill N of
## anything that dies," which is a valid if odd thing to ask for and is not
## guarded against.

@export var target_id: StringName = &""
@export var target_tag: StringName = &""
@export var count: int = 1

var _killed: int = 0

func on_event(evt: StringName, payload: Dictionary) -> void:
	if evt != &"combatant_died" or bool(payload.get("is_hero", false)):
		return
	var sid: StringName = payload.get("stats_id", &"")
	if target_id != &"" and sid != target_id:
		return
	if target_tag != &"":
		var stats := GameState.get_stats(sid)
		if stats == null or not stats.tags.has(target_tag):
			return
	_killed += 1

func progress() -> Vector2i:
	return Vector2i(mini(_killed, count), count)

func is_complete() -> bool:
	return _killed >= count

func kind() -> StringName:
	return &"slay"

func _to_dict_extra() -> Dictionary:
	return { "target_id": target_id, "target_tag": target_tag, "count": count }

func _from_dict_extra(data: Dictionary) -> void:
	target_id = StringName(data.get("target_id", &""))
	target_tag = StringName(data.get("target_tag", &""))
	count = int(data.get("count", 1))
