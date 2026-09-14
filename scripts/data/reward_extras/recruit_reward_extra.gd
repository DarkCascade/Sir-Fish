class_name RecruitRewardExtra
extends QuestRewardExtra
## The recruitment outline's reward (recruitment outline §5.5, resolved by
## D2) - the first concrete QuestRewardExtra. grant() adds class_id to
## active_party, which the outline's §5.6 correction flags as the first NEW
## path into the party the game has ever had (new_profile() and the save
## loader are the only other writers).
##
## Idempotent (grant() no-ops if class_id is already in active_party), so a
## RunController._run_complete() double-call is harmless.
##
## Decisions this resolves (backlog P1 §5):
##   1.1 The retrieved item is never a real Item mid-run (CollectObjective
##       tracks progress instead) - grant() creates it here, at victory.
##   1.2 The retrieved item becomes the recruit's starting weapon; a Common
##       armor_type piece rides along so the recruit is never handed an
##       unarmed start, the same reasoning GameState.new_profile() gives for
##       the warrior's own starter kit.
##   1.3 The recruit joins at the party's best level (GameState.hero_level()),
##       so it never trails the party that recruited it.
##   1.4 grant() runs at victory, alongside gold, from
##       RunController._run_complete() - the recruit is in the party the
##       moment the player is back in town (outline §5.3's "safe" option).

## The class joining the party, e.g. &"ranger". Must name a real ClassDef or
## grant() silently does nothing (weapon_type / armor_type would have nowhere
## eligible to equip anyway).
@export var class_id: StringName = &""
## The item type the retrieved token becomes - the recruit's starting weapon
## (decision 1.2). Should be one of class_id's ClassDef.item_types; empty
## skips the weapon entirely.
@export var weapon_type: StringName = &""
## The recruit's starting armor type, Common rarity, mirroring
## new_profile()'s warrior kit. Empty skips the armor piece.
@export var armor_type: StringName = &""

func grant() -> void:
	if class_id == &"" or GameState.active_party.has(class_id):
		return
	GameState.active_party.append(class_id)
	var lvl: int = GameState.hero_level()
	# [item power model] Magic, not Common: the retrieved item is a named
	# prize, not a random find, and a bare Common weapon would leave the
	# recruit's whole offense (item.gd's power() comment) at its floor.
	if weapon_type != &"":
		GameState.add_item(Itemizer.generate_typed_item(weapon_type, Item.Rarity.MAGIC, lvl))
	if armor_type != &"":
		GameState.add_item(Itemizer.generate_typed_item(armor_type, Item.Rarity.COMMON, lvl))

func describe() -> String:
	if class_id == &"":
		return ""
	return "Joins the party: %s" % String(class_id).capitalize()

func kind() -> StringName:
	return &"recruit"

func _to_dict_extra() -> Dictionary:
	return { "class_id": class_id, "weapon_type": weapon_type, "armor_type": armor_type }

func _from_dict_extra(data: Dictionary) -> void:
	class_id = StringName(data.get("class_id", &""))
	weapon_type = StringName(data.get("weapon_type", &""))
	armor_type = StringName(data.get("armor_type", &""))
