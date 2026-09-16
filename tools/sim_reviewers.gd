extends Node
## Three reviewer-archetype playthroughs: fresh profile -> hero level 5, each
## recruiting one of the two available party members along the way.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tools/sim_reviewers.tscn
##
## WHY THIS EXISTS, AND WHAT IT IS NOT
##
## This is a play-FEEL instrument, not a balance one. tools/sim_easy_attempts.gd
## already answers "how many tries to clear the easy quest" (and is currently
## broken - it calls GameState.day_phase / DayPhase / resolve_night, none of
## which exist any more). The question here is different: what does a given
## KIND of player actually experience on the way to level 5 - how long it takes
## in wall-clock seconds, how many decisions they are asked to make, and how
## much of that time they spend as a spectator with no input available.
##
## Those three numbers are what separate the three archetypes, so they are what
## this measures. Damage numbers are only here because you cannot get to level
## 5 without resolving combat.
##
## REUSED REAL SYSTEMS (the same trick sim_easy_attempts.gd uses): GameState for
## profile/expedition/XP/level state, Itemizer for every generated item, Item
## for prices, SlotIcon + SlotMachine.draw_nine() for the real bag and board,
## Upgrades for real upgrade costs and multipliers, and the real QuestDef /
## LevelDef / EncounterDef resources. Nothing about loot, levelling, pricing or
## the slot bag is re-derived here.
##
## NOT the real BattleDirector: a 3D fight needs a scene tree, AnimationPlayers
## and a camera, so combat is a discrete-event numeric resolver - every enemy
## gets its own attack_cooldown-paced clock (jittered exactly as
## BattleDirector._roll_initial_cooldown does) and the party gets one clock per
## slot spin cycle. It models the CURRENT slot rules: all DAMAGE icons on a
## board sum into ONE combined swing (slot_machine._resolve_board), the centre
## row double-resolves on a payline triple, crit doubles its own icon's share,
## BLOCK is max-not-sum for BLOCK_DURATION, and AoE icons resolve per-cell.
##
## Known unmodelled, all of them small and all of them CONSERVATIVE (they make
## the party slightly weaker than the real game): BLEED's damage-over-time,
## CLEAVE/RAIN's cross-spin buff, and per-target animation timing.
##
## The honest caveat, same as sim_easy_attempts.gd's: the town/gear/quest
## DECISIONS are a stated heuristic per archetype, not the real game. A real
## player chooses by eye. Change a policy below and that archetype's numbers
## change - this is a model of three stated play styles, not a measurement of
## three real humans.

const SlotMachineScript := preload("res://scripts/console/slot_machine.gd")

const TARGET_LEVEL := 5
const MAX_EXPEDITIONS := 40      # safety valve; a run that needs more is reported as stalled

## The two recruitable party members (GameState.new_profile() starts solo
## warrior; RecruitRewardExtra is the only path into the party).
const RECRUIT_QUESTS := {
	&"ranger": "res://resources/quests/ranger_recruit.tres",
	&"mage": "res://resources/quests/recruit_mage.tres",
}

