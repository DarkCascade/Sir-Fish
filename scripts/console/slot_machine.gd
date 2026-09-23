extends Control
## The management console's heart: a three-reel cabinet that spins continuously
## during combat. [slot phase 2] It is a *Luck be a Landlord* board now, not a
## Vegas match-to-win slot: a BAG of icons built from the party's gear and living
## heroes, nine drawn without replacement onto the 3x3 board each spin.
##
##   bag = [one icon per living hero]              (innate, §2)
##       + [one icon per equipped item modifier]   (§3)
##       + (BLANK_PAD blanks, bought down by `polish`)
##
## [combat loop redesign] The board is now the party's ONLY source of actions.
## Single-target attack icons are summed across the board and delivered as one
## swing by the front-line hero (Combatant.slot_attack), who plays the real
## attack animation - so three attack icons is one swing for ~3x one icon's
## roll.
##
## [slot vocabulary] The board speaks six categories (SlotIcon.category_of):
## a strike drawn as its owner's weapon, fire, ice, lightning, block, and a
## special charge drawn as its owner's profile on a gold coin. A charge icon
## only fills its owner's special meter - the old on-board bomb arrow,
## thunderburst, cleave and rain effects are gone, and the special is the
## payoff. Bleed and crit are wearer stats, not icons (_swing_for,
## Combatant.take_damage).
##
## The payline is a BONUS: three of the same CATEGORY along any line in
## Tuning.SLOT_PAYLINES makes those cells resolve twice, and keeps the banner,
## the confetti and the cabinet shake. Slot gold is gone entirely (§5).
##
## Upgrades change how OFTEN spins happen (Quick Reels), how MUCH a damage icon
## pays (Overcharge), and how DENSE the board is (Polish). None invents an icon.

const SHAKE_PIXELS := 4.0

var director = null               # BattleDirector (untyped: custom API)

var _reels: Array = []
var _running: bool = false          # a spin cycle coroutine is alive
var _should_spin: bool = false      # combat is active
var _home_position: Vector2

## The icon bag, rebuilt at the top of every spin (and on party changes while in
## attract mode). Entries are SlotIcon dicts; blanks included.
var _bag: Array = []
## The nine icons dealt this spin, row-major: [r0c0, r0c1, r0c2, r1c0, ...].
var _board: Array = []

## [ui-project-longshot] Cabinet layout constants - unchanged by slot phase 2,
## which does no cabinet, layout or texture work.
const CABINET_MARGIN := 12.0
const CABINET_INSET := 24.0
const WINDOW_INSET := 58.0
const WINDOW_MARGIN := 48.0
const PAYLINE_BAND := 60.0

## [slot ui phase 3] A plain Control now: its children (a plum backing and the
## item card's gold-vine nine-patch) are anchored to it, so apply_height()
## sizing the cabinet is all it takes to re-fit the frame.
@onready var cabinet: Control = $Cabinet
@onready var payline: Payline = $Payline
@onready var reel_grid: ReelGrid = $ReelGrid
@onready var result_frame: ResultFrame = $ResultFrame
@onready var banner: Label = $Banner
@onready var confetti: GPUParticles2D = $Confetti
## [black-glass] The three recessed reel windows, tweened by apply_boss_theme()/
## clear_boss_theme() alongside the cabinet face they sit inside.
@onready var _reel_windows: Array[ColorRect] = [$ReelWindow0, $ReelWindow1, $ReelWindow2]
@onready var _vines: NinePatchRect = $ReelGrid/Vines

const BiomeTheme := preload("res://scripts/ui/biome_theme.gd")
const ROOTWOOD_TILE := preload("res://resources/ui/slot_tile_rootwood.tres")
const BOSS_TILE := preload("res://resources/ui/slot_tile_boss.tres")
const BOSS_THEME_TIME := 0.3

func _ready() -> void:
	_home_position = position
	_reels = [$ReelWindow0/Reel, $ReelWindow1/Reel, $ReelWindow2/Reel]
	banner.modulate.a = 0.0
	result_frame.modulate.a = 0.0
	_rebuild_bag()
	_push_attract_strips()
	_enter_attract(true)
	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_ended.connect(_on_combat_ended)
	# Attract-mode reels mirror the current bag, so equipping something out of
	# combat visibly thickens the drifting reel (§4: "make the forge legible").
	EventBus.party_bonuses_changed.connect(_on_party_bonuses_changed)

