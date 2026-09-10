extends Node
## Monte Carlo simulation: starting from a brand-new profile (level 1, no
## gear, 150 gold), how many attempts at the EASY expedition does it take
## before one actually clears the boss?
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tools/sim_easy_attempts.tscn
##
## Every combat event below fires each actor independently at its own
## attack_cooldown - the real-time model this was written against, which
## BattleDirector.turn_based_combat defaulting false again ([combat loop
## redesign]) matches. NOTE: this resolver still models a hero meleeing off
## its own cooldown, which the redesign is removing in favour of slot-only
## party actions - re-derive the hero-output term against that before trusting
## the attempt-count result.
##
## Reuses the real systems wherever they work headless: GameState for
## profile/expedition/XP/leveling state, Itemizer for every item generated,
## LootPickup.spawn_for() for gold/scrap kills (it already falls back to a
## no-visual award when there is no battle_world in the tree), Item for
## prices, SlotIcon/SlotMachine.draw_nine() for the real bag/board math.
##
## What is NOT the real BattleDirector: a full 3D fight needs a scene tree,
## animation players and a live camera, impractical to run thousands of times
## headless. Combat is a discrete-event numeric resolver instead - every
## actor (hero melee, the hero's slot spins, each enemy) gets its own
## attack_cooldown-paced clock, jittered exactly as
## BattleDirector._roll_initial_cooldown() does, and events are processed in
## time order until one side is dead. This drops animation/impact-delay
## timing (a small, roughly-constant per-cycle offset that does not change
## average DPS) and the payline-triple double-resolve bonus (a few-percent
## underestimate of party output, conservative for "how many attempts").
##
## The one place this script IS an "AI player", not the real game, is between
## expeditions: gear/forge/buy/heal decisions need a stated heuristic since a
## real player chooses by eye. See _town_phase()'s comment for exactly what it
## does. Change that heuristic and the number changes - this is an estimate of
## a reasonable player's pace, not a guarantee.

const QUEST_PATH := "res://resources/quests/easy.tres"
const NUM_PLAYERS := 100
const MAX_ATTEMPTS := 100   # give up and record as "did not complete" past this

## Ruleset toggle. false (default, current shipped behaviour): kills bank XP
## into GameState.expedition_xp and it is applied once, at expedition end, via
## apply_expedition_xp() - a hero's level (and max_hp) never changes mid-fight.
## true: each kill's XP is applied to the hero THE INSTANT it dies, via the
## same GameState._apply_xp_to_hero() the real banked path eventually calls -
## a level-up (and the max_hp/current_hp bump it carries) can land mid-combat,
## strengthening the hero for the rest of that same fight and expedition.
## Reaching into a leading-underscore GameState method is deliberate here: this
## is an analysis tool comparing two rulesets, not shipped game code, and
## reusing the real curve/cap/HP-delta logic beats re-deriving an approximation
## of it.
const XP_APPLIED_IMMEDIATELY := false

var _attempts: Array[int] = []
var _gave_up := 0
var _quest: QuestDef

func _ready() -> void:
	_quest = load(QUEST_PATH)
	for p: int in range(NUM_PLAYERS):
		var n := _simulate_player()
		if n < 0:
			_gave_up += 1
		else:
			_attempts.append(n)
		if (p + 1) % 100 == 0:
			print("... %d / %d simulated players done" % [p + 1, NUM_PLAYERS])
	_report()
	get_tree().quit()

# =============================================================================
# One simulated player's whole career: repeat the easy expedition, with a full
# town cycle between attempts, until it clears or MAX_ATTEMPTS is reached.
# Returns the attempt number that won, or -1 if it never did.
# =============================================================================

func _simulate_player() -> int:
	GameState.new_profile()
	_town_phase()   # spend the starting 150 gold before the first attempt
	for attempt: int in range(1, MAX_ATTEMPTS + 1):
		GameState.start_expedition(_quest)
		var won := _run_expedition()
		GameState.apply_expedition_xp()
		if won:
			return attempt
		GameState.discard_expedition_loot()
		# Mirrors run_controller.gd's T2 (QUEST -> NIGHT_PENDING) so
		# resolve_night() below is reachable, same as a real loss.
		GameState.day_phase = GameState.DayPhase.NIGHT_PENDING
		GameState.quest = null
		GameState.meal_pct = 0
		_town_phase()
	return -1