## --- the three archetypes ---------------------------------------------------
##
## Each is a stated play style turned into a decision policy. The fields that
## matter for the measured outcome:
##   deliberation_s   seconds spent in town per visit, per screen they open -
##                    a proxy for "reads the cards" vs "knows what it wants".
##   shop_modal_s     seconds held on the mid-expedition shop modal, which is
##                    the ONLY blocking interaction inside a run.
##   buys_upgrades    whether they spend run gold in the console's upgrade tray -
##                    the only input the game accepts DURING combat.
##   upgrade_order    priority when they do.
##   sells/forges/    town economy engagement.
##   swaps_gear       whether they re-equip a better drop, or leave auto-equip
##                    (which only ever fills an EMPTY slot) to decide for them.
##   quest_pick       "safest" | "hardest" | "first" - how they read the board.
const ARCHETYPES := [
	{
		"id": &"casual",
		"name": "The Casual Game Lover",
		"seed": 20260916,
		# Plays at the game's pace and enjoys the spectacle; opens every screen.
		"deliberation_s": 25.0,
		"shop_modal_s": 18.0,
		"buys_upgrades": true,
		# Wants the board busier and the payouts splashier before it wants speed.
		"upgrade_order": [&"polish", &"overcharge", &"quick_reels"],
		"sells_junk": true,
		"buys_gear": true,
		"forges": true,
		"buys_meal": true,
		"rests_at_inn": true,
		"swaps_gear": true,
		"quest_pick": "safest",
		# A new party member is the draw, so they take the recruit quest early.
		"recruit_asap": true,
	},
	{
		"id": &"hardcore",
		"name": "The Hardcore Gamer",
		"seed": 20260917,
		# Knows what it wants the moment the screen opens; no browsing.
		"deliberation_s": 6.0,
		"shop_modal_s": 4.0,
		"buys_upgrades": true,
		# Damage first, then cycle speed. Polish last - denser boards are a
		# throughput gain, but overcharge is the direct dps lever.
		"upgrade_order": [&"overcharge", &"quick_reels", &"polish"],
		"sells_junk": true,
		"buys_gear": true,
		"forges": true,
		"buys_meal": true,
		# Skips the bed unless actually hurt - gold is for permanent power.
		"rests_at_inn": false,
		"swaps_gear": true,
		"quest_pick": "hardest",
		"recruit_asap": false,
	},
	{
		"id": &"nongamer",
		"name": "The Non-Gamer",
		"seed": 20260918,
		# Slow, but not because they are savouring it - they are working out
		# what the screen wants from them.
		"deliberation_s": 40.0,
		"shop_modal_s": 30.0,
		# Never finds the upgrade tray: it is a console widget that never asks
		# to be pressed.
		"buys_upgrades": false,
		"upgrade_order": [],
		"sells_junk": false,
		"buys_gear": false,
		"forges": false,
		"buys_meal": false,
		"rests_at_inn": false,
		# Leaves gear to auto-equip, which only fills an empty slot, never swaps.
		"swaps_gear": false,
		"quest_pick": "first",
		"recruit_asap": false,
	},
]

# --- timing model (all constants are the real Tuning values) -----------------

## One slot spin cycle at a given quick_reels multiplier, matching
## slot_machine._one_spin()'s awaits: the three reel stops scale with the
## upgrade, the 0.22 settle and the result hold do not.
func _spin_cycle(q: float) -> float:
	return (Tuning.SLOT_SPIN_DURATION + Tuning.SLOT_REEL_STAGGER * 2.0) * q \
		+ 0.22 + Tuning.SLOT_RESULT_HOLD

const ENEMY_ATTACK_CLIP := 0.8   # matches test_level_curves' ENEMY_ATTACK_CLIP

var _out: Array[String] = []

func _ready() -> void:
	_emit("# Sir Fish - reviewer archetype simulation")
	_emit("")
	_emit("Target: hero level %d from a fresh profile, recruiting one party member." % TARGET_LEVEL)
	_emit("")
	for arch: Dictionary in ARCHETYPES:
		var log := _play(arch)
		_report(arch, log)
	print("\n".join(_out))
	get_tree().quit()

func _emit(line: String) -> void:
	_out.append(line)

# =============================================================================
# One archetype's whole playthrough
# =============================================================================

