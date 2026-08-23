class_name MagicBolt
extends Node3D
## The priest's primary, as an aimed spell (overworld prototype).
##
## The side-on view resolved this as a bolt dropped out of the sky onto the
## target's head, which worked because caster and target were a fixed distance
## apart on one axis and the vertical drop read as "the priest did that". Under
## an overhead camera the caster can be anywhere on the field, so a strike that
## never travels from the caster no longer connects the two - the spell has to
## visibly leave the priest's hand and fly. The sky-drop version survives as
## the slot machine's lightning payout, which IS a called-down strike and reads
## correctly as one (BattleVfx.lightning_bolt).
##
## Damage is locked in at cast, like the arrow's, so a caster that dies
## mid-flight cannot null out the resolution.

var _target: Combatant = null
var _source: Combatant = null
var _director = null              # BattleDirector (untyped: custom API)
var _damage: int = 0
var _flying: bool = false
var _t: float = 0.0
var _flight_time: float = 0.5
var _start: Vector3
var _end: Vector3
var _color: Color = Tuning.C_LIGHTNING

@onready var _core: MeshInstance3D = $Core
@onready var _light: OmniLight3D = $Glow

func launch(source: Combatant, target: Combatant, director, _is_special: bool) -> void:
	_source = source
	_target = target
	_director = director
	_damage = source.compute_damage()
	_color = source.stats.accent_color

	_start = source.hand_world_position()
	_end = target.hit_world_position() if target != null else _start + Tuning.RUN_DIR * 6.0
	# Constant speed, not constant duration: a bolt at the far end of the field
	# must not arrive as fast as one fired at point-blank range.
	_flight_time = maxf(0.18, _start.distance_to(_end) / Tuning.MAGIC_BOLT_SPEED)
	global_position = _start
	_t = 0.0
	_flying = true
	_tint()

func _ready() -> void:
	_tint()

func _tint() -> void:
	if _core == null:
		return
	var m := _core.material_override as StandardMaterial3D
	if m != null:
		m.albedo_color = _color
	if _light != null:
		_light.light_color = _color
	var trail := get_node_or_null(^"Trail") as GPUParticles3D
	if trail != null:
		var pm := trail.process_material as ParticleProcessMaterial
		if pm != null:
			var grad := Gradient.new()
			grad.set_color(0, Color(_color, 0.9))
			grad.set_color(1, Color(_color, 0.0))
			var gt := GradientTexture1D.new()
			gt.gradient = grad
			pm.color_ramp = gt

func _process(delta: float) -> void:
	if not _flying:
		return
	_t = minf(1.0, _t + delta / _flight_time)
	# Re-read a living target's position so the bolt tracks a moving body -
	# which under this camera it will be, since melee fighters blink around.
	if _target != null and is_instance_valid(_target) and _target.is_alive():
		_end = _target.hit_world_position()

	# A shallow bow, so the bolt reads as thrown rather than as a laser. The
	# orb is a sphere and its trail emits in world coordinates, so unlike the
	# arrow there is nothing here that needs aiming.
	global_position = _start.lerp(_end, _t) \
		+ Vector3(0, Tuning.MAGIC_BOLT_ARC * 4.0 * _t * (1.0 - _t), 0)

	if _t >= 1.0:
		_flying = false
		_impact()

func _impact() -> void:
	BattleVfx.magic_burst(global_position, _color)
	var victim: Combatant = _target
	# Same retarget rule the arrow uses (spec 9.2 / 21-D8) - the most common
	# source of null crashes. Picked from the CASTER'S opposing side rather
	# than from living_enemies() outright, so an enemy caster does not heal-seek
	# its own rank the day one gets a magic attack_style.
	if victim == null or not is_instance_valid(victim) or not victim.is_alive():
		victim = null
		if _director != null and is_instance_valid(_source):
			var pool: Array = _director.living_enemies() if _source.is_hero \
				else _director.living_heroes()
			if not pool.is_empty():
				victim = pool[RNG.randi_range(0, pool.size() - 1)]
	if victim != null:
		EventBus.combatant_attacked.emit(_source, victim, _damage)
		victim.take_damage(_damage, _source)
	queue_free()
