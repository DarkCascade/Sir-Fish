extends Node3D
## Storm rain (M9 "gloom" pass). Owned end-to-end by the rain implementation
## agent; the rest of the storm work (environment, palette, lightning) lives in
## battle_world.tscn / tuning.gd / lightning.gd and does not touch this file.
##
## Instanced once by battle_world.tscn as `StormRain`, under the same
## orthographic camera as everything else: size 5.8, at (0, 2.2, 12), so the
## visible box is roughly x -4.9..4.9, y -0.7..5.1, with the parallax layers at
## z -14 (hills), -9 (far trees), -5 (near trees), 0 (ground) and +3 (brush).
## The camera transform is untilted (identity basis) - a pure side view - so
## world Y maps straight to screen Y, and anything flat in the XZ plane (e.g. a
## ground decal) would be seen exactly edge-on and vanish.
##
## Everything below is built at _ready() rather than authored in the .tscn
## (the same call ParallaxBackground makes for its tiles) because the rain
## bands and the splash layer all share derived quantities - most importantly
## how far a slanted drop drifts sideways while crossing its spawn box - that
## must stay locked to WIND_ANGLE_DEG or the bands visibly disagree on wind,
## which is the first thing that reads as fake. Deriving it once in code makes
## that impossible; hand-entering the same derived number in four places does
## not.
##
## Depth is entirely faked: an orthographic camera gives no perspective
## falloff, so a "near" drop is not naturally bigger or faster on screen than
## a "far" one. Three bands differ only in mesh size / fall speed / brightness
## / count, plus a Z position that puts Near in front of the Brush parallax
## layer, Mid straddling the characters, and Far behind them among the trees -
## the same trick ParallaxBackground uses for its own layers, applied to rain.

# --- wind & framing -----------------------------------------------------------
# Every band shares this angle exactly - the brief calls out bands disagreeing
# on wind as an obvious tell, so this is the one number that must never be
# duplicated.
const WIND_ANGLE_DEG := 15.0

const VIEW_X_HALF := 5.0                   # true camera box is +-4.9; a hair of slack
const VIEW_Y_TOP := 5.1
const VIEW_Y_BOTTOM := -0.7
const GROUND_Y := 0.0

# Drops spawn at a uniform-random point inside a box taller than the frame,
# not at a fixed top edge - GPUParticles3D box emission has no notion of "off
# screen". Padding the box well past both edges means most spawns land off
# screen anyway; the fade curve below (FADE_IN/OUT_FRAC) covers the rest so a
# drop that does spawn mid-frame still materialises softly instead of popping.
const SPAWN_TOP_Y := VIEW_Y_TOP + 2.5
const SPAWN_BOTTOM_Y := VIEW_Y_BOTTOM - 0.3

const FADE_IN_FRAC := 0.10                 # fraction of a drop's own lifetime
const FADE_OUT_FRAC := 0.82

# --- rain bands: 2-3 depth bands, near band fast/big/bright -------------------
# z picked against ParallaxBackground's layers (hills -14 .. brush +3) and the
# characters standing at z=0: Near sits in front of Brush (the frontmost
# parallax layer), Mid straddles the characters, Far sits between NearTrees
# and FarTrees. amount deliberately runs low->high near->far: a few bold
# streaks up front read as "close", a haze of small dim ones out back reads as
# "far" - matching how the parallax layers themselves sell depth.
const RAIN_BANDS: Array[Dictionary] = [
	{
		"name": "Near", "z": 4.4, "z_spread": 1.1,
		"speed": 11.5, "width": 0.032, "length": 0.62,
		"color": Color(0.87, 0.93, 1.0), "alpha": 0.48, "amount": 190,
	},
	{
		"name": "Mid", "z": -1.2, "z_spread": 2.4,
		"speed": 8.6, "width": 0.022, "length": 0.42,
		"color": Color(0.80, 0.88, 1.0), "alpha": 0.42, "amount": 280,
	},
	{
		"name": "Far", "z": -6.4, "z_spread": 2.2,
		"speed": 6.0, "width": 0.015, "length": 0.27,
		"color": Color(0.72, 0.82, 0.98), "alpha": 0.25, "amount": 300,
	},
]

