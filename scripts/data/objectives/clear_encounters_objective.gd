class_name ClearEncountersObjective
extends QuestObjective
## "Reach the end of the encounter list" - the objective every quest shipped
## with before this phase, ported as the first QuestObjective subclass so the
## three authored quests keep their exact prior behaviour (content phase 1
## spec §3 Step 1a: "ship objectives first as a pure refactor with no visible
## change"). One shared resource (res://resources/objectives/clear_encounters.tres)
## is referenced by every quest that wants this objective - it carries no
## authored fields, only bind()-derived runtime state, so one .tres instance
## duplicated per run is exactly as safe as one apiece.

var _current: int = 0
var _target: int = 0

func bind(_quest: QuestDef, level: LevelDef) -> void:
	_current = 0
	_target = level.encounters.size() if level != null else 0

func on_event(evt: StringName, payload: Dictionary) -> void:
	if evt != &"encounter_resolved":
		return
	# encounter_resolved fires with the index that just finished (0-based) -
	# current becomes "how many encounters have resolved so far".
	_current = maxi(_current, int(payload.get("index", -1)) + 1)

func progress() -> Vector2i:
	return Vector2i(_current, _target)

func is_complete() -> bool:
	return _target > 0 and _current >= _target

func kind() -> StringName:
	return &"clear_encounters"
