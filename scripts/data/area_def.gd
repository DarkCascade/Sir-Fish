class_name AreaDef
extends Resource
## A place a quest or the endless mode happens in (content phase 1 spec §3
## Step 3) - the concept `LevelDef.display_name` being a bare string never
## had (spec §1.2). Phase 1 ships the structure and authors exactly one
## instance, The Endless Wood, covering the one area that exists - new areas
## are a future content pass with an art dependency (spec §4).

@export var display_name: String = ""
@export var pool: EnemyPool

## [content phase 1] Joins `pool` once a run is at least one level/quest deep
## (endless depth >= 2 today) - preserves `_build_endless_level()`'s existing
## "depth 1 stays gentle" curve, which the spec's own AreaDef snippet (a
## single `pool` field) has no room for by itself. An area with no such curve
## simply leaves this null - the generator's rolled quests read `pool` alone,
## never this.
@export var mid_pool: EnemyPool

@export var boss_pool: EnemyPool

## A quest generated against this area picks its level_range from within this
## band (spec §3 Step 3). NOT read by endless mode, which scales its own band
## off depth directly (Tuning.ENDLESS_LEVELS_PER_DEPTH) - a single fixed band
## would not track a run that is, by design, unbounded in depth.
@export var level_band: Vector2i = Vector2i(1, 99)

## Parallax / palette hook (spec §3 Step 3) - authored, not yet consumed,
## mirroring CombatantStats.threat's own "the data is already there" note
## from Phase 0. There is one OverworldField palette today; wiring this in is
## a future art-dependent pass, not this one.
@export var field_profile: StringName = &""

## Quest-name fragments for the generator, e.g. "Shallow", "Wood", "Hollow" -
## see QuestGenerator._roll_name().
@export var name_fragments: PackedStringArray = []
