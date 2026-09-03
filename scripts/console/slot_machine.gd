extends Control
## The management console's heart: a three-reel cabinet that spins continuously
## during combat. [slot phase 2] It is a *Luck be a Landlord* board now, not a
## Vegas match-to-win slot: a BAG of icons built from the party's gear and living
## heroes, nine drawn without replacement onto the 3x3 board each spin, every
## non-blank icon resolving its own effect independently.
##
##   bag = [one icon per living hero]              (innate, §2)
##       + [one icon per equipped item modifier]   (§3)
##       + (BLANK_PAD blanks, bought down by `polish`)
##
## The payline survives only as a BONUS: three of the same icon on the centre
## row (the old jackpot) makes those three resolve twice, and keeps the banner,
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

@onready var cabinet: OrnateFrame = $Cabinet
@onready var payline: Payline = $Payline
@onready var reel_grid: ReelGrid = $ReelGrid
@onready var result_frame: ResultFrame = $ResultFrame
@onready var banner: Label = $Banner
@onready var confetti: GPUParticles2D = $Confetti

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
	payline.glow_color = Tuning.C_GOLD_DARK   # unlit
	if instant:
		modulate = Tuning.SLOT_ATTRACT_DIM
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate", Tuning.SLOT_ATTRACT_DIM, 0.4)

func _leave_attract() -> void:
	for reel: Variant in _reels:
		reel.stop_drift()
	payline.glow_color = Tuning.C_GOLD_BRIGHT  # lit
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
	for hero_class: StringName in _living_hero_classes():
		_bag.append(SlotIcon.innate(hero_class))
	for item: Item in GameState.inventory:
		if item.equipped_by == &"":
			continue
		for mod: Dictionary in item.modifiers:
			var icon := SlotIcon.from_modifier(mod)
			if not icon.is_empty():
				_bag.append(icon)
	# Never empty of icons (§2): if a wiped party somehow leaves nothing, drop in
	# a single damage icon so the board can still do something.
	if _icon_count() == 0:
		_bag.append(SlotIcon.innate(&"warrior"))
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

	var jackpot_id := _payline_triple()
	if jackpot_id != &"":
		_celebrate(jackpot_id)
	await _resolve_board(jackpot_id)

	await get_tree().create_timer(Tuning.SLOT_RESULT_HOLD * q).timeout

func _stop_reel(index: int) -> void:
	_reels[index].stop_at()
	_shake_cabinet()

func _shake_cabinet() -> void:
	var tw := create_tween()
	tw.tween_property(self, "position",
		_home_position + Vector2(0, SHAKE_PIXELS), 0.05)
	tw.tween_property(self, "position", _home_position, 0.08)

## The centre row's icon id if all three of _cells[2] show the same non-blank
## icon, else &"". This is the whole of what the payline means now (§3).
func _payline_triple() -> StringName:
	var result := evaluate([_board[3], _board[4], _board[5]])
	return StringName(result["id"])

## Kept per §3. `center_row` is the three centre-row icon dicts; returns
## { id, count } naming the majority icon, or { id: &"", count: 0 }.
static func evaluate(center_row: Array) -> Dictionary:
	var counts := {}
	for ic: Dictionary in center_row:
		var id := StringName(ic.get("id", &""))
		if SlotIcon.kind_of(id) == SlotIcon.Kind.BLANK:
			continue
		counts[id] = int(counts.get(id, 0)) + 1
	for id: Variant in counts.keys():
		if int(counts[id]) >= 3:
			return { "id": id, "count": int(counts[id]) }
	return { "id": &"", "count": 0 }

# --- resolution (§3) -----------------------------------------------------------

## Resolves every non-blank cell, independently, left-to-right and top-to-bottom,
## staggered by Tuning.AOE_STAGGER so the board reads as a sequence. Multiplier
## icons (dmg_pct) are summed first and lift every damage icon THIS spin only.
func _resolve_board(jackpot_id: StringName) -> void:
	var pct := 0
	for ic: Dictionary in _board:
		if SlotIcon.kind_of(StringName(ic.get("id", &""))) == SlotIcon.Kind.MULT:
			pct += int(ic.get("roll", 0))
	# dmg_pct stacks additively with Overcharge, which now lifts ALL damage icons.
	var mult := (1.0 + float(pct) / 100.0) * Upgrades.overcharge_mult()

	var total_damage := 0
	var total_heal := 0
	for idx: int in range(_board.size()):
		var ic: Dictionary = _board[idx]
		var kind: int = SlotIcon.kind_of(StringName(ic.get("id", &"")))
		if kind == SlotIcon.Kind.BLANK or kind == SlotIcon.Kind.MULT:
			continue
		# Centre row (indices 3-5) resolves twice on a payline triple (§3).
		var repeats := 2 if (jackpot_id != &"" and idx >= 3 and idx <= 5) else 1
		for _r: int in range(repeats):
			_pulse_cell(idx)
			var out := await _resolve_icon(ic, kind, mult)
			total_damage += out.x
			total_heal += out.y
			await get_tree().create_timer(Tuning.AOE_STAGGER).timeout

	if total_damage > 0 or total_heal > 0:
		GameState.run_stats["slot_wins"] = int(GameState.run_stats["slot_wins"]) + 1

	# Sir Fish (and anything else) reads this: a jackpot makes him smug, any
	# other paying spin makes him cheer (see sir_fish.gd).
	if jackpot_id != &"":
		EventBus.slot_payout.emit("jackpot", total_damage + total_heal)
	elif total_damage >= total_heal and total_damage > 0:
		EventBus.slot_payout.emit("damage", total_damage)
	elif total_heal > 0:
		EventBus.slot_payout.emit("heal", total_heal)

