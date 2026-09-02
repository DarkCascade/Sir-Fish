extends Node
## GameState — everything that survives an encounter (spec 4.4).
## Hero HP persists across encounters; there is no between-encounter heal.

const STATS_DIR := "res://resources/stats/"

## Party order is fixed left-to-right: Mage, Ranger, Warrior (spec 7.1).
const PARTY_ORDER: Array[StringName] = [&"mage", &"ranger", &"warrior"]

var gold: int = 0
var inventory: Array[Item] = []
var hero_runtime: Array = []       # [{stats_id, current_hp, max_hp, alive}]
var current_encounter_index: int = -1
var level: LevelDef

## Endless is the default mode (spec: Endless Mode) - a run keeps generating
## six-encounter levels back to back instead of ending after one fixed level,
## and only stops on a party wipe (run_controller._next_encounter() is what
## actually loops back into build_level() when a level runs out). Flipping
## this to false restores the original single fixed level (Whispering Wood).
var endless_mode: bool = true
var endless_level_number: int = 1

var run_stats := {
	"encounters_cleared": 0,
	"gold_earned": 0,
	"gold_spent": 0,          # [v2] upgrades + shop, for the summary
	"damage_dealt": 0,
	"damage_taken": 0,
	"slot_spins": 0,
	"slot_wins": 0,
	"items_found": 0,
	"items_sold": 0,
	"items_dropped": 0,       # [drops] drop-only subset of items_found, for the summary
	"upgrades_bought": 0,     # [v2]
	# [town] forge uses (spec 5.4). The slot machine's three run-scoped upgrades
	# stay counted by upgrades_bought - the forge is never an "upgrade".
	"items_forged": 0,
	"run_time": 0.0,
}

## [drops] Drops received per hero class this run. Cleared by
## start_expedition().
##
## The goal is COVERAGE, not fairness. A run where the mage never sees a
## staff is a run where a third of the party is inert once equipping exists, so
## a class that is behind is weighted up until it catches up. The weighting is
## soft - it changes the odds, it does not rotate a queue - because a guaranteed
## round robin is readable by the player within two levels and stops being a
## drop at all.
var drops_by_class: Dictionary = {}      # StringName -> int

# --- [town] profile vs. expedition (step 1 of the town/quests/forging spec) -
##
## Two lifetimes are being teased apart here. PROFILE survives everything and
## will be saved to disk (a later pass). EXPEDITION is one quest, from the
## mayor's desk to the result modal, and resets every retry exactly as the
## whole run used to.
##
## For now `reset_run()` below still calls both in sequence on every retry, so
## nothing observable changes yet - see reset_run()'s own comment for why that
## is deliberate rather than an oversight.

## [town] Scrap metal - the forge's currency (spec 5). Awarded by enemy pickups
## (spec 9, add_scrap via add_expedition_scrap) and spent by Itemizer.forge()
## (spec 10.2). Profile-scoped: it survives a retry, exactly like gold.
var scrap: int = 0

## [town] The heroes that actually take the field. PARTY_ORDER stays the
## canonical roster - it is what the drop-coverage weighting is written
## against, and restoring a three-hero party is one assignment - and this is
## who is currently in it. Profile-scoped.
##
## [town] spec 4.5: the party is solo. This initialiser and new_profile()'s
## matching assignment are the VALUE FLIP that actually makes it so - the three
## reads spec 4.5 lists (droppable_classes(), _reset_hero_runtime(),
## spawn_party() via hero_runtime) only matter once this stops equalling
## PARTY_ORDER. PARTY_ORDER itself is untouched.
var active_party: Array[StringName] = [&"warrior"]

## [town] The quest being run, or null in town / outside a quest (spec 8.1).
## build_level() branches on it first, ahead of endless_mode (spec 8.3); the
## mayor's office and debug `quest` set it via start_expedition(q).
var quest: QuestDef = null

## [town] The quest that just ENDED, kept for QuestResult to read (spec 8.5).
## spec 8.5 nulls `quest` before routing home and presenting the modal, so the
## reward row and the "this was a quest" branch need a value that outlives that
## null. Cleared by start_expedition(); stays null on the endless / fixed path.
var completed_quest: QuestDef = null

## [town] Gold and scrap picked up during the CURRENT expedition, tallied by
## add_expedition_gold() / add_expedition_scrap() as pickups land (spec 9) so
## QuestResult can state "you brought home N scrap" without diffing profile
## totals across a scene change (spec 8.5). Reset by start_expedition().
var expedition_gold: int = 0
var expedition_scrap: int = 0

## [day-night] Where the party is in the day/night loop (day/night spec §2.2).
## This enum is the whole enforcement mechanism for "one quest per day, one
## night per quest": resolve_night() is reachable ONLY from NIGHT_PENDING, and
## NIGHT_PENDING is reachable ONLY from QUEST, so two nights in a row is not a
## rule anybody has to check - it is a transition that does not exist.
##
## Replaces street_sleep_used, which was a flag guarding the same property by
## hand (§1.3). The HEAL that flag was guarding is unchanged.
enum DayPhase {
	DAY,            # in town. Shop, forge, eat, talk to the mayor. No quest run yet today.
	QUEST,          # an expedition is in flight. GameState.quest is non-null.
	NIGHT_PENDING,  # the quest ended; the night has not been chosen yet.
}

