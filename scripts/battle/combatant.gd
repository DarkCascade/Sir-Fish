class_name Combatant
extends Node3D
## One hero or enemy. Combatants do not run their own clocks - BattleDirector
## calls tick(delta) on every living combatant each frame in a fixed order, so
## combat is deterministic given a seed and trivially pausable (spec 8.1).

enum State { IDLE, RUNNING, ATTACKING, HURT, DEAD }

signal died(c: Combatant)

## Spec 9.6's per-caster telegraph colour.
const SPECIAL_FLASH_COLORS := {
	&"warrior": Tuning.C_DEFEND,   # defend blue
	&"ranger": Tuning.C_GOLD,      # bomb-arrow gold
	&"priest": Tuning.C_HEAL,      # heal green
}

@export var stats: CombatantStats

var current_hp: int
var max_hp: int
var state: State = State.IDLE
var cooldown_remaining: float = 0.0
var action_count: int = 0
## [v2] Q9. A special that was due but had no valid target stays pending, so the
## action counter keeps its rhythm through healthy stretches instead of freezing.
var special_pending: bool = false
var damage_multiplier: float = 1.0        # party damage buff + item dmg_pct
var damage_reduction: float = 0.0         # warrior defend lives here
var bonus_flat_damage: int = 0            # [v2] item dmg_flat + elemental (spec 13.5)
var is_hero: bool = false

## Set by BattleDirector when it spawns us.
var director = null               # BattleDirector (untyped: custom API)
## The action currently mid-animation (null when idle).
var pending: Ability = null

var _hurt_time: float = 0.0
var _defend_timer: SceneTreeTimer = null
var _built: bool = false
## Status icons this combatant owns, so death can free them (spec 8.5 / Q15).
var _status_icons: Array = []
## The dmg_pct share of damage_multiplier, kept apart so the party damage buff
## can be divided back out without wiping the item bonus (spec 17.3 / 21-D13).
var _item_pct_multiplier: float = 1.0
## [overworld prototype] The slot this combatant returns to after a blink. Set
## from its spawn position, or explicitly by the director for enemies, which
## spawn off-screen and run in to a slot they do not start on.
var _home_position: Vector3 = Vector3.ZERO
## True between the outbound blink and the return one, so death and the
## animation-finished handler both know there is a trip to unwind.
var _blinked: bool = false

@onready var visual: Node3D = $Visual
@onready var rig: Node3D = $Visual/Rig
@onready var anim: AnimationPlayer = $Visual/AnimationPlayer
@onready var bar_anchor: Marker3D = $BarAnchor
@onready var hand_anchor: Marker3D = $HandAnchor
@onready var hit_anchor: Marker3D = $HitAnchor
@onready var ability_timer: Timer = $AbilityTimer

func _ready() -> void:
	if stats != null and not _built:
		_build()
	if not anim.animation_finished.is_connected(_on_animation_finished):
		anim.animation_finished.connect(_on_animation_finished)

# --- construction -----------------------------------------------------------

func setup(s: CombatantStats, starting_hp: int = -1) -> void:
	stats = s
	if not is_inside_tree():
		await ready
	_build()
	max_hp = stats.max_hp
	current_hp = max_hp if starting_hp < 0 else clampi(starting_hp, 0, max_hp)
	is_hero = stats.is_hero
	state = State.IDLE
	action_count = 0
	special_pending = false
	damage_multiplier = 1.0
	damage_reduction = 0.0
	bonus_flat_damage = 0
	apply_party_bonuses()
	_home_position = global_position
	_blinked = false
	visual.visible = true
	# [overworld prototype] Facing is a direction on the ground plane now, not
	# a choice between two. Heroes face up the run axis, enemies back down it,
	# so the two sides face each other wherever RUN_DIR points. Still done by
	# rotating the whole node and never by negative scale, which would invert
	# the inverted-hull outline normals (spec 7.3).
	face_dir(Tuning.RUN_DIR if is_hero else -Tuning.RUN_DIR)
	play_anim(&"idle")

