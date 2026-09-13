class_name QuestGenerator
extends RefCounted
## Builds generated QuestDefs from a QuestTemplate rolled against an AreaDef
## (content phase 1 spec §3 Step 3). Emits a plain QuestDef - never a
## LevelDef directly (spec §3.1) - so every existing QuestDef reader
## (mayor_office.gd, GameState._build_quest_level(), QuestResult, the save
## file) needs no change to handle a generated quest alongside the three
## hand-authored ones.
##
## Not an autoload: pure, stateless generation, called by
## GameState.quest_board_offers() - the forge-stock pattern (spec §1.6)
## pointed at quests, same split Itemizer (generator) / GameState (persisted
## stock + accessor) already uses for the blacksmith.

const TEMPLATES_DIR := "res://resources/quest_templates/"

const _NAME_ADJECTIVES := [
	"Deep", "Dark", "Forgotten", "Restless", "Hidden", "Old", "Broken", "Silent",
]
const _GOLD_PER_ENCOUNTER := 50

static func _all_templates() -> Array[QuestTemplate]:
	var out: Array[QuestTemplate] = []
	var dir := DirAccess.open(TEMPLATES_DIR)
	if dir == null:
		return out
	for file_name: String in dir.get_files():
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var res := load(TEMPLATES_DIR + clean)
		if res is QuestTemplate:
			out.append(res)
	return out

## `n` quests, each a random template rolled against the endless area - the
## only area Phase 1 ships (spec §4). Returns fewer than `n` (possibly zero)
## if no QuestTemplate exists on disk, rather than crash the mayor's office.
static func generate_board(n: int, area: AreaDef) -> Array[QuestDef]:
	var templates := _all_templates()
	var out: Array[QuestDef] = []
	if templates.is_empty() or area == null:
		return out
	for i: int in range(n):
		var template: QuestTemplate = templates[RNG.randi_range(0, templates.size() - 1)]
		out.append(generate(template, area, i))
	return out

## One QuestDef from `template` rolled against `area`. `slot_index` only
## disambiguates this roll's id from a sibling rolled in the same board -
## it carries no other meaning.
static func generate(template: QuestTemplate, area: AreaDef, slot_index: int) -> QuestDef:
	var q := QuestDef.new()
	q.id = StringName("generated_%d_%d" % [RNG.randi_range(0, 999999999), slot_index])
	q.display_name = _roll_name(area)
	q.blurb = _roll_blurb(template)
	q.encounter_types = _roll_encounter_types(template)
	q.enemy_pool = area.pool.resolve() if area.pool != null else []
	var boss_source: EnemyPool = area.boss_pool if area.boss_pool != null else area.pool
	q.boss_pool = boss_source.resolve() if boss_source != null else []
	var enemy_ceiling: int = clampi(int(round(3.0 * template.difficulty_mult)), 2, Tuning.MAX_ENEMIES)
	q.enemy_count = Vector2i(2, enemy_ceiling)
	q.boss_drop_rarity_floor = 1
	q.level_range = area.level_band
	# D2: gold is always computed, never optional - every generated quest pays,
	# same as the content lint's gold_reward > 0 check enforces for authored ones.
	q.gold_reward = maxi(1, int(round(float(q.encounter_types.size())
		* _GOLD_PER_ENCOUNTER * template.gold_formula_mult)))
	q.objectives = [_roll_objective(template)]
	return q

## "The <adjective> <fragment>" - falls back to the area's own display_name
## with no fragments authored.
static func _roll_name(area: AreaDef) -> String:
	if area.name_fragments.is_empty():
		return area.display_name
	var adjective: String = _NAME_ADJECTIVES[RNG.randi_range(0, _NAME_ADJECTIVES.size() - 1)]
	var fragment: String = area.name_fragments[RNG.randi_range(0, area.name_fragments.size() - 1)]
	return "The %s %s" % [adjective, fragment]

static func _roll_blurb(template: QuestTemplate) -> String:
	if template.blurb_templates.is_empty():
		return ""
	return template.blurb_templates[RNG.randi_range(0, template.blurb_templates.size() - 1)]

## Tiles `template.rhythm` to fill every slot but the last, then appends one
## final COMBAT for the boss - every hand-authored quest's own invariant
## (quest_def.gd: "The LAST entry is always a COMBAT and becomes the boss
## fight"). An empty rhythm falls back to all-COMBAT.
static func _roll_encounter_types(template: QuestTemplate) -> Array[int]:
	var lo: int = maxi(template.length_range.x, 1)
	var hi: int = maxi(template.length_range.y, lo)
	var length: int = RNG.randi_range(lo, hi)
	var rhythm: Array[int] = template.rhythm if not template.rhythm.is_empty() \
		else [EncounterDef.Type.COMBAT]
	var types: Array[int] = []
	var i := 0
	while types.size() < length - 1:
		types.append(rhythm[i % rhythm.size()])
		i += 1
	types.append(EncounterDef.Type.COMBAT)
	return types

## [content-phase-1 questions doc Q1] Duplicated per roll, never the
## template's own shared instance - a null objective_proto falls back to a
## fresh ClearEncountersObjective, same shape a hand-authored quest with no
## other objective uses.
static func _roll_objective(template: QuestTemplate) -> QuestObjective:
	if template.objective_proto == null:
		return ClearEncountersObjective.new()
	return template.objective_proto.duplicate(true) as QuestObjective
