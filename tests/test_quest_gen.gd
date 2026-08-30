extends Node
## The quest level generator (spec 8.3 / 13.1). Lands at step 8 with QuestDef,
## the three .tres quests and _build_quest_level().
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_quest_gen.tscn

const TestSupport := preload("res://tests/test_support.gd")
const QUESTS := ["easy", "medium", "hard"]
const ITERATIONS := 60

func _ready() -> void:
	var t := TestSupport.new()
	t.guard_user_file(SaveGame.PATH)

	for id: String in QUESTS:
		var q: QuestDef = load("res://resources/quests/%s.tres" % id)
		t.check(q != null, "%s.tres loads as a QuestDef" % id)
		if q == null:
			continue

		# Every id the quest can name must resolve to real stats.
		var pools_ok := true
		for pool_name: String in ["enemy_pool", "boss_pool"]:
			for eid: StringName in q.get(pool_name):
				if GameState.get_stats(eid) == null:
					pools_ok = false
		t.check(pools_ok, "%s: every enemy_pool / boss_pool id resolves to real stats" % id)

		# Aggregate the RNG-path invariants over many builds, assert once each.
		var seq_ok := true
		var one_boss_last := true
		var boss_leads_pool := true
		var floor_ok := true
		var counts_in_range := true
		var ids_in_pool := true

		for _iteration: int in range(ITERATIONS):
			GameState.quest = q
			var lvl: LevelDef = GameState.build_level()

			if lvl.encounters.size() != q.encounter_types.size():
				seq_ok = false
			for i: int in range(mini(lvl.encounters.size(), q.encounter_types.size())):
				if int(lvl.encounters[i].type) != q.encounter_types[i]:
					seq_ok = false

			var boss_count := 0
			for j: int in range(lvl.encounters.size()):
				if lvl.encounters[j].is_boss:
					boss_count += 1
					if j != lvl.encounters.size() - 1:
						one_boss_last = false
			if boss_count != 1:
				one_boss_last = false

			var boss_enc: EncounterDef = lvl.encounters[lvl.encounters.size() - 1]
			if boss_enc.enemy_stat_ids.is_empty() or boss_enc.enemy_stat_ids[0] not in q.boss_pool:
				boss_leads_pool = false
			if boss_enc.boss_drop_rarity_floor != q.boss_drop_rarity_floor:
				floor_ok = false

			for enc: EncounterDef in lvl.encounters:
				if enc.type != EncounterDef.Type.COMBAT:
					continue
				var n := enc.enemy_stat_ids.size()
				if n < q.enemy_count.x or n > q.enemy_count.y:
					counts_in_range = false
				for eid: StringName in enc.enemy_stat_ids:
					if eid not in q.enemy_pool and eid not in q.boss_pool:
						ids_in_pool = false

		t.check(seq_ok, "%s: encounter type sequence always matches encounter_types" % id)
		t.check(one_boss_last, "%s: exactly one is_boss encounter, always the last" % id)
		t.check(boss_leads_pool, "%s: boss enemy_stat_ids[0] is always from boss_pool" % id)
		t.check(floor_ok, "%s: boss encounter carries the quest's boss_drop_rarity_floor" % id)
		t.check(counts_in_range, "%s: every combat group size stays within enemy_count" % id)
		t.check(ids_in_pool, "%s: every enemy id is in enemy_pool or boss_pool" % id)

	GameState.quest = null
	t.finish(get_tree(), "test_quest_gen")
