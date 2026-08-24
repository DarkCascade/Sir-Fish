extends Node
## Debug harness (spec 19.2 / Q21). Permanent and flag-gated, not temporary.
##
## This MCP build has no execute_editor_script and no execute_game_script, and
## set_game_node_property can set a property but cannot call a function. So the
## harness exposes ONE string property whose setter parses and executes:
##
##   set_game_node_property("/root/Debug", "command", "slot 0 0 0")
##
## Every command writes exactly one "[DEBUG] ..." line to the output log, which
## get_output_log reads back. Inert in exported release builds.

var enabled: bool = OS.is_debug_build() \
	and bool(ProjectSettings.get_setting("sir_fish/debug/harness", true))

var command: String = "":
	set(value):
		command = value
		if enabled and not value.is_empty():
			_run(value)

## Forced payline for the NEXT spin, or an empty array. Cleared once consumed.
var slot_override: Array[int] = []
## Forced buy prices for the next shop's three cards, or an empty array.
var shop_price_override: Array[int] = []

func _log(text: String) -> void:
	print("[DEBUG] %s" % text)

# --- dispatch ---------------------------------------------------------------

func _run(line: String) -> void:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return
	var verb := parts[0]
	var args := parts.slice(1)
	match verb:
		"anim": _cmd_anim(args)
		"spawn": _cmd_spawn(args)
		"sethp": _cmd_sethp(args)
		"damage": _cmd_damage(args)
		"kill": _cmd_kill(args)
		"slot": _cmd_slot(args)
		"shop": _cmd_shop(args)
		"gold": _cmd_gold(args)
		"upgrade": _cmd_upgrade(args)
		"additem": _cmd_additem(args)
		"drops": _cmd_drops(args)
		"equip": _cmd_equip(args)
		"parallax": _cmd_parallax(args)
		"lightning": _cmd_lightning()
		"bone": _cmd_bone(args)
		"state": _cmd_state()
		_: _log("unknown command: %s" % verb)

# --- lookup helpers ---------------------------------------------------------

func _director():
	var controller := get_tree().root.find_child("RunController", true, false)
	if controller == null:
		return null
	return controller.get("director")

## Resolves against stats.id. Two live combatants can share an id (two shadow
## monsters), so an explicit index is accepted as "shadow_monster:1".
func _find(token: String) -> Combatant:
	var d = _director()   # BattleDirector (untyped: custom API)
	if d == null:
		return null
	var want := token
	var want_index := 0
	if token.contains(":"):
		var bits := token.split(":")
		want = bits[0]
		want_index = int(bits[1])
	var seen := 0
	var pool: Array[Combatant] = []
	pool.append_array(d.heroes)
	pool.append_array(d.enemies)
	for c: Combatant in pool:
		if not is_instance_valid(c) or c.stats == null:
			continue
		if String(c.stats.id) != want:
			continue
		if seen == want_index:
			return c
		seen += 1
	return null

# --- commands ---------------------------------------------------------------

func _cmd_anim(args: Array) -> void:
	if args.size() < 2:
		_log("anim -> needs <combatant_id> <name>")
		return
	var c := _find(String(args[0]))
	if c == null:
		_log("anim -> no combatant '%s'" % args[0])
		return
	# Deliberately ignores state, so a gate can force every clip on demand.
	c.anim.stop()
	c.anim.play(StringName(String(args[1])))
	_log("anim -> %s playing '%s'" % [args[0], args[1]])

