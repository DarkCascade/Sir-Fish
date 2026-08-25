extends Control
## The management console's heart: a three-reel cabinet that spins continuously
## during combat and pays out in damage, gold and healing (spec 16).
##
## Upgrades and items change how OFTEN spins happen and how MUCH a win pays.
## Nothing here may touch Tuning.SLOT_STRIP, the win rule, or the 50.038% win
## rate - that figure is proved by exhaustive enumeration and tested over a
## million spins (spec 16.2). "More often" is delivered by Quick Reels
## compressing the cycle, i.e. the same 50% of MORE spins per minute.

const SHAKE_PIXELS := 4.0

var director = null               # BattleDirector (untyped: custom API)

var _reels: Array = []
var _running: bool = false          # a spin cycle coroutine is alive
var _should_spin: bool = false      # combat is active
var _last_hero_hits: Array[int] = []
var _home_position: Vector2

@onready var cabinet: OrnateFrame = $Cabinet
@onready var payline: Payline = $Payline
@onready var reel_grid: ReelGrid = $ReelGrid
@onready var result_frame: ResultFrame = $ResultFrame
@onready var banner: Label = $Banner
@onready var confetti: GPUParticles2D = $Confetti

## [ui-project-longshot] The cabinet was 860 wide inside a 1080 band, floating
## with 110 px of dead console either side. On the concept board it is
## near-full-bleed - the cabinet IS the console at this height - so these are
## measured off the board rather than inherited.
const CABINET_MARGIN := 12.0     # cabinet inset from the band's top and bottom
const CABINET_INSET := 24.0      # and from its left and right
## Where the reel window sits inside the cabinet. Must clear OrnateFrame's own
## `border` on the Cabinet node (34) or the window laps over the carved bevel.
const WINDOW_INSET := 58.0
const WINDOW_MARGIN := 48.0
## The payline's own control is taller than the line it draws, so its glow and
## sparkles have room; the line itself is drawn down its centre.
const PAYLINE_BAND := 60.0

func _ready() -> void:
	_home_position = position
	_reels = [$ReelWindow0/Reel, $ReelWindow1/Reel, $ReelWindow2/Reel]
	banner.modulate.a = 0.0
	result_frame.modulate.a = 0.0
	_enter_attract(true)
	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.hero_damage_dealt.connect(_on_hero_damage_dealt)

## Re-lays the cabinet for a band of `h` pixels, so the console can be given more
## or less room without a second authored slot machine (spec 17.4). The window
## always shows exactly three cells; everything else is measured from the centre.
func apply_height(h: float) -> void:
	custom_minimum_size = Vector2(1080, h)
	size = Vector2(1080, h)
	pivot_offset = size * 0.5
	var mid := h * 0.5
	var window_h := maxf(h - WINDOW_MARGIN * 2.0, 90.0)
	var window_w := 1080.0 - WINDOW_INSET * 2.0

	cabinet.position = Vector2(CABINET_INSET, CABINET_MARGIN)
	cabinet.size = Vector2(1080.0 - CABINET_INSET * 2.0, h - CABINET_MARGIN * 2.0)

	# The three windows now abut rather than floating apart - the cells are
	# separated by ReelGrid's gold cames laid OVER them, not by gaps between
	# them (see reel_grid.gd). Their edges therefore have to land exactly on
	# the same thirds the lattice draws, so the widths are derived here rather
	# than left at whatever the .tscn was authored with.
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
	# Exactly the reel window's middle row - the same span reel_grid.gd used to
	# rule off with its two horizontal dividers (see that file and
	# result_frame.gd) - so the result banner's frame lines up with the row the
	# payline actually reads.
	var row_h := window_h / 3.0
	result_frame.position = Vector2(WINDOW_INSET, mid - row_h * 0.5)
	result_frame.size = Vector2(window_w, row_h)
	banner.size = Vector2(1080, h)
	scale = Vector2.ONE * Tuning.SLOT_CABINET_SCALE
	# The shake tween returns here, and the console moves us before it calls this.
	_home_position = position

