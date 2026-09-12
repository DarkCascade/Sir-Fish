class_name QuestRuntime
extends Node
## Fans EventBus's existing combat/exploration signals out to the active
## quest's objectives, one on_event() call per objective per event (content
## phase 1 spec §3 Step 1a). A child of RunController, added once in its
## _ready(); subscribes once and no-ops whenever GameState.quest is null
## (endless / fixed dev runs), so it costs nothing outside a real quest.
##
## Emits EventBus.quest_progress after every dispatch so the HUD has a hook to
## read from later - Phase 1 ships the signal; no HUD widget reads it yet
## (content-phase-1 questions doc Q6 covers the reward-extra side of "shipped
## but not yet visually exercised"; the progress signal is the objective-side
## equivalent).

func _ready() -> void:
	EventBus.combatant_died.connect(_on_combatant_died)
	EventBus.encounter_resolved.connect(_on_encounter_resolved)
	EventBus.item_added.connect(_on_item_added)

func _on_combatant_died(c: Node) -> void:
	if GameState.quest == null:
		return
	var payload := { "combatant": c }
	if c is Combatant:
		var combatant := c as Combatant
		payload["stats_id"] = combatant.stats.id if combatant.stats != null else &""
		payload["is_hero"] = combatant.is_hero
	_dispatch(&"combatant_died", payload)

func _on_encounter_resolved(index: int, def: EncounterDef) -> void:
	if GameState.quest == null:
		return
	_dispatch(&"encounter_resolved", { "index": index, "def": def })

func _on_item_added(item: Item) -> void:
	if GameState.quest == null:
		return
	_dispatch(&"item_added", { "item": item })

func _dispatch(evt: StringName, payload: Dictionary) -> void:
	for obj: QuestObjective in GameState.quest_objectives:
		obj.on_event(evt, payload)
		var p := obj.progress()
		EventBus.quest_progress.emit(obj, p.x, p.y)
