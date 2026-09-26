extends Node
## Equipped hand items show their mesh (backlog §3 P3b, issue #77).
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_hand_props.tscn
##
## Builds the real hero scenes and checks which props under the KayKit
## handslots are visible for a given loadout. The rule under test is
## CombatantRig.apply_hand_props(): the weapon's `prop` in the right hand, the
## armor's in the left, a two-hander empties the left hand, and nothing else on
## either hand shows.

const TestSupport := preload("res://tests/test_support.gd")

var _t := TestSupport.new()

func _ready() -> void:
	_t.guard_user_file(SaveGame.PATH)
	GameState.inventory = []

	var warrior := _make_hero(&"warrior")
	_equip(&"warrior", &"sword")
	_equip(&"warrior", &"tower_shield")
	warrior.apply_party_bonuses()
	_t.check(_shown(warrior) == ["1H_Sword", "Rectangle_Shield"],
		"sword + tower shield show exactly their two props (got %s)" % [_shown(warrior)])

	_equip(&"warrior", &"greatsword")
	warrior.apply_party_bonuses()
	_t.check(_shown(warrior) == ["2H_Sword"],
		"a two-handed greatsword hides the shield (got %s)" % [_shown(warrior)])

	_equip(&"warrior", &"axe")
	warrior.apply_party_bonuses()
	_t.check(_shown(warrior) == ["Rectangle_Shield", "axe_1handed"],
		"the pack axe is instanced into the right hand beside the shield (got %s)" % [_shown(warrior)])
	var axe := CombatantRig.find_by_name(warrior, "axe_1handed") as Node3D
	var sword := CombatantRig.find_by_name(warrior, "1H_Sword") as Node3D
	_t.check(axe != null and sword != null and axe.get_parent() == sword.get_parent()
		and axe.transform.is_equal_approx(sword.transform),
		"the axe sits on the sword's handslot with the sword's local transform")
	warrior.apply_party_bonuses()
	var axes := 0
	for child: Node in sword.get_parent().get_children():
		if String(child.name).begins_with("axe_1handed"):
			axes += 1
	_t.check(axes == 1, "re-applying never instances a second axe (got %d)" % axes)

	for item: Item in GameState.inventory.duplicate():
		if item.equipped_by == &"warrior":
			GameState.unequip_item(item)
	warrior.apply_party_bonuses()
	_t.check(_shown(warrior).is_empty(), "an empty warrior's hands show nothing (got %s)" % [_shown(warrior)])

	var mage := _make_hero(&"mage")
	_equip(&"mage", &"staff")
	_equip(&"mage", &"tome")
	mage.apply_party_bonuses()
	_t.check(_shown(mage) == ["2H_Staff", "Spellbook"],
		"the staff is not two-handed: the mage keeps her book (got %s)" % [_shown(mage)])
	_equip(&"mage", &"wand")
	mage.apply_party_bonuses()
	_t.check(_shown(mage) == ["1H_Wand", "Spellbook"], "the wand replaces the staff (got %s)" % [_shown(mage)])
	var staff_mi := CombatantRig.find_by_name(mage, "2H_Staff") as MeshInstance3D
	var wand_mi := CombatantRig.find_by_name(mage, "1H_Wand") as MeshInstance3D
	_t.check(staff_mi.material_override != null and wand_mi.material_override == staff_mi.material_override,
		"the wand shares the staff's glow material, so the cast glow lights it")

	var ranger := _make_hero(&"ranger")
	_equip(&"ranger", &"heavy_crossbow")
	_equip(&"ranger", &"helm")
	ranger.apply_party_bonuses()
	_t.check(_shown(ranger) == ["2H_Crossbow"],
		"heavy crossbow shows, the helm has no hand prop, Throwable and the offhand knife stay hidden (got %s)" % [_shown(ranger)])
	_equip(&"ranger", &"bow")
	ranger.apply_party_bonuses()
	_t.check(_shown(ranger) == ["1H_Crossbow"], "the bow borrows the crossbow until #78 (got %s)" % [_shown(ranger)])

	# No enemy carries a KayKit hand prop (the skeletons' handslots import as
	# bare bones), so drive the pass with the warrior's own model and a
	# non-hero copy of its stats: every prop must be left as it was.
	var not_hero := GameState.get_stats(&"warrior").duplicate() as CombatantStats
	not_hero.is_hero = false
	var sword_node := CombatantRig.find_by_name(warrior, "1H_Sword") as Node3D
	sword_node.visible = true
	CombatantRig.apply_hand_props(warrior.rig, not_hero)
	_t.check(sword_node.visible, "a non-hero's hands are left alone")

	for id: StringName in Itemizer.ITEM_TYPES:
		var row: Dictionary = Itemizer.ITEM_TYPES[id]
		if bool(row.get("two_handed", false)):
			_t.check(int(row["slot"]) == Item.Slot.WEAPON, "%s: only a weapon can be two-handed" % id)

	_t.finish(get_tree(), "test_hand_props")

func _make_hero(id: StringName) -> Combatant:
	var stats := GameState.get_stats(id)
	var c := (load(stats.scene_path) as PackedScene).instantiate() as Combatant
	add_child(c)
	c.setup(stats, -1)
	return c

func _equip(hero: StringName, type: StringName) -> void:
	var item := Itemizer.generate_typed_item(type, Item.Rarity.COMMON, 1)
	GameState.add_item(item)
	GameState.equip_item(item, hero)

## Visible props under both handslots, sorted.
func _shown(c: Combatant) -> Array[String]:
	var out: Array[String] = []
	for slot_name: String in CombatantRig.HAND_SLOTS:
		var hand := CombatantRig.find_by_name(c, slot_name)
		if hand == null:
			continue
		for child: Node in hand.get_children():
			if child is Node3D and (child as Node3D).visible:
				out.append(String(child.name))
	out.sort()
	return out