## Re-lays the cabinet for a band of `h` pixels (spec 17.4). The window always
## shows exactly three cells; everything else is measured from the centre.
func apply_height(h: float) -> void:
	custom_minimum_size = Vector2(1080, h)
	size = Vector2(1080, h)
	pivot_offset = size * 0.5
	var mid := h * 0.5
	var window_h := maxf(h - WINDOW_MARGIN * 2.0, 90.0)
	var window_w := 1080.0 - WINDOW_INSET * 2.0

	cabinet.position = Vector2(CABINET_INSET, CABINET_MARGIN)
	cabinet.size = Vector2(1080.0 - CABINET_INSET * 2.0, h - CABINET_MARGIN * 2.0)

	for i: int in range(_reels.size()):
		var window := (_reels[i] as Control).get_parent() as Control
		var x0 := WINDOW_INSET + window_w * float(i) / 3.0
		var x1 := WINDOW_INSET + window_w * float(i + 1) / 3.0
		window.position = Vector2(x0, WINDOW_MARGIN)
		window.size = Vector2(x1 - x0, window_h)
		var reel = _reels[i]
		reel.size = window.size
		reel.set_cell_height(window_h / 3.0)

	reel_grid.position = Vector2(WINDOW_INSET, WINDOW_MARGIN)
	reel_grid.size = Vector2(window_w, window_h)

	payline.position = Vector2(WINDOW_INSET, mid - PAYLINE_BAND * 0.5)
	payline.size = Vector2(window_w, PAYLINE_BAND)
	var row_h := window_h / 3.0
	result_frame.position = Vector2(WINDOW_INSET, mid - row_h * 0.5)
	result_frame.size = Vector2(window_w, row_h)
	banner.size = Vector2(1080, h)
	scale = Vector2.ONE * Tuning.SLOT_CABINET_SCALE
	_home_position = position

# --- black-glass boss theme --------------------------------------------------

## Called by Console.apply_boss_theme(), itself called from boss_nameplate.gd's
## `impact` signal the instant a boss encounter's name lands (RunController).
func apply_boss_theme() -> void:
	_tween_cabinet_colors(Tuning.C_OBSIDIAN, Tuning.C_OBSIDIAN_DEEP)
	_vines.texture = BiomeTheme.card_frame(BiomeTheme.for_boss())
	reel_grid.boss_active = true
	result_frame.boss_active = true
	for reel: Variant in _reels:
		reel.set_boss_active(true)
		reel.set_tile_style(BOSS_TILE)

## Called by Console.clear_boss_theme() from RunController._on_combat_ended() -
## "all enemies dead" (or a wipe), never later, so the console cannot get
## stuck black-glass for the rest of the expedition.
func clear_boss_theme() -> void:
	_tween_cabinet_colors(Tuning.C_ROOTWOOD, Tuning.C_CANOPY_WELL)
	_vines.texture = BiomeTheme.card_frame()
	reel_grid.boss_active = false
	result_frame.boss_active = false
	for reel: Variant in _reels:
		reel.set_boss_active(false)
		reel.set_tile_style(ROOTWOOD_TILE)

## The cabinet's own StyleBoxFlat is duplicated once (if not already) so this
## can mutate bg_color in place - the live-stylebox trick biome_theme.gd's
## apply_panel_backdrop() already uses for the same reason.
func _tween_cabinet_colors(face: Color, window: Color) -> void:
	var panel := cabinet as Panel
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
	panel.add_theme_stylebox_override("panel", style)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(c: Color) -> void:
		style.bg_color = c
		panel.queue_redraw(), style.bg_color, face, BOSS_THEME_TIME)
	for rect: ColorRect in _reel_windows:
		tw.tween_property(rect, "color", window, BOSS_THEME_TIME)

# --- attract mode (spec 16.6 / Q17) -----------------------------------------

