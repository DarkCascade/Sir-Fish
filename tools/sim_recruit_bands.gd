extends Node
## Monte Carlo playtest of the two recruit quests' difficulty bands
## (backlog decision 2.2, issue #105 - "playtest-unverified" since the
## 2026-09-20 re-band to ranger_recruit 3-5 / recruit_mage 5-7).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tools/sim_recruit_bands.tscn
##
## Simulates the party a player actually has the FIRST moment each quest is
## offered - the mayor's office gates on unlock_level, so that is the
## hardest, most realistic attempt: ranger_recruit by a solo warrior at level
## 3, recruit_mage by a warrior + ranger (the ranger levels with the party
## from her own join level, per GameState.apply_expedition_xp()) at level 5.
##
## Reuses the REAL quest resources - enemy_pool, boss_pool, encounter_types,
## level_range - and GameState._build_quest_level()'s own level-interpolation
## formula, rather than restating them, so an edit to the .tres files is
## picked up automatically. Combat is the same discrete-event numeric
## resolver as tools/sim_easy_attempts.gd: real-time attack_cooldown clocks
## per actor, the real slot bag/board math (SlotIcon, SlotMachine.draw_nine())
## for party output, extended to N heroes / N enemies. Same conservative
## omissions as sim_easy_attempts.gd (payline double-resolve, crit doubling,
## bleed ticks, cleave/rain, class specials), plus LOOT/SHOP encounters are
## no-ops (no items gained mid-run). All of these UNDERSTATE a live player's
## odds, so read the tables relative to the easy.tres calibration row rather
## than as absolute win rates.

const SlotMachineScript := preload("res://scripts/console/slot_machine.gd")

const NUM_TRIALS := 400
const ENEMY_ATTACK_CLIP := 0.8
const _SPIN_CYCLE := Tuning.SLOT_SPIN_DURATION + Tuning.SLOT_REEL_STAGGER * 2.0 + Tuning.SLOT_RESULT_HOLD

## [levels] Mirrors test_level_curves.gd's GEAR_RARITY_AT_LEVEL - "what gear is
## this level's player plausibly wearing" per spec §5.1, not simulated drops.
## Only the rarity is fixed; the modifiers are rolled fresh every trial.
## L1-2 are generous: a fresh profile really has a Magic sword, a Common shield
## and no trinket.
const GEAR_RARITY_AT_LEVEL := {
	1: Item.Rarity.MAGIC, 2: Item.Rarity.MAGIC,
	3: Item.Rarity.MAGIC, 4: Item.Rarity.MAGIC, 5: Item.Rarity.MAGIC,
	6: Item.Rarity.MAGIC, 7: Item.Rarity.MAGIC,
}

const _GEAR_TYPES := {
	&"warrior": {Item.Slot.WEAPON: &"sword", Item.Slot.ARMOR: &"mail", Item.Slot.TRINKET: &"idol"},
	&"ranger": {Item.Slot.WEAPON: &"bow", Item.Slot.ARMOR: &"helm", Item.Slot.TRINKET: &"ring"},
}

const _SOLO_WARRIOR := [{"class": &"warrior", "geared": true}]
## The ranger as she joins: the guaranteed warbow and nothing else.
const _WARRIOR_RANGER_FRESH := [
	{"class": &"warrior", "geared": true}, {"class": &"ranger", "geared": false},
]
const _WARRIOR_RANGER_GEARED := [
	{"class": &"warrior", "geared": true}, {"class": &"ranger", "geared": true},
]

