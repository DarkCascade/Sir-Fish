extends CanvasLayer
## Background lightning (M9). A jagged Line2D bolt in the sky, a screen flash,
## a re-light of the whole battlefield, and thunder that arrives late as a
## camera rumble.
##
## Why a CanvasLayer of Line2D rather than 3D geometry: a bolt is a polyline
## with a width curve and a glow built from stacked strokes, which is exactly
## what Line2D is for. It lives INSIDE the battle SubViewport, so it is part
## of the battlefield image (the console UI below is a separate Control and
## never sees it), and 2D draws after 3D in the same viewport, which is what
## puts the bolt in front of the sky and the far trees.
##
## Why the flash is three things at once: a DirectionalLight3D pulse relights
## everything LIT (characters, ground, brush), a ParallaxBackground.set_flash()
## call relights the three UNSHADED generated layers that a light cannot touch
## (see that file), and a full-viewport ColorRect blooms over the top. Any one
## alone reads as a bug: light-only leaves the sky flat, sky-only leaves the
## characters standing in the dark.
##
## Its own RandomNumberGenerator, deliberately: RNG is the seeded run stream
## (spec 8.1) and lightning fires on wall-clock timers, so drawing from it
## would make a seeded run's combat rolls depend on how many bolts happened to
## strike. Weather must never be able to move a damage roll.

## Sky-region bounds in viewport pixels (the battle viewport is 1080x640).
## Bolts start above the top edge and stop at the tree line, never lower - a
## bolt that reaches the characters reads as an attack, not as weather.
const VIEW_W := 1080.0
const TREE_LINE_MIN := 250.0
const TREE_LINE_MAX := 400.0

const SUBDIVISIONS := 6
const JAGGED := 0.34                      # displacement as a share of segment length
const BRANCH_MAX := 3
const POOL_BOLTS := 2                     # a double strike needs two live bolts

const CORE_WIDTH := 6.0
const MID_WIDTH := 17.0
const GLOW_WIDTH := 42.0
const CORE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const MID_COLOR := Color(0.647, 0.788, 1.0, 0.70)
const GLOW_COLOR := Color(0.318, 0.443, 0.729, 0.38)

## Every stroke draws ADDITIVELY. Alpha-blended stacking was the first
## attempt and it is wrong: a wide dim halo painted over the sky just tints
## it, so three strokes produce a flat grey scratch instead of a hot line
## with light bleeding off it. Added together they accumulate - the halo
## lifts the sky, the body sits on top of the halo, the core blows out white
## - which is what a glow IS.
var _additive := CanvasItemMaterial.new()
var _rng := RandomNumberGenerator.new()
var _bolts: Array = []                    # Array[Dictionary], one stack per bolt
var _screen: ColorRect
var _light: DirectionalLight3D
var _parallax: Node
var _rain: Node
var _world: Node3D
var _env: Environment
var _sky_base: Color

func _ready() -> void:
	_rng.randomize()
	_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_world = get_parent() as Node3D
	_light = _world.get_node_or_null(^"LightningLight") as DirectionalLight3D
	_parallax = _world.get_node_or_null(^"ParallaxBackground")
	_rain = _world.get_node_or_null(^"StormRain")
	var we := _world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if we != null:
		_env = we.environment
		_sky_base = _env.background_color
	_build_screen_flash()
	for i: int in range(POOL_BOLTS):
		_bolts.append(_build_bolt())
	_set_flash(0.0)
	_set_bolt_alpha(0.0)
	_schedule_next()

# --- construction -------------------------------------------------------------

func _build_screen_flash() -> void:
	_screen = ColorRect.new()
	_screen.color = Tuning.STORM_SKY_FLASH
	_screen.anchor_right = 1.0
	_screen.anchor_bottom = 1.0
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.modulate.a = 0.0
	add_child(_screen)