func _cmd_spawn(args: Array) -> void:
	if args.is_empty():
		_log("spawn -> needs <stats_id>")
		return
	var d = _director()   # BattleDirector (untyped: custom API)
	if d == null:
		_log("spawn -> no director")
		return
	var stats := GameState.get_stats(StringName(String(args[0])))
	if stats == null:
		_log("spawn -> unknown stats id '%s'" % args[0])
		return
	var index: int = d.enemies.size()
	# [overworld prototype] Slots are points on the ground plane now, not
	# offsets along one axis, so this takes the whole position.
	var slot: Vector3 = d.world.enemy_slot_position(index, maxi(index + 1, Tuning.MAX_ENEMIES))
	var c: Combatant = d._spawn_combatant(stats, slot, -1)
	c.set_home(slot)
	d.enemies.append(c)
	EventBus.combatant_spawned.emit(c)
	_log("spawn -> %s at (%.2f, %.2f)" % [args[0], slot.x, slot.z])

func _cmd_sethp(args: Array) -> void:
	if args.size() < 2:
		_log("sethp -> needs <combatant_id> <hp> [<max>]")
		return
	var c := _find(String(args[0]))
	if c == null:
		_log("sethp -> no combatant '%s'" % args[0])
		return
	if args.size() >= 3:
		c.max_hp = maxi(1, int(String(args[2])))
	c.current_hp = clampi(int(String(args[1])), 0, c.max_hp)
	_log("sethp -> %s %d/%d" % [args[0], c.current_hp, c.max_hp])

func _cmd_damage(args: Array) -> void:
	if args.size() < 2:
		_log("damage -> needs <combatant_id> <amount>")
		return
	var c := _find(String(args[0]))
	if c == null:
		_log("damage -> no combatant '%s'" % args[0])
		return
	# No variance roll: take_damage takes an already-rolled number, so the exact
	# amount lands and the chunk arithmetic of spec 11.2 can be checked on screen.
	var amount := int(String(args[1]))
	c.take_damage(amount, null)
	_log("damage -> %s took %d, now %d/%d" % [args[0], amount, c.current_hp, c.max_hp])

func _cmd_kill(args: Array) -> void:
	if args.is_empty():
		_log("kill -> needs <combatant_id>")
		return
	var c := _find(String(args[0]))
	if c == null:
		_log("kill -> no combatant '%s'" % args[0])
		return
	c.current_hp = 0
	c.die()
	_log("kill -> %s dead" % args[0])

func _cmd_slot(args: Array) -> void:
	if args.size() < 3:
		_log("slot -> needs <s0> <s1> <s2>")
		return
	slot_override = [
		clampi(int(String(args[0])), 0, 3),
		clampi(int(String(args[1])), 0, 3),
		clampi(int(String(args[2])), 0, 3),
	]
	_log("slot -> next payline forced to %s" % str(slot_override))

## Consumed by SlotMachine at the top of a spin; the override is one-shot.
func take_slot_override() -> Array[int]:
	var out := slot_override
	slot_override = []
	return out

func _cmd_shop(args: Array) -> void:
	if args.size() < 3:
		_log("shop -> needs <p0> <p1> <p2>")
		return
	shop_price_override = [
		int(String(args[0])), int(String(args[1])), int(String(args[2])),
	]
	_log("shop -> next shop prices forced to %s" % str(shop_price_override))

## Rewrites each item's intrinsic value so buy_price() lands on the forced price.
func apply_shop_override(items: Array) -> void:
	if shop_price_override.is_empty():
		return
	for i: int in range(mini(items.size(), shop_price_override.size())):
		var item: Item = items[i]
		item.value = _value_for_price(shop_price_override[i])
	_log("shop -> applied %s" % str(shop_price_override))
	shop_price_override = []

## buy_price() rounds, so price / markup does not always round-trip: 250 / 1.5
## lands on 167, and 167 x 1.5 rounds back to 251. Nudge by one either way so the
## gate's exact numbers (spec 15.2's 200 / 250 / 300) come out exact.
func _value_for_price(price: int) -> int:
	var base := int(round(float(price) / Tuning.SHOP_BUY_MARKUP))
	for candidate: int in [base, base - 1, base + 1]:
		if int(round(float(candidate) * Tuning.SHOP_BUY_MARKUP)) == price:
			return maxi(1, candidate)
	return maxi(1, base)