## Returns a telemetry dictionary. `seconds` is modelled real playtime: every
## await the real RunController / SlotMachine performs, plus the archetype's own
## deliberation time in town.
func _play(arch: Dictionary) -> Dictionary:
	RNG.set_seed(int(arch["seed"]))
	GameState.new_profile()
	Upgrades.reset()

	# Which of the two recruits this reviewer happens to go after. Random per
	# reviewer, per the brief ("one random party member from the two available").
	var recruit_ids: Array = RECRUIT_QUESTS.keys()
	var recruit_id: StringName = recruit_ids[RNG.randi_range(0, recruit_ids.size() - 1)]

	var log := {
		"recruit_target": recruit_id,
		"recruited": false,
		"recruited_on": -1,
		"seconds": 0.0,
		"combat_seconds": 0.0,
		"travel_seconds": 0.0,
		"town_seconds": 0.0,
		"input_events": 0,           # discrete taps/clicks the player makes
		"in_combat_inputs": 0,       # of those, ones available DURING a fight
		"spins": 0,
		"expeditions": 0,
		"wipes": 0,
		"wins": 0,
		"first_win": -1,
		"items_found": 0,
		"items_equipped": 0,
		"gold_spent": 0,
		"upgrades_bought": 0,
		"forges": 0,
		"levels": [],                # (expedition_index, level) as it rises
		"stalled": false,
	}

	# The first town visit: spend the starting 150 gold before heading out.
	_town_phase(arch, log)

	for expedition: int in range(1, MAX_EXPEDITIONS + 1):
		var q := _choose_quest(arch, log, expedition)
		if q == null:
			log["stalled"] = true
			break
		log["expeditions"] = expedition
		# Accepting a quest at the mayor's office: open board, read, accept.
		log["input_events"] = int(log["input_events"]) + 2

		GameState.start_expedition(q)
		# Upgrades are RUN-scoped (Upgrades.reset() from start_expedition) - every
		# upgrade bought last expedition is gone. This is load-bearing for the
		# review: it is why the only in-combat input resets to zero every trip.
		var won := _run_expedition(arch, log)
		GameState.apply_expedition_xp()

		if won:
			log["wins"] = int(log["wins"]) + 1
			if int(log["first_win"]) < 0:
				log["first_win"] = expedition
			GameState.add_gold(q.gold_reward)
			# Observe the PARTY, not the reward's existence: a RecruitRewardExtra
			# whose hero_class failed to bind grants nothing while still
			# reporting kind() == &"recruit". Trusting kind() here is what made
			# the first run of this tool claim a ranger had joined a solo party.
			var before: int = GameState.active_party.size()
			for extra: QuestRewardExtra in q.reward_extras:
				extra.grant()
			if GameState.active_party.size() > before and not bool(log["recruited"]):
				log["recruited"] = true
				log["recruited_on"] = expedition
			if q.one_shot and not GameState.completed_quest_ids.has(q.id):
				GameState.completed_quest_ids.append(q.id)
			GameState.recover_after_expedition(true)
			log["seconds"] = float(log["seconds"]) + 2.0    # the victory run-off
		else:
			log["wipes"] = int(log["wipes"]) + 1
			GameState.discard_expedition_loot()
			GameState.recover_after_expedition(false)
			log["seconds"] = float(log["seconds"]) + 1.0    # the hold on the wipe

		GameState.quest = null
		# Dismissing the quest result modal.
		log["input_events"] = int(log["input_events"]) + 1

		var lvl := GameState.hero_level(&"warrior")
		(log["levels"] as Array).append([expedition, lvl])
		if lvl >= TARGET_LEVEL and bool(log["recruited"]):
			break

		_town_phase(arch, log)

	# Honest goal check: running the expedition budget out without both halves of
	# the goal is a STALL, not a finish. The first version of this reporter left
	# `stalled` false in that case and printed a final level of 9 as though the
	# run had succeeded.
	if GameState.hero_level(&"warrior") < TARGET_LEVEL or not bool(log["recruited"]):
		log["stalled"] = true
	log["final_level"] = GameState.hero_level(&"warrior")
	log["party"] = GameState.active_party.duplicate()
	log["gold"] = GameState.gold
	return log

## The mayor's board, exactly as mayor_office.gd assembles it: "Today's
## Postings" (GameState.quest_board_offers() - generated, anchored on the
## party's CURRENT level) followed by every authored quest on disk, minus any
## recruitment quest whose class has already joined, sorted by level_range.x.
##
## This matters a lot. The generated postings scale with the party; the
## authored easy/medium/hard do NOT, and sit on the same board at every level.
## Which of the two a given archetype reaches for is most of what separates
## their experiences.
func _board() -> Array[QuestDef]:
	var out: Array[QuestDef] = []
	out.append_array(GameState.quest_board_offers())
	var dir := DirAccess.open("res://resources/quests/")
	if dir != null:
		for file_name: String in dir.get_files():
			var clean := file_name.trim_suffix(".remap")
			if not clean.ends_with(".tres"):
				continue
			var res := load("res://resources/quests/" + clean)
			if res is QuestDef and not _already_recruited(res as QuestDef):
				out.append(res as QuestDef)
	out.sort_custom(func(a: QuestDef, b: QuestDef) -> bool:
		return a.level_range.x < b.level_range.x)
	return out

func _already_recruited(q: QuestDef) -> bool:
	for extra: QuestRewardExtra in q.reward_extras:
		if extra is RecruitRewardExtra \
				and GameState.active_party.has((extra as RecruitRewardExtra).hero_class):
			return true
	return false

## Whether `q` is the recruitment quest this reviewer is chasing.
func _is_target_recruit(q: QuestDef, log: Dictionary) -> bool:
	for extra: QuestRewardExtra in q.reward_extras:
		if extra is RecruitRewardExtra \
				and (extra as RecruitRewardExtra).hero_class == log["recruit_target"]:
			return true
	return false