## Each sweep runs every candidate level_range against every party level, on a
## copy of the real quest with only level_range swapped. The first candidate is
## the shipped band. Party levels start at the quest's unlock_level: the mayor
## never offers it lower.
const SWEEPS := [
	# Calibration, not a candidate: easy.tres has the ranger quest's layout, pool
	# and an identically-statted boss, and it has been played live. If the level
	# this table says a solo warrior first clears easy at disagrees with real
	# play, every other table here is off by the same amount.
	{
		"quest": "res://resources/quests/easy.tres",
		"party": _SOLO_WARRIOR,
		"party_levels": [2, 3, 4, 5],
		"ranges": [Vector2i(1, 5)],
	},
	{
		"quest": "res://resources/quests/ranger_recruit.tres",
		"party": _SOLO_WARRIOR,
		"party_levels": [3, 4, 5],
		"ranges": [Vector2i(3, 5), Vector2i(3, 4), Vector2i(2, 4), Vector2i(3, 3), Vector2i(2, 3)],
	},
	{
		"quest": "res://resources/quests/recruit_mage.tres",
		"party": _WARRIOR_RANGER_FRESH,
		"party_levels": [5, 6, 7],
		"ranges": [Vector2i(5, 7), Vector2i(5, 8), Vector2i(5, 9), Vector2i(5, 10)],
	},
	{
		"quest": "res://resources/quests/recruit_mage.tres",
		"party": _WARRIOR_RANGER_GEARED,
		"party_levels": [5, 6, 7],
		"ranges": [Vector2i(5, 7), Vector2i(5, 8), Vector2i(5, 9), Vector2i(5, 10)],
	},
]

const _RELIC_ITEM := {
	&"ranger": "res://resources/items/ranger_warbow.tres",
	&"mage": "res://resources/items/mage_heartstone.tres",
}

var _last_combat_secs := 0.0

func _ready() -> void:
	for s: Dictionary in SWEEPS:
		_run_sweep(s)
	get_tree().quit()

# =============================================================================
# Sweeps: one table per quest and party, a row per candidate level_range.
# =============================================================================

func _run_sweep(s: Dictionary) -> void:
	var base: QuestDef = load(s["quest"])
	var members: Array = s["party"]
	var party_desc := ", ".join(members.map(func(m: Dictionary) -> String:
		return "%s%s" % [m["class"], "" if m["geared"] else " (relic only)"]))
	print("\n=== %s | party: %s | unlock %d | %d trials per cell ===" % [
		base.id, party_desc, base.unlock_level, NUM_TRIALS])
	print("  cell = win%% / mean HP left on a win / mean boss fight length")
	var header := "  %-8s" % "range"
	for lvl: int in s["party_levels"]:
		header += " | %-24s" % ("party L%d" % lvl)
	print(header)
	for r: Vector2i in s["ranges"]:
		var quest := base.duplicate() as QuestDef
		quest.level_range = r
		var row := "  %-8s" % ("%d-%d%s" % [r.x, r.y, "*" if r == base.level_range else ""])
		for lvl: int in s["party_levels"]:
			var st := _run_cell(quest, members, lvl)
			row += " | %5.1f%% / %3.0f%% / %4.1fs " % [st["win_pct"], st["hp_left_pct"], st["boss_secs"]]
		print(row)
	print("  (* = shipped band)")

## NUM_TRIALS single-attempt expeditions. The trial seed is set ONCE, before
## the party is built, so the gear rolls, the enemy picks and the combat all
## differ trial to trial.
func _run_cell(quest: QuestDef, members: Array, party_level: int) -> Dictionary:
	var wins := 0
	var hp_left := 0.0
	var boss_secs := 0.0
	for trial: int in range(NUM_TRIALS):
		RNG.set_seed(hash("%s|%s|%d|%d" % [quest.id, quest.level_range, party_level, trial])
			+ members.size())
		var party := _build_party(members, party_level)
		var outcome := _run_quest(quest, party)
		boss_secs += float(outcome["boss_secs"])
		if outcome["won"]:
			wins += 1
			var hp := 0.0
			var max_hp := 0.0
			for h: Dictionary in party:
				hp += maxf(0.0, float(h["hp"]))
				max_hp += float(h["max_hp"])
			hp_left += hp / max_hp
	return {
		"win_pct": float(wins) / float(NUM_TRIALS) * 100.0,
		"hp_left_pct": (hp_left / float(wins) * 100.0) if wins > 0 else 0.0,
		"boss_secs": boss_secs / float(NUM_TRIALS),
	}

