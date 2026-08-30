class_name QuestDef
extends Resource
## [town] One authored expedition (spec 8.1). Three of these live in
## res://resources/quests/ (easy / medium / hard) and the mayor's office hands
## them out (spec 7.5). GameState.build_level() dispatches on GameState.quest and
## walks encounter_types to build the LevelDef (spec 8.3).
##
## Difficulty is expressed as DATA - which enemies, how many, how deep, what the
## boss guarantees - never as a stat-scaling multiplier: a second source of
## truth for combatant power alongside CombatantStats is exactly what
## _build_endless_level()'s own comment warns against (spec 8.1, spec 1.10).

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var blurb: String = ""

## The encounter sequence, as EncounterDef.Type values (0 COMBAT, 1 LOOT,
## 2 SHOP). The LAST entry is always a COMBAT and becomes the boss fight
## (is_boss, led by a boss_pool pick - spec 8.3). Authored in the inspector so a
## tier's pacing retunes without a script edit (CLAUDE.md).
@export var encounter_types: Array[int] = []

## Paid to the profile on completion (spec 8.5). No scrap reward - scrap comes
## only from the combat pickups (spec 5).
@export var gold_reward: int = 0

## The regular-combat enemy roster. Boss adds are drawn from here too; only the
## leftmost slot of the boss fight comes from boss_pool.
@export var enemy_pool: Array[StringName] = []
## Inclusive min/max group size for every combat encounter, boss included.
@export var enemy_count: Vector2i = Vector2i(2, 2)
## The boss fight's leftmost enemy is picked from this (spec 7.3 - leading the
## list keeps the scaled-up boss body in frame).
@export var boss_pool: Array[StringName] = []
## Lowest rarity the boss drop may roll, as an Item.Rarity index (0-3). This is
## the only cheap route to an Enhanced Rare, and the reason hard exists beyond
## its bigger gold reward (spec 8.2).
@export_range(0, 4, 1) var boss_drop_rarity_floor: int = 0

## Seconds of scrolling before each encounter, one per entry in encounter_types.
## Falls back to a 2 / 3 / ... / 4 ramp when short or empty (_build_quest_level).
@export var travel_durations: Array[float] = []
