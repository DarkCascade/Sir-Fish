extends Node
## The ranger recruitment quest (P1) and its 2026-09-20 relic-parity fix.
##
## ranger_recruit.tres shipped ahead of the authored-RELIC design
## (Item.Kind.RELIC, QuestDef.guaranteed_boss_drop, CollectObjective.
## target_weapon_type) that recruit_mage.tres introduced hours later the same
## day - collect_objective.gd's shared script was rewritten to the new
## item_added/target_weapon_type contract, but ranger_recruit.tres's own
## resources were never migrated to supply it: collect_ranger_bow.tres had no
## target_weapon_type (so its objective could never legitimately complete)
## and ranger_recruit.tres had no guaranteed_boss_drop (so RecruitRewardExtra
## had nothing authored to find - it would only ever equip the ranger with
## whatever ordinary `bow` loot happened to be sitting unequipped in
## inventory, same as any other Magic-rarity drop, not a specific recovered
## item). This mirrors test_recruit_mage.gd, checking the same contract now
## that ranger_recruit.tres/collect_ranger_bow.tres/recruit_ranger.tres carry
## it via the new &"warbow" relic type.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_recruit_ranger.tscn

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()
	t.guard_user_file(SaveGame.PATH)

	_check_authored_quest_consistency(t)
	_check_recruit_reward_extra(t)
	_check_join_level(t)
	_check_wipe_survival(t)
	_check_end_to_end(t)

	GameState.quest = null
	GameState.completed_quest = null
	t.finish(get_tree(), "test_recruit_ranger")

func _check_authored_quest_consistency(t: TestSupport) -> void:
	var q: QuestDef = load("res://resources/quests/ranger_recruit.tres")
	t.check(q != null, "ranger_recruit.tres loads as a QuestDef")
	t.check(q.unlock_level == 3, "ranger_recruit.tres unlocks at level 3")
	t.check(q.one_shot, "ranger_recruit.tres is one_shot")
	t.check(q.objectives.size() == 1 and q.objectives[0] is CollectObjective,
		"ranger_recruit.tres carries exactly one CollectObjective")
	t.check(q.reward_extras.size() == 1 and q.reward_extras[0] is RecruitRewardExtra,
		"ranger_recruit.tres carries exactly one RecruitRewardExtra")
	t.check(q.guaranteed_boss_drop != null and q.guaranteed_boss_drop.kind == Item.Kind.RELIC,
		"ranger_recruit.tres's guaranteed_boss_drop is an authored RELIC")

	var objective := q.objectives[0] as CollectObjective
	var extra := q.reward_extras[0] as RecruitRewardExtra
	var token: Item = q.guaranteed_boss_drop
	t.check(objective.target_weapon_type == token.weapon_type,
		"the objective's target_weapon_type matches the guaranteed drop's own weapon_type")
	t.check(extra.token_weapon_type == token.weapon_type,
		"the reward extra's token_weapon_type matches the guaranteed drop's own weapon_type")
	t.check(extra.hero_class == &"ranger", "the reward extra recruits the ranger")
	t.check(GameState.get_class_def(extra.hero_class) != null,
		"the recruited class has a registered ClassDef")
	t.check(not extra.description.is_empty() and extra.describe() == extra.description,
		"describe() returns the authored description naming the relic (issue #94), got %s"
		% extra.describe())
	t.check(extra.join_level == 3 and extra.join_level == q.unlock_level,
		"the ranger joins at her quest's own level (got join_level %d, unlock_level %d)"
			% [extra.join_level, q.unlock_level])

	# The relic must resolve to WEAPON, not fall through Item.slot()'s
	# unknown-type default - this is exactly the hazard backlog decision 1.1
	# named, and why &"warbow" has its own Itemizer.ITEM_TYPES row rather than
	# being left unregistered.
	t.check(token.slot() == Item.Slot.WEAPON, "the guaranteed drop resolves to the WEAPON slot")

func _check_recruit_reward_extra(t: TestSupport) -> void:
	GameState.new_profile()
	var extra := RecruitRewardExtra.new()
	extra.hero_class = &"ranger"
	extra.token_weapon_type = &"warbow"

	var token := Item.new()
	token.kind = Item.Kind.RELIC
	token.weapon_type = &"warbow"
	GameState.inventory.append(token)

	t.check(not GameState.active_party.has(&"ranger"), "ranger is not in a fresh profile's active_party")
	extra.grant()
	t.check(GameState.active_party.has(&"ranger"), "grant() adds the ranger to active_party")
	t.check(token.equipped_by == &"ranger", "grant() equips the picked-up token onto the recruit")
	t.check(token.slot() == Item.Slot.WEAPON, "the equipped token occupies the WEAPON slot")

	var party_size_before := GameState.active_party.size()
	extra.grant()
	t.check(GameState.active_party.size() == party_size_before,
		"grant() does not duplicate an already-recruited class")

