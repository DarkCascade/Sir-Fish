class_name RecruitRewardExtra
extends QuestRewardExtra
## Adds a class to the party (Recruitment Quest Acceptance Test Outline §5.5/
## §5.6). grant() appending to GameState.active_party is the first new path
## into the party the game has ever had - new_profile() and SaveGame's loader
## were the only two writers before this (see active_party's own comment in
## game_state.gd).
##
## Runs on victory only, alongside gold, from RunController._run_complete() -
## by that point the quest's CollectObjective could not have completed unless
## its token is already sitting in GameState.inventory, so token_weapon_type
## only has to FIND that item, never create or duplicate one (§5.4's "becomes
## the recruit's starting trinket", the most-work option the outline named,
## turns out to need no new item plumbing at all for exactly this reason).

@export var hero_class: StringName = &""

## Matches Item.weapon_type on the quest's own token (see
## QuestDef.guaranteed_boss_drop and the matching CollectObjective's
## target_weapon_type - all three must name the same authored relic type).
## Left empty, the recruit simply joins bare-handed.
@export var token_weapon_type: StringName = &""

func grant() -> void:
	if hero_class == &"" or GameState.active_party.has(hero_class):
		return
	GameState.active_party.append(hero_class)
	if token_weapon_type == &"":
		return
	for item: Item in GameState.inventory:
		if item.weapon_type == token_weapon_type and item.equipped_by == &"":
			GameState.equip_item(item, hero_class)
			break

func describe() -> String:
	return "%s joins the party" % String(hero_class).capitalize()

func kind() -> StringName:
	return &"recruit"

func _to_dict_extra() -> Dictionary:
	return { "hero_class": hero_class, "token_weapon_type": token_weapon_type }

func _from_dict_extra(data: Dictionary) -> void:
	hero_class = StringName(data.get("hero_class", &""))
	token_weapon_type = StringName(data.get("token_weapon_type", &""))