## Which quest this archetype accepts next, chosen off the real board.
func _choose_quest(arch: Dictionary, log: Dictionary, expedition: int) -> QuestDef:
	var board := _board()
	if board.is_empty():
		return null
	var lvl := GameState.hero_level(&"warrior")

	# The recruit quest is the only thing on the board that changes the party.
	if not bool(log["recruited"]):
		for q: QuestDef in board:
			if not _is_target_recruit(q, log):
				continue
			# The casual player takes it the moment they see it; the others get
			# to it once they have a level or two behind them.
			if bool(arch["recruit_asap"]) or expedition >= 2 or lvl >= 3:
				return q

	match String(arch["quest_pick"]):
		"hardest":
			# Reaches for the highest-level contract on the board, which is how
			# an authored quest far above the party's band gets accepted.
			var hardest: QuestDef = board[0]
			for q: QuestDef in board:
				if q.level_range.y > hardest.level_range.y:
					hardest = q
			return hardest
		"safest":
			var safest: QuestDef = board[0]
			for q: QuestDef in board:
				if q.level_range.y < safest.level_range.y:
					safest = q
			return safest
		_:
			# Takes whatever is at the top of the list.
			return board[0]

# =============================================================================
# One expedition
# =============================================================================

## Runs GameState.level's encounters. Returns true iff the party survives them
## all. Mutates `log` with time and input telemetry.
func _run_expedition(arch: Dictionary, log: Dictionary) -> bool:
	var party := _build_party()
	var won := true
	var encounters: Array = GameState.level.encounters

	for i: int in range(encounters.size()):
		var enc: EncounterDef = encounters[i]
		# Travel into the encounter: the run-in plus the decel on arrival.
		var travel: float = enc.travel_duration + Tuning.TRAVEL_DECEL_TIME
		log["travel_seconds"] = float(log["travel_seconds"]) + travel
		log["seconds"] = float(log["seconds"]) + travel

		match enc.type:
			EncounterDef.Type.COMBAT:
				if not _run_combat(arch, log, enc, party):
					won = false
					break
			EncounterDef.Type.LOOT:
				_run_loot(arch, log, enc)
			EncounterDef.Type.SHOP:
				_run_shop(arch, log, enc)

		# ENCOUNTER_RESOLVE_PAUSE between "cleared" and travel restarting.
		log["seconds"] = float(log["seconds"]) + Tuning.ENCOUNTER_RESOLVE_PAUSE

	_store_party(party)
	return won

## One dict per living party member, seeded from profile HP/level/gear.
func _build_party() -> Array:
	var out: Array = []
	for id: StringName in GameState.active_party:
		var entry := GameState.hero_entry(id)
		var max_hp := GameState.hero_max_hp(id)
		out.append({
			"id": id,
			"max_hp": max_hp,
			"hp": int(entry.get("current_hp", max_hp)) if not entry.is_empty() else max_hp,
			"armor": GameState.hero_armor(id),
			"block": 0,
			"block_until": -1.0,
		})
	return out

func _store_party(party: Array) -> void:
	for h: Dictionary in party:
		var entry := GameState.hero_entry(h["id"])
		if entry.is_empty():
			continue
		entry["current_hp"] = maxi(0, int(h["hp"]))
		entry["max_hp"] = int(h["max_hp"])
		entry["alive"] = int(h["hp"]) > 0

# =============================================================================
# Combat: discrete-event resolver
# =============================================================================

## Mirrors battle_director.start_combat()'s boss handling: slot 0 of a boss
## encounter gets BOSS_LEVEL_BONUS levels and its max_hp/hp_per_level scaled by
## BOSS_HP_MULT before the level resolve, drop_chance forced to 1.0, and its
## drop floor raised to the encounter's boss_drop_rarity_floor.
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
			"weapon_power": s.weapon_power_at(lvl),
			"attack_cooldown": s.attack_cooldown,
			"is_boss_unit": is_boss_unit,
			"drop_chance": drop_chance, "drop_floor": drop_floor,
			"next_action": s.attack_cooldown * Tuning.COOLDOWN_START_FRACTION
				* RNG.randf_range(1.0 - Tuning.COOLDOWN_START_JITTER,
					1.0 + Tuning.COOLDOWN_START_JITTER),
		})
	return out