func _on_combat_started(_heroes: Array, _enemies: Array) -> void:
	_should_spin = true
	_leave_attract()
	if not _running:
		_spin_loop()

func _on_combat_ended(_victory: bool) -> void:
	_should_spin = false

func _on_party_bonuses_changed(_bonuses: Dictionary) -> void:
	_rebuild_bag()
	if not _should_spin:
		_push_attract_strips()

## The reels never stop moving out of combat - they just stop mattering (pillar
## 2: dead air is a bug).
func _enter_attract(instant: bool = false) -> void:
	for reel: Variant in _reels:
		reel.start_drift()
	if instant:
		modulate = Tuning.SLOT_ATTRACT_DIM
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate", Tuning.SLOT_ATTRACT_DIM, 0.4)

func _leave_attract() -> void:
	for reel: Variant in _reels:
		reel.stop_drift()
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.2)

## Feeds every reel a filler strip drawn from the current bag, so a drifting
## attract-mode reel shows the party's actual icons rather than blanks.
func _push_attract_strips() -> void:
	for reel: Variant in _reels:
		reel.set_filler_strip(_bag)

## Called by the retry path (spec 18.3) to put the cabinet back to attract mode.
func reset_to_attract() -> void:
	_should_spin = false
	_enter_attract(true)
	_rebuild_bag()
	_push_attract_strips()

# --- the bag (§2) ---------------------------------------------------------

func _rebuild_bag() -> void:
	_bag.clear()
	var living := _living_hero_classes()
	for hero_class: StringName in living:
		_bag.append(SlotIcon.innate(hero_class, GameState.hero_weapon_power(hero_class)))
	for item: Item in GameState.inventory:
		# [content phase 1 §1.5] A dead hero's gear stops putting icons in the
		# bag on the very next rebuild, same as its innate icon already does
		# (_living_hero_classes() above) - harmless while only one class ever
		# executed anything, a real gap now that Executor gives icons owners.
		if item.equipped_by == &"" or item.equipped_by not in living:
			continue
		# [levels] Every equipped item contributes its slot's base icon
		# regardless of rarity or modifier count (spec §4.3) - the fix for a
		# Common putting zero icons in the bag. Added before the modifier loop
		# so a Common's one icon and a fully-modded item's base+N icons both
		# read as "this item is in the bag" first.
		# [owner swings] Every icon an item contributes belongs to its wearer, so
		# its damage becomes that hero's own swing rather than the party's pooled
		# one - see SlotIcon.innate()'s `owner` note.
		var base_icon := SlotIcon.from_item_base(item)
		base_icon["owner"] = item.equipped_by
		_bag.append(base_icon)
		for mod: Dictionary in item.modifiers:
			var icon := SlotIcon.from_modifier(mod, item)
			if icon.is_empty():
				continue
			icon["owner"] = item.equipped_by
			_bag.append(icon)
	# Never empty of icons (§2): if a wiped party somehow leaves nothing, drop in
	# a single damage icon so the board can still do something.
	if _icon_count() == 0:
		_bag.append(SlotIcon.innate(&"warrior", GameState.hero_weapon_power(&"warrior")))
	for _i: int in range(_blank_pad()):
		_bag.append(SlotIcon.blank())

## The living heroes' classes - from the director mid-combat (so a hero dying
## stops contributing its innate icon on the very next spin), from the profile
## roster otherwise.
func _living_hero_classes() -> Array[StringName]:
	var out: Array[StringName] = []
	if director != null and _should_spin:
		for h: Variant in director.living_heroes():
			if h != null and h.stats != null:
				out.append(h.stats.id)
	else:
		for e: Dictionary in GameState.party_status():
			if bool(e.get("alive", false)):
				out.append(e["stats_id"])
	return out

func _icon_count() -> int:
	var n := 0
	for ic: Dictionary in _bag:
		if not SlotIcon.is_blank(ic):
			n += 1
	return n

## SLOT_BLANK_PAD_START, minus what `polish` has bought off, clamped at the floor.
func _blank_pad() -> int:
	return maxi(Tuning.SLOT_BLANK_PAD_START - Upgrades.polish_blanks_removed(),
		Tuning.SLOT_BLANK_PAD_FLOOR)

