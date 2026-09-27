extends Control
## [rune floor demo] One combat encounter at a time, forever, in the Rune Floor
## style (design canvas concept A): a high tactical camera over a floating
## island, the slot board carved into the ground between the party and the
## enemies, and a dock of hero plates under the thumb - each hero's health,
## charge and special button in one (HeroPlate).
##
## No town, no travel, no encounter track. A random fight starts; when it
## resolves, the next one starts. A victory keeps the party's HP and meters
## (heroes carry their wounds between fights, as on an expedition) and nudges
## the enemy level up every `level_step_every` wins; a wipe heals and revives
## everyone, clears the meters and drops the level back to `enemy_level`.
##
## The combat is the shipped combat: the real BattleDirector, the real
## SlotMachine (kept hidden - RuneFloor mirrors it onto the ground), the real
## overlay. The party is a fresh in-memory profile built here.
##
## [rune floor spike] The town reaches this scene (Place.RUNE_FLOOR), so the
## player's real profile is in memory on the way in. The demo replaces it, so
## SaveGame is suspended for the whole visit - otherwise the app-pause save
## (SaveGame._notification) would write the demo trio over the player's save
## the first time a phone switched apps. Leaving restores the real profile from
## disk, which is current in town because every town mutation saves.

## The trio's level and the rarity/level of the gear rolled for each slot.
@export var hero_level: int = 5
@export var gear_rarity: Item.Rarity = Item.Rarity.MAGIC
## The first fight's enemy level, and how many wins in a row raise it by one.
@export var enemy_level: int = 4
@export var level_step_every: int = 2
## Every Nth fight is a boss (the lead enemy scaled up, as a level's boss is).
## 0 turns bosses off.
@export var boss_every: int = 5
## The pause between a fight resolving and the next one starting.
@export var restart_pause: float = 1.2

@onready var world = $BattleView/BattleViewport/RuneFloorWorld
@onready var slot_machine = $HiddenCabinet/SlotMachine
@onready var plates: HBoxContainer = $Dock/Plates
@onready var fight_label: Label = $TopBar/FightLabel
@onready var record_label: Label = $TopBar/RecordLabel
@onready var banner: Label = $Banner
@onready var back_button: Button = $TopBar/BackButton
@onready var overlay = $BattleOverlay

var director: BattleDirector

var _fight: int = 0
var _streak: int = 0
var _wins: int = 0
var _losses: int = 0
var _hud_was_visible: bool = true

func _ready() -> void:
	# spec 3.1: every routed scene re-asserts its own place.
	SceneRouter.place = SceneRouter.Place.RUNE_FLOOR
	# Before anything touches GameState - see the header.
	SaveGame.suspended = true
	back_button.pressed.connect(SceneRouter.go.bind(SceneRouter.Place.TOWN))

	# The Hud autoload's town/quest buttons and currency plate belong to the
	# real game; the demo has its own top bar.
	_hud_was_visible = Hud.visible
	Hud.visible = false

	_build_party()
	BattleVfx.warm_up(world)

	director = BattleDirector.new()
	director.name = "BattleDirector"
	director.world = world
	add_child(director)

	slot_machine.apply_height(600.0)
	slot_machine.director = director
	for plate: HeroPlate in plates.get_children():
		plate.director = director
	(world.get_node("RuneFloor") as RuneFloor).bind(slot_machine, director)

	EventBus.combat_ended.connect(_on_combat_ended)
	banner.modulate.a = 0.0
	director.spawn_party()
	_next_fight()

func _exit_tree() -> void:
	Hud.visible = _hud_was_visible
	# Put the player's profile back. A direct launch (F6) with no save on disk
	# just keeps the demo party in memory, which is harmless: nothing persisted.
	SaveGame.suspended = false
	if SaveGame.load_profile():
		GameState.special_charges.clear()
		GameState.quest = null
		EventBus.gold_changed.emit(GameState.gold, 0)
		EventBus.scrap_changed.emit(GameState.scrap, 0)

## A full trio at `hero_level`, each wearing a weapon, an armor and a trinket of
## `gear_rarity`, so the bag has something from everyone in it. In memory only.
func _build_party() -> void:
	GameState.new_profile()
	GameState.inventory.clear()
	GameState.active_party = [&"warrior", &"ranger", &"mage"]
	for id: StringName in GameState.active_party:
		GameState.hero_levels[id] = hero_level
		var classes: Array[StringName] = [id]
		for slot: Item.Slot in [Item.Slot.WEAPON, Item.Slot.ARMOR, Item.Slot.TRINKET]:
			var types := Itemizer.types_for_slot(slot, classes)
			if types.is_empty():
				continue
			var item := Itemizer.generate_typed_item(RNG.pick(types), int(gear_rarity), hero_level)
			item.equipped_by = id
			GameState.inventory.append(item)
	GameState.start_expedition()
	GameState.heal_party()

# --- the loop ---------------------------------------------------------------------

func _next_fight() -> void:
	_fight += 1
	@warning_ignore("integer_division")
	var level := enemy_level + _streak / maxi(level_step_every, 1)
	var boss := boss_every > 0 and _fight % boss_every == 0
	director.start_combat(_roll_enemies(boss), boss, 1, level)
	fight_label.text = "Fight %d  ·  %s level %d" % [_fight, "BOSS" if boss else "foes", level]
	record_label.text = "%d won  ·  %d lost  ·  streak %d" % [_wins, _losses, _streak]

## Two or three from the Endless Wood's early and mid pools; a boss fight leads
## with one from its boss pool (slot 0 is the one start_combat() scales up).
func _roll_enemies(boss: bool) -> Array[StringName]:
	var area: AreaDef = GameState.ENDLESS_WOOD_AREA
	var pool: Array[StringName] = area.pool.resolve()
	if area.mid_pool != null:
		pool.append_array(area.mid_pool.resolve())
	var out: Array[StringName] = []
	if boss and area.boss_pool != null:
		out.append(RNG.pick(area.boss_pool.resolve()))
		out.append(RNG.pick(pool))
		return out
	for i: int in range(RNG.randi_range(2, 3)):
		out.append(RNG.pick(pool))
	return out

func _on_combat_ended(victory: bool) -> void:
	if victory:
		_wins += 1
		_streak += 1
	else:
		_losses += 1
		_streak = 0
	print("[rune floor] fight %d %s" % [_fight, "won" if victory else "lost"])
	_show_banner("Cleared" if victory else "The party falls", victory)
	director.begin_corpse_cleanup()
	await director.await_corpse_cleanup()
	await get_tree().create_timer(restart_pause).timeout
	if not is_inside_tree():
		return
	if not victory:
		# A wipe resets the run: everyone up at full HP, no banked charge. The
		# enemies that won leave without dying, so nothing frees their health
		# bars - the overlay is cleared by hand, as RunController does on a wipe.
		director.clear_enemies()
		overlay.clear_all()
		GameState.special_charges.clear()
		GameState.heal_party()
		director.spawn_party()
	_next_fight()

func _show_banner(text: String, victory: bool) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", Tuning.C_GOLD_BRIGHT if victory else Tuning.C_DANGER)
	banner.scale = Vector2.ONE * 0.8
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(banner, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.2)
	tw.tween_property(banner, "modulate:a", 0.0, 0.35)
