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
## bleed ticks, mid-fight leveling), plus: LOOT/SHOP encounters are no-ops
## here (no items generated or bought mid-run) and HP does not carry a heal
## between quests - both slightly UNDERSTATE a live player's real odds.

const SlotMachineScript := preload("res://scripts/console/slot_machine.gd")

const NUM_TRIALS := 300
const ENEMY_ATTACK_CLIP := 0.8
const _SPIN_CYCLE := Tuning.SLOT_SPIN_DURATION + Tuning.SLOT_REEL_STAGGER * 2.0 + Tuning.SLOT_RESULT_HOLD

## [levels] Mirrors test_level_curves.gd's GEAR_RARITY_AT_LEVEL - "what gear is
## this level's player plausibly wearing" per spec §5.1, not simulated drops.
const GEAR_RARITY_AT_LEVEL := {
	3: Item.Rarity.MAGIC, 4: Item.Rarity.MAGIC, 5: Item.Rarity.MAGIC,
	6: Item.Rarity.MAGIC, 7: Item.Rarity.MAGIC,
}

const _GEAR_TYPES := {
	&"warrior": {Item.Slot.WEAPON: &"sword", Item.Slot.ARMOR: &"mail", Item.Slot.TRINKET: &"idol"},
	&"ranger": {Item.Slot.WEAPON: &"bow", Item.Slot.ARMOR: &"helm", Item.Slot.TRINKET: &"ring"},
}

## One case per quest: the party attempting it right when the mayor first
## offers it. "relic_only" models the ranger fresh off her own quest, wearing
## only the guaranteed warbow (spec's actual join state) - the conservative,
## worst-case gear read; "geared" (run second, printed alongside) gives her a
## full plausible loadout instead, the more typical few-quests-later state.
const CASES := [
	{
		"quest": "res://resources/quests/ranger_recruit.tres",
		"party_level": 3,
		"members": [{"class": &"warrior", "geared": true}],
	},
	{
		"quest": "res://resources/quests/ranger_recruit.tres",
		"party_level": 4,
		"members": [{"class": &"warrior", "geared": true}],
	},
	{
		"quest": "res://resources/quests/ranger_recruit.tres",
		"party_level": 5,
		"members": [{"class": &"warrior", "geared": true}],
	},
	{
		"quest": "res://resources/quests/recruit_mage.tres",
		"party_level": 5,
		"members": [
			{"class": &"warrior", "geared": true},
			{"class": &"ranger", "geared": false},
		],
	},
	{
		"quest": "res://resources/quests/recruit_mage.tres",
		"party_level": 5,
		"members": [
			{"class": &"warrior", "geared": true},
			{"class": &"ranger", "geared": true},
		],
	},
	{
		"quest": "res://resources/quests/recruit_mage.tres",
		"party_level": 6,
		"members": [
			{"class": &"warrior", "geared": true},
			{"class": &"ranger", "geared": true},
		],
	},
	{
		"quest": "res://resources/quests/recruit_mage.tres",
		"party_level": 7,
		"members": [
			{"class": &"warrior", "geared": true},
			{"class": &"ranger", "geared": true},
		],
	},
]

const _RELIC_ITEM := {
	&"ranger": "res://resources/items/ranger_warbow.tres",
	&"mage": "res://resources/items/mage_heartstone.tres",
}

func _ready() -> void:
	for c: Dictionary in CASES:
		_run_case(c)
	get_tree().quit()

# =============================================================================
# One case: NUM_TRIALS single-attempt expeditions at a fixed party level.
# =============================================================================

func _run_case(c: Dictionary) -> void:
	var quest: QuestDef = load(c["quest"])
	var label := "%s (party L%d, %s)" % [quest.id, int(c["party_level"]),
		", ".join((c["members"] as Array).map(func(m: Dictionary) -> String:
			return "%s%s" % [m["class"], "" if m["geared"] else " relic-only"]))]
	print("\n=== %s | level_range %s, unlock %d ===" % [label, quest.level_range, quest.unlock_level])

	var wins := 0
	var deaths_at: Dictionary = {}
	for trial: int in range(NUM_TRIALS):
		RNG.set_seed(hash("%s|%d" % [label, trial]))
		var party := _build_party(c["members"], int(c["party_level"]))
		var outcome := _run_quest(quest, party)
		if outcome["won"]:
			wins += 1
		else:
			var idx: int = outcome["died_at"]
			deaths_at[idx] = int(deaths_at.get(idx, 0)) + 1

	var rate := float(wins) / float(NUM_TRIALS) * 100.0
	print("  win rate: %.1f%% (%d/%d)" % [rate, wins, NUM_TRIALS])
	if wins < NUM_TRIALS:
		print("  wipes by combat encounter index: %s" % str(deaths_at))

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
## rarity/level.
func _make_geared_item(slot: Item.Slot, rarity: int, level: int,
		type_id: StringName, hero: StringName) -> Item:
	RNG.set_seed(hash("gear|%s|%d|%d|%s|%s" % [hero, level, int(slot), type_id, rarity]))
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
		if not _run_combat(enemies, party):
			return {"won": false, "died_at": combat_index}
		combat_index += 1
	return {"won": true, "died_at": -1}

func _interpolated_level(band: Vector2i, index: int, count: int) -> int:
	var t: float = float(index) / float(maxi(count - 1, 1))
	return int(round(lerpf(float(band.x), float(band.y), t)))

func _spawn_enemies(quest: QuestDef, level: int, is_boss_encounter: bool) -> Array:
	var ids: Array[StringName] = []
	if is_boss_encounter:
		ids.append(RNG.pick(quest.boss_pool) as StringName)
		for i: int in range(maxi(quest.enemy_count.x - 1, 0)):
			ids.append(RNG.pick(quest.enemy_pool) as StringName)
	else:
		var count: int = RNG.randi_range(quest.enemy_count.x, quest.enemy_count.y)
		for i: int in range(count):
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
	if enemies.is_empty():
		return true
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

		for e: Dictionary in enemies:
			if e["hp"] <= 0 and not e.get("_counted", false):
				e["_counted"] = true

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
