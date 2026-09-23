extends Node
## The mage recruitment quest (Recruitment Quest Acceptance Test Outline):
## CollectObjective, RecruitRewardExtra, QuestDef.guaranteed_boss_drop, the
## discard_expedition_loot() RELIC exemption, and the authored
## recruit_mage.tres quest's internal consistency (all three of its
## hand-authored weapon_type references must agree).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_recruit_mage.tscn

const TestSupport := preload("res://tests/test_support.gd")

func _ready() -> void:
	var t := TestSupport.new()
	t.guard_user_file(SaveGame.PATH)

	_check_collect_objective(t)
	_check_authored_quest_consistency(t)
	_check_recruit_reward_extra(t)
	_check_join_level(t)
	_check_wipe_survival(t)
	_check_end_to_end(t)
	_check_persistence(t)

	GameState.quest = null
	GameState.completed_quest = null
	t.finish(get_tree(), "test_recruit_mage")

func _check_collect_objective(t: TestSupport) -> void:
	var obj := CollectObjective.new()
	obj.target_weapon_type = &"heartstone"
	obj.count = 1
	t.check(not obj.is_complete(), "CollectObjective: not complete with nothing collected")

	var unrelated := Item.new()
	unrelated.weapon_type = &"amulet"
	obj.on_event(&"item_added", { "item": unrelated })
	t.check(not obj.is_complete(),
		"CollectObjective: an item of a different weapon_type does not count")

	var relic := Item.new()
	relic.weapon_type = &"heartstone"
	relic.kind = Item.Kind.RELIC
	obj.on_event(&"item_added", { "item": relic })
	t.check(obj.is_complete(), "CollectObjective: the matching weapon_type completes it")
	t.check(obj.progress() == Vector2i(1, 1), "CollectObjective: progress reports (1, 1)")

func _check_authored_quest_consistency(t: TestSupport) -> void:
	var q: QuestDef = load("res://resources/quests/recruit_mage.tres")
	t.check(q != null, "recruit_mage.tres loads as a QuestDef")
	t.check(q.objectives.size() == 1 and q.objectives[0] is CollectObjective,
		"recruit_mage.tres carries exactly one CollectObjective")
	t.check(q.reward_extras.size() == 1 and q.reward_extras[0] is RecruitRewardExtra,
		"recruit_mage.tres carries exactly one RecruitRewardExtra")
	t.check(q.guaranteed_boss_drop != null and q.guaranteed_boss_drop.kind == Item.Kind.RELIC,
		"recruit_mage.tres's guaranteed_boss_drop is an authored RELIC")

	var objective := q.objectives[0] as CollectObjective
	var extra := q.reward_extras[0] as RecruitRewardExtra
	var token: Item = q.guaranteed_boss_drop
	t.check(objective.target_weapon_type == token.weapon_type,
		"the objective's target_weapon_type matches the guaranteed drop's own weapon_type")
	t.check(extra.token_weapon_type == token.weapon_type,
		"the reward extra's token_weapon_type matches the guaranteed drop's own weapon_type")
	t.check(extra.hero_class == &"mage", "the reward extra recruits the mage")
	t.check(GameState.get_class_def(extra.hero_class) != null,
		"the recruited class has a registered ClassDef")
	t.check(q.unlock_level == 5, "recruit_mage.tres unlocks at level 5")
	t.check(not extra.description.is_empty() and extra.describe() == extra.description,
		"describe() returns the authored description naming the relic (issue #94), got %s"
		% extra.describe())
	t.check(extra.join_level == 5 and extra.join_level == q.unlock_level,
		"the mage joins at her quest's own level (got join_level %d, unlock_level %d)"
			% [extra.join_level, q.unlock_level])

	# §5.8 (resolved): the mage must actually be able to equip a TRINKET.
	t.check(token.slot() == Item.Slot.TRINKET, "the guaranteed drop resolves to the TRINKET slot")

func _check_recruit_reward_extra(t: TestSupport) -> void:
	GameState.new_profile()
	var extra := RecruitRewardExtra.new()
	extra.hero_class = &"mage"
	extra.token_weapon_type = &"heartstone"

	var token := Item.new()
	token.kind = Item.Kind.RELIC
	token.weapon_type = &"heartstone"
	GameState.inventory.append(token)

	t.check(not GameState.active_party.has(&"mage"), "mage is not in a fresh profile's active_party")
	extra.grant()
	t.check(GameState.active_party.has(&"mage"), "grant() adds the mage to active_party")
	t.check(token.equipped_by == &"mage", "grant() equips the picked-up token onto the recruit")
	t.check(token.slot() == Item.Slot.TRINKET, "the equipped token occupies the TRINKET slot")

	# Idempotence: a second grant() (e.g. a save/quit mid-result-screen replaying
	# the same victory) must not duplicate the class or re-equip destructively.
	var party_size_before := GameState.active_party.size()
	extra.grant()
	t.check(GameState.active_party.size() == party_size_before,
		"grant() does not duplicate an already-recruited class")