## Resolves one icon. Returns Vector2i(damage_dealt, heal_done).
func _resolve_icon(ic: Dictionary, kind: int, mult: float) -> Vector2i:
	if director == null:
		return Vector2i.ZERO
	var id := StringName(ic.get("id", &""))
	var roll := int(ic.get("roll", 0))
	match kind:
		SlotIcon.Kind.DAMAGE:
			return Vector2i(await _hit_one(id, roll, mult), 0)
		SlotIcon.Kind.DAMAGE_ALL:
			return Vector2i(await _hit_all(id, roll, mult), 0)
		SlotIcon.Kind.HEAL:
			return Vector2i(0, _heal_lowest(roll))
	return Vector2i.ZERO

func _hit_one(id: StringName, roll: int, mult: float) -> int:
	var targets: Array[Combatant] = director.living_enemies()
	if targets.is_empty():
		return 0
	var enemy: Combatant = targets[RNG.randi_range(0, targets.size() - 1)]
	return _strike(enemy, id, roll, mult)

func _hit_all(id: StringName, roll: int, mult: float) -> int:
	var targets: Array[Combatant] = director.living_enemies()
	if targets.is_empty():
		return 0
	targets.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		return a.global_position.x < b.global_position.x)
	var total := 0
	for enemy: Combatant in targets:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		total += _strike(enemy, id, roll, mult)
		await get_tree().create_timer(Tuning.AOE_STAGGER).timeout
	return total

## One damage application, VFX and floating number included. `source` is null on
## purpose: slot damage is never attributed to a hero.
func _strike(enemy: Combatant, id: StringName, roll: int, mult: float) -> int:
	if not is_instance_valid(enemy) or not enemy.is_alive():
		return 0
	var tint := _element_tint(id)
	var overlay: Variant = get_tree().get_first_node_in_group("battle_overlay")
	if overlay != null:
		overlay.number_color_override = tint
	BattleVfx.lightning_bolt(director, enemy, tint)
	var base := maxi(1, int(round(float(roll) * mult)))
	var rolled := maxi(1, int(round(float(base) * RNG.randf_range(
		1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE))))
	enemy.take_damage(rolled, null)
	if overlay != null:
		overlay.number_color_override = null
	return rolled

func _heal_lowest(pct: int) -> int:
	var hero: Combatant = director.lowest_hp_living_hero()
	if hero == null or not is_instance_valid(hero) or not hero.is_alive():
		return 0
	var amount := maxi(1, int(round(float(hero.max_hp) * float(pct) / 100.0)))
	hero.heal(amount)
	BattleVfx.heal_icon(hero, amount)
	return amount

## Elemental icons tint their number; everything else uses the called-down
## strike's electric blue, exactly as slot lightning did before.
func _element_tint(id: StringName) -> Color:
	match SlotIcon.element_of(id):
		&"fire": return Tuning.C_FIRE
		&"ice": return Tuning.C_ICE
		&"light": return Tuning.C_LIGHTNING
	return Tuning.C_LIGHTNING

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

## The jackpot celebration: the centre row pulses hard, the payline flashes, the
## banner and its frame fade in and out, and (always, since a triple is the only
## trigger now) the confetti falls and the cabinet punches.
func _celebrate(jackpot_id: StringName) -> void:
	var rest := Vector2.ONE * Tuning.SLOT_CABINET_SCALE
	for reel: Variant in _reels:
		var cell: Variant = reel.payline_cell()
		cell.pivot_offset = cell.size * 0.5
		var tw: Tween = cell.create_tween()
		tw.tween_property(cell, "scale", rest * 1.30, 0.175) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(cell, "scale", rest, 0.175)

	var flash := create_tween().set_loops(2)
	flash.tween_property(payline, "glow_color", Color.WHITE, 0.09)
	flash.tween_property(payline, "glow_color", Tuning.C_GOLD_BRIGHT, 0.09)

	banner.text = "%s x3" % SlotIcon.short_label(jackpot_id)
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