## Recruits join at their quest's level, not level 1 and not the party's best.
func _check_join_level(t: TestSupport) -> void:
	var extra: RecruitRewardExtra = (load("res://resources/quests/ranger_recruit.tres") as QuestDef).reward_extras[0]

	GameState.new_profile()
	GameState.hero_levels[&"warrior"] = 8   # a party well past her quest's level
	extra.grant()
	t.check(GameState.hero_level(&"ranger") == 3,
		"the ranger joins at level 3, not level 1 and not the level-8 party's (got %d)"
			% GameState.hero_level(&"ranger"))
	t.check(GameState.hero_xp_for(&"ranger") == 0, "a fresh recruit starts with no xp toward the next level")
	var entry := _status_entry(&"ranger")
	t.check(not entry.is_empty() and int(entry["level"]) == 3
			and int(entry["max_hp"]) == GameState.get_stats(&"ranger").hp_at(3),
		"party_status() shows the ranger at level 3 max hp")

	# A second grant must not reset a recruit who has since levelled.
	GameState.hero_levels[&"ranger"] = 4
	extra.grant()
	t.check(GameState.hero_level(&"ranger") == 4, "a repeat grant() leaves a levelled recruit alone")

	# And a class that somehow already outranks the join level is never lowered.
	GameState.new_profile()
	GameState.hero_levels[&"ranger"] = 7
	extra.grant()
	t.check(GameState.hero_level(&"ranger") == 7, "grant() never lowers a level the class already has")

	# join_level survives a save round-trip.
	var back := QuestRewardExtra.from_dict(extra.to_dict()) as RecruitRewardExtra
	t.check(back != null and back.join_level == 3, "join_level round-trips through to_dict()/from_dict()")
	var legacy := extra.to_dict()
	legacy.erase("join_level")
	var legacy_back := QuestRewardExtra.from_dict(legacy) as RecruitRewardExtra
	t.check(legacy_back != null and legacy_back.join_level == 1,
		"a save with no join_level loads as 1 (the old behaviour)")

## The party_status() row for `id`, or {} when that hero is not in the party.
func _status_entry(id: StringName) -> Dictionary:
	for e: Dictionary in GameState.party_status():
		if e["stats_id"] == id:
			return e
	return {}

func _check_wipe_survival(t: TestSupport) -> void:
	GameState.new_profile()
	var q: QuestDef = load("res://resources/quests/ranger_recruit.tres")
	GameState.start_expedition(q)

	var relic := Item.new()
	relic.kind = Item.Kind.RELIC
	relic.weapon_type = &"warbow"
	var mundane := Itemizer.generate_item_with_rarity(Item.Rarity.COMMON)
	GameState.inventory.append(relic)
	GameState.inventory.append(mundane)

	GameState.discard_expedition_loot()
	t.check(GameState.inventory.has(relic),
		"an unequipped RELIC survives discard_expedition_loot() on a wipe")
	t.check(not GameState.inventory.has(mundane),
		"an unequipped non-RELIC is still discarded on a wipe")

	GameState.quest = null
	GameState.completed_quest = null

func _check_end_to_end(t: TestSupport) -> void:
	GameState.new_profile()
	var q: QuestDef = load("res://resources/quests/ranger_recruit.tres")
	GameState.start_expedition(q)
	t.check(GameState.quest_objectives.size() == 1 and GameState.quest_objectives[0] is CollectObjective,
		"start_expedition() duplicates ranger_recruit.tres's CollectObjective")
	t.check(not GameState.quest_objectives_complete(), "objective is incomplete before the token drops")

	# The boss drop + pickup, exactly as BattleDirector._roll_drop() /
	# RunController._award_drops() would produce it.
	var relic: Item = q.guaranteed_boss_drop.duplicate(true)
	GameState.add_item(relic)
	GameState.quest_objectives[0].on_event(&"item_added", { "item": relic })
	t.check(GameState.quest_objectives_complete(),
		"quest_objectives_complete() is true once the warbow is added to inventory")

	for extra: QuestRewardExtra in q.reward_extras:
		extra.grant()
	t.check(GameState.active_party.has(&"ranger"), "the reward pass recruits the ranger")
	t.check(relic.equipped_by == &"ranger", "the reward pass equips the very item that was picked up")
	t.check(GameState.inventory.has(relic),
		"the token is never removed from inventory - it becomes gear, not a consumed keepsake")
