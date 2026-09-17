class_name Spoils
extends RefCounted
## [party-wipe-consequences] The four-reel spoils roll on the run summary
## (quest_result.gd): one reel per thing the expedition banked, each landing on
## one Outcome that both scales what the player keeps and feeds the verdict's
## red/yellow/green rating.
##
## DOUBLE on ITEMS does not clone the haul - Itemizer rolls a second batch of
## the same size (GameState.apply_spoils). "Twice the loot" is true; "two of the
## same sword" would not be.

enum Outcome { LOSE, KEEP, KEEP_HALF, DOUBLE }

## The four banks a run fills, in reel order, left to right.
enum Category { XP, ITEMS, GOLD, SCRAP }

const CATEGORY_ORDER: Array[int] = [
	Category.XP, Category.ITEMS, Category.GOLD, Category.SCRAP,
]

## Uniform draw - the four outcomes average to a 0.875x multiplier and a net
## zero rating, so the roll is a swing rather than a tax.
const OUTCOME_POOL: Array[int] = [
	Outcome.LOSE, Outcome.KEEP, Outcome.KEEP_HALF, Outcome.DOUBLE,
]

static func roll() -> Outcome:
	return OUTCOME_POOL[RNG.randi_range(0, OUTCOME_POOL.size() - 1)] as Outcome

static func multiplier(outcome: Outcome) -> float:
	match outcome:
		Outcome.LOSE:
			return 0.0
		Outcome.KEEP_HALF:
			return 0.5
		Outcome.DOUBLE:
			return 2.0
	return 1.0

## Verdict rating. Bringing home what you earned is par, so KEEP and KEEP_HALF
## are both worth nothing - only losing the lot or doubling it moves the needle.
static func points(outcome: Outcome) -> int:
	match outcome:
		Outcome.LOSE:
			return -1
		Outcome.DOUBLE:
			return 1
	return 0

static func label(outcome: Outcome) -> String:
	match outcome:
		Outcome.LOSE:
			return "LOSE"
		Outcome.KEEP_HALF:
			return "HALF"
		Outcome.DOUBLE:
			return "DOUBLE"
	return "KEEP"

static func color(outcome: Outcome) -> Color:
	match outcome:
		Outcome.LOSE:
			return Tuning.C_DANGER
		Outcome.KEEP_HALF:
			return Tuning.C_GOLD
		Outcome.DOUBLE:
			return Tuning.C_HEAL
	return Tuning.C_TEXT

static func caption(category: Category) -> String:
	match category:
		Category.XP:
			return "XP"
		Category.ITEMS:
			return "Items"
		Category.GOLD:
			return "Gold"
	return "Scrap"