func _build() -> void:
	_built = true
	is_hero = stats.is_hero
	max_hp = stats.max_hp
	if current_hp <= 0:
		current_hp = max_hp
	CombatantRig.build(rig, stats)
	# model_scale lives on Rig rather than Visual so that the squash/stretch
	# tracks (which key Visual.scale) cannot wipe it out. See QUESTIONS.md Q5.
	rig.scale = Vector3.ONE * stats.model_scale
	var ms := stats.model_scale
	bar_anchor.position = Vector3(0, 2.05, 0) * ms
	hit_anchor.position = Vector3(0, 0.9, 0) * ms
	hand_anchor.position = Vector3(0.34, 1.06, 0.12) * ms
	CombatantAnimations.build(anim, stats)
	# The required set is derived from data, so this check is real (spec 8.3 / Q5).
	for n: StringName in stats.required_anims():
		assert(anim.has_animation(n),
			"%s is missing required animation '%s'" % [stats.id, n])

## Heroes carry the party-wide item bonus pool (spec 13.5). Enemies never do.
## The party damage buff multiplies on top of dmg_pct, which is why 17.3 divides
## its multiplier back out rather than resetting to 1.0.
func apply_party_bonuses() -> void:
	if not is_hero:
		return
	var b := GameState.party_bonuses()
	var buff: float = damage_multiplier / _item_pct_multiplier
	bonus_flat_damage = int(b["dmg_flat"])
	_item_pct_multiplier = 1.0 + float(b["dmg_pct"]) / 100.0
	damage_multiplier = buff * _item_pct_multiplier

# --- queries ----------------------------------------------------------------

func is_alive() -> bool:
	return state != State.DEAD and current_hp > 0

func hp_fraction() -> float:
	return clampf(float(current_hp) / float(maxi(max_hp, 1)), 0.0, 1.0)

func cooldown_fraction() -> float:
	if state == State.ATTACKING:
		return 0.0
	return clampf(cooldown_remaining / maxf(stats.attack_cooldown, 0.0001), 0.0, 1.0)

# --- per-frame --------------------------------------------------------------

func tick(delta: float) -> void:
	if state == State.HURT:
		_hurt_time -= delta
		if _hurt_time <= 0.0:
			state = State.IDLE
			play_anim(&"idle")

## Turn-based combat (experiment). Called by BattleDirector's per-frame loop
## the instant this combatant's cooldown reaches zero. The combatant does not
## act immediately - it hands the request to the director, which queues it
## and dispatches turns one at a time in arrival order.
func request_turn() -> void:
	if director != null:
		director.request_turn(self)

# --- animation --------------------------------------------------------------

func play_anim(anim_name: StringName) -> void:
	if anim == null or not anim.has_animation(anim_name):
		return
	anim.play(anim_name)

# --- facing / home slot (overworld prototype) --------------------------------

func face_dir(dir: Vector3) -> void:
	rotation.y = Tuning.yaw_along(dir)

func face_position(pos: Vector3) -> void:
	face_dir(pos - global_position)

## Faces back the way this side starts the fight facing - up the run axis for
## a hero, down it for an enemy.
func face_home_dir() -> void:
	face_dir(Tuning.RUN_DIR if is_hero else -Tuning.RUN_DIR)

## Enemies spawn off-screen and run in, so the slot they belong to is not the
## position they were created at; the director tells them which it is.
func set_home(pos: Vector3) -> void:
	_home_position = pos

func home_position() -> Vector3:
	return _home_position

func set_running(running: bool) -> void:
	if state == State.DEAD:
		return
	if running:
		state = State.RUNNING
		play_anim(&"run")
	else:
		state = State.IDLE
		play_anim(&"idle")

func _on_animation_finished(anim_name: StringName) -> void:
	if state == State.DEAD:
		return                                    # the corpse holds its pose
	if anim_name == &"attack" or anim_name == &"special":
		# [overworld prototype] A melee attacker is standing next to its victim
		# at this point. Blink it home BEFORE releasing the turn, so the next
		# combatant never acts around a fighter stranded in the enemy rank.
		if _blinked:
			await _blink_home()
			if not is_instance_valid(self) or state == State.DEAD:
				return
		else:
			face_home_dir()
		pending = null
		state = State.IDLE
		# The cooldown starts refilling only after the attack finishes, then
		# drains to 0 (spec 10.2 step 6).
		cooldown_remaining = stats.attack_cooldown
		play_anim(&"idle")
	elif anim_name == &"hurt":
		if state == State.HURT:
			state = State.IDLE
			play_anim(&"idle")