# --- attract mode (spec 16.6 / Q17) -----------------------------------------

func _on_combat_started(_heroes: Array, _enemies: Array) -> void:
	_should_spin = true
	_leave_attract()
	if not _running:
		_spin_loop()

func _on_combat_ended(_victory: bool) -> void:
	# The current spin finishes its stop sequence and pays out normally; the loop
	# then exits and the cabinet decays into attract mode.
	_should_spin = false

## The reels never stop moving out of combat - they just stop mattering. v1 dimmed
## the cabinet hard and froze it, which left the single largest element on screen
## dead through all travel, the whole loot encounter and the whole shop encounter,
## i.e. most of the demo's runtime. Dead air is a bug (pillar 2).
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

# --- rolling hero-damage buffer (spec 16.5) --------------------------------

func _on_hero_damage_dealt(amount: int) -> void:
	_last_hero_hits.append(amount)
	while _last_hero_hits.size() > 3:
		_last_hero_hits.pop_front()

func clear_hit_buffer() -> void:
	_last_hero_hits.clear()

func _avg_last_three() -> float:
	if _last_hero_hits.is_empty():
		return float(Tuning.SLOT_LIGHTNING_FALLBACK)   # 12
	var total := 0
	for v: int in _last_hero_hits:
		total += v
	return float(total) / float(_last_hero_hits.size())

## Called by the retry path (spec 18.3) to put the cabinet back to attract mode.
func reset_to_attract() -> void:
	_should_spin = false
	clear_hit_buffer()
	_enter_attract(true)

# --- spin cycle (spec 16.3) -------------------------------------------------

func _spin_loop() -> void:
	_running = true
	while _should_spin:
		await _one_spin()
	_running = false
	_enter_attract()

func _one_spin() -> void:
	# Quick Reels compresses the whole cycle: 1.00 / 0.86 / 0.74 / 0.64, so the
	# base 2.51 s becomes 1.60 s at level 3 (spec 16.3, 17.6).
	var q := Upgrades.quick_reels_mult()

	GameState.run_stats["slot_spins"] = int(GameState.run_stats["slot_spins"]) + 1
	EventBus.slot_spin_started.emit()
	for reel: Variant in _reels:
		reel.start_spin()

	var targets := _roll_targets()

	await get_tree().create_timer(Tuning.SLOT_SPIN_DURATION * q).timeout
	_stop_reel(0, targets[0])
	await get_tree().create_timer(Tuning.SLOT_REEL_STAGGER * q).timeout
	_stop_reel(1, targets[1])
	await get_tree().create_timer(Tuning.SLOT_REEL_STAGGER * q).timeout
	_stop_reel(2, targets[2])
	await get_tree().create_timer(0.22).timeout

	var symbols: Array[int] = []
	for reel: Variant in _reels:
		symbols.append(reel.payline_symbol())
	EventBus.slot_spin_stopped.emit(symbols)

	var result := evaluate(symbols)
	if int(result["count"]) >= 2:
		GameState.run_stats["slot_wins"] = int(GameState.run_stats["slot_wins"]) + 1
		_celebrate(int(result["symbol"]), int(result["count"]))
		_pay_out(int(result["symbol"]), int(result["count"]))

	await get_tree().create_timer(Tuning.SLOT_RESULT_HOLD * q).timeout

## Uniformly random stop indices, unless the Debug harness has forced a payline
## for this spin (spec 19.2). The override never touches the strip or the odds -
## it only picks which stops this one spin lands on.
func _roll_targets() -> Array[int]:
	var forced := Debug.take_slot_override()
	var targets: Array[int] = []
	for i: int in range(3):
		if forced.size() == 3:
			targets.append(_stop_index_for(forced[i]))
		else:
			targets.append(RNG.randi_range(0, Tuning.SLOT_REEL_STOPS - 1))
	return targets

