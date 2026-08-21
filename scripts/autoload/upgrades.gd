extends Node
## Upgrades (spec 17.6). Three purchasable slot upgrades at three levels each -
## the vertical slice of the initial vision's core loop, not the whole system.
##
## Upgrades change how OFTEN spins happen and how MUCH a win pays. They never
## touch Tuning.SLOT_STRIP, the win rule, or the 50.038% win rate (spec 16.2).
##
## Run-scoped: reset() is called from GameState.reset_run(). No meta-progression.

const DEFS := {
	&"quick_reels": {
		"name": "Quick Reels",
		"blurb": "Reels spin %d%% faster",
		"base": Tuning.UPGRADE_QUICK_REELS_BASE,
	},
	&"overcharge": {
		"name": "Overcharge",
		"blurb": "Lightning pays +%d%%",
		"base": Tuning.UPGRADE_OVERCHARGE_BASE,
	},
	&"fat_purse": {
		"name": "Fat Purse",
		"blurb": "Gold pays +%d%%",
		"base": Tuning.UPGRADE_FAT_PURSE_BASE,
	},
}

## The tray's three buttons, in display order.
const ORDER: Array[StringName] = [&"quick_reels", &"overcharge", &"fat_purse"]

var levels := { &"quick_reels": 0, &"overcharge": 0, &"fat_purse": 0 }

func level(id: StringName) -> int:
	return int(levels.get(id, 0))

func is_maxed(id: StringName) -> bool:
	return level(id) >= Tuning.UPGRADE_MAX_LEVEL

func cost(id: StringName) -> int:
	if is_maxed(id):
		return -1
	var base: int = int((DEFS[id] as Dictionary)["base"])
	return int(round(float(base) * pow(Tuning.UPGRADE_COST_GROWTH, float(level(id)))))

func buy(id: StringName) -> bool:
	if not DEFS.has(id) or is_maxed(id):
		return false
	var price := cost(id)
	if not GameState.spend_gold(price):
		return false
	levels[id] = level(id) + 1
	GameState.run_stats["upgrades_bought"] = int(GameState.run_stats["upgrades_bought"]) + 1
	EventBus.upgrade_purchased.emit(id, level(id))
	return true

func reset() -> void:
	for id: StringName in DEFS.keys():
		levels[id] = 0

# --- derived multipliers, read by the slot machine (spec 16.3, 16.5) --------

## Spin-cycle multiplier: compounding, 1.00 / 0.86 / 0.74 / 0.64.
func quick_reels_mult() -> float:
	return pow(Tuning.UPGRADE_QUICK_REELS_STEP, float(level(&"quick_reels")))

## Lightning payout multiplier: additive, 1.00 / 1.25 / 1.50 / 1.75.
func overcharge_mult() -> float:
	return 1.0 + Tuning.UPGRADE_OVERCHARGE_STEP * float(level(&"overcharge"))

## Gold payout multiplier: additive, 1.00 / 1.40 / 1.80 / 2.20.
func fat_purse_mult() -> float:
	return 1.0 + Tuning.UPGRADE_FAT_PURSE_STEP * float(level(&"fat_purse"))

## The blurb text for the NEXT level's cumulative effect (spec 17.6 button spec).
func next_effect_percent(id: StringName) -> int:
	var next := mini(level(id) + 1, Tuning.UPGRADE_MAX_LEVEL)
	match id:
		&"quick_reels":
			# "faster" reads as the cycle-time reduction, not the multiplier.
			return int(round((1.0 - pow(Tuning.UPGRADE_QUICK_REELS_STEP, float(next))) * 100.0))
		&"overcharge":
			return int(round(Tuning.UPGRADE_OVERCHARGE_STEP * float(next) * 100.0))
		&"fat_purse":
			return int(round(Tuning.UPGRADE_FAT_PURSE_STEP * float(next) * 100.0))
	return 0