## Called from the animation's method track at the ability's impact_delay.
func _anim_impact() -> void:
	if pending != null:
		pending.resolve(self)

## Priest only - the charge/telegraph beat before the bolt lands.
func _anim_charge() -> void:
	if pending != null:
		pending.charge(self)

## Spec 9.6 / Q19. Universal special-ability telegraph, fired from a call track
## at t = 0 of every `special` clip.
##
## v1 gave the ranger's special the same draw and release as its primary, and the
## only difference before impact was a powder bag roughly 0.3 world units across
## in a 640 px viewport - so a player watching the console did not register that
## a special was incoming until the explosion, which is exactly backwards. One
## flash per ability gives every special a consistent "something is about to
## happen" beat, and it is why flash() must remember its base colour via metadata
## rather than reading the live albedo: specials now overlap with hit flashes.
func _anim_special_cast() -> void:
	var color := SPECIAL_FLASH_COLORS.get(stats.id, Tuning.C_TEXT) as Color
	CelMaterials.flash(rig, color, Tuning.SPECIAL_CAST_FLASH_TIME)

# --- actions ----------------------------------------------------------------

func begin_action(ability: Ability) -> void:
	pending = ability
	state = State.ATTACKING
	if ability.wants_teleport(self):
		_blink_strike(ability)
		return
	# Ranged and magic attackers never leave the file - they only turn to aim.
	# Turning matters: HandAnchor sits at +X, so an unturned caster would fire
	# its bolt off its own shoulder.
	if ability.target != null and is_instance_valid(ability.target):
		face_position(ability.target.global_position)
	play_anim(ability.anim_name)

## Blink to the target, swing, then blink home (see BattleVfx.blink_out for
## what the effect is doing and why). `state` stays ATTACKING for the whole
## round trip, which is what makes the turn queue hold the next combatant
## until this one is back in the party file - one action at a time, fully
## resolved, exactly as _advance_turn_queue() already assumed.
##
## The model is hidden outright rather than alpha-faded: at 0.13 s a fade is
## imperceptible anyway, and driving rig alpha here would collide with the
## corpse-fade tweens and CelMaterials.flash(), which own that same channel.
func _blink_strike(ability: Ability) -> void:
	var from := global_position
	var dest: Vector3 = ability.strike_position(self)

	BattleVfx.blink_out(self, stats.accent_color)
	visual.visible = false
	await get_tree().create_timer(Tuning.TELEPORT_OUT_TIME).timeout
	if not is_instance_valid(self) or state != State.ATTACKING:
		return                                    # died, or was cancelled, mid-blink

	global_position = dest
	_blinked = true
	if ability.target != null and is_instance_valid(ability.target):
		face_position(ability.target.global_position)
	BattleVfx.blink_trail(from, dest, stats.accent_color)
	BattleVfx.blink_in(self, stats.accent_color)
	visual.visible = true
	play_anim(ability.anim_name)

## The return leg. Runs after the attack animation finishes, so the swing is
## seen where it lands before the attacker leaves.
func _blink_home() -> void:
	await get_tree().create_timer(Tuning.TELEPORT_RETURN_DELAY).timeout
	if not is_instance_valid(self) or state == State.DEAD:
		return
	var from := global_position
	BattleVfx.blink_out(self, stats.accent_color)
	visual.visible = false
	await get_tree().create_timer(Tuning.TELEPORT_OUT_TIME).timeout
	if not is_instance_valid(self) or state == State.DEAD:
		return
	global_position = _home_position
	face_home_dir()
	BattleVfx.blink_trail(from, _home_position, stats.accent_color)
	BattleVfx.blink_in(self, stats.accent_color)
	visual.visible = true
	_blinked = false

# --- damage / healing -------------------------------------------------------

## Spec 8.4. Includes the party damage buff and the per-hit variance roll.
func compute_damage() -> int:
	var raw := (float(stats.base_damage) + float(bonus_flat_damage)) * damage_multiplier
	raw *= RNG.randf_range(1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE)
	return maxi(1, int(round(raw)))

