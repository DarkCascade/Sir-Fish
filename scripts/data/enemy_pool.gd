class_name EnemyPool
extends Resource
## A filterable enemy roster (content-phase-0 spec §3 Step 4) - replaces the
## const arrays that used to live in game_state.gd (ENDLESS_EARLY_POOL,
## ENDLESS_MID_POOL, BOSS_POOL). A pool resolves against every CombatantStats
## GameState has cached, AT CALL TIME, so a monster joins every pool it
## qualifies for the moment its .tres lands - no registration step, no second
## place to remember.

@export var require_tags: Array[StringName] = []
@export var exclude_tags: Array[StringName] = []

## [content phase 0] Authored, not yet consumed - no caller passes a level to
## filter by (that is Phase 1's generated-encounter concern). Kept alongside
## `threat` on CombatantStats for the same reason: the day a caller needs it,
## the data is already there.
@export var level_band: Vector2i = Vector2i(1, 99)

## Hand-pin a set-piece roster, bypassing the tag filter entirely - a
## hand-authored fight should not have to be expressed as a filter. The three
## pools this step migrated (endless_early / endless_mid / boss_pool) all use
## this: they are today's exact hand-authored rosters, not derived filters,
## and a same-story migration is the safest one (nothing about play changes).
@export var explicit_ids: Array[StringName] = []

func resolve() -> Array[StringName]:
	if not explicit_ids.is_empty():
		return explicit_ids.duplicate()
	var out: Array[StringName] = []
	for id: StringName in GameState.all_stats_ids():
		var stats := GameState.get_stats(id)
		if stats == null or stats.is_hero:
			continue
		if _matches(stats):
			out.append(id)
	return out

func _matches(stats: CombatantStats) -> bool:
	for tag: StringName in require_tags:
		if not stats.tags.has(tag):
			return false
	for tag: StringName in exclude_tags:
		if stats.tags.has(tag):
			return false
	return true
