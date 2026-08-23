class_name BattleDirector
extends Node
## Owns a single fight from spawn to resolution (spec 10). Also owns the party
## for the whole run, because heroes persist between encounters.

var world = null                  # BattleWorld (untyped: custom API)

var heroes: Array[Combatant] = []
var enemies: Array[Combatant] = []

var _active: bool = false
var _resolving: bool = false

## Dev-only combat-mode toggle (not exposed to the player in any way). True:
## combatants request a turn on cooldown expiry and the director dispatches
## them one at a time via _turn_queue, below. False: a combatant acts the
## instant its cooldown expires, same as before turn-based combat existed -
## multiple combatants can act simultaneously.
@export var turn_based_combat: bool = true

## Turn-based combat. Combatants no longer act the instant their cooldown
## expires - they request a turn, the director queues requests in the order
## they arrive, and only the combatant at the front of the queue is told to
## act. One combatant acts at a time; everyone else keeps waiting even if
## their own cooldown has also finished. Unused when turn_based_combat is false.
var _turn_queue: Array[Combatant] = []
var _acting: Combatant = null

signal corpse_cleanup_done()

var _pending_corpse_fades: int = 0

func _ready() -> void:
	# Items are a party-wide pool, so a hero's damage has to follow the inventory
	# even mid-fight (spec 13.5).
	EventBus.party_bonuses_changed.connect(_on_party_bonuses_changed)
	# [v3.5 D4] Per-death fade starts the moment an enemy dies, not only when
	# begin_corpse_cleanup() runs at the end of the fight.
	EventBus.combatant_died.connect(_on_combatant_died)

func _on_combatant_died(c) -> void:
	if _active and c is Combatant and enemies.has(c):
		_pending_corpse_fades += 1
		var gen: int = int(c.get_meta("corpse_gen", 0)) + 1
		c.set_meta("corpse_gen", gen)
		_run_corpse_fade(c, Tuning.ENEMY_DEATH_HOLD, Tuning.ENEMY_DEATH_FADE, gen)

func _on_party_bonuses_changed(_bonuses: Dictionary) -> void:
	for h: Combatant in living_heroes():
		h.apply_party_bonuses()

# --- party ------------------------------------------------------------------

## Spawns the three heroes into their fixed slots: Priest, Ranger, Warrior,
## left to right (spec 7.1). Called once per run.
func spawn_party() -> void:
	clear_party()
	for i: int in range(GameState.hero_runtime.size()):
		var entry: Dictionary = GameState.hero_runtime[i]
		var stats := GameState.get_stats(entry["stats_id"])
		if stats == null:
			continue
		var c := _spawn_combatant(stats, world.hero_slot_position(i), int(entry["current_hp"]))
		heroes.append(c)
		if not entry["alive"]:
			c.state = Combatant.State.DEAD
			c.current_hp = 0
			c.play_anim(&"die")
		EventBus.combatant_spawned.emit(c)

func clear_party() -> void:
	for c: Combatant in heroes:
		if is_instance_valid(c):
			c.queue_free()
	heroes.clear()

func clear_enemies() -> void:
	for c: Combatant in enemies:
		if is_instance_valid(c):
			c.queue_free()
	enemies.clear()

func _spawn_combatant(stats: CombatantStats, pos: Vector3, hp: int) -> Combatant:
	var packed: PackedScene = load(stats.scene_path)
	var c := packed.instantiate() as Combatant
	var parent: Node3D = world.hero_slots if stats.is_hero else world.enemy_root
	parent.add_child(c)
	c.position = pos
	c.director = self
	c.setup(stats, hp)
	return c

# --- combat lifecycle -------------------------------------------------------

## Slot 0 is the boss by convention (see game_state.gd's encounter builders,
## which always list the boss id first) - scaled up here from a
## runtime-duplicated CombatantStats, never the shared cached one GameState
## hands out, so the same id spawned at its normal size elsewhere (e.g. the
## regular pool encounters) is untouched.
const BOSS_SCALE_MULT := 1.5