func _cmd_gold(args: Array) -> void:
	if args.is_empty():
		_log("gold -> needs <n>")
		return
	var n := maxi(0, int(String(args[0])))
	var delta := n - GameState.gold
	GameState.gold = n
	EventBus.gold_changed.emit(GameState.gold, delta)
	_log("gold -> %d" % GameState.gold)

func _cmd_upgrade(args: Array) -> void:
	if args.size() < 2:
		_log("upgrade -> needs <id> <level>")
		return
	var id := StringName(String(args[0]))
	if not Upgrades.DEFS.has(id):
		_log("upgrade -> unknown id '%s'" % args[0])
		return
	var level := clampi(int(String(args[1])), 0, Tuning.UPGRADE_MAX_LEVEL)
	Upgrades.levels[id] = level
	EventBus.upgrade_purchased.emit(id, level)
	_log("upgrade -> %s at level %d" % [args[0], level])

func _cmd_additem(args: Array) -> void:
	var item: Item
	if args.is_empty():
		item = Itemizer.generate_item()
	elif args.size() >= 2:
		# additem <rarity> <class> forces a specific class's drop, e.g.
		# "additem magic ranger" -> Itemizer.generate_drop(&"ranger", 2).
		item = Itemizer.generate_drop(StringName(String(args[1])), _parse_rarity(String(args[0])))
	else:
		item = Itemizer.generate_item_with_rarity(_parse_rarity(String(args[0])))
	GameState.add_item(item)
	_log("additem -> %s (%s), value %d" % [item.display_name, item.subtitle(), item.value])

func _cmd_drops(args: Array) -> void:
	if not args.is_empty() and String(args[0]) == "clear":
		GameState.drops_by_class.clear()
		_log("drops -> cleared")
		return
	var bits: PackedStringArray = []
	for c: StringName in Itemizer.droppable_classes():
		bits.append("%s %d" % [String(c), GameState.drop_count(c)])
	var d = _director()
	_log("drops -> %s | banked %d | next %s" % [
		", ".join(bits),
		d.pending_drops.size() if d != null else 0,
		String(GameState.next_drop_class())])

func _parse_rarity(token: String) -> int:
	match token.to_lower():
		"common": return Item.Rarity.COMMON
		"uncommon": return Item.Rarity.UNCOMMON
		"magic": return Item.Rarity.MAGIC
		"rare": return Item.Rarity.RARE
		_: return clampi(int(token), 0, 3)

func _cmd_equip(args: Array) -> void:
	if args.is_empty():
		_log("equip -> needs <index> [class]")
		return
	var index := int(String(args[0]))
	if index < 0 or index >= GameState.inventory.size():
		_log("equip -> index %d out of range" % index)
		return
	var item: Item = GameState.inventory[index]
	var hero_class: StringName
	if args.size() >= 2:
		hero_class = StringName(String(args[1]))
	else:
		var classes := item.usable_by()
		if classes.is_empty():
			_log("equip -> '%s' has no eligible class" % item.display_name)
			return
		hero_class = classes[0]
	GameState.equip_item(item, hero_class)
	_log("equip -> '%s' equipped by %s" % [item.display_name, hero_class])

## [v3] Advances every parallax layer by <units> world units at its own speed
## multiplier, wrapping normally, without touching scroll_speed or the run
## state. Exists because a tile boundary on layer 1 sits far enough off-screen
## (spec 5.8's 36-unit width) that reaching it by travel alone takes longer
## than the whole demo - this is what actually drives the M7.5 seam gate
## (spec 19.2, 7.5.4).
func _cmd_parallax(args: Array) -> void:
	if args.is_empty():
		_log("parallax -> needs <units>")
		return
	var d = _director()   # BattleDirector (untyped: custom API)
	if d == null or d.world == null:
		_log("parallax -> no battle world")
		return
	var units := float(String(args[0]))
	d.world.parallax.advance_tiles(units)
	_log("parallax -> advanced %.2f units" % units)

