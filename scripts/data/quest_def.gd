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
##
## [levels] `level_range` EXTENDS that rule rather than breaking it (levels &
## stats spec §2.2). A level is authored data on the quest, resolved into
## authored data on each EncounterDef, and read by the one place that already
## builds a combatant (BattleDirector.start_combat()). It is not a scaling
## factor layered on top of CombatantStats after the fact - it is an argument
## to CombatantStats.hp_at() / weapon_power_at() / magic_power_at(), which is
## the ONLY place a level and a stat combine.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var blurb: String = ""

## The encounter sequence, as EncounterDef.Type values (0 COMBAT, 1 LOOT,
## 2 SHOP). The LAST entry is always a COMBAT and becomes the boss fight
## (is_boss, led by a boss_pool pick - spec 8.3). Authored in the inspector so a
## tier's pacing retunes without a script edit (CLAUDE.md).
@export var encounter_types: Array[int] = []

## Paid to the profile on completion (spec 8.5). No scrap reward - scrap comes
## only from the combat pickups (spec 5), unless a future ScrapRewardExtra
## amends this rule explicitly (see QuestRewardExtra's own header).
@export var gold_reward: int = 0

## [content phase 1] What this quest asks for, beyond "reach the end of the
## encounter list" (spec §3 Step 1a). Every quest must carry at least one -
## the three hand-authored quests each reference the shared
## res://resources/objectives/clear_encounters.tres. Duplicated into fresh
## runtime instances by GameState.start_expedition(); see QuestObjective's own
## header for why this resource must never be read as authored state once a
## run is live.
@export var objectives: Array[QuestObjective] = []

## [content phase 1] Reward beyond gold_reward (decision D2, spec §3 Step 1b).
## Empty on every quest Phase 1 ships, authored or generated - see
## QuestRewardExtra's header for the two traps its first real entry will hit.
@export var reward_extras: Array[QuestRewardExtra] = []

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
@export_range(0, 3, 1) var boss_drop_rarity_floor: int = 0

## Seconds of scrolling before each encounter, one per entry in encounter_types.
## Falls back to a 2 / 3 / ... / 4 ramp when short or empty (_build_quest_level).
@export var travel_durations: Array[float] = []

## [levels] Inclusive level band for this expedition (spec §2.2). The first
## encounter runs at x, the last regular (non-boss) encounter at y,
## interpolated across the list; the boss sits Tuning.BOSS_LEVEL_BONUS above y.
## Bands are authored wide and non-overlapping ACROSS quests on purpose - see
## the spec's §5.3 for why the item-level churn the brief asks for depends on
## that gap, not on how steep any one curve is.
@export var level_range: Vector2i = Vector2i(1, 1)

# --- persistence (spec §3 Step 3.2) -----------------------------------------

## A flat dictionary of primitives for the profile save - same reasoning as
## Item.to_dict(): a saved .tres embeds this script's path, so moving
## quest_def.gd later would silently invalidate every generated quest sitting
## in a player's saved board. Only a GENERATED quest is ever saved this way -
## the three hand-authored quests are loaded by id from disk - but every field
## round-trips regardless, so nothing here is a special case for one or the
## other.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"blurb": blurb,
		"encounter_types": encounter_types.duplicate(),
		"gold_reward": gold_reward,
		"objectives": objectives.map(func(o: QuestObjective) -> Dictionary: return o.to_dict()),
		"reward_extras": reward_extras.map(func(e: QuestRewardExtra) -> Dictionary: return e.to_dict()),
		"enemy_pool": enemy_pool.duplicate(),
		"enemy_count": enemy_count,
		"boss_pool": boss_pool.duplicate(),
		"boss_drop_rarity_floor": boss_drop_rarity_floor,
		"travel_durations": travel_durations.duplicate(),
		"level_range": level_range,
	}

## Rebuilds a QuestDef from to_dict()'s output. Unknown / missing keys fall
## back to a fresh QuestDef's defaults, same "total, not strict" contract as
## Item.from_dict() - a partially-readable save is already rejected wholesale
## by SaveGame.load_profile()'s version gate.
static func from_dict(data: Dictionary) -> QuestDef:
	var q := QuestDef.new()
	q.id = StringName(data.get("id", &""))
	q.display_name = String(data.get("display_name", ""))
	q.blurb = String(data.get("blurb", ""))
	var types: Array[int] = []
	for t: Variant in data.get("encounter_types", []):
		types.append(int(t))
	q.encounter_types = types
	q.gold_reward = int(data.get("gold_reward", 0))
	var objs: Array[QuestObjective] = []
	for o: Variant in data.get("objectives", []):
		var obj := QuestObjective.from_dict(o as Dictionary)
		if obj != null:
			objs.append(obj)
	q.objectives = objs
	var extras: Array[QuestRewardExtra] = []
	for e: Variant in data.get("reward_extras", []):
		var extra := QuestRewardExtra.from_dict(e as Dictionary)
		if extra != null:
			extras.append(extra)
	q.reward_extras = extras
	var pool: Array[StringName] = []
	for p: Variant in data.get("enemy_pool", []):
		pool.append(StringName(p))
	q.enemy_pool = pool
	q.enemy_count = data.get("enemy_count", Vector2i(2, 2))
	var boss: Array[StringName] = []
	for p: Variant in data.get("boss_pool", []):
		boss.append(StringName(p))
	q.boss_pool = boss
	q.boss_drop_rarity_floor = int(data.get("boss_drop_rarity_floor", 0))
	var durs: Array[float] = []
	for d: Variant in data.get("travel_durations", []):
		durs.append(float(d))
	q.travel_durations = durs
	q.level_range = data.get("level_range", Vector2i(1, 1))
	return q