func start_combat(enemy_stat_ids: Array, is_boss: bool = false) -> void:
	clear_enemies()
	_resolving = false
	_turn_queue.clear()
	_acting = null
	# Step 1 of spec 10.1: every hero picks up the current item bonuses first.
	for h: Combatant in living_heroes():
		h.apply_party_bonuses()
	var total: int = enemy_stat_ids.size()
	for i: int in range(total):
		var stats := GameState.get_stats(enemy_stat_ids[i])
		if stats == null:
			continue
		if is_boss and i == 0:
			stats = stats.duplicate() as CombatantStats
			stats.model_scale *= BOSS_SCALE_MULT
		# [overworld prototype] Spec 10.1's fade-in is gone. Enemies now spawn
		# off-screen past the top-right corner and RUN to their slots, which is
		# the one entrance that reads correctly on an open field - a fade would
		# have them materialise out of empty grass the camera can see straight
		# through.
		var slot: Vector3 = world.enemy_slot_position(i, total)
		var c := _spawn_combatant(stats, world.enemy_entry_position(i, total), -1)
		c.set_home(slot)
		enemies.append(c)
		_run_enemy_in(c, slot, i)
		EventBus.combatant_spawned.emit(c)

	for c: Combatant in _all():
		_roll_initial_cooldown(c)

	_active = true
	EventBus.combat_started.emit(heroes, enemies)

## The entrance: sprint from off-screen down the run axis into the slot, on a
## per-enemy stagger so a rank of three arrives as a charge rather than as a
## wall. State is RUNNING throughout, which is what stops them attacking
## mid-approach - the per-frame loop only calls request_turn() on an IDLE
## combatant.
func _run_enemy_in(c: Combatant, slot: Vector3, index: int) -> void:
	c.set_running(true)
	c.face_dir(-Tuning.RUN_DIR)
	if index > 0:
		await get_tree().create_timer(float(index) * Tuning.ENEMY_ENTRY_STAGGER).timeout
		if not is_instance_valid(c) or not c.is_alive():
			return
	var tw := c.create_tween()
	tw.tween_property(c, "global_position", slot, Tuning.ENEMY_ENTRY_TIME) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	await tw.finished
	if not is_instance_valid(c) or not c.is_alive():
		return
	c.set_running(false)
	c.face_dir(-Tuning.RUN_DIR)
	# Re-roll on arrival. The cooldown rolled at spawn has been draining for the
	# whole run-in (the per-frame loop only skips ATTACKING combatants, not
	# RUNNING ones), so without this an enemy lands already overdue and swings
	# on the frame it stops - no beat between the charge and the first blow.
	_roll_initial_cooldown(c)

## Half full, times a +/-10% jitter that exists only to de-sync identical enemy
## types that would otherwise act on the same frame (spec 10.1 / 21-D2).
func _roll_initial_cooldown(c: Combatant) -> void:
	c.cooldown_remaining = c.stats.attack_cooldown \
		* Tuning.COOLDOWN_START_FRACTION \
		* RNG.randf_range(1.0 - Tuning.COOLDOWN_START_JITTER,
			1.0 + Tuning.COOLDOWN_START_JITTER)

func stop_combat() -> void:
	_active = false
	_turn_queue.clear()
	_acting = null

func is_active() -> bool:
	return _active

# --- per-frame loop ---------------------------------------------------------

func _process(delta: float) -> void:
	if not _active:
		return
	for c: Combatant in _living_in_order():
		if not c.is_alive():
			continue
		c.tick(delta)
		# [v2] Q8. v1 decremented the cooldown during an attack and then overwrote
		# it on animation finish, so the decrement was always discarded - dead code
		# that made the loop read as if the cooldown ran concurrently with the
		# attack. Skipping is equivalent in behaviour, honest in intent, and it
		# matches the bar, which reads 0 throughout an attack (spec 11.3).
		if c.state == Combatant.State.ATTACKING:
			continue
		# Already queued (or currently acting) - its cooldown stays at 0 rather
		# than drifting negative while it waits its turn.
		if c == _acting or _turn_queue.has(c):
			continue
		c.cooldown_remaining -= delta
		if c.cooldown_remaining <= 0.0 and c.state == Combatant.State.IDLE:
			c.request_turn()
	_advance_turn_queue()
	_check_resolution()

