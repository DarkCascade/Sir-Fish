class_name Projectile
extends Node3D
## The ranger's arrow and bomb arrow (spec 9.2). Travels on a parabolic arc and
## resolves on arrival.

const FLIGHT_TIME := 0.55
const ARC_HEIGHT := 1.6

## [overworld prototype] The arrow's parts are authored at true scale for a
## side-on camera that filled a 640 px strip with about 10 world units. The
## overhead camera sits 26 units back, where a 0.55-long shaft is a couple of
## pixels and the shot simply cannot be read. This scales the whole projectile
## up so it stays legible.
##
## It deliberately does NOT add a trail to the ordinary arrow: spec 9.6 makes
## "trail or no trail" the thing that tells a bomb arrow from a plain one in
## flight, and that distinction is worth more than the extra visibility would be.
##
## [move-elements-to-editor] The scale is authored on both projectile scenes'
## root transforms; this constant survives only because look_at() below
## discards it and it has to be re-applied every frame.
const VIEW_SCALE := 1.8

@export var is_bomb: bool = false

var _t: float = 0.0
var _start: Vector3
var _end: Vector3
var _target: Combatant = null
var _source: Combatant = null
var _director = null              # BattleDirector (untyped: custom API)
var _damage: int = 0
var _flying: bool = false

func launch(source: Combatant, target: Combatant, director, bomb: bool) -> void:
	is_bomb = bomb
	_source = source
	_target = target
	_director = director
	# Damage is locked in at release so a source that dies mid-flight cannot
	# null out the resolution.
	_damage = source.compute_damage()
	if is_bomb:
		_damage = maxi(1, int(round(float(source.stats.base_damage)
			* source.damage_multiplier * Tuning.RANGER_BOMB_AOE_MULT)))
	_start = source.hand_world_position()
	# [overworld prototype] The fallback aim is down the run axis, not +X: the
	# ranger can be facing anywhere on the field now.
	_end = target.hit_world_position() if target != null \
		else _start + Tuning.RUN_DIR * 6.0
	global_position = _start
	_t = 0.0
	_flying = true
	# Held until _impact() so the target can't start its own attack (and
	# possibly blink away) while this is still chasing it.
	if _target != null and is_instance_valid(_target):
		_target.begin_incoming_attack()

func _process(delta: float) -> void:
	if not _flying:
		return
	_t = minf(1.0, _t + delta / FLIGHT_TIME)
	# Re-read a living target's position so the arrow tracks a moving body -
	# which under the overhead camera it will be, since melee fighters blink.
	if _target != null and is_instance_valid(_target) and _target.is_alive():
		_end = _target.hit_world_position()
	var prev := global_position
	var pos := _start.lerp(_end, _t) + Vector3(0, ARC_HEIGHT * 4.0 * _t * (1.0 - _t), 0)
	global_position = pos

	# [overworld prototype] The old `rotation.z = atan2(dy, flat.x)` only aimed
	# the shaft inside the screen plane, which was all a side-on camera could
	# see. The arrow now flies across a ground plane in any direction, so it is
	# aimed at its own velocity in full 3D. The mesh is built lying along +X
	# (see arrow.tscn), and look_at() points a node's -Z, hence the +X basis fix-up.
	var step := pos - prev
	if step.length_squared() > 0.000001:
		look_at(pos + step, Vector3.UP)
		rotate_object_local(Vector3.UP, PI * 0.5)
		# look_at() builds an ORTHONORMAL basis, which throws VIEW_SCALE away.
		# Re-applying it here keeps the arrow at a readable size; the scale
		# setter recomposes the basis around the rotation look_at just set.
		scale = Vector3.ONE * VIEW_SCALE

	if _t >= 1.0:
		_flying = false
		_impact()

func _impact() -> void:
	if _target != null and is_instance_valid(_target):
		_target.end_incoming_attack()
	if is_bomb:
		# Staggered, so it must finish before the node goes away.
		await _explode()
	else:
		_hit()
	queue_free()

func _hit() -> void:
	BattleVfx.arrow_sparks(global_position)
	var victim: Combatant = _target
	# Retarget rule (spec 9.2 / 21-D8): the most common source of null crashes.
	if victim == null or not is_instance_valid(victim) or not victim.is_alive():
		victim = _director.random_living_enemy() if _director != null else null
	if victim == null:
		return                                    # fizzle harmlessly
	EventBus.combatant_attacked.emit(_source, victim, _damage)
	victim.take_damage(_damage, _source)

func _explode() -> void:
	BattleVfx.explosion(global_position)
	if _director == null:
		return
	# Every living enemy, regardless of the original target's state, each rolling
	# variance independently (spec 9.2).
	#
	# Resolved one at a time, left to right by world X, AOE_STAGGER apart (spec
	# 9.7 / Q10). v1 landed all three simultaneously, which is unreadable.
	# Aggregating into one number is rejected: a single "126" says nothing about
	# how the damage was distributed, and the per-target numbers are how a player
	# reads whether an enemy is about to die.
	var targets: Array[Combatant] = _director.living_enemies()
	targets.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		return a.global_position.x < b.global_position.x)
	for enemy: Combatant in targets:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var rolled := maxi(1, int(round(float(_damage) * RNG.randf_range(
			1.0 - Tuning.DAMAGE_VARIANCE, 1.0 + Tuning.DAMAGE_VARIANCE))))
		EventBus.combatant_attacked.emit(_source, enemy, rolled)
		enemy.take_damage(rolled, _source)
		await _tree_timer(Tuning.AOE_STAGGER)

## The projectile frees itself the frame it impacts, so the stagger has to be
## driven from a tree timer rather than from this node.
func _tree_timer(seconds: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	await tree.create_timer(seconds).timeout
