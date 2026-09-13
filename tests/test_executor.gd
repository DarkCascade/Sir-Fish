extends Node
## Content Phase 1, Step 2a/§1.5: the executor rule (D1) and the dead-hero
## item-icon filter. Builds bare Combatant/BattleDirector instances directly
## (never added to the scene tree, never setup()) since _executor_for() and
## _rebuild_bag() only ever touch `.stats` / `.state` / `.current_hp` - not
## any @onready node a real setup() would need.
##
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_executor.tscn

const TestSupport := preload("res://tests/test_support.gd")
const SlotMachineScript := preload("res://scripts/console/slot_machine.gd")

func _ready() -> void:
	var t := TestSupport.new()
	t.guard_user_file(SaveGame.PATH)

	_check_executor_ownership(t)
	_check_dead_hero_item_filter(t)

	t.finish(get_tree(), "test_executor")

func _make_hero(id: StringName, alive: bool) -> Combatant:
	var c := Combatant.new()
	c.stats = GameState.get_stats(id)
	c.is_hero = true
	c.max_hp = 100
	if alive:
		c.state = Combatant.State.IDLE
		c.current_hp = 100
	else:
		c.state = Combatant.State.DEAD
		c.current_hp = 0
	return c

func _check_executor_ownership(t: TestSupport) -> void:
	var director := BattleDirector.new()
	var machine := SlotMachineScript.new()
	machine.director = director

	# --- a solo warrior: DAMAGE resolves to warrior, exactly as the old
	# "first living hero" rule did (exit criterion: "a solo warrior plays
	# identically"). ---
	var warrior := _make_hero(&"warrior", true)
	director.heroes = [warrior]
	t.check(machine._executor_for(SlotIcon.Kind.DAMAGE) == warrior,
		"solo warrior: DAMAGE resolves to the warrior")

	# --- a full living party: DAMAGE resolves to warrior specifically, not
	# to the first living hero in roster order (mage) - proves ownership, not
	# just presence, decides the executor. ---
	var mage := _make_hero(&"mage", true)
	var ranger := _make_hero(&"ranger", true)
	director.heroes = [mage, ranger, warrior]   # roster order: mage, ranger, warrior
	t.check(machine._executor_for(SlotIcon.Kind.DAMAGE) == warrior,
		"full party: DAMAGE resolves to warrior (the class that owns it), not the roster-first mage")
	t.check(machine._executor_for(SlotIcon.Kind.HEAL) == mage,
		"full party: HEAL resolves to mage")
	t.check(machine._executor_for(SlotIcon.Kind.DAMAGE_ALL) == ranger,
		"full party: DAMAGE_ALL resolves to ranger")

	# --- orphaned icons: with the DAMAGE owner dead, the icon falls back to
	# the first living hero in roster order rather than fizzling (§2a). ---
	var dead_warrior := _make_hero(&"warrior", false)
	director.heroes = [mage, ranger, dead_warrior]
	t.check(machine._executor_for(SlotIcon.Kind.DAMAGE) == mage,
		"orphaned DAMAGE (warrior dead) falls back to the first living hero (mage)")

	# --- no living heroes at all: no executor, no crash. ---
	director.heroes = [dead_warrior]
	t.check(machine._executor_for(SlotIcon.Kind.DAMAGE) == null,
		"no living heroes: _executor_for() returns null rather than crashing")

	mage.free()
	ranger.free()
	warrior.free()
	dead_warrior.free()
	director.free()
	machine.free()

## [content phase 1 §1.5] A dead hero's equipped gear stops contributing icons
## to the bag on the very next rebuild - same rule _living_hero_classes()
## already applied to the innate icon, extended to base/modifier icons now
## that Executor gives icons owners.
func _check_dead_hero_item_filter(t: TestSupport) -> void:
	var saved_inventory := GameState.inventory

	var director := BattleDirector.new()
	var warrior := _make_hero(&"warrior", true)
	var ranger := _make_hero(&"ranger", false)
	director.heroes = [warrior, ranger]

	var warrior_item := Itemizer.generate_typed_item(&"sword", Item.Rarity.COMMON, 1)
	warrior_item.equipped_by = &"warrior"
	var ranger_item := Itemizer.generate_typed_item(&"dagger", Item.Rarity.COMMON, 1)
	ranger_item.equipped_by = &"ranger"
	GameState.inventory = [warrior_item, ranger_item]

	var machine := SlotMachineScript.new()
	machine.director = director
	machine._should_spin = true
	machine._rebuild_bag()

	var bag: Array = machine._bag
	var has_warrior_base := false
	var has_ranger_base := false
	for ic: Dictionary in bag:
		if ic.get("id", &"") == SlotIcon.base_for(warrior_item.slot()) and int(ic.get("roll", -1)) == warrior_item.power():
			has_warrior_base = true
		if ic.get("id", &"") == SlotIcon.base_for(ranger_item.slot()) and int(ic.get("roll", -1)) == ranger_item.power():
			has_ranger_base = true
	t.check(has_warrior_base, "the living warrior's equipped item still contributes its base icon")
	t.check(not has_ranger_base, "the dead ranger's equipped item no longer contributes its base icon")

	GameState.inventory = saved_inventory
	warrior.free()
	ranger.free()
	director.free()
	machine.free()