# --- ground splash -------------------------------------------------------------
# One extra emitter, flush with the ground plane, stands in for every band at
# once rather than one splash per band - a splash's height is so small it does
# not need its own depth read, it just needs to span the same Z range the rain
# bands land in. Short lifetime + strong gravity keeps the arc a few
# centimetres tall so it never reads as "climbing" a character's legs.
const SPLASH_Z_CENTER := -1.0
const SPLASH_Z_SPREAD := 4.6
const SPLASH_AMOUNT := 220
const SPLASH_LIFETIME := 0.36
const SPLASH_UP_SPEED_MIN := 0.9
const SPLASH_UP_SPEED_MAX := 1.8
const SPLASH_GRAVITY := 9.5
const SPLASH_SPREAD_DEG := 55.0
const SPLASH_SIZE := Vector2(0.045, 0.3)
const SPLASH_COLOR := Color(0.90, 0.95, 1.0)
const SPLASH_ALPHA := 0.85

# --- lightning flash -----------------------------------------------------------
# How hard the shared streak material glows at set_flash(1.0). See that
# function for why this drives EMISSION rather than an ALBEDO lerp.
const FLASH_EMISSION_PEAK := 2.4

var _mat: StandardMaterial3D               # the one material shared by every band + splash

func _ready() -> void:
	var wind_dir := _wind_direction()
	_mat = _streak_material()
	for band: Dictionary in RAIN_BANDS:
		add_child(_build_rain_band(band, wind_dir, _mat))
	add_child(_build_splash_layer(wind_dir, _mat))

## Lifts the shared streak material toward a bright flash - 0.0 = storm dark
## (the authored look, untouched), 1.0 = full strike. lightning.gd calls this
## on every frame of a flash tween, alongside its other flash calls: the
## screen ColorRect, LightningLight, ParallaxBackground.set_flash(), and the
## sky's background_color (see lightning.gd's _set_flash() for the full set
## and why each one exists).
##
## The streak material stays UNSHADED (see _streak_material()) - the reviewer
## proposed shading it so LightningLight would reach it for free, but the key
## light is 0.72 and cold and ambient is 0.22, so a LIT raindrop in a scene
## this dark is a near-black raindrop; shading it would lose the rain to fix
## the flash. That also rules out lerping ALBEDO toward Tuning.STORM_SKY_FLASH
## the way ParallaxBackground.set_flash() lerps its layer_color: ALBEDO here
## multiplies against each particle's own vertex colour (see
## vertex_color_use_as_albedo below), and STORM_SKY_FLASH is darker per
## channel than the rain's own near-white ramp colours - it is tuned to lift
## the storm's near-black sky and parallax tones, not the rain's already-
## bright one - so multiplying toward it would DIM the rain on every strike,
## exactly backwards for a flash. EMISSION adds on top of the authored colour
## instead of multiplying it, so it can only brighten, nets to nothing at
## amount 0, and - because every band and the splash layer share this one
## material - mutating it touches exactly one resource no matter how many
## drops are alive.
func set_flash(amount: float) -> void:
	if _mat != null:
		_mat.emission_energy_multiplier = clampf(amount, 0.0, 1.0) * FLASH_EMISSION_PEAK

# --- shared geometry ------------------------------------------------------------

func _wind_direction() -> Vector3:
	var rad := deg_to_rad(WIND_ANGLE_DEG)
	return Vector3(sin(rad), -cos(rad), 0.0)

## Sideways drift a drop accumulates crossing the whole spawn box, at the
## shared wind angle. Widening every band's emission box by this amount keeps
## the upwind edge fed with drops that drifted in from off screen instead of
## thinning out there as the box scrolls past.
func _sideways_drift() -> float:
	return (SPAWN_TOP_Y - SPAWN_BOTTOM_Y) * tan(deg_to_rad(WIND_ANGLE_DEG))

# --- rain bands -----------------------------------------------------------------

func _build_rain_band(band: Dictionary, wind_dir: Vector3,
		mat: StandardMaterial3D) -> GPUParticles3D:
	var box_height := SPAWN_TOP_Y - SPAWN_BOTTOM_Y
	var box_center_y := (SPAWN_TOP_Y + SPAWN_BOTTOM_Y) * 0.5
	var box_half_width := VIEW_X_HALF + _sideways_drift()
	var z_spread := float(band["z_spread"])
	var speed := float(band["speed"])
	var vertical_speed := speed * cos(deg_to_rad(WIND_ANGLE_DEG))

	var p := GPUParticles3D.new()
	p.name = "Rain%s" % String(band["name"])
	p.position = Vector3(0.0, box_center_y, float(band["z"]))
	p.amount = int(band["amount"])
	p.lifetime = box_height / vertical_speed
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.5
	# GPUParticles3D built at runtime has no editor-baked visibility AABB, and
	# an unset one defaults far too small - the whole system would get frustum
	# culled the instant its (wrong) bounds left view. Pad generously; this
	# only affects culling, not draw cost.
	p.visibility_aabb = AABB(
		Vector3(-box_half_width - 1.0, -box_height * 0.5 - 1.0, -z_spread - 1.5),
		Vector3((box_half_width + 1.0) * 2.0, box_height + 2.0, (z_spread + 1.5) * 2.0))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(box_half_width, box_height * 0.5, z_spread)
	pm.direction = wind_dir
	pm.spread = 0.0                            # zero spread = every drop parallel, on spec
	pm.initial_velocity_min = speed * 0.92
	pm.initial_velocity_max = speed * 1.08
	# Constant velocity (no gravity) keeps the align-Y streak orientation
	# fixed for a drop's whole life instead of slowly rotating as it "falls".
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.8
	pm.scale_max = 1.25
	pm.particle_flag_align_y = true
	pm.color_ramp = _fade_gradient(band["color"] as Color, float(band["alpha"]))
	p.process_material = pm

	p.draw_pass_1 = _streak_mesh(float(band["width"]), float(band["length"]))
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