## The two recovery options resolve_night() takes (day/night spec §3.5).
enum NightChoice { INN, STREET }

## Profile-scoped, saved (§8.1). A loaded profile that predates this field
## defaults to DAY, which is correct - a save written before this pass could
## only ever have been written in town.
var day_phase: DayPhase = DayPhase.DAY

## [day-night] Days elapsed, 1-based, incremented by resolve_night(). Display
## only: printed on both night modals so the run reads as a campaign (§1.6).
## NOTHING may branch on this value - see §0.2.
var day_number: int = 1

## [day-night] What the last night restored, captured by resolve_night() BEFORE
## it heals, so NightResult can draw the bars as they were and then fill them
## (§4.3). One entry per hero, in hero_runtime order:
##   {stats_id, before_hp, after_hp, max_hp, was_dead}
## Not saved: it is presentation state with a lifetime of one modal.
var last_night_report: Array = []

## [day-night] The meal buff (day/night spec §9). Percent added to every hero's
## damage for the current or next expedition; 0 when the party is unfed.
## Profile-scoped and SAVED, because a meal bought before a quit must still be
## there after it.
var meal_pct: int = 0

## [day-night] Whether today's meal has been eaten. Cleared by resolve_night(),
## the same call that advances day_number - so the rhythm is one bed, one meal,
## one quest, and the buff cannot be stacked five times before leaving town
## (§9.4).
var meal_eaten_today: bool = false

## [town] Inventory size at the moment the current expedition started, so a
## failed quest can later tell "brought from town" apart from "found this
## trip" without tagging every Item. Inert until the failure flow reads it.
##
## Underscored because nothing outside GameState should WRITE it; spec 8.5's
## failure flow needs to READ it to pick which unequipped items to discard, so
## the intended access path is a discard helper on GameState rather than a
## reach-in from RunController. Spec 2.2's field listing omits this field
## entirely - it appears only in 8.5's prose - which is why it is called out
## here rather than left to be rediscovered.
var _expedition_inventory_mark: int = 0

## [town] The blacksmith's cached Buy-tab stock (spec 7.4). Profile-scoped and
## saved with the profile: generated once on the first blacksmith visit, rerolled
## ONLY by the refresh button, and a purchase erases the bought item from it.
## Walking out of the blacksmith and back in must not reroll - the same rule the
## quest shop follows via EncounterDef.cached_shop_items. Cleared by new_profile().
var forge_stock: Array[Item] = []

## [town] Whether forge_stock has ever been generated for this profile. Distinct
## from forge_stock.is_empty(), which is ALSO true once the player has bought
## every card - and using emptiness as the sentinel makes buying out the stock a
## free refresh, which is exactly what spec 7.4 forbids. Cleared by new_profile();
## set by the blacksmith's first generation and by every reroll.
var forge_stock_generated: bool = false

var _stats_cache: Dictionary = {}   # StringName -> CombatantStats

func _ready() -> void:
	_load_all_stats()

# --- stats registry ---------------------------------------------------------

func _load_all_stats() -> void:
	_stats_cache.clear()
	var dir := DirAccess.open(STATS_DIR)
	if dir == null:
		push_error("GameState: cannot open %s" % STATS_DIR)
		return
	for file_name: String in dir.get_files():
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var res := load(STATS_DIR + clean)
		if res is CombatantStats:
			_stats_cache[(res as CombatantStats).id] = res

func get_stats(id: StringName) -> CombatantStats:
	if not _stats_cache.has(id):
		push_error("GameState: unknown combatant stats id '%s'" % id)
		return null
	return _stats_cache[id]

# --- gold -------------------------------------------------------------------

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	run_stats["gold_earned"] = int(run_stats["gold_earned"]) + amount
	EventBus.gold_changed.emit(gold, amount)

func spend_gold(amount: int) -> bool:
	if amount <= 0 or gold < amount:
		return false
	gold -= amount
	run_stats["gold_spent"] = int(run_stats["gold_spent"]) + amount
	EventBus.gold_changed.emit(gold, -amount)
	return true

# --- scrap (spec 5) -------------------------------------------------------------

## [town] The forge's currency. One faucet - enemy pickups (spec 9) - and one
## sink - forging (spec 10.2). Never bought, sold, or converted to gold in
## either direction (spec 10.5). Mirrors add_gold()/spend_gold() so the HUD's
## CurrencyPlate animates it off scrap_changed exactly as it does gold.
func add_scrap(amount: int) -> void:
	if amount <= 0:
		return
	scrap += amount
	EventBus.scrap_changed.emit(scrap, amount)

func spend_scrap(amount: int) -> bool:
	if amount <= 0 or scrap < amount:
		return false
	scrap -= amount
	EventBus.scrap_changed.emit(scrap, -amount)
	return true

