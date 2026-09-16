extends Node
## Throwaway diagnostic for sim_reviewers.gd: dumps one fresh-profile easy
## expedition blow-by-blow, so the 100%-wipe result can be confirmed or blamed
## on the resolver. Also checks what RecruitRewardExtra.grant() actually does
## for each of the two recruit quests.

func _ready() -> void:
	RNG.set_seed(20260916)
	GameState.new_profile()
	Upgrades.reset()

	print("=== fresh profile ===")
	print("gold=%d scrap=%d" % [GameState.gold, GameState.scrap])
	for item: Item in GameState.inventory:
		print("  item: %s | slot=%d equipped_by=%s value=%d power=%d armor=%d" % [
			item.display_name, item.slot(), item.equipped_by, item.value,
			item.power(), item.armor_value()])
	print("warrior: level=%d max_hp=%d armor=%d weapon_power=%d" % [
		GameState.hero_level(&"warrior"), GameState.hero_max_hp(&"warrior"),
		GameState.hero_armor(&"warrior"), GameState.hero_weapon_power(&"warrior")])

	print("\n=== recruit reward extras ===")
	for path: String in ["res://resources/quests/ranger_recruit.tres",
			"res://resources/quests/recruit_mage.tres"]:
		var q: QuestDef = load(path)
		print("%s: one_shot=%s unlock_level=%d extras=%d objectives=%d" % [
			q.id, q.one_shot, q.unlock_level, q.reward_extras.size(), q.objectives.size()])
		for extra: QuestRewardExtra in q.reward_extras:
			print("   extra kind=%s hero_class='%s' token='%s' -> %s" % [
				extra.kind(), extra.get("hero_class"), extra.get("token_weapon_type"),
				extra.describe()])
		for obj: QuestObjective in q.objectives:
			print("   objective kind=%s target_weapon_type='%s' count=%s" % [
				obj.kind(), obj.get("target_weapon_type"), obj.get("count")])

	print("\n=== one easy expedition, blow by blow ===")
	var quest: QuestDef = load("res://resources/quests/easy.tres")
	GameState.start_expedition(quest)
	var hp := GameState.hero_max_hp(&"warrior")
	var max_hp := hp
	var armor := GameState.hero_armor(&"warrior")

	for i: int in range(GameState.level.encounters.size()):
		var enc: EncounterDef = GameState.level.encounters[i]
		if enc.type != EncounterDef.Type.COMBAT:
			print("encounter %d: type=%d level=%d (non-combat)" % [i, enc.type, enc.level])
			continue
		print("encounter %d: level=%d boss=%s enemies=%s" % [
			i, enc.level, enc.is_boss, str(enc.enemy_stat_ids)])
		for eid: StringName in enc.enemy_stat_ids:
			var s := GameState.get_stats(eid)
			var lvl: int = enc.level + (Tuning.BOSS_LEVEL_BONUS if enc.is_boss else 0)
			print("    %s: lvl=%d hp=%d weapon_power=%d cooldown=%.2f" % [
				eid, lvl, s.hp_at(lvl), s.weapon_power_at(lvl), s.attack_cooldown])

	print("\n=== what one spin pays, fresh profile ===")
	var bag := _bag()
	print("bag size=%d (non-blank=%d)" % [bag.size(), _non_blank(bag)])
	var totals: Array[int] = []
	for _t: int in range(200):
		totals.append(_spin_damage(bag))
	var sum := 0
	for v: int in totals:
		sum += v
	print("mean combined swing per spin over 200 spins: %.1f" % (float(sum) / 200.0))
	print("spin cycle: %.2f s -> party dps ~ %.1f" % [
		2.44, float(sum) / 200.0 / 2.44])

	print("\n=== warrior survivability ===")
	print("warrior hp=%d armor=%d" % [max_hp, armor])
	var s_shadow := GameState.get_stats(&"shadow_monster")
	if s_shadow != null:
		var dmg: int = maxi(1, s_shadow.weapon_power_at(1) - armor)
		print("shadow_monster lvl1 hits for %d after armor -> %d hits to kill warrior" % [
			dmg, int(ceil(float(max_hp) / float(dmg)))])
	get_tree().quit()

func _bag() -> Array:
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

func _non_blank(bag: Array) -> int:
	var n := 0
	for ic: Dictionary in bag:
		if not SlotIcon.is_blank(ic):
			n += 1
	return n

func _spin_damage(bag: Array) -> int:
	var board: Array = SlotMachineScript.draw_nine(bag)
	var swing := 0
	for ic: Dictionary in board:
		var id := StringName(ic.get("id", &""))
		if SlotIcon.kind_of(id) == SlotIcon.Kind.DAMAGE:
			swing += maxi(1, int(ic.get("roll", 0))) + Tuning.SLOT_ATTACK_ICON_FLOOR
	return swing

const SlotMachineScript := preload("res://scripts/console/slot_machine.gd")