func _draw_board() -> Array:
	# The Debug harness can force the whole board for one spin (spec 19.2).
	var forced: Array = Debug.take_slot_override()
	if forced.size() == Tuning.SLOT_BOARD_CELLS:
		return forced
	return draw_nine(_bag)

## Nine icons drawn WITHOUT replacement from `bag` (§2). Pads with blanks if the
## bag is somehow shorter than nine. Fisher-Yates over the SEEDED RNG -
## Array.shuffle() would use the global generator and desync the tests. Static so
## test_slot_odds.gd exercises the real draw.
static func draw_nine(bag: Array) -> Array:
	var pool: Array = bag.duplicate()
	while pool.size() < Tuning.SLOT_BOARD_CELLS:
		pool.append(SlotIcon.blank())
	for i: int in range(pool.size() - 1, 0, -1):
		var j := RNG.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, Tuning.SLOT_BOARD_CELLS)

# --- spin cycle (spec 16.3) -------------------------------------------------

func _spin_loop() -> void:
	_running = true
	while _should_spin:
		await _one_spin()
	_running = false
	_enter_attract()

func _one_spin() -> void:
	# Quick Reels compresses the whole cycle (spec 16.3, 17.6).
	var q := Upgrades.quick_reels_mult()

	GameState.run_stats["slot_spins"] = int(GameState.run_stats["slot_spins"]) + 1
	EventBus.slot_spin_started.emit()

	_rebuild_bag()
	_board = _draw_board()
	for c: int in range(3):
		_reels[c].set_column(_board[c], _board[3 + c], _board[6 + c], _bag)
		_reels[c].start_spin()

	await get_tree().create_timer(Tuning.SLOT_SPIN_DURATION * q).timeout
	_stop_reel(0)
	await get_tree().create_timer(Tuning.SLOT_REEL_STAGGER * q).timeout
	_stop_reel(1)
	await get_tree().create_timer(Tuning.SLOT_REEL_STAGGER * q).timeout
	_stop_reel(2)
	await get_tree().create_timer(0.22).timeout

	EventBus.slot_spin_stopped.emit(_board.map(func(ic: Dictionary) -> StringName:
		return StringName(ic.get("id", &""))))

	var wins := _winning_lines()
	if not wins.is_empty():
		_celebrate(wins)
	await _resolve_board(wins)

	await get_tree().create_timer(Tuning.SLOT_RESULT_HOLD * q).timeout

func _stop_reel(index: int) -> void:
	_reels[index].stop_at()
	_shake_cabinet()

func _shake_cabinet() -> void:
	var tw := create_tween()
	tw.tween_property(self, "position",
		_home_position + Vector2(0, SHAKE_PIXELS), 0.05)
	tw.tween_property(self, "position", _home_position, 0.08)

## [slot vocabulary] Every payline that won this board - see winning_lines().
func _winning_lines() -> Array:
	return winning_lines(_board)

## [slot vocabulary] The lines in `lines` (row-major board indices, default
## Tuning.SLOT_PAYLINES) whose three cells all show the same non-blank
## CATEGORY - a sword strike, a bow strike and a staff strike match, as do any
## three charge coins whoever they belong to. Each win is { cells, category }.
## Static so the balance harness (test_slot_jackpots) scores the real rule.
static func winning_lines(board: Array, lines: Array = Tuning.SLOT_PAYLINES) -> Array:
	var wins: Array = []
	for line: Array in lines:
		var category := SlotIcon.category_of(StringName((board[line[0]] as Dictionary).get("id", &"")))
		if category == &"":
			continue
		var all_match := true
		for idx: int in line:
			if SlotIcon.category_of(StringName((board[idx] as Dictionary).get("id", &""))) != category:
				all_match = false
				break
		if all_match:
			wins.append({ "cells": line, "category": category })
	return wins

## [slot vocabulary] The board cells a set of winning lines covers - each
## resolves twice. A cell on two winning lines still resolves only twice.
static func jackpot_cells(wins: Array) -> Dictionary:
	var cells := {}
	for win: Dictionary in wins:
		for idx: int in win["cells"]:
			cells[idx] = true
	return cells

