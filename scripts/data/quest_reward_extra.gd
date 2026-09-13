class_name QuestRewardExtra
extends Resource
## A reward beyond the gold every quest already pays (decision D2, content
## phase 1 spec §3 Step 1b). QuestDef.gold_reward stays its own required field
## - this array is for whatever joins it later (scrap, XP, and eventually the
## recruitment outline's RecruitRewardExtra). Ships with zero concrete
## subclasses and an empty array on every Phase 1 quest, authored or
## generated; RunController._run_complete() walks it on victory only, calling
## grant() once per entry, and quest_result.gd / mayor_office.gd render
## describe() for display.
##
## Two traps recorded for whoever adds the first subclass (spec §3 Step 1b):
##   - Bank an XP extra into GameState.expedition_xp BEFORE _run_complete()
##     calls apply_expedition_xp(), or grant() it straight to the hero -
##     apply_expedition_xp() runs first and zeroes expedition_xp right after.
##   - A ScrapRewardExtra amends "scrap comes only from combat pickups"
##     (quest_def.gd / the town spec's own comment) - update both comments in
##     the same commit that ships one.

@export var description: String = ""

## Applies this reward. Called once, on victory only, from
## RunController._run_complete() - never on a wipe (spec 8.5's failure flow
## pays no reward extras, same as it pays no gold).
func grant() -> void:
	pass

## Display text for the reward row (quest_result.gd) and the mayor's quest
## button (mayor_office.gd). Empty string renders no row.
func describe() -> String:
	return ""

# --- persistence (spec §3 Step 3.2) -----------------------------------------
## Same shape as QuestObjective's persistence pair - see its header. No
## concrete subclass ships this phase (D2 / §4: every reward_extras array is
## empty), so the registry below has nothing to hold yet; it exists so
## QuestDef.to_dict()/from_dict() need no edit the day the first one lands.

func kind() -> StringName:
	return &""

func to_dict() -> Dictionary:
	return { "kind": kind(), "description": description }

static func from_dict(data: Dictionary) -> QuestRewardExtra:
	match StringName(data.get("kind", &"")):
		_:
			return null