func take_damage(amount: int, source: Combatant) -> void:
	if not is_alive():
		return
	var reduction := clampf(damage_reduction, 0.0, 0.9)
	var final := maxi(1, int(round(float(amount) * (1.0 - reduction))))
	var previous_hp := current_hp
	current_hp = maxi(0, current_hp - final)

	EventBus.combatant_damaged.emit(self, final, previous_hp, current_hp)

	# Only hero attacks feed the slot's rolling buffer; slot lightning must not
	# feed back into the average that drives it (spec 21-D6).
	if source != null and source.is_hero:
		EventBus.hero_damage_dealt.emit(final)

	if is_hero:
		GameState.run_stats["damage_taken"] = int(GameState.run_stats["damage_taken"]) + final
	else:
		GameState.run_stats["damage_dealt"] = int(GameState.run_stats["damage_dealt"]) + final

	if current_hp == 0:
		die()
	elif state != State.ATTACKING:
		state = State.HURT
		_hurt_time = Tuning.HURT_ANIM_TIME
		play_anim(&"hurt")
	else:
		# Being hit never interrupts an attack already under way; a brief white
		# flash keeps the hit readable instead (spec 8.5).
		CelMaterials.flash(rig, Color.WHITE, 0.08)

func heal(amount: int) -> void:
	if not is_alive() or amount <= 0:
		return
	var before := current_hp
	current_hp = mini(max_hp, current_hp + amount)
	var applied := current_hp - before
	if applied > 0:
		EventBus.combatant_healed.emit(self, applied)

func die() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	current_hp = 0
	cancel_all_effects()
	play_anim(&"die")
	BattleVfx.death_burst(self)
	CelMaterials.flash(rig, Color.WHITE, 0.15)
	EventBus.combatant_died.emit(self)
	died.emit(self)

## Spec 8.5 / Q15. A defence buff icon hovering over a corpse is a legibility
## failure and reads as a bug, so everything this combatant owns is torn down the
## instant it dies - without waiting for any fade-out.
func cancel_all_effects() -> void:
	# 1. Cancel any in-progress attack and any scheduled impact call.
	pending = null
	if anim != null:
		anim.stop()
	# 1b. [overworld prototype] Dying mid-blink must not leave an invisible
	# corpse. The body stays where it fell rather than snapping back to its
	# slot - a corpse teleporting home with no effect playing reads as a bug,
	# and the exit tween carries dead heroes off the field anyway (spec 12.5).
	_blinked = false
	if visual != null:
		visual.visible = true
	# 2. Drop the defence and orphan its timer.
	damage_reduction = 0.0
	_defend_timer = null
	# 3. Free every status icon this combatant owns, immediately.
	for icon: Variant in _status_icons:
		if is_instance_valid(icon):
			(icon as Node).queue_free()
	_status_icons.clear()
	# 4. The bars are freed by BattleOverlay on combatant_died (spec 10.4).

## Called by BattleOverlay when it spawns an icon over this combatant.
func register_status_icon(icon: Node) -> void:
	_status_icons.append(icon)
	if not icon.tree_exited.is_connected(_on_status_icon_gone):
		icon.tree_exited.connect(_on_status_icon_gone.bind(icon))

func _on_status_icon_gone(icon: Node) -> void:
	_status_icons.erase(icon)

# --- warrior defend ---------------------------------------------------------

func apply_defend() -> void:
	damage_reduction = Tuning.WARRIOR_DEFEND_REDUCTION
	# Re-applying refreshes the duration rather than stacking (spec 9.1).
	var timer := get_tree().create_timer(Tuning.WARRIOR_DEFEND_DURATION)
	_defend_timer = timer
	await timer.timeout
	if _defend_timer == timer:
		damage_reduction = 0.0
		_defend_timer = null

func is_defending() -> bool:
	return damage_reduction > 0.0

# --- world helpers ----------------------------------------------------------

func bar_world_position() -> Vector3:
	return bar_anchor.global_position

func hit_world_position() -> Vector3:
	return hit_anchor.global_position

func hand_world_position() -> Vector3:
	return hand_anchor.global_position