# --- resolution (§3) -----------------------------------------------------------

## Resolves every non-blank cell, independently, left-to-right and top-to-bottom,
## staggered by Tuning.AOE_STAGGER so the board reads as a sequence.
func _resolve_board(wins: Array) -> void:
	# [icons phase 2] dmg_pct is gone - Overcharge is the only remaining lift on
	# damage icons.
	var mult := Upgrades.overcharge_mult()
	var doubled := jackpot_cells(wins)

	var total_damage := 0
	# [combat loop redesign] Single-target attack icons no longer call down
	# their own lightning. Their rolled magnitudes are summed here and dealt as
	# a swing after the rest of the board resolves ("one swing, 3x damage").
	# [owner swings] Summed PER OWNER now, not into one pooled total: each hero
	# swings for the icons their own gear put on the board, so the ranger's and
	# mage's gear animates them instead of feeding a warrior swing. Keyed by
	# hero class, totals in board order. [armor items] BLOCK icons still
	# aggregate into ONE party-wide temp-armor grant - it buffs every hero, so
	# it has no meaningful owner. Bomb arrow / thunderburst still resolve
	# per-cell, in place, staggered. Overcharge touches damage output only,
	# never BLOCK.
	var swings: Dictionary = {}
	var block := 0
	# [run-summary-modal] "X icons hit in Y spins" - live-incremented per icon
	# resolution rather than tallied at the end, so a spin the wipe cuts off
	# mid-resolve still counts whatever it actually resolved before that.
	var any_icon_resolved := false

	# [combat loop redesign fix] Known before anything resolves, so the
	# fallback:false cosmetic gestures below (_should_gesture) can tell whether
	# they are about to collide with a REAL swing this same spin. A DAMAGE icon
	# anywhere on the board guarantees its owner swings once the loop finishes
	# (every contribution is >= 1 + the floor), so this needs no repeats/payline
	# handling of its own - presence is all it has to answer.
	# [owner swings] A LIST now, since several heroes can swing on one board.
	var swinging: Array[Combatant] = []
	for ic: Dictionary in _board:
		if SlotIcon.kind_of(StringName(ic.get("id", &""))) != SlotIcon.Kind.DAMAGE:
			continue
		var owner := _swing_hero_for(ic)
		if owner != null and not swinging.has(owner):
			swinging.append(owner)

	for idx: int in range(_board.size()):
		var ic: Dictionary = _board[idx]
		var id := StringName(ic.get("id", &""))
		var kind: int = SlotIcon.kind_of(id)
		if kind == SlotIcon.Kind.BLANK:
			continue
		# A cell on a winning payline resolves twice (§3).
		var repeats := 2 if doubled.has(idx) else 1
		for _r: int in range(repeats):
			_pulse_cell(idx)
			any_icon_resolved = true
			GameState.run_stats["slot_icons_hit"] = int(GameState.run_stats["slot_icons_hit"]) + 1
			# [specials] Every icon a hero owns charges THAT hero's special. The raw
			# owner, not _swing_hero_for() - its DAMAGE-executor fallback exists so
			# damage is never dropped, and crediting the warrior for an unowned icon
			# would charge his meter off other heroes' gear. A payline triple charges
			# twice, same as it resolves twice. [slot vocabulary] A charge coin adds
			# SLOT_CHARGE_ICON_CHARGE instead of 1 - it is the only thing it does.
			var charge := Tuning.SLOT_CHARGE_ICON_CHARGE if kind == SlotIcon.Kind.CHARGE else 1
			GameState.add_special_charge(StringName(ic.get("owner", &"")), charge)
			if kind == SlotIcon.Kind.DAMAGE:
				# [balance pass] Flat per-icon floor on top of the rolled value.
				# [slot vocabulary] The same figure the tile prints (board_value).
				var contribution := SlotIcon.board_value(ic, mult)
				# [owner swings] Banked against this icon's owner rather than one
				# pooled total. An unowned icon resolves to the DAMAGE executor,
				# so no damage is ever dropped.
				var swinger := _swing_hero_for(ic)
				var key: StringName = swinger.stats.id if swinger != null else &""
				swings[key] = int(swings.get(key, 0)) + contribution
			elif kind == SlotIcon.Kind.BLOCK:
				block += maxi(1, int(ic.get("roll", 0)))
			elif kind == SlotIcon.Kind.CHARGE:
				# [slot vocabulary] The charge itself was added above; this is
				# only the owner's nod, so the player sees whose meter moved.
				var owner_hero := _living_hero(StringName(ic.get("owner", &"")))
				if owner_hero != null and _should_gesture(owner_hero, swinging):
					owner_hero.slot_gesture()
			await get_tree().create_timer(Tuning.AOE_STAGGER).timeout

	if any_icon_resolved:
		GameState.run_stats["slot_spins_resolved"] = int(GameState.run_stats["slot_spins_resolved"]) + 1

	if not swings.is_empty():
		total_damage += await _deliver_swings(swings)
	if block > 0:
		_grant_block(block)

	if total_damage > 0 or block > 0:
		GameState.run_stats["slot_wins"] = int(GameState.run_stats["slot_wins"]) + 1

	# Sir Fish (and anything else) reads this: a jackpot makes him smug, any
	# other paying spin makes him cheer (see sir_fish.gd).
	if not wins.is_empty():
		EventBus.slot_payout.emit("jackpot", total_damage)
	elif total_damage > 0:
		EventBus.slot_payout.emit("damage", total_damage)
	elif block > 0:
		EventBus.slot_payout.emit("block", block)