func _run_combat(arch: Dictionary, log: Dictionary, enc: EncounterDef, party: Array) -> bool:
	var enemies := _spawn_enemies(enc)
	if enemies.is_empty():
		return true

	var t := 0.0
	var next_spin: float = _spin_cycle(Upgrades.quick_reels_mult())
	var guard := 0

	while _any_alive(party) and _living(enemies) and guard < 20000:
		guard += 1

		# During a fight the ONLY thing a player may press is the upgrade tray.
		# Model it as: when they can afford their next priority, they buy it.
		if bool(arch["buys_upgrades"]):
			_maybe_buy_upgrade(arch, log)

		var next_t: float = next_spin
		var acting: Dictionary = {}
		for e: Dictionary in enemies:
			if e["hp"] > 0 and e["next_action"] < next_t:
				next_t = e["next_action"]
				acting = e
		t = next_t

		if not acting.is_empty():
			acting["next_action"] = t + float(acting["attack_cooldown"]) + ENEMY_ATTACK_CLIP
			var target: Variant = _random_living_hero(party)
			if target != null:
				var raw: float = float(acting["weapon_power"]) * RNG.randf_range(
					1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE)
				var block: int = int(target.get("block", 0)) \
					if t < float(target.get("block_until", -1.0)) else 0
				target["hp"] = int(target["hp"]) - maxi(1,
					int(round(raw)) - int(target["armor"]) - block)
		else:
			next_spin = t + _spin_cycle(Upgrades.quick_reels_mult())
			log["spins"] = int(log["spins"]) + 1
			_resolve_spin(log, party, enemies, t)

		for e: Dictionary in enemies:
			if e["hp"] <= 0 and not e.get("_counted", false):
				e["_counted"] = true
				_on_enemy_died(arch, log, e)

	log["combat_seconds"] = float(log["combat_seconds"]) + t
	log["seconds"] = float(log["seconds"]) + t
	return _any_alive(party)

## One spin, resolved as slot_machine._resolve_board() does it TODAY: every
## DAMAGE icon's contribution sums into a single combined swing at one random
## enemy; the centre row resolves twice on a payline triple; AoE icons hit every
## living enemy per-cell; HEAL tops up the lowest hero; BLOCK is granted to the
## whole party as temp armor, max-not-sum.
func _resolve_spin(log: Dictionary, party: Array, enemies: Array, now: float) -> void:
	var bag := _build_bag(party)
	var board: Array = SlotMachineScript.draw_nine(bag)
	var mult := Upgrades.overcharge_mult()
	var jackpot := _payline_triple(board)

	var swing := 0
	var block := 0
	for idx: int in range(board.size()):
		var ic: Dictionary = board[idx]
		var id := StringName(ic.get("id", &""))
		var kind: int = SlotIcon.kind_of(id)
		if kind == SlotIcon.Kind.BLANK:
			continue
		var repeats: int = 2 if (jackpot and idx >= 3 and idx <= 5) else 1
		for _r: int in range(repeats):
			var roll := int(ic.get("roll", 0))
			match kind:
				SlotIcon.Kind.DAMAGE:
					var contribution: int = maxi(1, int(round(float(roll) * mult))) \
						+ Tuning.SLOT_ATTACK_ICON_FLOOR
					if id == &"crit" and RNG.randf() < Tuning.CRIT_CHANCE:
						contribution *= 2
					swing += contribution
				SlotIcon.Kind.BLOCK:
					block += maxi(1, roll)
				SlotIcon.Kind.BOMB_ARROW, SlotIcon.Kind.THUNDERBURST:
					for e: Dictionary in enemies:
						if e["hp"] > 0:
							e["hp"] = int(e["hp"]) - _rolled(roll, mult)
				SlotIcon.Kind.HEAL:
					var low: Variant = _lowest_hero(party)
					if low != null:
						var amount: int = maxi(1, int(round(
							float(low["max_hp"]) * float(roll) / 100.0)))
						low["hp"] = mini(int(low["max_hp"]), int(low["hp"]) + amount)
				_:
					pass

	if swing > 0:
		var primary = _random_living_enemy(enemies)
		if primary != null:
			primary["hp"] = int(primary["hp"]) - maxi(1, int(round(float(swing)
				* RNG.randf_range(1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE))))
	if block > 0:
		for h: Dictionary in party:
			if int(h["hp"]) <= 0:
				continue
			var carried: int = int(h.get("block", 0)) \
				if now < float(h.get("block_until", -1.0)) else 0
			h["block"] = maxi(carried, block)
			h["block_until"] = now + Tuning.BLOCK_DURATION

## The centre row (indices 3-5) being three of the same non-blank icon.
func _payline_triple(board: Array) -> bool:
	var a := StringName((board[3] as Dictionary).get("id", &""))
	var b := StringName((board[4] as Dictionary).get("id", &""))
	var c := StringName((board[5] as Dictionary).get("id", &""))
	if a == &"" or SlotIcon.is_blank(board[3] as Dictionary):
		return false
	return a == b and b == c

func _rolled(roll: int, mult: float) -> int:
	var base := maxi(1, int(round(float(roll) * mult))) + Tuning.SLOT_ATTACK_ICON_FLOOR
	return maxi(1, int(round(float(base) * RNG.randf_range(
		1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE))))