## [town] spec 8.4: a pickup in the forest credits the PROFILE immediately (so
## the quest's mid-run shop can spend today's winnings) and is ALSO tallied into
## the expedition bank the result modal reads back. Kept apart from add_gold() /
## add_scrap() so the quest reward (spec 8.5) and slot payouts never land in the
## "brought home" row.
func add_expedition_gold(amount: int) -> void:
	if amount <= 0:
		return
	add_gold(amount)
	expedition_gold += amount

func add_expedition_scrap(amount: int) -> void:
	if amount <= 0:
		return
	add_scrap(amount)
	expedition_scrap += amount

# --- inventory --------------------------------------------------------------

func add_item(item: Item) -> void:
	if item == null:
		return
	inventory.append(item)
	_maybe_auto_equip(item)
	EventBus.item_added.emit(item)
	EventBus.party_bonuses_changed.emit(party_bonuses())

func remove_item(item: Item) -> void:
	var index := inventory.find(item)
	if index < 0:
		return
	inventory.remove_at(index)
	EventBus.item_removed.emit(item)
	EventBus.party_bonuses_changed.emit(party_bonuses())

# --- equipping ----------------------------------------------------------

## [town] The item in `hero_class`'s `slot`, or null (spec 4.3). `equipped_by`
## still records only the hero, not the slot - the slot is recoverable from the
## item's own type (Item.slot()), so one item is never ambiguous about which
## slot it fills, which is why this needs no new field on Item.
func equipped_item(hero_class: StringName, slot: Item.Slot) -> Item:
	for i: Item in inventory:
		if i.equipped_by == hero_class and i.slot() == slot:
			return i
	return null

## [town] Every item `hero_class` currently wears, in Slot order, gaps omitted
## (spec 4.3). What the forge and the inventory modal's Equipped section list.
func equipped_set(hero_class: StringName) -> Array[Item]:
	var out: Array[Item] = []
	for s: Item.Slot in [Item.Slot.WEAPON, Item.Slot.ARMOR, Item.Slot.TRINKET]:
		var it := equipped_item(hero_class, s)
		if it != null:
			out.append(it)
	return out

## Equips item for hero_class, replacing whatever that hero already had in
## THAT item's slot - "one item per slot" (spec 4.3). Does not require
## hero_class to be in item.usable_by(): the UI only ever offers eligible
## classes, and the Debug harness wants the freedom to force odd states.
func equip_item(item: Item, hero_class: StringName) -> void:
	if item == null or hero_class == &"":
		return
	var previous := equipped_item(hero_class, item.slot())
	if previous != null:
		previous.equipped_by = &""
	item.equipped_by = hero_class
	# [town] spec 3.3: the deliberate-equip hook (step 6). Auto-equip on pickup
	# stays silent - it only fills a slot the player left empty. party_bonuses
	# still fires for both, since both change the pool.
	EventBus.item_equipped.emit(item, hero_class, int(item.slot()))
	EventBus.party_bonuses_changed.emit(party_bonuses())

func unequip_item(item: Item) -> void:
	if item == null or item.equipped_by == &"":
		return
	item.equipped_by = &""
	EventBus.party_bonuses_changed.emit(party_bonuses())

## Fills an EMPTY slot only - never swaps out an existing equip (§ equip
## request 2). Picks the first of the item's eligible classes whose matching
## slot is empty; in practice every generated item has exactly one eligible
## class today, so there is no real ambiguity to resolve.
##
## Only a class in active_party is a candidate. Generation is already party-
## gated (Itemizer._roll_typed passes active_party), so a non-party item can
## only reach here via the Debug harness - but without this guard it would
## still be silently equipped onto a hero who is not on the run, which locks it
## out of the Sell UI and feeds party_bonuses() a modifier no one is wearing.
func _maybe_auto_equip(item: Item) -> void:
	for hero_class: StringName in item.usable_by():
		if hero_class not in active_party:
			continue
		if equipped_item(hero_class, item.slot()) == null:
			item.equipped_by = hero_class
			return

# --- party bonuses (spec 13.5) ---------------------------------------------

