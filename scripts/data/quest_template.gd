class_name QuestTemplate
extends Resource
## A generator's recipe for one quest (content phase 1 spec §3 Step 3):
## rolled against an AreaDef by QuestGenerator to produce a plain QuestDef,
## exactly the way an authored one is authored by hand.

## Duplicated per roll (never shared - see QuestObjective's own header for
## why). Null defaults to a ClearEncountersObjective, same as a hand-authored
## quest that only wants "reach the end."
@export var objective_proto: QuestObjective

## The encounter-type pattern (EncounterDef.Type values) QuestGenerator tiles
## to build the non-boss portion of encounter_types - see
## QuestGenerator._roll_encounter_types() for exactly how length_range and
## this interact. An empty rhythm falls back to all-COMBAT.
@export var rhythm: Array[int] = []

## Inclusive range for the TOTAL encounter count, boss slot included (the
## generator always appends one final COMBAT for the boss, mirroring every
## hand-authored quest's own invariant).
@export var length_range: Vector2i = Vector2i(5, 5)

## Multiplies the difficulty knobs a generated quest exposes - currently only
## enemy_count's ceiling (see QuestGenerator.generate()). Authored, largely
## unused until a second area/tier exists to differentiate against (spec §4).
@export var difficulty_mult: float = 1.0

## Multiplies the gold-per-encounter base the generator pays (spec §3 Step
## 3, D2: gold is always computed, never optional).
@export var gold_formula_mult: float = 1.0

## Flavour text, one line picked at random per roll. Empty falls back to "".
@export var blurb_templates: PackedStringArray = []