# =============================================================================
# Party / gear construction
# =============================================================================

func _build_party(members: Array, party_level: int) -> Array:
	var party: Array = []
	for m: Dictionary in members:
		var hero_class: StringName = m["class"]
		var items: Array[Item] = []
		if m["geared"]:
			items = _geared_loadout(hero_class, party_level)
		else:
			items = _relic_loadout(hero_class)
		var armor := 0
		for it: Item in items:
			armor += it.armor_value()
		party.append({
			"class": hero_class,
			"level": party_level,
			"hp": GameState.get_stats(hero_class).hp_at(party_level),
			"max_hp": GameState.get_stats(hero_class).hp_at(party_level),
			"armor": armor,
			"items": items,
		})
	return party

## A full generated loadout (weapon/armor/trinket) at the level's plausible
## rarity, in this class's own item types - same shape as
## test_level_curves.gd's _geared_entry().
func _geared_loadout(hero_class: StringName, level: int) -> Array[Item]:
	var rarity: int = int(GEAR_RARITY_AT_LEVEL.get(level, Item.Rarity.COMMON))
	var types: Dictionary = _GEAR_TYPES[hero_class]
	var items: Array[Item] = []
	for slot: Item.Slot in [Item.Slot.WEAPON, Item.Slot.ARMOR, Item.Slot.TRINKET]:
		items.append(_make_geared_item(slot, rarity, level, types[slot], hero_class))
	return items

## Just the quest's guaranteed relic - what a recruit is actually wearing the
## instant they join (RecruitRewardExtra.grant()), before any drops.
func _relic_loadout(hero_class: StringName) -> Array[Item]:
	var relic := (load(_RELIC_ITEM[hero_class]) as Item).duplicate(true) as Item
	relic.equipped_by = hero_class
	return [relic]

## Mirrors test_level_curves.gd's _make_geared_item(): a real generated item
## with real rolled modifiers from Itemizer's own pool/roll ranges, so this
## gear is exactly as strong as an actually-generated item of the same
## rarity/level. Unlike that harness it does NOT reseed: it draws from the
## trial's stream, so gear luck varies across trials instead of every trial
## wearing one fixed roll.
func _make_geared_item(slot: Item.Slot, rarity: int, level: int,
		type_id: StringName, hero: StringName) -> Item:
	var item := Item.new()
	item.kind = Item.Kind.WEAPON
	item.weapon_type = type_id
	item.rarity = rarity
	item.level = level
	item.equipped_by = hero
	var mods: Array[Dictionary] = []
	var pool: Array = Itemizer._modifiers_for_type(type_id).duplicate()
	var count: int = Itemizer.RARITY_MOD_COUNT[rarity]
	for i: int in range(count):
		if pool.is_empty():
			pool = Itemizer._modifiers_for_type(type_id).duplicate()
		var pick_index: int = RNG.randi_range(0, pool.size() - 1)
		var def: Dictionary = pool[pick_index]
		pool.remove_at(pick_index)
		var is_enhanced_rung: bool = rarity == Item.Rarity.ENHANCED and i == count - 1
		var roll: int = Itemizer._roll_icon_magnitude(def, item, is_enhanced_rung)
		mods.append({"id": def["id"], "roll": roll, "enhanced": is_enhanced_rung})
	item.modifiers = mods
	return item

func _hero_icons(hero_class: StringName, items: Array[Item]) -> Array:
	var weapon_power := 0
	for item: Item in items:
		if item.slot() == Item.Slot.WEAPON:
			weapon_power = item.power()
			break
	var icons: Array = [SlotIcon.innate(hero_class, weapon_power)]
	for item: Item in items:
		icons.append(SlotIcon.from_item_base(item))
		for mod: Dictionary in item.modifiers:
			var ic := SlotIcon.from_modifier(mod, item)
			if not ic.is_empty():
				icons.append(ic)
	return icons