## Called by a combatant (see Combatant.request_turn) when its cooldown has
## expired. In turn-based mode this just appends to the queue in arrival
## order and lets _advance_turn_queue() dispatch it later. In real-time mode
## there is no queueing - the combatant acts immediately, same as before
## turn-based combat existed.
func request_turn(c: Combatant) -> void:
	if not turn_based_combat:
		_take_action(c)
		return
	if c == _acting or _turn_queue.has(c):
		return
	_turn_queue.append(c)

## Dispatches the next queued combatant once nobody is mid-action. Only one
## combatant acts at a time - everyone else's turn request just waits in line.
func _advance_turn_queue() -> void:
	if _acting != null:
		if is_instance_valid(_acting) and _acting.state == Combatant.State.ATTACKING:
			return
		_acting = null
	if _turn_queue.is_empty():
		return
	var c: Combatant = _turn_queue.pop_front()
	if not is_instance_valid(c) or not c.is_alive():
		return
	_take_action(c)
	if c.state == Combatant.State.ATTACKING:
		_acting = c

## Heroes left-to-right, then enemies left-to-right. Returns a copy, because
## actions can kill combatants mid-iteration (spec 10.2).
func _living_in_order() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c: Combatant in heroes:
		if is_instance_valid(c) and c.is_alive():
			out.append(c)
	var alive_enemies := living_enemies()
	alive_enemies.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		return a.position.x < b.position.x)
	out.append_array(alive_enemies)
	return out

func _all() -> Array[Combatant]:
	var out: Array[Combatant] = []
	out.append_array(heroes)
	out.append_array(enemies)
	return out

func _take_action(c: Combatant) -> void:
	c.action_count += 1
	var due: bool = c.stats.special_every_n_actions > 0 \
		and c.action_count % c.stats.special_every_n_actions == 0
	var use_special: bool = due or c.special_pending

	# Wounded-ally skip rule (spec 4.1 / 10.2, V6). [v3] Data-driven, not an id
	# check: special_requires_wounded_ally is true only on priest.tres. Applying
	# this to every special would also suppress the warrior's Defend at full
	# party HP, which is backwards - Defend is most useful before anyone is
	# hurt. "Ally" means every living combatant on the caster's own side,
	# including the caster, so a wounded priest in an otherwise-healthy party
	# still heals itself.
	#
	# v1 decremented action_count so the next action re-tested the same multiple.
	# That worked but froze the counter: through a healthy stretch the priest's
	# primaries stopped advancing the rhythm, so a heal fired on the very first
	# action after anyone took a scratch - reactive twitch rather than a cadence
	# the player can feel. A pending flag lets the counter advance normally AND
	# still fires a skipped heal as soon as a target exists.
	if use_special and c.stats.special_requires_wounded_ally \
			and _every_living_ally_at_full_hp(c):
		use_special = false
		c.special_pending = true
	elif use_special:
		c.special_pending = false

	# [v3] special_targets_opponent, not an id check (spec 4.1 / 10.2, V6). The
	# warrior's Defend and the priest's Heal must still fire when no opponent is
	# alive - during the resolve window after the last enemy (or last hero)
	# dies. The ranger's bomb arrow is aimed, so it correctly aborts here; bomb
	# arrow and slot lightning ignore the chosen target at resolution anyway.
	var target: Combatant = null
	if not (use_special and not c.stats.special_targets_opponent):
		target = _random_target_for(c)
		if target == null:
			c.cooldown_remaining = c.stats.attack_cooldown
			return

	c.begin_action(Ability.make(c, use_special, target, self))

## Uniformly random among living opponents (spec 10.2 step 3).
func _random_target_for(c: Combatant) -> Combatant:
	var pool := living_enemies() if c.is_hero else living_heroes()
	if pool.is_empty():
		return null
	return pool[RNG.randi_range(0, pool.size() - 1)]

## [v3] "Ally" is every living combatant on c's own side, including c itself,
## so a wounded priest in an otherwise-healthy party still heals itself
## (spec 10.2, V6).
func _every_living_ally_at_full_hp(c: Combatant) -> bool:
	var side := living_heroes() if c.is_hero else living_enemies()
	for a: Combatant in side:
		if a.current_hp < a.max_hp:
			return false
	return true

# --- queries used by abilities and the slot machine -------------------------

func living_heroes() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c: Combatant in heroes:
		if is_instance_valid(c) and c.is_alive():
			out.append(c)
	return out

func living_enemies() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c: Combatant in enemies:
		if is_instance_valid(c) and c.is_alive():
			out.append(c)
	return out