## [combat loop redesign fix] Whether a fallback:false cosmetic gesture
## (Combatant.slot_gesture()) should actually play, or whether `executor` is
## about to make a REAL swing later in this same _resolve_board() call instead.
##
## Both calls play the identical "attack" clip through the identical
## ATTACKING-state guard (Combatant.slot_attack), so without this check the
## cosmetic gesture fires FIRST (CLEAVE/BLEED/etc. resolve earlier in the board
## than the aggregated swing) and is still mid-clip when the real swing tries to
## start - which then silently no-ops, since slot_attack() never sets `pending`
## if it doesn't run. The player sees an attack animation with no damage number
## and no enemy reaction.
##
## [owner swings] `swinging` is every hero who will swing this board, so this now
## covers any hero who owns both a DAMAGE icon and a CLEAVE/RAIN/BLEED one - not
## just the warrior, who used to be the only hero a real swing could land on.
func _should_gesture(executor: Combatant, swinging: Array[Combatant]) -> bool:
	return not swinging.has(executor)

## [owner swings] The hero who swings for `ic`: its `owner` if that hero is alive
## and on the field, otherwise the DAMAGE executor. The fallback is what keeps a
## rigged test board, a legacy save's icon or a hero who died between the bag
## rebuild and resolution from silently dropping damage.
func _swing_hero_for(ic: Dictionary) -> Combatant:
	if director == null:
		return null
	var owner_hero := _living_hero(StringName(ic.get("owner", &"")))
	return owner_hero if owner_hero != null else _executor_for(SlotIcon.Kind.DAMAGE)

## The living hero of class `hero_class` on the field, or null.
func _living_hero(hero_class: StringName) -> Combatant:
	if director == null or hero_class == &"":
		return null
	for h: Combatant in director.living_heroes():
		if h.stats != null and h.stats.id == hero_class:
			return h
	return null