## Runs the quest's 5 encounters against GameState.level (already built by
## start_expedition()). Returns true iff the boss encounter is cleared.
func _run_expedition() -> bool:
	var stats := GameState.get_stats(&"warrior")
	var level := GameState.hero_level(&"warrior")
	var entry := GameState.hero_entry(&"warrior")
	var hero := {
		"max_hp": stats.hp_at(level),
		"hp": int(entry.get("current_hp", stats.hp_at(level))),
		"level": level,
	}
	var won := true
	for enc: EncounterDef in GameState.level.encounters:
		match enc.type:
			EncounterDef.Type.COMBAT:
				if not _run_combat(enc, hero):
					won = false
					break
			EncounterDef.Type.LOOT:
				_run_loot(enc)
			EncounterDef.Type.SHOP:
				_run_shop(enc)
	entry["current_hp"] = hero["hp"]
	entry["max_hp"] = hero["max_hp"]
	entry["alive"] = hero["hp"] > 0
	return won

# =============================================================================
# Combat: discrete-event numeric resolver
# =============================================================================

## Builds the encounter's enemy list exactly as battle_director.start_combat()
## does: slot 0 of a boss encounter is duplicated, leveled up by
## BOSS_LEVEL_BONUS and its max_hp/hp_per_level scaled by BOSS_HP_MULT before
## the level resolve (the corrected Phase 2 fix), drop_chance forced to 1.0,
## drop_rarity_floor raised to the encounter's own boss_drop_rarity_floor.
func _spawn_enemies(enc: EncounterDef) -> Array:
	var out: Array = []
	for i: int in range(enc.enemy_stat_ids.size()):
		var s := GameState.get_stats(enc.enemy_stat_ids[i])
		if s == null:
			continue
		var lvl: int = enc.level
		var is_boss_unit: bool = enc.is_boss and i == 0
		var max_hp: int
		var drop_chance: float = s.drop_chance
		var drop_floor: int = s.drop_rarity_floor
		if is_boss_unit:
			lvl += Tuning.BOSS_LEVEL_BONUS
			var boosted_base: int = int(round(float(s.max_hp) * Tuning.BOSS_HP_MULT))
			var boosted_growth: int = int(round(float(s.hp_per_level) * Tuning.BOSS_HP_MULT))
			max_hp = CombatantStats.at_level(boosted_base, boosted_growth, lvl)
			drop_chance = 1.0
			drop_floor = maxi(drop_floor, maxi(1, enc.boss_drop_rarity_floor))
		else:
			max_hp = s.hp_at(lvl)
		out.append({
			"stats": s, "level": lvl, "hp": max_hp, "max_hp": max_hp,
			"weapon_power": s.weapon_power_at(lvl), "attack_cooldown": s.attack_cooldown,
			"is_boss_unit": is_boss_unit, "drop_chance": drop_chance, "drop_floor": drop_floor,
			"next_action": s.attack_cooldown * Tuning.COOLDOWN_START_FRACTION
				* RNG.randf_range(1.0 - Tuning.COOLDOWN_START_JITTER, 1.0 + Tuning.COOLDOWN_START_JITTER),
		})
	return out

const _SPIN_CYCLE := Tuning.SLOT_SPIN_DURATION + Tuning.SLOT_REEL_STAGGER * 2.0 + Tuning.SLOT_RESULT_HOLD

## [balance pass] The hero no longer melees off its own cooldown - the slot
## spin is the party's ONLY action (Defend went with it, shelved). The
## resolver is just "slot spins vs enemy swings" now. Enemies pay their attack
## clip on top of attack_cooldown, matching test_level_curves' ENEMY_ATTACK_CLIP.
const _ENEMY_ATTACK_CLIP := 0.8