func _party_bag(party: Array) -> Array:
	var bag: Array = []
	for h: Dictionary in party:
		bag.append_array(_hero_icons(h["class"], h["items"]))
	for _i: int in range(Tuning.SLOT_BLANK_PAD_START):
		bag.append(SlotIcon.blank())
	return bag

# =============================================================================
# One quest attempt: walks the real encounter_types / level interpolation,
# fighting every COMBAT encounter with the discrete-event resolver below.
# Party HP carries across encounters within the attempt (no mid-run heal
# modeled - see file header). Returns won + which combat index a wipe happened
# at (0-based over COMBAT encounters only), or -1 if it won.
# =============================================================================

func _run_quest(quest: QuestDef, party: Array) -> Dictionary:
	var n: int = quest.encounter_types.size()
	var combat_index := 0
	for i: int in range(n):
		if quest.encounter_types[i] != EncounterDef.Type.COMBAT:
			continue
		var level: int = _interpolated_level(quest.level_range, i, n)
		var is_last := i == n - 1
		var enemies := _spawn_enemies(quest, level, is_last)
		var won := _run_combat(enemies, party)
		if not won:
			return {"won": false, "died_at": combat_index,
				"boss_secs": _last_combat_secs if is_last else 0.0}
		if is_last:
			return {"won": true, "died_at": -1, "boss_secs": _last_combat_secs}
		combat_index += 1
	return {"won": true, "died_at": -1, "boss_secs": 0.0}

func _interpolated_level(band: Vector2i, index: int, count: int) -> int:
	var t: float = float(index) / float(maxi(count - 1, 1))
	return int(round(lerpf(float(band.x), float(band.y), t)))

func _spawn_enemies(quest: QuestDef, level: int, is_boss_encounter: bool) -> Array:
	var ids: Array[StringName] = []
	var count: int = RNG.randi_range(quest.enemy_count.x, quest.enemy_count.y)
	if is_boss_encounter:
		ids.append(RNG.pick(quest.boss_pool) as StringName)
		for i: int in range(clampi(count - 1, 0, Tuning.MAX_ENEMIES - 1)):
			ids.append(RNG.pick(quest.enemy_pool) as StringName)
	else:
		for i: int in range(clampi(count, 1, Tuning.MAX_ENEMIES)):
			ids.append(RNG.pick(quest.enemy_pool) as StringName)

	var out: Array = []
	for i: int in range(ids.size()):
		var s := GameState.get_stats(ids[i])
		var is_boss_unit: bool = is_boss_encounter and i == 0
		var lvl := level
		var max_hp: int
		if is_boss_unit:
			lvl += Tuning.BOSS_LEVEL_BONUS
			var boosted_base: int = int(round(float(s.max_hp) * Tuning.BOSS_HP_MULT))
			var boosted_growth: int = int(round(float(s.hp_per_level) * Tuning.BOSS_HP_MULT))
			max_hp = CombatantStats.at_level(boosted_base, boosted_growth, lvl)
		else:
			max_hp = s.hp_at(lvl)
		out.append({
			"id": ids[i], "level": lvl, "hp": max_hp, "max_hp": max_hp,
			"weapon_power": s.weapon_power_at(lvl), "attack_cooldown": s.attack_cooldown,
			"next_action": s.attack_cooldown * Tuning.COOLDOWN_START_FRACTION
				* RNG.randf_range(1.0 - Tuning.COOLDOWN_START_JITTER, 1.0 + Tuning.COOLDOWN_START_JITTER),
		})
	return out