## [combat loop redesign] The board's summed attack-icon damage, delivered as
## real swings by the heroes who own the icons. One variance roll per hero's
## total, so a board of three attack icons lands as ~3x one icon.
##
## [owner swings] Was ONE swing by whoever executes DAMAGE (always the warrior).
## Now every owner with damage banked this board swings for their own share, in
## roster order, staggered by SLOT_SWING_STAGGER so three heroes read as a volley
## rather than one blob. Every swing lands on the SAME primary target: the total
## damage put on one enemy is therefore unchanged from the pooled version, which
## is what keeps test_level_curves' bands honest - spreading it per hero would
## quietly nerf the party by splitting damage across the group.
##
func _deliver_swings(swings: Dictionary) -> int:
	if director == null:
		return 0
	var primary: Combatant = director.random_living_enemy()
	if primary == null:
		return 0
	# Orphaned damage (an owner who died mid-resolution, or an unowned icon)
	# folds into the DAMAGE executor so none of it is lost.
	var fallback: Combatant = _executor_for(SlotIcon.Kind.DAMAGE)
	var banked: Dictionary = {}
	for key: StringName in swings:
		var hero: Combatant = null
		for h: Combatant in director.living_heroes():
			if h.stats != null and h.stats.id == key:
				hero = h
				break
		if hero == null:
			hero = fallback
		if hero == null:
			continue
		banked[hero] = int(banked.get(hero, 0)) + int(swings[key])

	var total := 0
	for hero: Combatant in director.living_heroes():
		if not banked.has(hero):
			continue
		total += _swing_for(hero, int(banked[hero]), primary)
		await get_tree().create_timer(Tuning.SLOT_SWING_STAGGER).timeout
	# slot_attack lands on the animation's impact beat - hold here so the hits
	# and their numbers resolve inside SLOT_RESULT_HOLD, not over the next spin.
	await get_tree().create_timer(Tuning.SLOT_SWING_SETTLE).timeout
	return total

## One hero's swing for `amount` at `primary`.
##
## [slot vocabulary] Bleed is a weapon stat now: a hero whose weapon carries a
## `bleed` modifier opens (or refreshes) a bleed on the target with
## Tuning.BLEED_PROC_CHANCE per swing. Crit doubles in Combatant.take_damage,
## where it covers every attack the hero makes, not just this one.
func _swing_for(hero: Combatant, amount: int, primary: Combatant) -> int:
	var dealt := maxi(1, int(round(float(amount) * RNG.randf_range(
		1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE))))
	hero.slot_attack(primary, dealt)
	var bleed := GameState.hero_bleed(hero.stats.id)
	if bleed > 0 and RNG.randf() < Tuning.BLEED_PROC_CHANCE:
		primary.apply_bleed(bleed)
	return dealt

## [armor items] The board's summed BLOCK value, granted as temporary flat
## armor to every living hero for Tuning.BLOCK_DURATION (Combatant.add_temp_armor).
func _grant_block(amount: int) -> void:
	if director == null:
		return
	for h: Combatant in director.living_heroes():
		if is_instance_valid(h) and h.is_alive():
			h.add_temp_armor(amount)
			BattleVfx.defend_icon(h, Tuning.BLOCK_DURATION)

## [content phase 1] The executor rule (D1, spec §2.1/§3 Step 2a): the first
## living party member, in roster order, whose class executes `kind`. Falls
## back to the first living hero in roster order when no living class owns it
## and `fallback` is true (the default) - a dead executor, or a party that
## rolled an icon kind nothing it owns can execute (a solo warrior's
## icon kind, per §2a) - so a class dying is never a lost turn, matching the
## existing rule that the party's turn is never simply lost (Combatant.
## slot_attack). Replaces _swinging_hero(); with a solo warrior this resolves
## identically to the old "first living hero" rule, since the warrior is both
## the only living hero AND DAMAGE's executor.
##
## `fallback: false` is for a purely cosmetic call (Combatant.slot_gesture(),
## §5 the ranger/mage combat-visibility fix) that must never land on a hero
## who did not actually earn it - the fallback hero already has a REAL action
## this spin often enough (DAMAGE's _hero_swing()) that handing it a second,
## fake one risks eating the real one via slot_gesture()'s own ATTACKING guard.
##
## director.living_heroes() is already roster order: it walks `heroes`, which
## spawn_party() built from GameState.hero_runtime, itself built from
## active_party in PARTY_ORDER's order (GameState._reset_hero_runtime()).
func _executor_for(kind: SlotIcon.Kind, fallback: bool = true) -> Combatant:
	if director == null:
		return null
	var living: Array[Combatant] = director.living_heroes()
	if living.is_empty():
		return null
	for h: Combatant in living:
		var cdef := GameState.get_class_def(h.stats.id)
		if cdef != null and kind in cdef.executes:
			return h
	return living[0] if fallback else null

# --- presentation (spec 16.4) --------------------------------------------------