## Only EQUIPPED items contribute - an item sitting unequipped in inventory is
## inert. Carrying loot only makes the party stronger once it is actually worn;
## selling an equipped item empties that slot the moment it leaves the inventory.
##
## [town] Up to THREE items per hero now, one per Item.Slot (spec 4.3) - it was
## one. That is the point of three slots: spec 1.5 records the solo warrior
## carrying a third as much as the old three-hero party into this pool, and the
## slot machine, the core loop, is what reads the result.
##
## Recomputed on demand and re-emitted on every inventory/equip change.
func party_bonuses() -> Dictionary:
	var out := {
		"dmg_flat": 0,
		"dmg_pct": 0,
		# [day-night] §9.5 - NOT from an item, and NOT summed into dmg_pct: it is
		# a separate multiplier (combatant.gd) and a separate strip glyph (§9.6).
		"meal_pct": meal_pct,
		"element": &"",
		"slot_bolt": 0,
		"slot_purse": 0,
		"slot_mend": 0,
	}
	# Elemental totals are kept apart rather than summed into one number, because
	# resistances are the obvious next step (spec 22).
	var elements := { &"fire": 0, &"ice": 0, &"light": 0 }
	for item: Item in inventory:
		if item.equipped_by == &"":
			continue
		for mod: Dictionary in item.modifiers:
			var id: StringName = mod["id"]
			var roll: int = int(mod.get("roll", 0))
			match id:
				&"dmg_flat":
					out["dmg_flat"] = int(out["dmg_flat"]) + roll
				&"dmg_pct":
					out["dmg_pct"] = int(out["dmg_pct"]) + roll
				&"elem_fire":
					out["dmg_flat"] = int(out["dmg_flat"]) + roll
					elements[&"fire"] = int(elements[&"fire"]) + roll
				&"elem_ice":
					out["dmg_flat"] = int(out["dmg_flat"]) + roll
					elements[&"ice"] = int(elements[&"ice"]) + roll
				&"elem_light":
					out["dmg_flat"] = int(out["dmg_flat"]) + roll
					elements[&"light"] = int(elements[&"light"]) + roll
				&"slot_bolt":
					out["slot_bolt"] = int(out["slot_bolt"]) + roll
				&"slot_purse":
					out["slot_purse"] = int(out["slot_purse"]) + roll
				&"slot_mend":
					out["slot_mend"] = int(out["slot_mend"]) + roll
	var best: StringName = &""
	var best_total: int = 0
	for key: StringName in elements.keys():
		if int(elements[key]) > best_total:
			best_total = int(elements[key])
			best = key
	out["element"] = best
	return out

## The damage-number colour for the party's dominant element (spec 11.4).
## Plain danger red when the party carries no elemental modifier.
func element_color() -> Color:
	match party_bonuses()["element"]:
		&"fire": return Tuning.C_FIRE
		&"ice": return Tuning.C_ICE
		&"light": return Tuning.C_LIGHTNING
	return Tuning.C_DANGER

# --- enemy drops (§4) --------------------------------------------------------

func drop_count(hero_class: StringName) -> int:
	return int(drops_by_class.get(hero_class, 0))

func record_drop(hero_class: StringName) -> void:
	drops_by_class[hero_class] = drop_count(hero_class) + 1

## The class the next drop is aimed at, or &"" when there are none to aim at.
## `force_hungriest` skips the roll entirely - the §4.2 boss guarantee.
func next_drop_class(force_hungriest: bool = false) -> StringName:
	var classes: Array[StringName] = Itemizer.droppable_classes()
	if classes.is_empty():
		return &""
	if force_hungriest:
		# Ties break in PARTY_ORDER rather than by dictionary iteration order:
		# the boss drop is the one drop a player will remember, so which class
		# it favours must not depend on insertion order.
		var best: StringName = classes[0]
		for c: StringName in classes:
			if drop_count(c) < drop_count(best):
				best = c
		return best
	var leader: int = 0
	for c: StringName in classes:
		leader = maxi(leader, drop_count(c))
	var weights: Array[int] = []
	for c: StringName in classes:
		# x100 because weighted_index takes integers and DROP_CATCHUP is
		# fractional. Only the ratios matter, not the scale.
		weights.append(int(round(100.0 * (1.0 + Tuning.DROP_CATCHUP
			* float(leader - drop_count(c))))))
	return classes[RNG.weighted_index(weights)]

# --- heroes -----------------------------------------------------------------

func hero_entry(stats_id: StringName) -> Dictionary:
	for entry: Dictionary in hero_runtime:
		if entry["stats_id"] == stats_id:
			return entry
	return {}

func living_hero_count() -> int:
	var n := 0
	for entry: Dictionary in hero_runtime:
		if entry["alive"]:
			n += 1
	return n

## [town] spec 3.2 party panel: the active party's HP for display, one entry per
## active_party member in roster order - {stats_id, display_name, current_hp,
## max_hp, alive, color}. Reads hero_runtime where it has been built
## (new_profile / start_expedition / any heal all run _reset_hero_runtime), and
## falls back to a full-HP synthetic entry for a profile loaded from a save that
## predates the "heroes" key: an un-run profile's heroes ARE whole, so that is
## the honest thing to show.
func party_status() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in active_party:
		var s := get_stats(id)
		if s == null:
			continue
		var entry := hero_entry(id)
		var cur: int = int(entry.get("current_hp", s.max_hp))
		var top: int = int(entry.get("max_hp", s.max_hp))
		out.append({
			"stats_id": id,
			"display_name": s.display_name,
			"current_hp": cur,
			"max_hp": top,
			"alive": bool(entry.get("alive", cur > 0)),
			"color": s.accent_color,
		})
	return out

# --- run lifecycle ----------------------------------------------------------

## Dispatches on endless_mode (spec: Endless Mode). This is the seam spec
## 12.1 / 22 called out for a future level generator - _build_endless_level()
## is that generator; _build_whispering_wood_level() is the original fixed
## level, kept for endless_mode = false.
func build_level() -> LevelDef:
	# [town] spec 8.3: a quest wins over endless_mode, which stays default-true
	# and is only bypassed here. endless / fixed are the dev paths from now on.
	if quest != null:
		return _build_quest_level(quest)
	if endless_mode:
		return _build_endless_level(endless_level_number)
	return _build_whispering_wood_level()

