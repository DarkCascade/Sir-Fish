extends Node
## Upgrades (spec 17.6). Three purchasable slot upgrades at four levels each -
## the vertical slice of the core loop, not the whole system.
##
## Upgrades change how OFTEN spins happen, how MUCH a damage icon pays, and how
## DENSE the board is. They never invent icons or touch how one resolves.
##
## Run-scoped: reset() is called from GameState.start_expedition(), which
## today is only ever reached through reset_run(). No meta-progression - spec
## 5.4 is explicit that these are NOT the forge.

const DEFS := {
	&"quick_reels": {
		"name": "Quick Reels",
		"blurb": "Reels spin %d%% faster",
		"base": Tuning.UPGRADE_QUICK_REELS_BASE,
	},
	&"overcharge": {
		"name": "Overcharge",
		# [slot phase 2] Was "Lightning pays +%d%%". Lightning is gone - it now
		# lifts every damage icon on the board.
		"blurb": "Damage icons pay +%d%%",
		"base": Tuning.UPGRADE_OVERCHARGE_BASE,
	},
	# [slot phase 2] Replaces `fat_purse` ("Gold pays +%d%%"), retired with slot
	# gold. Removes blanks from the bag, making the board denser every level.
	&"polish": {
		"name": "Polish",
		"blurb": "Remove %d blanks from the reel",
		"base": Tuning.UPGRADE_POLISH_BASE,
	},
}

## The tray's three buttons, in display order.
const ORDER: Array[StringName] = [&"quick_reels", &"overcharge", &"polish"]

var levels := { &"quick_reels": 0, &"overcharge": 0, &"polish": 0 }

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

# --- derived multipliers, read by the slot machine (spec 16.3, §6) ----------

## Spin-cycle multiplier: compounding, 1.00 / 0.86 / 0.74 / 0.64.
func quick_reels_mult() -> float:
	return pow(Tuning.UPGRADE_QUICK_REELS_STEP, float(level(&"quick_reels")))

## Damage-icon payout multiplier: additive, 1.00 / 1.25 / 1.50 / 1.75 / 2.00.
func overcharge_mult() -> float:
	return 1.0 + Tuning.UPGRADE_OVERCHARGE_STEP * float(level(&"overcharge"))

## [slot phase 2] Blanks the `polish` upgrade has removed from the bag: additive,
## 0 / 2 / 4 / 6 / 8. SlotMachine subtracts this from SLOT_BLANK_PAD_START and
## clamps at SLOT_BLANK_PAD_FLOOR, so the effective floor is reached at level 4.
func polish_blanks_removed() -> int:
	return Tuning.UPGRADE_POLISH_STEP * level(&"polish")

## The blurb text for the NEXT level's cumulative effect (spec 17.6 button spec).
## quick_reels / overcharge report a percent; polish reports a blank COUNT.
func next_effect_percent(id: StringName) -> int:
	var next := mini(level(id) + 1, Tuning.UPGRADE_MAX_LEVEL)
	match id:
		&"quick_reels":
			# "faster" reads as the cycle-time reduction, not the multiplier.
			return int(round((1.0 - pow(Tuning.UPGRADE_QUICK_REELS_STEP, float(next))) * 100.0))
		&"overcharge":
			return int(round(Tuning.UPGRADE_OVERCHARGE_STEP * float(next) * 100.0))
		&"polish":
			return Tuning.UPGRADE_POLISH_STEP * next
	return 0