## One bolt is three strokes over the same points - a wide dim halo, a mid
## body, a hot core - plus its branches and a bloom at the strike point.
## Stacking strokes is how a Line2D gets a glow: Environment glow is a 3D
## post-process and never reaches a canvas item, so a single-stroke bolt would
## be a hard white scratch.
func _build_bolt() -> Dictionary:
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(1.0, 0.35))
	var strokes: Array[Line2D] = []
	for spec: Array in [[GLOW_WIDTH, GLOW_COLOR], [MID_WIDTH, MID_COLOR], [CORE_WIDTH, CORE_COLOR]]:
		strokes.append(_stroke(float(spec[0]), spec[1], taper))
	var branches: Array = []
	for i: int in range(BRANCH_MAX):
		branches.append({
			"glow": _stroke(GLOW_WIDTH * 0.45, GLOW_COLOR, taper),
			"core": _stroke(CORE_WIDTH * 0.6, CORE_COLOR, taper),
		})
	# The strike point blooms: two coincident points at a huge width with
	# round caps is a soft disc for free - no texture, no extra node type.
	var impact := _stroke(GLOW_WIDTH * 2.2, Color(0.749, 0.847, 1.0, 0.30), null)
	return { "strokes": strokes, "branches": branches, "impact": impact }

func _stroke(width: float, color: Color, taper: Curve) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.material = _additive
	if taper != null:
		line.width_curve = taper
	line.visible = false
	add_child(line)
	return line

# --- scheduling ---------------------------------------------------------------

func _schedule_next() -> void:
	var wait := _rng.randf_range(Tuning.LIGHTNING_INTERVAL_MIN, Tuning.LIGHTNING_INTERVAL_MAX)
	get_tree().create_timer(wait).timeout.connect(_strike, CONNECT_ONE_SHOT)

## Fires a strike right now, out of band with the schedule. Exists for the
## Debug harness (spec 19.2): the natural interval is 4.5-11 s, which is far
## too long to sit through when you are checking whether a bolt still draws.
func strike_now() -> void:
	_fire(0)

func _strike() -> void:
	_fire(0)
	# Real storms rarely flash exactly once, and the second bolt landing in a
	# different part of the sky is most of what sells the first one.
	if _rng.randf() < Tuning.LIGHTNING_DOUBLE_CHANCE:
		var gap := _rng.randf_range(0.12, 0.30)
		get_tree().create_timer(gap).timeout.connect(_fire.bind(1), CONNECT_ONE_SHOT)
	_schedule_next()

func _fire(index: int) -> void:
	if index >= _bolts.size():
		return
	_shape_bolt(_bolts[index])
	_play_flash()
	_rumble()

# --- geometry -----------------------------------------------------------------

func _shape_bolt(bolt: Dictionary) -> void:
	var start := Vector2(_rng.randf_range(120.0, VIEW_W - 120.0), -30.0)
	var end_point := Vector2(
		clampf(start.x + _rng.randf_range(-190.0, 190.0), 40.0, VIEW_W - 40.0),
		_rng.randf_range(TREE_LINE_MIN, TREE_LINE_MAX))
	var points := _jagged(start, end_point, SUBDIVISIONS)
	for line: Line2D in bolt["strokes"]:
		line.points = points

	# Branches fork off the trunk and die out short of it. A fork that runs as
	# far as the trunk turns one bolt into two thin ones and the silhouette
	# stops reading as lightning at all.
	var count := _rng.randi_range(1, BRANCH_MAX)
	for i: int in range(BRANCH_MAX):
		var branch: Dictionary = bolt["branches"][i]
		var show_branch: bool = i < count and points.size() > 4
		var from_idx := _rng.randi_range(1, maxi(points.size() - 3, 1))
		var from: Vector2 = points[from_idx]
		var to := from + Vector2(
			_rng.randf_range(-150.0, 150.0),
			_rng.randf_range(60.0, 150.0))
		var branch_points := _jagged(from, to, 3)
		for key: String in ["glow", "core"]:
			var line: Line2D = branch[key]
			line.points = branch_points if show_branch else PackedVector2Array()

	var impact: Line2D = bolt["impact"]
	impact.points = PackedVector2Array([end_point, end_point + Vector2(0.5, 0.0)])