## Recruits join at their quest's level, not level 1 and not the party's best.
func _check_join_level(t: TestSupport) -> void:
	var extra: RecruitRewardExtra = (load("res://resources/quests/recruit_mage.tres") as QuestDef).reward_extras[0]

	GameState.new_profile()
	GameState.hero_levels[&"warrior"] = 9   # a party well past her quest's level
	extra.grant()
	t.check(GameState.hero_level(&"mage") == 5,
		"the mage joins at level 5, not level 1 and not the level-9 party's (got %d)"
			% GameState.hero_level(&"mage"))
	t.check(GameState.hero_xp_for(&"mage") == 0, "a fresh recruit starts with no xp toward the next level")
	var entry := _status_entry(&"mage")
	t.check(not entry.is_empty() and int(entry["level"]) == 5
			and int(entry["max_hp"]) == GameState.get_stats(&"mage").hp_at(5),
		"party_status() shows the mage at level 5 max hp")

	GameState.hero_levels[&"mage"] = 6
	extra.grant()
	t.check(GameState.hero_level(&"mage") == 6, "a repeat grant() leaves a levelled recruit alone")

	var back := QuestRewardExtra.from_dict(extra.to_dict()) as RecruitRewardExtra
	t.check(back != null and back.join_level == 5, "join_level round-trips through to_dict()/from_dict()")

## The party_status() row for `id`, or {} when that hero is not in the party.
func _status_entry(id: StringName) -> Dictionary:
	for e: Dictionary in GameState.party_status():
		if e["stats_id"] == id:
			return e
	return {}

func _check_wipe_survival(t: TestSupport) -> void:
	GameState.new_profile()
	var q: QuestDef = load("res://resources/quests/recruit_mage.tres")
	GameState.start_expedition(q)

	var relic := Item.new()
	relic.kind = Item.Kind.RELIC
	relic.weapon_type = &"heartstone"
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
	var q: QuestDef = load("res://resources/quests/recruit_mage.tres")
	GameState.start_expedition(q)
	t.check(GameState.quest_objectives.size() == 1 and GameState.quest_objectives[0] is CollectObjective,
		"start_expedition() duplicates recruit_mage.tres's CollectObjective")
	t.check(not GameState.quest_objectives_complete(), "objective is incomplete before the token drops")

	# The boss drop + pickup, exactly as BattleDirector._roll_drop() /
	# RunController._award_drops() would produce it.
	var relic: Item = q.guaranteed_boss_drop.duplicate(true)
	GameState.add_item(relic)
	GameState.quest_objectives[0].on_event(&"item_added", { "item": relic })
	t.check(GameState.quest_objectives_complete(),
		"quest_objectives_complete() is true once the relic is added to inventory")

	# RunController._run_complete()'s reward pass.
	for extra: QuestRewardExtra in q.reward_extras:
		extra.grant()
	t.check(GameState.active_party.has(&"mage"), "the reward pass recruits the mage")
	t.check(relic.equipped_by == &"mage", "the reward pass equips the very item that was picked up")
	t.check(GameState.inventory.has(relic),
		"the token is never removed from inventory - it becomes gear, not a consumed keepsake")

func _check_persistence(t: TestSupport) -> void:
	var obj := CollectObjective.new()
	obj.description = "Recover the mage's stolen heartstone."
	obj.target_weapon_type = &"heartstone"
	obj.count = 1
	var obj_back := QuestObjective.from_dict(obj.to_dict()) as CollectObjective
	t.check(obj_back != null and obj_back.target_weapon_type == &"heartstone" and obj_back.count == 1,
		"CollectObjective round-trips through to_dict()/from_dict()")

	var extra := RecruitRewardExtra.new()
	extra.description = "The mage joins the party, heartstone in hand."
	extra.hero_class = &"mage"
	extra.token_weapon_type = &"heartstone"
	var extra_back := QuestRewardExtra.from_dict(extra.to_dict()) as RecruitRewardExtra
	t.check(extra_back != null and extra_back.hero_class == &"mage"
			and extra_back.token_weapon_type == &"heartstone"
			and extra_back.description == extra.description,
		"RecruitRewardExtra round-trips through to_dict()/from_dict()")
