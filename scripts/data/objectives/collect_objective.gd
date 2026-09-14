class_name CollectObjective
extends QuestObjective
## "Retrieve a specific item" (recruitment outline §1, backlog P1 decision
## 1.1) - the token is never a real Item mid-run (that would hit Item.slot()'s
## unknown-type fallback and discard_expedition_loot()'s wipe sweep, the two
## hazards §5.1/§5.2 flag). Instead this completes when the quest's boss
## falls, exactly like ClearEncountersObjective already does since the boss
## is always the last encounter (quest_def.gd's own comment) - and
## RecruitRewardExtra.grant() creates the real item, and the recruit, at
## victory. Reads the same encounter_resolved event ClearEncountersObjective
## does, filtered to the boss encounter, so it still resolves correctly even
## if a future quest ever puts the boss somewhere other than last.

var _complete: bool = false

func on_event(evt: StringName, payload: Dictionary) -> void:
	if evt != &"encounter_resolved" or _complete:
		return
	var def: EncounterDef = payload.get("def")
	if def != null and def.is_boss:
		_complete = true

func progress() -> Vector2i:
	return Vector2i(1 if _complete else 0, 1)

func is_complete() -> bool:
	return _complete

## The boss is always the last encounter (quest_def.gd), so this never
## resolves before ClearEncountersObjective would anyway - no early-end
## warning on the notice sheet (quest_notice_sheet.gd's _road_note).
func can_end_early() -> bool:
	return false

func kind() -> StringName:
	return &"collect"