func _stop_index_for(symbol: int) -> int:
	var candidates: Array[int] = []
	for i: int in range(Tuning.SLOT_REEL_STOPS):
		if Tuning.SLOT_STRIP[i] == symbol:
			candidates.append(i)
	if candidates.is_empty():
		return 0
	return candidates[RNG.randi_range(0, candidates.size() - 1)]

func _stop_reel(index: int, target: int) -> void:
	_reels[index].stop_at(target)
	_shake_cabinet()

func _shake_cabinet() -> void:
	var tw := create_tween()
	tw.tween_property(self, "position",
		_home_position + Vector2(0, SHAKE_PIXELS), 0.05)
	tw.tween_property(self, "position", _home_position, 0.08)

## A win is 2 or 3 of the same non-blank symbol on the payline, counting any two
## of the three positions (spec 16.2 / 21-D4).
static func evaluate(symbols: Array) -> Dictionary:
	var counts := {}
	for s: int in symbols:
		if s == Tuning.Sym.BLANK:
			continue
		counts[s] = int(counts.get(s, 0)) + 1
	for s: Variant in counts.keys():
		if int(counts[s]) >= 2:
			return { "symbol": int(s), "count": int(counts[s]) }
	return { "symbol": -1, "count": 0 }

# --- win presentation (spec 16.4) ------------------------------------------

func _celebrate(symbol: int, count: int) -> void:
	for reel: Variant in _reels:
		if reel.payline_symbol() != symbol:
			continue
		var cell: Variant = reel.payline_cell()
		cell.pivot_offset = cell.size * 0.5
		# Rest pose is Tuning.SLOT_CABINET_SCALE, not Vector2.ONE - every cell
		# is scaled down permanently now (see slot_reel.gd's _resize_cells()),
		# and tweening back to ONE here would snap just THIS cell back to full
		# size the first time its symbol wins, leaving it visibly bigger than
		# its neighbours for good.
		var cell_rest := Vector2.ONE * Tuning.SLOT_CABINET_SCALE
		var tw: Tween = cell.create_tween()
		tw.tween_property(cell, "scale", cell_rest * 1.30, 0.175) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(cell, "scale", cell_rest, 0.175)

	var flash := create_tween().set_loops(2)
	flash.tween_property(payline, "glow_color", Color.WHITE, 0.09)
	flash.tween_property(payline, "glow_color", Tuning.C_GOLD_BRIGHT, 0.09)

	banner.text = SlotSymbol.result_text(symbol, count)
	banner.modulate.a = 0.0
	var btw := create_tween()
	btw.tween_property(banner, "modulate:a", 1.0, 0.12)
	btw.tween_interval(1.0)
	btw.tween_property(banner, "modulate:a", 0.0, 0.25)

	# The frame and its blackout fade in lockstep with the banner text it
	# surrounds - two independent tweens rather than one shared tween because
	# the frame has no text to swap in, just an alpha to match.
	result_frame.modulate.a = 0.0
	var ftw := create_tween()
	ftw.tween_property(result_frame, "modulate:a", 1.0, 0.12)
	ftw.tween_interval(1.0)
	ftw.tween_property(result_frame, "modulate:a", 0.0, 0.25)

	if count >= 3:
		confetti.restart()
		confetti.emitting = true
		pivot_offset = size * 0.5
		# Rest pose is Tuning.SLOT_CABINET_SCALE, not Vector2.ONE - the cabinet
		# is scaled down permanently now (see that constant), and tweening
		# back to ONE here would undo the shrink for good the first time this
		# fires.
		var rest := Vector2.ONE * Tuning.SLOT_CABINET_SCALE
		var punch := create_tween()
		punch.tween_property(self, "scale", rest * 1.05, 0.125) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		punch.tween_property(self, "scale", rest, 0.125)