## The live slot bag, exactly as slot_machine._rebuild_bag() builds it: one
## innate icon per LIVING party member, then every equipped item's base icon and
## its modifier icons (trinket ultimates damped by TRINKET_ICON_INCLUDE_CHANCE),
## then the blank pad less whatever Polish has bought off.
func _build_bag(party: Array) -> Array:
	var bag: Array = []
	var living: Array[StringName] = []
	for h: Dictionary in party:
		if int(h["hp"]) > 0:
			living.append(h["id"])
	for id: StringName in living:
		bag.append(SlotIcon.innate(id, GameState.hero_weapon_power(id)))
	for item: Item in GameState.inventory:
		if item.equipped_by == &"" or item.equipped_by not in living:
			continue
		bag.append(SlotIcon.from_item_base(item))
		for mod: Dictionary in item.modifiers:
			var ic := SlotIcon.from_modifier(mod, item)
			if ic.is_empty():
				continue
			var iid := StringName(ic.get("id", &""))
			var is_ult: bool = iid == &"crit" or iid == &"cleave" \
				or iid == &"rain" or iid == &"thunderburst"
			if is_ult and RNG.randf() >= Tuning.TRINKET_ICON_INCLUDE_CHANCE:
				continue
			bag.append(ic)
	var pad: int = maxi(Tuning.SLOT_BLANK_PAD_START - Upgrades.polish_blanks_removed(),
		Tuning.SLOT_BLANK_PAD_FLOOR)
	for _i: int in range(pad):
		bag.append(SlotIcon.blank())
	return bag

func _on_enemy_died(arch: Dictionary, log: Dictionary, e: Dictionary) -> void:
	var xp: int = Tuning.XP_PER_ENEMY_LEVEL * int(e["level"])
	if e["is_boss_unit"]:
		xp = int(round(float(xp) * Tuning.XP_BOSS_MULT))
	GameState.expedition_xp += xp
	LootPickup.spawn_for(Vector3.ZERO, e["is_boss_unit"])
	if RNG.randf() <= float(e["drop_chance"]):
		var hero_class := GameState.next_drop_class(
			e["is_boss_unit"] and Tuning.DROP_BOSS_TARGETS_HUNGRIEST)
		if hero_class != &"":
			var item := Itemizer.generate_drop(hero_class, int(e["drop_floor"]), int(e["level"]))
			GameState.record_drop(hero_class)
			GameState.add_item(item)
			log["items_found"] = int(log["items_found"]) + 1
			_maybe_swap(arch, log, item)

# --- small combat helpers ---------------------------------------------------

func _any_alive(party: Array) -> bool:
	for h: Dictionary in party:
		if int(h["hp"]) > 0:
			return true
	return false

func _living(enemies: Array) -> bool:
	for e: Dictionary in enemies:
		if int(e["hp"]) > 0:
			return true
	return false

func _random_living_hero(party: Array) -> Variant:
	var pool: Array = []
	for h: Dictionary in party:
		if int(h["hp"]) > 0:
			pool.append(h)
	if pool.is_empty():
		return null
	return pool[RNG.randi_range(0, pool.size() - 1)]

func _random_living_enemy(enemies: Array) -> Variant:
	var pool: Array = []
	for e: Dictionary in enemies:
		if int(e["hp"]) > 0:
			pool.append(e)
	if pool.is_empty():
		return null
	return pool[RNG.randi_range(0, pool.size() - 1)]

func _lowest_hero(party: Array) -> Variant:
	var best: Variant = null
	for h: Dictionary in party:
		if int(h["hp"]) <= 0:
			continue
		if best == null or float(h["hp"]) / float(h["max_hp"]) \
				< float(best["hp"]) / float(best["max_hp"]):
			best = h
	return best

# =============================================================================
# Non-combat encounters
# =============================================================================

func _run_loot(arch: Dictionary, log: Dictionary, enc: EncounterDef) -> void:
	# chest pop-in, open, then one glyph per item (run_controller._run_loot).
	var items := Itemizer.generate_items(Tuning.LOOT_ITEMS_PER_CHEST, enc.level)
	log["seconds"] = float(log["seconds"]) + 0.5 + 0.45 + 0.35 + 0.25 * float(items.size())
	for item: Item in items:
		GameState.add_item(item)
		log["items_found"] = int(log["items_found"]) + 1
		_maybe_swap(arch, log, item)

## The mid-expedition shop. This is the one BLOCKING interaction inside a run -
## the encounter does not resolve until the modal's close button is pressed.
func _run_shop(arch: Dictionary, log: Dictionary, enc: EncounterDef) -> void:
	log["seconds"] = float(log["seconds"]) + 0.4 + 0.45 + float(arch["shop_modal_s"])
	log["input_events"] = int(log["input_events"]) + 1        # the close button
	log["in_combat_inputs"] = int(log["in_combat_inputs"]) + 1
	if not bool(arch["buys_gear"]):
		return
	for item: Item in Itemizer.generate_shop_stock(enc.level):
		var price := item.buy_price()
		if GameState.gold < price:
			continue
		var current := GameState.equipped_item(&"warrior", item.slot())
		if current != null and item.value <= current.value:
			continue
		if GameState.spend_gold(price):
			log["gold_spent"] = int(log["gold_spent"]) + price
			log["input_events"] = int(log["input_events"]) + 1
			GameState.add_item(item)
			_maybe_swap(arch, log, item)

## GameState.add_item()'s auto-equip only ever fills an EMPTY slot. Swapping a
## better item into an occupied slot is a player decision - which is exactly the
## decision the non-gamer archetype never makes.
func _maybe_swap(arch: Dictionary, log: Dictionary, item: Item) -> void:
	if item.equipped_by != &"":
		log["items_equipped"] = int(log["items_equipped"]) + 1
		return
	if not bool(arch["swaps_gear"]):
		return
	for id: StringName in GameState.active_party:
		if item.usable_by().has(id):
			var current := GameState.equipped_item(id, item.slot())
			if current == null or item.value > current.value:
				GameState.equip_item(item, id)
				log["items_equipped"] = int(log["items_equipped"]) + 1
				log["input_events"] = int(log["input_events"]) + 2   # open bag, tap equip
			return

# =============================================================================
# Town
# =============================================================================

func _town_phase(arch: Dictionary, log: Dictionary) -> void:
	var screens := 1                      # the town hub itself
	if bool(arch["sells_junk"]) or bool(arch["buys_gear"]):
		screens += 1                      # blacksmith
	if bool(arch["forges"]):
		screens += 1                      # item forge
	if bool(arch["buys_meal"]) or bool(arch["rests_at_inn"]):
		screens += 1                      # inn
	var town_time: float = float(arch["deliberation_s"]) * float(screens)
	log["town_seconds"] = float(log["town_seconds"]) + town_time
	log["seconds"] = float(log["seconds"]) + town_time
	log["input_events"] = int(log["input_events"]) + screens * 2

	if bool(arch["sells_junk"]):
		_sell_unequipped(log)
	if bool(arch["buys_gear"]):
		_blacksmith(arch, log)
	if bool(arch["forges"]):
		_forge_pass(log)
	if bool(arch["buys_meal"]) and GameState.gold >= GameState.meal_cost():
		if GameState.buy_meal():
			log["gold_spent"] = int(log["gold_spent"]) + GameState.meal_cost()
			log["input_events"] = int(log["input_events"]) + 1
	if bool(arch["rests_at_inn"]) and _party_hurt() \
			and GameState.gold >= Tuning.INN_NIGHT_COST:
		if GameState.rest_at_inn():
			log["gold_spent"] = int(log["gold_spent"]) + Tuning.INN_NIGHT_COST
			log["input_events"] = int(log["input_events"]) + 1

func _party_hurt() -> bool:
	for entry: Dictionary in GameState.party_status():
		if int(entry.get("current_hp", 0)) < int(entry.get("max_hp", 1)):
			return true
	return false

func _sell_unequipped(log: Dictionary) -> void:
	for i: int in range(GameState.inventory.size() - 1, -1, -1):
		var item: Item = GameState.inventory[i]
		if item.equipped_by != &"" or item.kind == Item.Kind.RELIC:
			continue
		GameState.add_gold(item.sell_price())
		GameState.remove_item(item)
		log["input_events"] = int(log["input_events"]) + 1

func _blacksmith(arch: Dictionary, log: Dictionary) -> void:
	for item: Item in Itemizer.generate_forge_stock(GameState.hero_level(&"warrior")):
		var price := item.buy_price()
		if GameState.gold < price:
			continue
		var best_owner := &""
		for id: StringName in GameState.active_party:
			if item.usable_by().has(id):
				best_owner = id
				break
		if best_owner == &"":
			continue
		var current := GameState.equipped_item(best_owner, item.slot())
		if current != null and item.value <= current.value:
			continue
		if GameState.spend_gold(price):
			log["gold_spent"] = int(log["gold_spent"]) + price
			log["input_events"] = int(log["input_events"]) + 1
			GameState.add_item(item)
			_maybe_swap(arch, log, item)