## `party` is mutated in place (hp, block/block_until). Returns true iff every
## enemy dies before the whole party's hp reaches 0.
func _run_combat(enemies: Array, party: Array) -> bool:
	_last_combat_secs = 0.0
	if enemies.is_empty():
		return true
	# Each fight's clock starts at 0, so a block granted late in the last fight
	# must not read as still active here.
	for h: Dictionary in party:
		h.erase("block")
		h.erase("block_until")
	var t := 0.0
	var party_next_spin: float = _SPIN_CYCLE
	var guard := 0
	while _living_heroes(party).size() > 0 and _living(enemies) and guard < 20000:
		guard += 1
		var next_t: float = party_next_spin
		var acting_enemy: Dictionary = {}
		for e: Dictionary in enemies:
			if e["hp"] > 0 and e["next_action"] < next_t:
				next_t = e["next_action"]
				acting_enemy = e
		t = next_t

		if not acting_enemy.is_empty():
			acting_enemy["next_action"] = t + acting_enemy["attack_cooldown"] + ENEMY_ATTACK_CLIP
			var target = _random_living_hero(party)
			if target != null:
				var raw: float = float(acting_enemy["weapon_power"]) \
					* RNG.randf_range(1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE)
				var block: int = int(target.get("block", 0)) if t < float(target.get("block_until", -1.0)) else 0
				target["hp"] -= maxi(1, int(round(raw)) - int(target["armor"]) - block)
		else:
			party_next_spin = t + _SPIN_CYCLE
			_resolve_spin(party, enemies, t)

	_last_combat_secs = t
	return _living_heroes(party).size() > 0

func _living(enemies: Array) -> bool:
	for e: Dictionary in enemies:
		if e["hp"] > 0:
			return true
	return false

func _living_heroes(party: Array) -> Array:
	var out: Array = []
	for h: Dictionary in party:
		if h["hp"] > 0:
			out.append(h)
	return out

func _random_living(enemies: Array) -> Variant:
	var pool: Array = []
	for e: Dictionary in enemies:
		if e["hp"] > 0:
			pool.append(e)
	if pool.is_empty():
		return null
	return pool[RNG.randi_range(0, pool.size() - 1)]

## All living heroes equally likely to be hit - same assumption
## test_level_curves.gd's ttd model documents.
func _random_living_hero(party: Array) -> Variant:
	var pool := _living_heroes(party)
	if pool.is_empty():
		return null
	return pool[RNG.randi_range(0, pool.size() - 1)]

func _rolled(roll: int, mult: float) -> int:
	var base := maxi(1, int(round(float(roll) * mult))) + Tuning.SLOT_ATTACK_ICON_FLOOR
	return maxi(1, int(round(float(base) * RNG.randf_range(
		1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE))))

## One shared party bag/board per spin (SlotMachine._rebuild_bag()'s real
## shape for a multi-hero party). BLOCK grants temp armor to whichever hero
## drew it - modeled as the whole party's front line, i.e. a random living
## hero, since the bag has no per-hero BLOCK routing today.
func _resolve_spin(party: Array, enemies: Array, now: float) -> void:
	var bag := _party_bag(party)
	var board: Array = SlotMachineScript.draw_nine(bag)
	var mult := Upgrades.overcharge_mult()
	var block := 0
	for ic: Dictionary in board:
		var id := StringName(ic.get("id", &""))
		var kind: int = SlotIcon.kind_of(id)
		var roll := int(ic.get("roll", 0))
		match kind:
			SlotIcon.Kind.DAMAGE:
				var target = _random_living(enemies)
				if target != null:
					target["hp"] -= _rolled(roll, mult)
			SlotIcon.Kind.BOMB_ARROW, SlotIcon.Kind.THUNDERBURST:
				for e: Dictionary in enemies:
					if e["hp"] > 0:
						e["hp"] -= _rolled(roll, mult)
			SlotIcon.Kind.BLOCK:
				block += maxi(1, roll)
	if block > 0:
		var hero = _random_living_hero(party)
		if hero != null:
			var carried: int = int(hero.get("block", 0)) if now < float(hero.get("block_until", -1.0)) else 0
			hero["block"] = maxi(carried, block)
			hero["block_until"] = now + Tuning.BLOCK_DURATION
