extends Node
## Content Phase 1, Step 1a/1b/3.2: QuestObjective, QuestRewardExtra, and
## GameState's per-run duplication of them.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_quest_objectives.tscn

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()
	t.guard_user_file(SaveGame.PATH)

	_check_clear_encounters(t)
	_check_slay(t)
	_check_duplication_isolation(t)
	_check_gamestate_integration(t)
	_check_persistence(t)

	GameState.quest = null
	GameState.completed_quest = null
	t.finish(get_tree(), "test_quest_objectives")

func _check_clear_encounters(t: TestSupport) -> void:
	var obj := ClearEncountersObjective.new()
	var level := LevelDef.new()
	level.encounters = [EncounterDef.new(), EncounterDef.new(), EncounterDef.new()]
	obj.bind(null, level)
	t.check(not obj.is_complete(), "ClearEncountersObjective: not complete before any encounter resolves")
	obj.on_event(&"encounter_resolved", { "index": 0 })
	t.check(not obj.is_complete(), "ClearEncountersObjective: not complete after 1 of 3")
	obj.on_event(&"encounter_resolved", { "index": 1 })
	t.check(not obj.is_complete(), "ClearEncountersObjective: not complete after 2 of 3")
	obj.on_event(&"encounter_resolved", { "index": 2 })
	t.check(obj.is_complete(), "ClearEncountersObjective: complete after the last encounter resolves")
	t.check(obj.progress() == Vector2i(3, 3), "ClearEncountersObjective: progress reports (3, 3)")

func _check_slay(t: TestSupport) -> void:
	var obj := SlayObjective.new()
	obj.target_tag = &"undead"
	obj.count = 2
	t.check(not obj.is_complete(), "SlayObjective: not complete with 0 kills")

	# A hero death never counts, regardless of tag.
	obj.on_event(&"combatant_died", { "stats_id": &"skeleton_minion", "is_hero": true })
	t.check(not obj.is_complete(), "SlayObjective: a hero death is never counted")

	# A non-matching enemy does not count.
	obj.on_event(&"combatant_died", { "stats_id": &"shadow_monster", "is_hero": false })
	t.check(obj.progress().x == 0, "SlayObjective: an enemy without the target tag does not count")

	# skeleton_minion carries &"undead" (see resources/stats/skeleton_minion.tres).
	obj.on_event(&"combatant_died", { "stats_id": &"skeleton_minion", "is_hero": false })
	t.check(obj.progress() == Vector2i(1, 2), "SlayObjective: one matching kill registers (1, 2)")
	t.check(not obj.is_complete(), "SlayObjective: not complete after 1 of 2")
	obj.on_event(&"combatant_died", { "stats_id": &"skeleton_warrior", "is_hero": false })
	t.check(obj.is_complete(), "SlayObjective: complete after 2 of 2 (a second undead id)")

	# target_id, when set, overrides the tag match entirely.
	var by_id := SlayObjective.new()
	by_id.target_id = &"sporecap"
	by_id.count = 1
	by_id.on_event(&"combatant_died", { "stats_id": &"skeleton_minion", "is_hero": false })
	t.check(not by_id.is_complete(), "SlayObjective: target_id ignores a non-matching id even if tagged")
	by_id.on_event(&"combatant_died", { "stats_id": &"sporecap", "is_hero": false })
	t.check(by_id.is_complete(), "SlayObjective: target_id matches the exact id")

func _check_duplication_isolation(t: TestSupport) -> void:
	var shared := load("res://resources/objectives/clear_encounters.tres") as ClearEncountersObjective
	var level_a := LevelDef.new()
	level_a.encounters = [EncounterDef.new(), EncounterDef.new()]
	var level_b := LevelDef.new()
	level_b.encounters = [EncounterDef.new(), EncounterDef.new()]

	var run_a := shared.duplicate(true) as ClearEncountersObjective
	var run_b := shared.duplicate(true) as ClearEncountersObjective
	run_a.bind(null, level_a)
	run_b.bind(null, level_b)
	run_a.on_event(&"encounter_resolved", { "index": 0 })
	run_a.on_event(&"encounter_resolved", { "index": 1 })
	t.check(run_a.is_complete(), "duplicated objective A completes independently")
	t.check(not run_b.is_complete(),
		"duplicating the shared clear_encounters.tres does not leak progress into a second run")
	t.check(not shared.is_complete(),
		"the shared cached resource itself is never mutated by a run's progress")