# --- quests (spec 8.3) -----------------------------------------------------

## Walks quest.encounter_types into a LevelDef: COMBAT slots filled from
## quest.enemy_pool at quest.enemy_count, LOOT / SHOP at the same Tuning counts
## every other builder uses, and the LAST entry (always a COMBAT) marked is_boss
## with its enemy list LED by a quest.boss_pool pick - leading the list puts the
## scaled-up boss body at the leftmost slot so it stays in frame (spec 7.3).
##
## No stat-scaling factor: difficulty is the pool, the counts, the depth and the
## boss drop floor, never a multiplier on CombatantStats (spec 8.1).
func _build_quest_level(q: QuestDef) -> LevelDef:
	var lvl := LevelDef.new()
	lvl.display_name = q.display_name
	var n: int = q.encounter_types.size()
	for i: int in range(n):
		var enc := EncounterDef.new()
		enc.travel_duration = q.travel_durations[i] if i < q.travel_durations.size() \
			else _default_quest_travel(i, n)
		var is_last: bool = i == n - 1
		match q.encounter_types[i]:
			EncounterDef.Type.LOOT:
				enc.type = EncounterDef.Type.LOOT
				enc.loot_item_count = Tuning.LOOT_ITEMS_PER_CHEST
			EncounterDef.Type.SHOP:
				enc.type = EncounterDef.Type.SHOP
				enc.shop_item_count = Tuning.SHOP_ITEMS_FOR_SALE
			_:
				enc.type = EncounterDef.Type.COMBAT
				var count: int = RNG.randi_range(q.enemy_count.x, q.enemy_count.y)
				if is_last:
					enc.is_boss = true
					enc.boss_drop_rarity_floor = q.boss_drop_rarity_floor
					var ids: Array[StringName] = [RNG.pick(q.boss_pool) as StringName]
					ids.append_array(_random_enemies(q.enemy_pool,
						clampi(count - 1, 0, Tuning.MAX_ENEMIES - 1)))
					enc.enemy_stat_ids = ids
				else:
					enc.enemy_stat_ids = _random_enemies(q.enemy_pool,
						clampi(count, 1, Tuning.MAX_ENEMIES))
		lvl.encounters.append(enc)
	return lvl

## Fallback travel ramp when a quest leaves travel_durations short: 2s in, 4s
## before the boss, 3s for everything between - the same shape the endless
## builder hardcodes.
func _default_quest_travel(index: int, count: int) -> float:
	if index == 0:
		return 2.0
	if index == count - 1:
		return 4.0
	return 3.0

# --- endless mode (spec: Endless Mode) --------------------------------------

## Regular enemies available from the first level. skeleton_minion is the
## other "weak" combatant alongside shadow_monster - a swarm of either reads
## as an easy opener.
const ENDLESS_EARLY_POOL: Array[StringName] = [&"shadow_monster", &"skeleton_minion"]
## Join the pool once the party has cleared at least one level, so depth 1
## stays as gentle as the old fixed level's opening fight.
##
## The orc barbarian is out of the rotation: it is the last in-house model,
## built from separate primitive blocks (O_Head, O_ArmL, O_Torso...), and
## next to the KayKit skeletons it reads as a stick figure. The stats, scene
## and rig branches all stay - nothing spawns it, so nothing renders it.
const ENDLESS_MID_POOL: Array[StringName] = [
	&"skeleton_warrior", &"skeleton_mage", &"skeleton_rogue", &"sporecap",
]
## [UI pass] Was just the orc warlord. Any of the four KayKit skeletons can
## anchor encounter 6 now - battle_director.start_combat() scales whichever
## one gets picked up 150% for the boss slot (a runtime-duplicated
## CombatantStats, never the shared cached one, so the regular-sized version
## other encounters spawn from ENDLESS_MID_POOL is untouched).
const BOSS_POOL: Array[StringName] = [
	&"skeleton_warrior", &"skeleton_mage", &"skeleton_rogue", &"skeleton_minion",
]

