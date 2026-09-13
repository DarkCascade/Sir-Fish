class_name QuestObjective
extends Resource
## What a quest asks for, beyond "reach the end of the encounter list" (content
## phase 1 spec §3 Step 1a). A QuestDef's `objectives` array is authored/cached
## like any other Resource; GameState.start_expedition() duplicate(true)s each
## entry into a fresh runtime instance before a run starts, so two expeditions
## of the same quest never share progress state - the same trap
## Combatant.level's own comment documents for CombatantStats.
##
## QuestRuntime (scripts/run/quest_runtime.gd) fans EventBus events to
## on_event() for every objective on the active quest; RunController asks
## GameState.quest_objectives_complete() at each encounter-resolution boundary
## to decide whether the quest has been won (content-phase-1 questions doc Q1).

@export var description: String = ""          # "Slay the Bone Warden"

## Reads `evt` (an EventBus signal name, e.g. &"combatant_died") and `payload`
## (that signal's arguments, packed into a Dictionary by QuestRuntime) and
## updates this objective's own progress. No-op by default.
func on_event(_evt: StringName, _payload: Dictionary) -> void:
	pass

## (current, target). Godot has no generic Vector2i(0, 1) NaN, so a target of 1
## with current 0 is the "not started" floor for an objective with no
## meaningful progress bar of its own.
func progress() -> Vector2i:
	return Vector2i(0, 1)

func is_complete() -> bool:
	return false

## [content-phase-1 questions Q5] Called once by GameState.start_expedition(),
## right after this objective is duplicated onto a fresh run, so it can read
## whatever context it needs from the quest/level it is bound to (an encounter
## count, a level band) instead of carrying that as authored state that would
## have to be kept in sync by hand. No-op by default - most objectives resolve
## purely off events.
func bind(_quest: QuestDef, _level: LevelDef) -> void:
	pass

# --- persistence (spec §3 Step 3.2) -----------------------------------------

## A stable id for this objective's concrete type, for save-file round-
## tripping - never a script path, so moving this script later never
## invalidates a save the way embedding a .tres would (see Item.to_dict()'s
## own comment for the same reasoning). Empty on the base class; every
## concrete subclass overrides it.
func kind() -> StringName:
	return &""

## AUTHORED fields only - a generated quest's offer is saved before it is ever
## run, so there is no runtime progress (on_event()'s tallies) to persist,
## only what a fresh bind() needs to reconstruct the same objective. Concrete
## subclasses override _to_dict_extra()/_from_dict_extra() rather than
## to_dict()/from_dict() themselves, so the kind/description plumbing lives in
## exactly one place.
func to_dict() -> Dictionary:
	var d := { "kind": kind(), "description": description }
	for key: String in _to_dict_extra():
		d[key] = _to_dict_extra()[key]
	return d

func _to_dict_extra() -> Dictionary:
	return {}

func _from_dict_extra(_data: Dictionary) -> void:
	pass

## Reconstructs the right concrete subclass from to_dict()'s output. Every
## subclass this phase ships must be registered here - there is no reflection
## trick that avoids this list, so it is deliberately the one place a new
## subclass must be added for saves to round-trip it (mirrors the MIGRATIONS
## table in save_game.gd: a short, explicit table beats a clever lookup).
## Returns null for an unrecognised kind - the caller (QuestDef.from_dict())
## drops it rather than crash a load over one bad entry.
static func from_dict(data: Dictionary) -> QuestObjective:
	var obj: QuestObjective
	match StringName(data.get("kind", &"")):
		&"clear_encounters":
			obj = ClearEncountersObjective.new()
		&"slay":
			obj = SlayObjective.new()
		_:
			return null
	obj.description = String(data.get("description", ""))
	obj._from_dict_extra(data)
	return obj