func _check_gamestate_integration(t: TestSupport) -> void:
	GameState.new_profile()
	var q: QuestDef = load("res://resources/quests/easy.tres")

	GameState.start_expedition(q)
	t.check(GameState.quest_objectives.size() == 1,
		"start_expedition() duplicates easy.tres's one objective")
	t.check(GameState.quest_objectives[0] is ClearEncountersObjective,
		"the duplicated objective is a ClearEncountersObjective")
	t.check(not GameState.quest_objectives_complete(),
		"quest_objectives_complete() is false at the start of a fresh expedition")

	var total: int = GameState.level.encounters.size()
	for i: int in range(total - 1):
		GameState.quest_objectives[0].on_event(&"encounter_resolved", { "index": i })
	t.check(not GameState.quest_objectives_complete(),
		"quest_objectives_complete() is still false one encounter short")
	GameState.quest_objectives[0].on_event(&"encounter_resolved", { "index": total - 1 })
	t.check(GameState.quest_objectives_complete(),
		"quest_objectives_complete() is true once the last encounter resolves")

	# A second start_expedition() of the SAME quest gets a fresh, un-progressed
	# instance - the trap QuestObjective's own header names.
	GameState.start_expedition(q)
	t.check(not GameState.quest_objectives_complete(),
		"a second start_expedition() of the same quest starts with fresh objective progress")

	GameState.quest_objectives = []
	t.check(not GameState.quest_objectives_complete(),
		"quest_objectives_complete() is false (never a win) with an empty objectives list")

func _check_persistence(t: TestSupport) -> void:
	var slay := SlayObjective.new()
	slay.description = "Slay the Bone Warden"
	slay.target_id = &"skeleton_warrior"
	slay.target_tag = &"undead"
	slay.count = 3
	var round_tripped := QuestObjective.from_dict(slay.to_dict()) as SlayObjective
	t.check(round_tripped != null and round_tripped.target_id == &"skeleton_warrior"
			and round_tripped.target_tag == &"undead" and round_tripped.count == 3
			and round_tripped.description == "Slay the Bone Warden",
		"SlayObjective round-trips through to_dict()/from_dict()")

	var ceo := ClearEncountersObjective.new()
	var ceo_back := QuestObjective.from_dict(ceo.to_dict())
	t.check(ceo_back is ClearEncountersObjective,
		"ClearEncountersObjective round-trips through to_dict()/from_dict()")

	t.check(QuestObjective.from_dict({ "kind": &"not_a_real_kind" }) == null,
		"an unrecognised objective kind reconstructs as null rather than crashing")

	# QuestDef, end to end - the shape a saved generated quest will take (Step 3).
	var q := QuestDef.new()
	q.id = &"generated_test"
	q.display_name = "A Generated Quest"
	q.encounter_types = [0, 1, 0]
	q.gold_reward = 123
	q.enemy_pool = [&"shadow_monster"]
	q.boss_pool = [&"skeleton_warrior"]
	q.enemy_count = Vector2i(1, 2)
	q.level_range = Vector2i(3, 9)
	q.objectives = [slay]
	var q_back := QuestDef.from_dict(q.to_dict())
	t.check(q_back.id == q.id and q_back.display_name == q.display_name
			and q_back.encounter_types == q.encounter_types and q_back.gold_reward == q.gold_reward
			and q_back.enemy_pool == q.enemy_pool and q_back.boss_pool == q.boss_pool
			and q_back.enemy_count == q.enemy_count and q_back.level_range == q.level_range,
		"QuestDef.to_dict()/from_dict() round-trips every scalar/array field")
	t.check(q_back.objectives.size() == 1 and q_back.objectives[0] is SlayObjective
			and (q_back.objectives[0] as SlayObjective).count == 3,
		"QuestDef round-trips its objectives array")
	t.check(q_back.reward_extras.is_empty(), "QuestDef round-trips an empty reward_extras array")