func _forge_pass(log: Dictionary) -> void:
	var slots: Array[Item.Slot] = [Item.Slot.WEAPON, Item.Slot.ARMOR, Item.Slot.TRINKET]
	var progressed := true
	while progressed:
		progressed = false
		for id: StringName in GameState.active_party:
			for s: Item.Slot in slots:
				var item := GameState.equipped_item(id, s)
				if item == null or item.rarity >= Item.Rarity.ENHANCED:
					continue
				var cost: Array = Tuning.FORGE_COSTS[item.rarity]
				if GameState.scrap >= int(cost[0]) and GameState.gold >= int(cost[1]):
					if Itemizer.forge(item):
						progressed = true
						log["forges"] = int(log["forges"]) + 1
						log["gold_spent"] = int(log["gold_spent"]) + int(cost[1])
						log["input_events"] = int(log["input_events"]) + 1

## The upgrade tray - the only input the game accepts while a fight is running.
func _maybe_buy_upgrade(arch: Dictionary, log: Dictionary) -> void:
	for id: StringName in (arch["upgrade_order"] as Array):
		if Upgrades.is_maxed(id):
			continue
		var price := Upgrades.cost(id)
		if price < 0 or GameState.gold < price:
			continue
		if Upgrades.buy(id):
			log["gold_spent"] = int(log["gold_spent"]) + price
			log["upgrades_bought"] = int(log["upgrades_bought"]) + 1
			log["input_events"] = int(log["input_events"]) + 1
			log["in_combat_inputs"] = int(log["in_combat_inputs"]) + 1
		return

# =============================================================================
# Report
# =============================================================================

func _report(arch: Dictionary, log: Dictionary) -> void:
	var secs := float(log["seconds"])
	var combat := float(log["combat_seconds"])
	var travel := float(log["travel_seconds"])
	var town := float(log["town_seconds"])
	var inputs := int(log["input_events"])
	# "Spectating" = inside an expedition, where the only possible input is the
	# upgrade tray (and the one shop modal). Combat + travel time, less the
	# handful of in-run taps, is time the player watches without agency.
	var in_run := combat + travel
	var ipm: float = (float(inputs) / (secs / 60.0)) if secs > 0.0 else 0.0

	_emit("## %s" % arch["name"])
	_emit("")
	_emit("- Recruit sought: **%s** | recruited: **%s**%s" % [
		String(log["recruit_target"]),
		"yes" if bool(log["recruited"]) else "NO",
		"" if not bool(log["recruited"]) else " (expedition %d)" % int(log["recruited_on"]),
	])
	_emit("- Final party: %s | final level: **%d**%s" % [
		str(log["party"]), int(log["final_level"]),
		"  **(GOAL NOT MET - expedition budget exhausted)**" if bool(log["stalled"]) else "",
	])
	_emit("- Expeditions: %d | **won %d, wiped %d** | first win: %s" % [
		int(log["expeditions"]), int(log["wins"]), int(log["wipes"]),
		("expedition %d" % int(log["first_win"])) if int(log["first_win"]) > 0 else "never"])
	_emit("- Total playtime to level %d: **%s** (%.0f s)" % [
		TARGET_LEVEL, _mmss(secs), secs])
	_emit("    - in-expedition (combat + travel): %s (%.0f%%)" % [
		_mmss(in_run), 100.0 * in_run / maxf(secs, 1.0)])
	_emit("    - town / menus: %s (%.0f%%)" % [
		_mmss(town), 100.0 * town / maxf(secs, 1.0)])
	_emit("- Slot spins watched: %d (all automatic - no spin input exists)" % int(log["spins"]))
	_emit("- Total inputs: %d (%.1f per minute)" % [inputs, ipm])
	_emit("    - of which available during a fight: %d" % int(log["in_combat_inputs"]))
	_emit("- Items found: %d | equipped: %d | upgrades bought: %d | forges: %d" % [
		int(log["items_found"]), int(log["items_equipped"]),
		int(log["upgrades_bought"]), int(log["forges"])])
	_emit("- Gold spent: %d | gold left: %d" % [int(log["gold_spent"]), int(log["gold"])])
	var curve: Array[String] = []
	for pair: Array in (log["levels"] as Array):
		curve.append("exp%d:L%d" % [int(pair[0]), int(pair[1])])
	_emit("- Level curve: %s" % ", ".join(curve))
	_emit("")

func _mmss(seconds: float) -> String:
	var m := int(seconds) / 60
	var s := int(seconds) % 60
	return "%dm %02ds" % [m, s]