## [v4.5 / R12 / spec 9.0.2] Logs a bone's rest, pose and global-pose
## transforms. No MCP tool exposes Skeleton3D.get_bone_rest/get_bone_pose and
## this build has no execute_game_script, so this is the only way to verify
## the rest-composing fix - and the "pose == rest with every delta zeroed"
## check is the two-minute assertion that would have caught the M8b blocker
## on day one. Permanent, not throwaway: needed again for every rigged
## character in M8b and M8c.
## Forces a lightning strike (spec 7.6). The storm fires on a 4.5-11 s timer,
## which is longer than anyone wants to wait to see whether a bolt still draws.
func _cmd_lightning() -> void:
	var node := get_tree().get_first_node_in_group("storm_lightning")
	if node == null or not node.has_method("strike_now"):
		_log("lightning -> no storm in this scene")
		return
	node.call("strike_now")
	_log("lightning -> struck")

func _cmd_bone(args: Array) -> void:
	if args.size() < 2:
		_log("bone -> needs <combatant_id> <BoneName>")
		return
	var c := _find(String(args[0]))
	if c == null:
		_log("bone -> no combatant '%s'" % args[0])
		return
	var skel := _find_skeleton(c)
	if skel == null:
		_log("bone -> %s has no Skeleton3D" % args[0])
		return
	var bone_name := String(args[1])
	var idx := skel.find_bone(bone_name)
	if idx < 0:
		_log("bone -> %s has no bone '%s'" % [args[0], bone_name])
		return
	var rest := skel.get_bone_rest(idx)
	var pose := skel.get_bone_pose(idx)
	var global_pose := skel.get_bone_global_pose(idx)
	_log("bone -> %s %s rest=%s pose=%s global=%s" % [
		args[0], bone_name, rest, pose, global_pose,
	])

## Depth-first search for the first Skeleton3D under a combatant's rig - the
## imported model's skeleton sits at Visual/Rig/Model/<RigName>/Skeleton3D,
## and the exact <RigName> varies per character, so this is name-agnostic.
func _find_skeleton(c: Combatant) -> Skeleton3D:
	return _find_skeleton_under(c.rig)

func _find_skeleton_under(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found := _find_skeleton_under(child)
		if found != null:
			return found
	return null

func _cmd_state() -> void:
	var d = _director()   # BattleDirector (untyped: custom API)
	var controller := get_tree().root.find_child("RunController", true, false)
	var run_state: String = str(controller.get("state")) if controller != null else "?"
	var hp_bits: Array[String] = []
	if d != null:
		var pool: Array[Combatant] = []
		pool.append_array(d.heroes)
		pool.append_array(d.enemies)
		for c: Combatant in pool:
			if is_instance_valid(c) and c.stats != null:
				hp_bits.append("%s %d/%d%s" % [c.stats.id, c.current_hp, c.max_hp,
					"" if c.is_alive() else " DEAD"])
	var levels: Array[String] = []
	for id: StringName in Upgrades.DEFS.keys():
		levels.append("%s=%d" % [id, Upgrades.level(id)])
	var drop_bits: Array[String] = []
	for c: StringName in Itemizer.droppable_classes():
		drop_bits.append("%s=%d" % [c, GameState.drop_count(c)])
	var equip_bits: Array[String] = []
	for c: StringName in Itemizer.droppable_classes():
		var equipped := GameState.equipped_item(c)
		equip_bits.append("%s=%s" % [c, equipped.display_name if equipped != null else "none"])
	_log("state -> run=%s encounter=%d gold=%d | %s | upgrades %s | drops %s | equipped %s | bonuses %s" % [
		run_state, GameState.current_encounter_index, GameState.gold,
		", ".join(hp_bits), ", ".join(levels), ", ".join(drop_bits), ", ".join(equip_bits),
		str(GameState.party_bonuses()),
	])