## Midpoint displacement: split every segment, push the new point along the
## segment's normal, halve the amplitude, repeat. Displacing along the NORMAL
## rather than on x alone is what keeps the zigzag perpendicular to the bolt's
## own direction, so a diagonal bolt stays as jagged as a vertical one.
func _jagged(from: Vector2, to: Vector2, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array([from, to])
	var amplitude := from.distance_to(to) * JAGGED
	for step: int in range(steps):
		var next := PackedVector2Array()
		for i: int in range(points.size() - 1):
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			var mid := (a + b) * 0.5
			var normal := (b - a).orthogonal().normalized()
			next.append(a)
			next.append(mid + normal * _rng.randf_range(-amplitude, amplitude))
		next.append(points[points.size() - 1])
		points = next
		amplitude *= 0.52
	return points

# --- the flash ----------------------------------------------------------------

## Two curves, not one. The bolt is gone long before the sky stops being
## bright: it stutters through hard on/off frames (this is the Castlevania
## beat) while the light behind it decays smoothly. Tying them together makes
## the bolt look like it fades out, which no bolt has ever done.
func _play_flash() -> void:
	var bolt := create_tween()
	bolt.tween_method(_set_bolt_alpha, 1.0, 1.0, 0.045)
	bolt.tween_method(_set_bolt_alpha, 0.0, 0.0, 0.035)
	bolt.tween_method(_set_bolt_alpha, 1.0, 1.0, 0.055)
	bolt.tween_method(_set_bolt_alpha, 0.0, 0.0, 0.030)
	bolt.tween_method(_set_bolt_alpha, 0.85, 0.0, 0.130)

	var flash := create_tween()
	flash.tween_method(_set_flash, 0.0, 1.0, 0.03)
	flash.tween_method(_set_flash, 1.0, 0.35, 0.09)
	flash.tween_method(_set_flash, 0.35, 0.95, 0.06)
	flash.tween_method(_set_flash, 0.95, 0.0, 0.42).set_trans(Tween.TRANS_QUAD)

func _set_bolt_alpha(value: float) -> void:
	var lit: bool = value > 0.01
	for bolt: Dictionary in _bolts:
		for line: Line2D in bolt["strokes"]:
			line.visible = lit and line.points.size() > 1
			line.modulate.a = value
		for branch: Dictionary in bolt["branches"]:
			for key: String in ["glow", "core"]:
				var line: Line2D = branch[key]
				line.visible = lit and line.points.size() > 1
				line.modulate.a = value
		var impact: Line2D = bolt["impact"]
		impact.visible = lit and impact.points.size() > 1
		impact.modulate.a = value

func _set_flash(value: float) -> void:
	if _screen != null:
		_screen.modulate.a = value * Tuning.LIGHTNING_SCREEN_ALPHA
	if _light != null:
		_light.light_energy = value * Tuning.LIGHTNING_LIGHT_ENERGY
	if _parallax != null and _parallax.has_method("set_flash"):
		_parallax.set_flash(value * 0.85)
	# The rain is unshaded for the same reason the generated layers are - a
	# lit raindrop in a scene this dark is a black raindrop - so it needs the
	# same explicit hook rather than the light pulse. Guarded on has_method:
	# the storm still works if the rain is absent or predates the hook.
	if _rain != null and _rain.has_method("set_flash"):
		_rain.set_flash(value)
	if _env != null:
		_env.background_color = _sky_base.lerp(Tuning.STORM_SKY_FLASH, value * 0.9)

## Thunder is late, and the delay is the whole point: the light arrives, then
## the sky rolls. With no audio assets in the project the roll IS the camera
## shake, which is why it is long and weak rather than the short sharp kick an
## ability uses (ability.gd's 0.05 / 0.18).
func _rumble() -> void:
	if _world == null or not _world.has_method("shake"):
		return
	var delay := _rng.randf_range(
		Tuning.LIGHTNING_THUNDER_DELAY_MIN, Tuning.LIGHTNING_THUNDER_DELAY_MAX)
	get_tree().create_timer(delay).timeout.connect(_shake_now, CONNECT_ONE_SHOT)

func _shake_now() -> void:
	if is_instance_valid(_world):
		_world.shake(Tuning.LIGHTNING_SHAKE, Tuning.LIGHTNING_SHAKE_TIME)
