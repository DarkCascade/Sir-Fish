class_name Projectile
extends Node3D
## The ranger's arrow and bomb arrow (spec 9.2). Travels on a parabolic arc and
## resolves on arrival.

const FLIGHT_TIME := 0.55
const ARC_HEIGHT := 1.6

@export var is_bomb: bool = false

var _t: float = 0.0
var _start: Vector3
var _end: Vector3
var _target: Combatant = null
var _source: Combatant = null
var _director = null              # BattleDirector (untyped: custom API)
var _damage: int = 0
var _flying: bool = false

func _ready() -> void:
	_build()

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
	_end = target.hit_world_position() if target != null else _start + Vector3(6, 0, 0)
	global_position = _start
	_t = 0.0
	_flying = true

func _process(delta: float) -> void:
	if not _flying:
		return
	_t = minf(1.0, _t + delta / FLIGHT_TIME)
	# Re-read a living target's position so the arrow tracks a moving body.
	if _target != null and is_instance_valid(_target) and _target.is_alive():
		_end = _target.hit_world_position()
	var pos := _start.lerp(_end, _t) + Vector3(0, ARC_HEIGHT * 4.0 * _t * (1.0 - _t), 0)
	global_position = pos

	var flat := _end - _start
	var dy := flat.y + ARC_HEIGHT * 4.0 * (1.0 - 2.0 * _t)
	rotation.z = atan2(dy, flat.x)

	if _t >= 1.0:
		_flying = false
		_impact()

func _impact() -> void:
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

# --- visuals ----------------------------------------------------------------

func _build() -> void:
	for old: Node in get_children():
		old.free()
	# The mesh lies along +X so rotation.z aims it along the flight path.
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.018
	shaft.bottom_radius = 0.018
	shaft.height = 0.55
	shaft.radial_segments = 6
	_add(shaft, Tuning.C_WOOD, Vector3.ZERO, Vector3(0, 0, -90))

	var fletch := BoxMesh.new()
	fletch.size = Vector3(0.06, 0.10, 0.02)
	_add(fletch, Tuning.C_PRIEST_CLOTH, Vector3(-0.24, 0, 0))

	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.035
	tip.height = 0.12
	tip.radial_segments = 6
	_add(tip, Tuning.C_ORC_IRON, Vector3(0.32, 0, 0), Vector3(0, 0, -90))

	if is_bomb:
		var bag := SphereMesh.new()
		bag.radius = 0.14
		bag.height = 0.28
		bag.radial_segments = 10
		bag.rings = 6
		_add(bag, Tuning.C_WOOD_DARK, Vector3(0.18, 0, 0))
		var fuse := CylinderMesh.new()
		fuse.top_radius = 0.012
		fuse.bottom_radius = 0.012
		fuse.height = 0.14
		fuse.radial_segments = 5
		_add(fuse, Tuning.C_PRIEST_CLOTH, Vector3(0.22, 0.16, 0), Vector3(0, 0, -35))

		var spark := GPUParticles3D.new()
		spark.name = "FuseSpark"
		spark.amount = 12
		spark.lifetime = 0.25
		spark.position = Vector3(0.26, 0.23, 0)
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 45.0
		pm.initial_velocity_min = 0.3
		pm.initial_velocity_max = 0.8
		pm.gravity = Vector3(0, -0.5, 0)
		pm.scale_min = 0.4
		pm.scale_max = 0.8
		var grad := Gradient.new()
		grad.set_color(0, Tuning.C_GOLD)
		grad.set_color(1, Color(Tuning.C_DANGER, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		pm.color_ramp = gt
		spark.process_material = pm
		var pmesh := BoxMesh.new()
		pmesh.size = Vector3.ONE * 0.04
		spark.draw_pass_1 = pmesh
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.vertex_color_use_as_albedo = true
		spark.material_override = sm
		add_child(spark)
		spark.emitting = true

		# Spec 9.6: the ordinary arrow has no trail, so the two are distinguishable
		# in flight from anywhere on screen - which is the whole point of the
		# telegraph.
		add_child(_bomb_trail())

		var light := OmniLight3D.new()
		light.name = "FuseLight"
		light.light_color = Tuning.C_GOLD
		light.light_energy = 1.5
		light.omni_range = 1.2
		light.position = Vector3(0.26, 0.23, 0)
		add_child(light)

func _add(mesh: Mesh, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = CelMaterials.cel(color, Color.BLACK, 0.0, 0.010)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Spec 9.6's bomb-arrow trail: amount 40, lifetime 0.45, point emission,
## gravity (0, -0.6, 0), ramp #E03131 -> #F2C230 -> transparent, scale 0.06 -> 0.
func _bomb_trail() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "BombTrail"
	p.amount = 40
	p.lifetime = 0.45
	p.local_coords = false     # the trail is left behind, not carried along
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3(0, -0.6, 0)
	pm.scale_min = 1.0
	pm.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Tuning.C_DANGER)
	grad.add_point(0.5, Tuning.C_GOLD)
	grad.set_color(grad.get_point_count() - 1, Color(Tuning.C_GOLD, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.06
	p.draw_pass_1 = bm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	p.material_override = sm
	p.emitting = true
	return p