func random_living_enemy() -> Combatant:
	var pool := living_enemies()
	if pool.is_empty():
		return null
	return pool[RNG.randi_range(0, pool.size() - 1)]

func lowest_hp_living_hero() -> Combatant:
	var best: Combatant = null
	for h: Combatant in living_heroes():
		if best == null or h.current_hp < best.current_hp:
			best = h
	return best

func dead_heroes() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c: Combatant in heroes:
		if is_instance_valid(c) and not c.is_alive():
			out.append(c)
	return out

# --- resolution -------------------------------------------------------------

func _check_resolution() -> void:
	if _resolving:
		return
	# Defeat is checked first so a mutual wipe is a loss (spec 10.5).
	if living_heroes().is_empty():
		_resolving = true
		_active = false
		sync_heroes_to_state()
		EventBus.combat_ended.emit(false)
		return
	if living_enemies().is_empty():
		_resolving = true
		_active = false
		_finish_victory()

func _finish_victory() -> void:
	await get_tree().create_timer(Tuning.ENCOUNTER_RESOLVE_PAUSE).timeout
	sync_heroes_to_state()
	EventBus.combat_ended.emit(true)

## [v3.5 D4] Enemy corpses hold, then fade, on a timer that starts the moment
## each one dies (see _on_combatant_died). If the fight ends while a corpse is
## still holding or fading, this rushes it so nothing is on screen when travel
## begins - it kills any in-flight slow tween and resumes from the corpse's
## current alpha, never stacking a second tween on the same property.
func begin_corpse_cleanup() -> void:
	for c: Combatant in enemies:
		if is_instance_valid(c) and not c.is_alive():
			# Bumping the generation invalidates any in-flight SLOW coroutine for
			# this corpse (it checks the generation after its own await and bails
			# if it no longer matches) without also invalidating the rush call
			# this loop is about to start itself - a shared boolean flag can't
			# tell "an older coroutine was superseded" from "I am the new one".
			var gen: int = int(c.get_meta("corpse_gen", 0)) + 1
			c.set_meta("corpse_gen", gen)
			if c.has_meta("corpse_tween"):
				var tw = c.get_meta("corpse_tween")
				if tw is Tween and tw.is_valid():
					tw.kill()
			_run_corpse_fade(c, Tuning.ENEMY_DEATH_HOLD_RUSH, Tuning.ENEMY_DEATH_FADE_RUSH, gen)

## Resolves once every corpse fade started this encounter has freed its node.
func await_corpse_cleanup() -> void:
	if _pending_corpse_fades <= 0:
		return
	await corpse_cleanup_done

func _run_corpse_fade(c: Combatant, hold: float, fade: float, gen: int) -> void:
	if hold > 0.0:
		await get_tree().create_timer(hold).timeout
		if not is_instance_valid(c) or int(c.get_meta("corpse_gen", 0)) != gen:
			return
	if not is_instance_valid(c) or int(c.get_meta("corpse_gen", 0)) != gen:
		return
	var start_alpha: float = float(c.get_meta("corpse_alpha", 1.0))
	var tw := c.create_tween()
	c.set_meta("corpse_tween", tw)
	tw.tween_method(Callable(self, "_set_corpse_alpha").bind(c), start_alpha, 0.0, fade)
	tw.tween_callback(Callable(self, "_finish_corpse").bind(c))

func _set_corpse_alpha(alpha: float, c: Combatant) -> void:
	if not is_instance_valid(c):
		return
	c.set_meta("corpse_alpha", alpha)
	CelMaterials.set_alpha_on(alpha, c.rig)

func _finish_corpse(c: Combatant) -> void:
	_pending_corpse_fades = maxi(0, _pending_corpse_fades - 1)
	if _pending_corpse_fades == 0:
		corpse_cleanup_done.emit()
	if is_instance_valid(c):
		c.queue_free()

func sync_heroes_to_state() -> void:
	for i: int in range(mini(heroes.size(), GameState.hero_runtime.size())):
		var c: Combatant = heroes[i]
		if not is_instance_valid(c):
			continue
		var entry: Dictionary = GameState.hero_runtime[i]
		entry["current_hp"] = c.current_hp
		entry["alive"] = c.is_alive()
