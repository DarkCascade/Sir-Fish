class_name QuestRewardExtra
extends Resource
## A reward beyond the gold every quest already pays (decision D2, content
## phase 1 spec §3 Step 1b). QuestDef.gold_reward stays its own required field
## - this array is for whatever joins it later (scrap, XP, and - as of the
## backlog P1 recruitment quest - RecruitRewardExtra). Empty on every quest
## that doesn't need one; RunController._run_complete() walks it on victory
## only, calling grant() once per entry, and quest_notice_sheet.gd /
## mayor_office.gd render describe() for display.
##
## Two traps recorded for whoever adds an XP or scrap subclass (spec §3 Step
## 1b; RecruitRewardExtra hits neither):
##   - [party-wipe-consequences] An XP extra may now bank into
##     GameState.expedition_xp and it will land: apply_expedition_xp() moved out
##     of _run_complete() and into GameState.apply_spoils(), which the result
##     modal drives AFTER grant() has run. It used to run first and strand
##     anything banked here. Note that a wipe's XP reel can scale what is banked;
##     grant() straight to the hero to keep a reward off that table (and reward
##     extras only ever run on victory, whose roll is always KEEP anyway).
##   - A ScrapRewardExtra amends "scrap comes only from combat pickups"
##     (quest_def.gd / the town spec's own comment) - update both comments in
##     the same commit that ships one.
##
## [recruitment] RecruitRewardExtra is the first concrete subclass - see its
## own header. Neither trap above applies to it: it touches active_party, not
## expedition_xp or scrap.

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
## Same shape as QuestObjective's persistence pair - see its header.
## Concrete subclasses override _to_dict_extra()/_from_dict_extra() rather
## than to_dict()/from_dict() themselves, so the kind/description plumbing
## lives in exactly one place. [backlog P1] RecruitRewardExtra is the first
## concrete subclass to actually use this shape.

func kind() -> StringName:
	return &""

func to_dict() -> Dictionary:
	var d := { "kind": kind(), "description": description }
	for key: String in _to_dict_extra():
		d[key] = _to_dict_extra()[key]
	return d

func _to_dict_extra() -> Dictionary:
	return {}

func _from_dict_extra(_data: Dictionary) -> void:
	pass

static func from_dict(data: Dictionary) -> QuestRewardExtra:
	var extra: QuestRewardExtra
	match StringName(data.get("kind", &"")):
		&"recruit":
			extra = RecruitRewardExtra.new()
		_:
			return null
	extra.description = String(data.get("description", ""))
	extra._from_dict_extra(data)
	return extra