## Six encounters, same COMBAT/LOOT/COMBAT/SHOP/COMBAT/boss-COMBAT rhythm as
## the fixed level (that pacing was already tuned - only which enemies fill
## the combat slots is generated). Called again every time the party walks
## off the end of a level (run_controller._next_encounter()), with
## endless_level_number already incremented, so difficulty is entirely from
## a wider enemy pool and slightly bigger groups at higher depths - no
## stat-scaling multiplier, to avoid a second source of truth for combatant
## power alongside CombatantStats.
func _build_endless_level(level_number: int) -> LevelDef:
	var lvl := LevelDef.new()
	lvl.display_name = "The Endless Wood — Depth %d" % level_number

	var pool: Array[StringName] = ENDLESS_EARLY_POOL.duplicate()
	if level_number >= 2:
		pool.append_array(ENDLESS_MID_POOL)
	@warning_ignore("integer_division")
	var enemy_count := mini(2 + level_number / 3, 3)

	var e0 := EncounterDef.new()
	e0.type = EncounterDef.Type.COMBAT
	e0.enemy_stat_ids = _random_enemies(pool, enemy_count)
	e0.travel_duration = 2.0

	var e1 := EncounterDef.new()
	e1.type = EncounterDef.Type.LOOT
	e1.loot_item_count = Tuning.LOOT_ITEMS_PER_CHEST
	e1.travel_duration = 3.0

	var e2 := EncounterDef.new()
	e2.type = EncounterDef.Type.COMBAT
	e2.enemy_stat_ids = _random_enemies(pool, enemy_count)
	e2.travel_duration = 3.0

	var e3 := EncounterDef.new()
	e3.type = EncounterDef.Type.SHOP
	e3.shop_item_count = Tuning.SHOP_ITEMS_FOR_SALE
	e3.travel_duration = 3.0

	var e4 := EncounterDef.new()
	e4.type = EncounterDef.Type.COMBAT
	e4.enemy_stat_ids = _random_enemies(pool, enemy_count)
	e4.travel_duration = 3.0

	# Boss listed first so it lands at the leftmost enemy slot (spec 7.3),
	# same convention as the fixed level's boss encounter.
	var boss_id: StringName = RNG.pick(BOSS_POOL)
	var e5_ids: Array[StringName] = [boss_id]
	e5_ids.append_array(_random_enemies(pool, mini(enemy_count, 2)))
	var e5 := EncounterDef.new()
	e5.type = EncounterDef.Type.COMBAT
	e5.is_boss = true
	e5.enemy_stat_ids = e5_ids
	e5.travel_duration = 4.0

	lvl.encounters = [e0, e1, e2, e3, e4, e5]
	return lvl