## `hero` is mutated in place (hp). Returns true if every enemy dies before
## the hero's hp reaches 0.
func _run_combat(enc: EncounterDef, hero: Dictionary) -> bool:
	var enemies := _spawn_enemies(enc)
	if enemies.is_empty():
		return true

	var t := 0.0
	var hero_next_spin: float = _SPIN_CYCLE

	var guard := 0
	while hero["hp"] > 0 and _living(enemies) and guard < 20000:
		guard += 1
		# The next event is the hero's slot spin or the soonest enemy swing.
		var next_t: float = hero_next_spin
		var acting_enemy: Dictionary = {}
		for e: Dictionary in enemies:
			if e["hp"] > 0 and e["next_action"] < next_t:
				next_t = e["next_action"]
				acting_enemy = e
		t = next_t

		if not acting_enemy.is_empty():
			acting_enemy["next_action"] = t + acting_enemy["attack_cooldown"] + _ENEMY_ATTACK_CLIP
			var raw: float = float(acting_enemy["weapon_power"]) \
				* RNG.randf_range(1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE)
			hero["hp"] -= maxi(1, int(round(raw)))
		else:
			hero_next_spin = t + _SPIN_CYCLE
			_resolve_spin(hero, enemies)

		# One death check per event, after whichever branch above ran - this is
		# the ONLY place _on_enemy_died() is called, so a kill is counted
		# exactly once regardless of which action landed it (melee, spin
		# DAMAGE, or spin DAMAGE_ALL hitting several at once).
		for e: Dictionary in enemies:
			if e["hp"] <= 0 and not e.get("_counted", false):
				e["_counted"] = true
				_on_enemy_died(e, hero)

	return hero["hp"] > 0

func _living(enemies: Array) -> bool:
	for e: Dictionary in enemies:
		if e["hp"] > 0:
			return true
	return false

func _random_living(enemies: Array) -> Variant:
	var pool: Array = []
	for e: Dictionary in enemies:
		if e["hp"] > 0:
			pool.append(e)
	if pool.is_empty():
		return null
	return pool[RNG.randi_range(0, pool.size() - 1)]

## Awards XP/gold/scrap/a possible drop for one enemy death - the numeric
## equivalent of battle_director._on_combatant_died() + LootPickup.spawn_for().
##
## `hero` is the in-combat state dict (see _run_combat) - only touched when
## XP_APPLIED_IMMEDIATELY, to sync GameState.hero_runtime to the LIVE in-fight
## HP before applying (so a level-up's HP-delta lands on the real current HP,
## not the stale pre-fight snapshot _run_expedition() seeded it from) and to
## read the result back afterward (level/max_hp/current_hp can all change mid-
## kill, and every later event in this same fight must see the new numbers).
func _on_enemy_died(e: Dictionary, hero: Dictionary) -> void:
	var xp: int = Tuning.XP_PER_ENEMY_LEVEL * int(e["level"])
	if e["is_boss_unit"]:
		xp = int(round(float(xp) * Tuning.XP_BOSS_MULT))
	LootPickup.spawn_for(Vector3.ZERO, e["is_boss_unit"])
	if RNG.randf() <= float(e["drop_chance"]):
		var hero_class := GameState.next_drop_class(e["is_boss_unit"] and Tuning.DROP_BOSS_TARGETS_HUNGRIEST)
		if hero_class != &"":
			var item := Itemizer.generate_drop(hero_class, e["drop_floor"], int(e["level"]))
			GameState.record_drop(hero_class)
			GameState.add_item(item)
			_maybe_upgrade_swap(item)

	if XP_APPLIED_IMMEDIATELY:
		var entry := GameState.hero_entry(&"warrior")
		if not entry.is_empty():
			entry["current_hp"] = hero["hp"]
			entry["max_hp"] = hero["max_hp"]
			entry["alive"] = hero["hp"] > 0
		GameState._apply_xp_to_hero(&"warrior", xp)
		var updated := GameState.hero_entry(&"warrior")
		hero["level"] = GameState.hero_level(&"warrior")
		if not updated.is_empty():
			hero["max_hp"] = int(updated.get("max_hp", hero["max_hp"]))
			hero["hp"] = int(updated.get("current_hp", hero["hp"]))
	else:
		GameState.expedition_xp += xp