## A quick scale pop on the scoring cell an icon just resolved from - the
## per-icon feedback §7.1 asks for, so the board reads as a sequence of separate
## events rather than one flash.
func _pulse_cell(board_index: int) -> void:
	@warning_ignore("integer_division")
	var row := board_index / 3
	var col := board_index % 3
	var cell: Variant = _reels[col].scoring_cell(row)
	if cell == null:
		return
	cell.pivot_offset = cell.size * 0.5
	var rest := Vector2.ONE * Tuning.SLOT_CABINET_SCALE
	var tw: Tween = cell.create_tween()
	tw.tween_property(cell, "scale", rest * 1.18, 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cell, "scale", rest, 0.12)

## [slot vocabulary] One payline segment per winning line, in the payline's
## local space: from half a cell beyond the line's first cell centre to half a
## cell beyond its last, so a row spans the window as it always did and a
## diagonal runs corner to corner.
func _win_segments(wins: Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var to_local: Transform2D = payline.get_global_transform().affine_inverse()
	for win: Dictionary in wins:
		var cells: Array = win["cells"]
		var first := _cell_centre(int(cells[0]))
		var last := _cell_centre(int(cells[cells.size() - 1]))
		var reach := (last - first) * 0.25
		out.append(PackedVector2Array([to_local * (first - reach), to_local * (last + reach)]))
	return out

## A scoring cell's centre in canvas space.
func _cell_centre(board_index: int) -> Vector2:
	@warning_ignore("integer_division")
	var cell: Control = _reels[board_index % 3].scoring_cell(board_index / 3)
	return cell.get_global_rect().get_center() if cell != null else Vector2.ZERO

## The jackpot celebration: the winning cells pulse hard, the payline flashes, the
## banner and its frame fade in and out, and (always, since a triple is the only
## trigger now) the confetti falls and the cabinet punches.
func _celebrate(wins: Array) -> void:
	var rest := Vector2.ONE * Tuning.SLOT_CABINET_SCALE
	# [slot vocabulary] Every cell on a winning line pops, whichever lines won.
	for idx: int in jackpot_cells(wins):
		@warning_ignore("integer_division")
		var cell: Variant = _reels[idx % 3].scoring_cell(idx / 3)
		if cell == null:
			continue
		cell.pivot_offset = cell.size * 0.5
		var tw: Tween = cell.create_tween()
		tw.tween_property(cell, "scale", rest * 1.30, 0.175) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(cell, "scale", rest, 0.175)

	# [slot ui phase 3] The payline is not drawn at rest any more (slot_machine.tscn
	# authors it at alpha 0). It appears only for the jackpot, fading in and out
	# with the banner so the line reads as part of the win, not as furniture.
	payline.segments = _win_segments(wins)
	payline.modulate.a = 0.0
	var ptw := create_tween()
	ptw.tween_property(payline, "modulate:a", 1.0, 0.12)
	ptw.tween_interval(1.0)
	ptw.tween_property(payline, "modulate:a", 0.0, 0.25)

	var flash := create_tween().set_loops(2)
	flash.tween_property(payline, "glow_color", Color.WHITE, 0.09)
	flash.tween_property(payline, "glow_color", Tuning.C_GOLD_BRIGHT, 0.09)

	var category: StringName = (wins[0] as Dictionary)["category"]
	banner.text = "%s x3" % SlotIcon.category_label(category) if wins.size() == 1 \
		else "%d lines!" % wins.size()
	banner.modulate.a = 0.0
	var btw := create_tween()
	btw.tween_property(banner, "modulate:a", 1.0, 0.12)
	btw.tween_interval(1.0)
	btw.tween_property(banner, "modulate:a", 0.0, 0.25)

	result_frame.modulate.a = 0.0
	var ftw := create_tween()
	ftw.tween_property(result_frame, "modulate:a", 1.0, 0.12)
	ftw.tween_interval(1.0)
	ftw.tween_property(result_frame, "modulate:a", 0.0, 0.25)

	confetti.restart()
	confetti.emitting = true
	pivot_offset = size * 0.5
	var punch := create_tween()
	punch.tween_property(self, "scale", rest * 1.05, 0.125) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	punch.tween_property(self, "scale", rest, 0.125)