func _random_enemies(pool: Array[StringName], count: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i: int in range(count):
		var id: StringName = RNG.pick(pool)
		out.append(id)
	return out

# --- fixed level (endless_mode = false) --------------------------------------

func _build_whispering_wood_level() -> LevelDef:
	var lvl := LevelDef.new()
	lvl.display_name = "The Whispering Wood"

	var e0 := EncounterDef.new()
	e0.type = EncounterDef.Type.COMBAT
	e0.enemy_stat_ids = [&"shadow_monster", &"shadow_monster"]
	e0.travel_duration = 2.0

	var e1 := EncounterDef.new()
	e1.type = EncounterDef.Type.LOOT
	e1.loot_item_count = Tuning.LOOT_ITEMS_PER_CHEST
	e1.travel_duration = 3.0

	var e2 := EncounterDef.new()
	e2.type = EncounterDef.Type.COMBAT
	# skeleton_warrior fills the heavy slot the orc barbarian used to hold
	# (see ENDLESS_MID_POOL) - closest melee bruiser in the roster.
	e2.enemy_stat_ids = [&"shadow_monster", &"shadow_monster", &"skeleton_warrior"]
	e2.travel_duration = 3.0

	var e3 := EncounterDef.new()
	e3.type = EncounterDef.Type.SHOP
	e3.shop_item_count = Tuning.SHOP_ITEMS_FOR_SALE
	e3.travel_duration = 3.0

	var e4 := EncounterDef.new()
	e4.type = EncounterDef.Type.COMBAT
	e4.enemy_stat_ids = [&"skeleton_warrior", &"skeleton_warrior", &"shadow_monster"]
	e4.travel_duration = 3.0

	# Boss listed first so it lands at the leftmost enemy slot (x = 1.6) and
	# its scaled-up body stays inside the frame (spec 7.3).
	var e5 := EncounterDef.new()
	e5.type = EncounterDef.Type.COMBAT
	e5.is_boss = true
	e5.enemy_stat_ids = [RNG.pick(BOSS_POOL), &"shadow_monster"]
	e5.travel_duration = 4.0

	lvl.encounters = [e0, e1, e2, e3, e4, e5]
	return lvl

## [town] Whether the blacksmith should generate Buy-tab stock on entry (spec
## 7.4). The ONLY caller is blacksmith.gd's _ready(); it lives here rather than in
## the scene so it is reachable headless (see tests/test_forge_stock.gd). Not
## derivable from forge_stock.is_empty() - that is also true once every card has
## been bought, and treating "sold out" as "never generated" turns leaving the
## screen into a free refresh (spec 7.4).
func needs_forge_restock() -> bool:
	return not forge_stock_generated

## [town] A brand new profile - the thing a missing / unreadable save file
## falls back to (spec 2.4). Resets everything PROFILE-scoped: currencies,
## inventory, the active party, and hero HP to full. Memory only - the caller
## persists the fallback (see "THIS FUNCTION DOES NOT SAVE" below).
##
## Step 2 (spec 14) replaced this function's step-1 placeholders: gold/scrap now
## use spec 11's PROFILE_STARTING_GOLD / PROFILE_STARTING_SCRAP (a 75-gold
## profile shipping forever was the failure mode). STARTING_GOLD (75) is
## untouched and still means "gold the slot economy was balanced against"
## (test_economy.gd:41).
##
## THIS FUNCTION DOES NOT SAVE, and that is deliberate (step-2 Q4). It is a
## memory-only reset; whoever DECIDES a new profile is real - boot.tscn, on
## load_profile() returning false (spec 3.1) - is what persists it.
##
## The reason is that this function is DESTRUCTIVE and reset_run() calls it
## unconditionally, which RunController._start_run() calls on every boot and
## retry. A save call here would mean every single launch overwrites the
## player's file with a fresh 150-gold profile before anything has a chance to
## load it. A new profile is fully deterministic, so re-deriving it after a
## crash costs nothing - there is no state here worth persisting eagerly.
## Spec 2.4's own "When to save" list never names this function.
##
## [town] spec 4.5 flipped active_party here to the solo warrior - this
## assignment plus the field's initialiser are the value flip that makes the
## party solo. PARTY_ORDER stays the canonical roster.
func new_profile() -> void:
	gold = Tuning.PROFILE_STARTING_GOLD
	scrap = Tuning.PROFILE_STARTING_SCRAP
	inventory.clear()
	forge_stock.clear()          # the blacksmith regenerates on first visit (spec 7.4)
	forge_stock_generated = false
	active_party = [&"warrior"] as Array[StringName]
	# [day-night] a fresh profile starts a fresh first day, unfed, no night owed.
	day_phase = DayPhase.DAY
	day_number = 1
	meal_pct = 0
	meal_eaten_today = false
	_reset_hero_runtime(true)     # full heal - a new profile starts whole

## [town] Everything an EXPEDITION owns, and nothing a profile owns. Called from
## the mayor's office (spec 7.5) and debug `quest` on accept, and from reset_run()
## with no argument for the endless / fixed dev path.
##
## Deliberately does NOT touch gold, scrap or inventory - see reset_run()'s
## comment for why that absence matters once this stops being called back to
## back with new_profile() on every retry.
func start_expedition(q: QuestDef = null) -> void:
	quest = q
	completed_quest = null
	# [day-night] T1: DAY -> QUEST (day/night spec §2.2). Guarded on q != null and
	# this is NOT cosmetic: reset_run() and debug.gd's `route quest` call this
	# with no argument for the endless path, whose quest-end blocks (where T2
	# lives) are inside `if GameState.quest != null`. An unguarded T1 would push
	# the endless path into QUEST and strand it there - no T2, no T3, and the
	# mayor's §2.3 guard then locks the player out of quests permanently.
	if q != null:
		day_phase = DayPhase.QUEST
	current_encounter_index = -1
	# Must precede build_level() - _build_endless_level() reads it. Spec 2.3's
	# listing omits this line; without it a retry regenerates at the depth the
	# party died on, and test_endless_level_gen.gd:13 is what catches that.
	endless_level_number = 1
	expedition_gold = 0
	expedition_scrap = 0
	_expedition_inventory_mark = inventory.size()
	drops_by_class.clear()
	Upgrades.reset()
	level = build_level()
	_reset_hero_runtime(false)    # keep current HP - the inn is the heal

	for key: String in run_stats.keys():
		if key == "run_time":
			run_stats[key] = 0.0
		else:
			run_stats[key] = 0
	EventBus.gold_changed.emit(gold, 0)
	EventBus.party_bonuses_changed.emit(party_bonuses())
	if quest != null:
		EventBus.quest_started.emit(quest)

## [town] Rebuilds hero_runtime from active_party, exactly as spec 2.3 words
## it ("rebuilds hero_runtime from active_party, not PARTY_ORDER").
##
## Reading active_party here is a provable no-op today - the field is
## initialised to PARTY_ORDER.duplicate() and nothing writes it - so it costs
## no behaviour change and takes one site off spec 4.5's list of three. The
## coupling 4.5 worries about (drops targeting a hero who is not on the field)
## is created by active_party's VALUE changing, not by which name each site
## reads, so moving this one read early decouples nothing.
##
## `full_heal` false preserves an existing entry's current_hp instead of
## resetting it to max. That is what lets damage carry home once new_profile()
## and start_expedition() stop being called back to back (spec 2.1: hero HP is
## profile-scoped, the inn is the heal). `alive` is derived from the resulting
## hp, never assumed true, so a hero who died stays dead until something heals
## them - which is what spec 8.5's two recovery buttons are for.
func _reset_hero_runtime(full_heal: bool) -> void:
	var previous: Array = hero_runtime
	hero_runtime = []
	for id: StringName in active_party:
		var s := get_stats(id)
		if s == null:
			continue
		var hp: int = s.max_hp
		if not full_heal:
			for entry: Dictionary in previous:
				if entry["stats_id"] == id:
					hp = int(entry["current_hp"])
					break
		hero_runtime.append({
			"stats_id": id,
			"current_hp": hp,
			"max_hp": s.max_hp,
			"alive": hp > 0,
		})

## [town] The inn's "Rest for the night" (spec 7.2): every hero in active_party
## back to full HP, the dead among them revived. Hero HP is profile-scoped
## (spec 2.1), so GameState owns the heal and the inn scene only spends the
## gold. This is new_profile()'s full-heal branch without the rest of the wipe.
func heal_party() -> void:
	_reset_hero_runtime(true)

## [town] spec 8.5 failure flow: a lost quest keeps profile gold and scrap but
## discards every UNEQUIPPED item picked up during the expedition - inventory
## entries at indices >= _expedition_inventory_mark (the snapshot start_expedition()
## took). Gear worn into or found on the trip survives; items bought at the
## quest's shop are discarded too, which is correct - expedition gold bought them
## and they never made it home. Iterates backwards so remove_at() is index-safe.
func discard_expedition_loot() -> void:
	for i: int in range(inventory.size() - 1, _expedition_inventory_mark - 1, -1):
		if inventory[i].equipped_by == &"":
			inventory.remove_at(i)
	EventBus.party_bonuses_changed.emit(party_bonuses())

## The free "Sleep in the street" night option: every hero heals ceil(half its
## missing HP), the dead among them revived to that. Arithmetic byte-for-byte
## as it was (day/night spec §3.2); only the guard changed - it used to set
## street_sleep_used, now the day/night state machine makes a second call
## unreachable (§2.2). Called by resolve_night(NightChoice.STREET).
func street_sleep_recover() -> void:
	for entry: Dictionary in hero_runtime:
		var missing: int = int(entry["max_hp"]) - int(entry["current_hp"])
		if missing > 0:
			entry["current_hp"] = int(entry["current_hp"]) \
				+ ceili(float(missing) * Tuning.INN_STREET_HEAL_FRACTION)
		entry["alive"] = int(entry["current_hp"]) > 0

# --- [day-night] the night and the meal (day/night spec §3.5, §9) -----------

## The price of a full-heal night: INN_REST_COST_PER_HERO x party size. Moved
## here so inn.gd and quest_result.gd stop each owning a copy of this arithmetic
## (day/night spec §3.1).
func night_inn_cost() -> int:
	return Tuning.INN_REST_COST_PER_HERO * maxi(active_party.size(), 1)

## [day-night] The one and only heal in the game outside combat (§2.2 T3).
## Charges for the inn, applies the chosen recovery, advances the day, and
## returns the report NightResult replays (§4.3).
##
## Returns [] - and mutates NOTHING - if no night is owed, or if the inn was
## chosen and cannot be paid for. The caller checks for the empty array and
## leaves its buttons live; there is no partial application to unwind.
func resolve_night(choice: NightChoice) -> Array:
	if day_phase != DayPhase.NIGHT_PENDING:
		return []

	# Snapshot BEFORE any mutation - this is what the bars start at (§4.3).
	var report: Array = []
	for entry: Dictionary in hero_runtime:
		report.append({
			"stats_id": entry["stats_id"],
			"before_hp": int(entry["current_hp"]),
			"after_hp": int(entry["current_hp"]),   # rewritten below
			"max_hp": int(entry["max_hp"]),
			"was_dead": int(entry["current_hp"]) <= 0,
		})

	if choice == NightChoice.INN:
		if not spend_gold(night_inn_cost()):
			return []                      # unaffordable: no charge, no heal
		heal_party()                       # town spec §7.2, unchanged
	else:
		street_sleep_recover()             # §3.2, unchanged

	for i: int in range(report.size()):
		report[i]["after_hp"] = int(hero_runtime[i]["current_hp"])

	day_phase = DayPhase.DAY
	day_number += 1
	meal_eaten_today = false               # a new day, a new meal (§9.4)
	last_night_report = report
	return report

## [day-night] The inn's meal (§9.3). One per day, in town only. Returns false
## and spends nothing if the guard or the gold check fails - the caller leaves
## its button live rather than unwinding a partial purchase.
func buy_meal() -> bool:
	if day_phase != DayPhase.DAY or meal_eaten_today:
		return false
	if not spend_gold(meal_cost()):
		return false
	meal_pct = Tuning.MEAL_DAMAGE_PCT      # assigned, never accumulated
	meal_eaten_today = true
	EventBus.party_bonuses_changed.emit(party_bonuses())   # §9.5
	return true

func meal_cost() -> int:
	return Tuning.MEAL_COST_PER_HERO * maxi(active_party.size(), 1)

## The meal as a multiplier, for combatant.gd. 1.0 when unfed.
func meal_multiplier() -> float:
	return 1.0 + float(meal_pct) / 100.0

## The endless-mode entry point: the one caller that wants BOTH halves.
## RunController on boot and on retry, and test_endless_level_gen.gd directly,
## all mean "reset absolutely everything, right now" - which is exactly the
## two halves in sequence, so nothing observable changed at step 1. Gold,
## scrap and inventory still reset on every retry, same as before the split.
##
## This is NOT a temporary shim, despite spec 2.3's "reset_run() is deleted".
## Spec 13.3 requires test_endless_level_gen.gd to keep passing with NO edits
## for the whole of this pass, and that test calls reset_run() directly; 13.3
## also states endless mode survives intact, "only bypassed when quest !=
## null". Deleting this function would force the test edit 13.3 forbids, so it
## stays, permanently, as endless mode's way in.
##
## What DOES change later is that quest accept calls start_expedition() ALONE
## (spec 8, via the mayor's office). That is the path on which gold, scrap and
## inventory finally survive a retry, and it is the whole reason the two halves
## are separate functions. Nothing on this line reaches that path.
func reset_run() -> void:
	new_profile()
	start_expedition()