## One slot spin's worth of resolution: rebuild the bag from currently
## equipped gear, draw 9, resolve mult icons first, then every DAMAGE /
## DAMAGE_ALL / HEAL icon - the same shape as slot_machine._resolve_board(),
## minus the payline-triple double-resolve (a conservative, few-percent
## underestimate of party output).
func _resolve_spin(hero: Dictionary, enemies: Array) -> void:
	var bag := _build_bag(hero["level"])
	var board: Array = SlotMachineScript.draw_nine(bag)
	var pct := 0
	for ic: Dictionary in board:
		if SlotIcon.kind_of(StringName(ic.get("id", &""))) == SlotIcon.Kind.MULT:
			pct += int(ic.get("roll", 0))
	var mult := (1.0 + float(pct) / 100.0) * Upgrades.overcharge_mult()
	for ic: Dictionary in board:
		var kind: int = SlotIcon.kind_of(StringName(ic.get("id", &"")))
		var roll := int(ic.get("roll", 0))
		match kind:
			SlotIcon.Kind.DAMAGE:
				var target = _random_living(enemies)
				if target != null:
					target["hp"] -= _rolled(roll, mult)
			SlotIcon.Kind.DAMAGE_ALL:
				for e: Dictionary in enemies:
					if e["hp"] > 0:
						e["hp"] -= _rolled(roll, mult)
			SlotIcon.Kind.HEAL:
				var amount: int = maxi(1, int(round(float(hero["max_hp"]) * float(roll) / 100.0)))
				hero["hp"] = mini(hero["max_hp"], hero["hp"] + amount)

func _rolled(roll: int, mult: float) -> int:
	# [balance pass] + the flat per-attack-icon floor (slot_machine._strike).
	var base := maxi(1, int(round(float(roll) * mult))) + Tuning.SLOT_ATTACK_ICON_FLOOR
	return maxi(1, int(round(float(base) * RNG.randf_range(
		1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE))))

## The warrior's current slot bag - one innate icon plus one base icon and its
## modifier icons per equipped item (spec §4.3), same as
## SlotMachine._rebuild_bag(). Upgrades stay at level 0 (see the town-phase
## comment), so the blank pad is the unmodified SLOT_BLANK_PAD_START.
func _build_bag(level: int) -> Array:
	var bag: Array = []
	bag.append(SlotIcon.innate(&"warrior", GameState.hero_weapon_power(&"warrior")))
	for item: Item in GameState.inventory:
		if item.equipped_by == &"":
			continue
		bag.append(SlotIcon.from_item_base(item))
		for mod: Dictionary in item.modifiers:
			var ic := SlotIcon.from_modifier(mod, item)
			if not ic.is_empty():
				bag.append(ic)
	for _i: int in range(Tuning.SLOT_BLANK_PAD_START):
		bag.append(SlotIcon.blank())
	return bag

# =============================================================================
# LOOT / SHOP encounters
# =============================================================================

func _run_loot(enc: EncounterDef) -> void:
	for item: Item in Itemizer.generate_items(Tuning.LOOT_ITEMS_PER_CHEST, enc.level):
		GameState.add_item(item)
		_maybe_upgrade_swap(item)

## Buys anything that (a) fills an empty slot or (b) beats the currently
## equipped item's value, spending down to whatever gold is on hand. `value`
## is the right proxy for "board power" here: it already folds in rarity,
## item level and every rolled modifier (Itemizer._generate_typed()'s own
## value formula), which is exactly what decides an item's total icon output.
func _run_shop(enc: EncounterDef) -> void:
	for item: Item in Itemizer.generate_shop_stock(enc.level):
		var price := item.buy_price()
		if GameState.gold < price:
			continue
		var current := GameState.equipped_item(&"warrior", item.slot())
		if current != null and item.value <= current.value:
			continue
		if GameState.spend_gold(price):
			GameState.add_item(item)
			_maybe_upgrade_swap(item)

## GameState.add_item()'s auto-equip only fills an EMPTY slot (never swaps).
## This is the "player" half: swap into an occupied slot if the new item is a
## strict upgrade by value.
func _maybe_upgrade_swap(item: Item) -> void:
	if item.equipped_by != &"":
		return   # auto-equip already handled an empty slot
	var current := GameState.equipped_item(&"warrior", item.slot())
	if current == null or item.value > current.value:
		GameState.equip_item(item, &"warrior")

# =============================================================================
# Town phase (the "AI player" heuristic)
#
# In order: sell every unequipped item for gold; buy from a freshly generated
# blacksmith stock (6 cards) anything that upgrades a slot, cheapest-affects-
# first is NOT modeled - cards are taken in generation order, matching a
# player scanning left to right rather than optimally; forge the weapon slot
# first, then armor, then trinket (prioritising offense) with whatever
# scrap+gold remain, one rung at a time, until nothing more is affordable;
# buy today's meal if affordable; sleep at the inn if affordable (full heal),
# else free street sleep (partial). Upgrades (Quick Reels/Overcharge/Polish)
# are never bought - modeled as a player who spends everything on permanent
# gear instead of a per-run consumable.
# =============================================================================