# --- ground splash -----------------------------------------------------------

func _build_splash_layer(wind_dir: Vector3, mat: StandardMaterial3D) -> GPUParticles3D:
	# Droplets kick up mostly straight up, nudged slightly downwind so they
	# read as being hit by the same weather rather than an unrelated effect.
	var up_dir := Vector3(wind_dir.x * 0.4, 1.0, 0.0).normalized()
	var rise := (SPLASH_UP_SPEED_MAX * SPLASH_UP_SPEED_MAX) / (2.0 * SPLASH_GRAVITY)

	var p := GPUParticles3D.new()
	p.name = "Splash"
	p.position = Vector3(0.0, GROUND_Y, SPLASH_Z_CENTER)
	p.amount = SPLASH_AMOUNT
	p.lifetime = SPLASH_LIFETIME
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.9
	p.visibility_aabb = AABB(
		Vector3(-VIEW_X_HALF - 0.5, -0.2, -SPLASH_Z_SPREAD - 0.5),
		Vector3((VIEW_X_HALF + 0.5) * 2.0, rise + 0.3, (SPLASH_Z_SPREAD + 0.5) * 2.0))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(VIEW_X_HALF, 0.02, SPLASH_Z_SPREAD)
	pm.direction = up_dir
	pm.spread = SPLASH_SPREAD_DEG
	pm.initial_velocity_min = SPLASH_UP_SPEED_MIN
	pm.initial_velocity_max = SPLASH_UP_SPEED_MAX
	pm.gravity = Vector3(0.0, -SPLASH_GRAVITY, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	# Same streak-follows-velocity trick as the rain bands; here the velocity
	# itself curves under gravity, so the flick visibly arcs as it flies.
	pm.particle_flag_align_y = true
	pm.color_ramp = _fade_gradient(SPLASH_COLOR, SPLASH_ALPHA, 0.12, 0.6)
	p.process_material = pm

	p.draw_pass_1 = _streak_mesh(SPLASH_SIZE.x, SPLASH_SIZE.y)
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

# --- shared mesh / material / gradient builders -------------------------------

## A quad in local XY (long edge along Y), the same shape BattleVfx._quad()
## uses. Lying flat in XY means it always faces this project's untilted
## camera; the process material's align-Y flag then swings that Y axis onto
## the fall direction, which is what stretches a dot into a motion-streaked
## drop with zero per-frame GDScript.
func _streak_mesh(width: float, length: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(width, length)
	return q

## Flat white + unshaded: the tint and the fade both come from each emitter's
## own color_ramp (vertex_color_use_as_albedo is what makes that ramp reach
## the material at all), so one shared material is correct for every band -
## the same split BattleVfx._burst() uses for its own gradient-driven bursts.
func _streak_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	# Flash hook (set_flash()): emission is enabled but zeroed at rest, so a
	# rain system that never sees a strike renders bit-for-bit as before.
	m.emission_enabled = true
	m.emission = Tuning.STORM_SKY_FLASH
	m.emission_energy_multiplier = 0.0
	return m

## Fades a drop in over the start of its life and out before the end. Box
## emission spawns a drop at a uniform-random point in the whole spawn volume
## (there is no "top edge" to spawn at), so this is what keeps a drop that
## happens to spawn mid-frame from popping into existence at full brightness,
## and what keeps every drop from blinking out when its lifetime simply ends.
func _fade_gradient(color: Color, alpha: float, in_frac: float = FADE_IN_FRAC,
		out_frac: float = FADE_OUT_FRAC) -> GradientTexture1D:
	var g := Gradient.new()
	var transparent := Color(color, 0.0)
	var full := Color(color, alpha)
	g.offsets = PackedFloat32Array([0.0, in_frac, out_frac, 1.0])
	g.colors = PackedColorArray([transparent, full, full, transparent])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt
