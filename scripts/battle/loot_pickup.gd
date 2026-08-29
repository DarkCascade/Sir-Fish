class_name LootPickup
extends RefCounted
## [town] spec 9: gold and scrap that arc off a dead enemy and tick the HUD
## counter up as they settle.
##
## Tweened ballistic arcs, never RigidBody3D (spec 9.2): up to thirty objects
## can be settling at once on the most expensive screen in the game, and a
## computed parabola is deterministic, physics-tick-free and visually
## indistinguishable at this size and duration.
##
## Fired from BattleDirector._on_combatant_died, concurrently with the corpse
## hold (spec 9.1), so the whole ~0.90s animation hides inside time nothing else
## is using and costs the encounter zero seconds. The award (and the
## gold_changed / scrap_changed the HUD plate animates off) lands at the end of
## each object's fade (spec 9.4).

static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

static func _world() -> Node3D:
	var t := _tree()
	if t == null:
		return null
	return t.get_first_node_in_group("battle_world") as Node3D

## Rolls gold and scrap for one kill and spawns the meshes that represent them.
## `is_boss` triples both rolls - the one scaled-up unit, not the whole
## encounter (spec 11.1's "the boss counting triple").
static func spawn_for(origin: Vector3, is_boss: bool) -> void:
	var mult: int = Tuning.BOSS_LOOT_MULT if is_boss else 1
	var gold: int = RNG.randi_range(Tuning.ENEMY_GOLD_DROP.x, Tuning.ENEMY_GOLD_DROP.y) * mult
	var scrap: int = RNG.randi_range(Tuning.ENEMY_SCRAP_DROP.x, Tuning.ENEMY_SCRAP_DROP.y) * mult
	_drop(origin, gold, true)
	_drop(origin, scrap, false)

## Object count is decoupled from value (spec 9.3): spawn
## mini(value, LOOT_PICKUP_MAX_OBJECTS) meshes and split the value across them so
## the shares sum back to `value` exactly - a boss paying 27 and a grunt paying
## 5 both spawn at most five. The number is flavour; the counter is the reward.
static func _drop(origin: Vector3, value: int, is_gold: bool) -> void:
	if value <= 0:
		return
	var shares := _split(value, mini(value, Tuning.LOOT_PICKUP_MAX_OBJECTS))
	var world := _world()
	if world == null:
		# Headless / no battle world: no visuals, but the kill still pays out,
		# and still in the same instalments so run_stats and the banks match.
		for share: int in shares:
			_award(share, is_gold)
		return
	for share: int in shares:
		_spawn_object(world, origin, share, is_gold)

## `value` divided into `count` whole shares that sum back to `value` exactly -
## the first `value % count` shares carry one extra (spec 9.3).
static func _split(value: int, count: int) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	var remainder: int = value % count
	for i: int in range(count):
		out.append(value / count + (1 if i < remainder else 0))
	return out

static func _award(amount: int, is_gold: bool) -> void:
	if is_gold:
		GameState.add_expedition_gold(amount)
	else:
		GameState.add_expedition_scrap(amount)

static var _mesh_cache: Mesh = null

static func _mesh() -> Mesh:
	if _mesh_cache == null:
		var b := BoxMesh.new()
		b.size = Vector3(0.16, 0.16, 0.16)
		_mesh_cache = b
	return _mesh_cache

static func _spawn_object(world: Node3D, origin: Vector3, share: int, is_gold: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Tuning.C_GOLD if is_gold else Tuning.C_ROCK
	mat.metallic = 0.7 if is_gold else 0.1
	mat.roughness = 0.3 if is_gold else 0.85
	mat.emission_enabled = is_gold
	mat.emission = Tuning.C_GOLD_BRIGHT
	mat.emission_energy_multiplier = 0.35 if is_gold else 0.0
	mi.material_override = mat
	world.add_child(mi)

	var dir := Vector3(RNG.randf_range(-1.0, 1.0), 0.0, RNG.randf_range(-1.0, 1.0))
	if dir.length_squared() < 0.0001:
		dir = Vector3.RIGHT
	var land: Vector3 = origin + dir.normalized() * RNG.randf_range(0.15, Tuning.LOOT_SCATTER_RADIUS)
	land.y = origin.y

	mi.global_position = origin
	mi.rotation = Vector3(RNG.randf_range(0.0, TAU), RNG.randf_range(0.0, TAU), RNG.randf_range(0.0, TAU))

	# Independent spin, running for the whole arc-plus-settle.
	var spin := mi.create_tween()
	spin.tween_property(mi, "rotation",
		mi.rotation + Vector3(RNG.randf_range(4.0, 9.0), RNG.randf_range(4.0, 9.0), 0.0),
		Tuning.LOOT_ARC_TIME + Tuning.LOOT_SETTLE_TIME)

	# The ballistic arc: lerp start->land while adding a parabola that peaks at
	# LOOT_ARC_HEIGHT halfway across (4*t*(1-t) is 1.0 at t = 0.5).
	var tw := mi.create_tween()
	tw.tween_method(
		func(t: float) -> void:
			var p: Vector3 = origin.lerp(land, t)
			p.y += Tuning.LOOT_ARC_HEIGHT * 4.0 * t * (1.0 - t)
			mi.global_position = p,
		0.0, 1.0, Tuning.LOOT_ARC_TIME)
	tw.tween_interval(Tuning.LOOT_SETTLE_TIME)
	tw.tween_property(mi, "scale", Vector3.ZERO, Tuning.LOOT_FADE_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		_award(share, is_gold)
		mi.queue_free())