func _town_phase() -> void:
	_sell_unequipped()
	_visit_blacksmith_buy()
	_forge_pass()
	if GameState.day_phase == GameState.DayPhase.DAY and not GameState.meal_eaten_today:
		if GameState.gold >= GameState.meal_cost():
			GameState.buy_meal()
	if GameState.day_phase == GameState.DayPhase.NIGHT_PENDING:
		if GameState.gold >= GameState.night_inn_cost():
			GameState.resolve_night(GameState.NightChoice.INN)
		else:
			GameState.resolve_night(GameState.NightChoice.STREET)

func _sell_unequipped() -> void:
	for i: int in range(GameState.inventory.size() - 1, -1, -1):
		var item: Item = GameState.inventory[i]
		if item.equipped_by == &"":
			GameState.add_gold(item.sell_price())
			GameState.remove_item(item)

func _visit_blacksmith_buy() -> void:
	for item: Item in Itemizer.generate_forge_stock(GameState.hero_level(&"warrior")):
		var price := item.buy_price()
		if GameState.gold < price:
			continue
		var current := GameState.equipped_item(&"warrior", item.slot())
		if current != null and item.value <= current.value:
			continue
		if GameState.spend_gold(price):
			GameState.add_item(item)
			_maybe_upgrade_swap(item)

func _forge_pass() -> void:
	var slots: Array[Item.Slot] = [Item.Slot.WEAPON, Item.Slot.ARMOR, Item.Slot.TRINKET]
	var progressed := true
	while progressed:
		progressed = false
		for s: Item.Slot in slots:
			var item := GameState.equipped_item(&"warrior", s)
			if item == null or item.rarity >= Item.Rarity.ENHANCED:
				continue
			var cost: Array = Tuning.FORGE_COSTS[item.rarity]
			if GameState.scrap >= int(cost[0]) and GameState.gold >= int(cost[1]):
				if Itemizer.forge(item):
					progressed = true

# =============================================================================
# Report
# =============================================================================

func _report() -> void:
	_attempts.sort()
	print("\n=== easy expedition: attempts from a fresh profile to first clear ===")
	print("players simulated: %d | never cleared within %d attempts: %d"
		% [NUM_PLAYERS, MAX_ATTEMPTS, _gave_up])
	if _attempts.is_empty():
		print("no player ever cleared it - see _gave_up above")
		return
	var n := _attempts.size()
	var sum := 0
	for a: int in _attempts:
		sum += a
	var mean := float(sum) / float(n)
	var median: float = _percentile(50.0)
	var p10 := _percentile(10.0)
	var p25 := _percentile(25.0)
	var p75 := _percentile(75.0)
	var p90 := _percentile(90.0)
	print("mean %.2f | median %.1f | p10 %.1f | p25 %.1f | p75 %.1f | p90 %.1f | min %d | max %d"
		% [mean, median, p10, p25, p75, p90, _attempts[0], _attempts[-1]])
	# A small histogram, attempt 1..12, then a tail bucket.
	var buckets := {}
	for a: int in _attempts:
		var k: int = mini(a, 13)
		buckets[k] = int(buckets.get(k, 0)) + 1
	for k: int in range(1, 14):
		var count: int = int(buckets.get(k, 0))
		if count == 0:
			continue
		var label: String = ("%d" % k) if k < 13 else "13+"
		print("  attempt %-3s: %s (%d)" % [label, "#".repeat(maxi(1, int(round(float(count) / float(n) * 60.0)))), count])

func _percentile(p: float) -> float:
	if _attempts.is_empty():
		return -1.0
	var idx: float = p / 100.0 * float(_attempts.size() - 1)
	var lo: int = int(floor(idx))
	var hi: int = int(ceil(idx))
	if lo == hi:
		return float(_attempts[lo])
	var frac: float = idx - float(lo)
	return lerpf(float(_attempts[lo]), float(_attempts[hi]), frac)

const SlotMachineScript := preload("res://scripts/console/slot_machine.gd")