# --- payouts (spec 16.5) ----------------------------------------------------

func _pay_out(symbol: int, count: int) -> void:
	match symbol:
		Tuning.Sym.LIGHTNING:
			EventBus.slot_payout.emit("lightning", count)
			_pay_lightning(count)
		Tuning.Sym.GOLD:
			EventBus.slot_payout.emit("gold", count)
			_pay_gold(count)
		Tuning.Sym.PLUS:
			EventBus.slot_payout.emit("heal", count)
			_pay_heal(count)

func _pay_lightning(count: int) -> void:
	if director == null:
		return
	var mult := Tuning.SLOT_LIGHTNING_3_MULT if count >= 3 else Tuning.SLOT_LIGHTNING_2_MULT
	var b := GameState.party_bonuses()
	# round(avg x mult x overcharge) + slot_bolt (spec 16.5, 13.5, 17.6).
	var base := int(round(_avg_last_three() * mult * Upgrades.overcharge_mult())) \
		+ int(b["slot_bolt"])
	var targets: Array[Combatant] = director.living_enemies()
	if targets.is_empty():
		return              # skip silently; the celebration already played
	# Left to right by world X, AOE_STAGGER apart (spec 9.7).
	targets.sort_custom(func(a: Combatant, x: Combatant) -> bool:
		return a.global_position.x < x.global_position.x)
	var overlay: Variant = get_tree().get_first_node_in_group("battle_overlay")
	if overlay != null:
		overlay.number_color_override = Tuning.C_LIGHTNING
	for enemy: Combatant in targets:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		# The mage's bolt builder, reused - but WITHOUT the darkening pass. The
		# slot fires far too often to darken the screen for (spec 16.5).
		BattleVfx.lightning_bolt(director, enemy, Tuning.C_LIGHTNING)
		var rolled := maxi(1, int(round(float(base) * RNG.randf_range(
			1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE))))
		# `source` is null on purpose: slot damage is not attributed to a hero and
		# must never feed _last_hero_hits. A loop where slot damage inflates the
		# average that drives future slot damage would run away (spec 21-D6).
		enemy.take_damage(rolled, null)
		await get_tree().create_timer(Tuning.AOE_STAGGER).timeout
	if overlay != null:
		overlay.number_color_override = null

func _pay_gold(count: int) -> void:
	var b := GameState.party_bonuses()
	var base := Tuning.SLOT_PAY_3_GOLD if count >= 3 else Tuning.SLOT_PAY_2_GOLD
	# round(base x fat_purse) + slot_purse (spec 16.5).
	GameState.add_gold(int(round(float(base) * Upgrades.fat_purse_mult()))
		+ int(b["slot_purse"]))

func _pay_heal(count: int) -> void:
	if director == null:
		return
	var b := GameState.party_bonuses()
	var base_fraction := Tuning.SLOT_HEAL_3_FRACTION if count >= 3 \
		else Tuning.SLOT_HEAL_2_FRACTION
	var fraction := clampf(base_fraction + float(b["slot_mend"]) / 100.0, 0.0, 1.0)
	if count >= 3:
		var party: Array[Combatant] = director.living_heroes()
		party.sort_custom(func(a: Combatant, x: Combatant) -> bool:
			return a.global_position.x < x.global_position.x)
		for hero: Combatant in party:
			_heal_hero(hero, fraction)
			await get_tree().create_timer(Tuning.AOE_STAGGER).timeout
	else:
		var hero: Combatant = director.lowest_hp_living_hero()
		if hero != null:
			_heal_hero(hero, fraction)

func _heal_hero(hero: Combatant, fraction: float) -> void:
	# Cannot exceed max_hp and cannot revive the dead (spec 16.5).
	if not is_instance_valid(hero) or not hero.is_alive():
		return
	var amount := int(round(float(hero.max_hp) * fraction))
	hero.heal(amount)
	BattleVfx.heal_icon(hero, amount)
