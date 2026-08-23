class_name BattleVfx
extends RefCounted
## Every one-shot visual effect in the battle. Nothing appears or disappears
## without a tween (design pillar 3).

static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

static func world() -> Node3D:
	var t := _tree()
	if t == null:
		return null
	return t.get_first_node_in_group("battle_world") as Node3D

static func overlay() -> Variant:
	var t := _tree()
	if t == null:
		return null
	return t.get_first_node_in_group("battle_overlay")

# --- generic builders -------------------------------------------------------

static func _unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m

static func _quad(size: Vector2, color: Color) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _unshaded(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## A quad that always turns to face the camera. Used for the blink afterimages,
## which have to read as figures from an overhead camera that sees them from
## any angle - a ground-plane quad would foreshorten into a sliver.
static func _billboard(size: Vector2, color: Color) -> MeshInstance3D:
	var mi := _quad(size, color)
	var m := mi.material_override as StandardMaterial3D
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return mi

## A flat ring lying on the ground. TorusMesh's axis is already +Y, so it needs
## no rotation to lie in the XZ plane.
static func _ring(inner: float, outer: float, color: Color) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 24
	t.ring_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = t
	var m := _unshaded(color)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func _set_alpha(mi: MeshInstance3D, color: Color, a: float) -> void:
	if is_instance_valid(mi):
		(mi.material_override as StandardMaterial3D).albedo_color = Color(color, a)

static func _free_after(node: Node, seconds: float) -> void:
	var t := node.get_tree().create_timer(seconds)
	await t.timeout
	if is_instance_valid(node):
		node.queue_free()

static func _burst(parent: Node3D, pos: Vector3, count: int, color_a: Color,
		color_b: Color, lifetime: float, velocity: float, mesh_size: float = 0.07,
		gravity: Vector3 = Vector3(0, -2.0, 0)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, count)
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = velocity * 0.5
	pm.initial_velocity_max = velocity
	pm.gravity = gravity
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, color_a)
	grad.set_color(1, Color(color_b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * mesh_size
	p.draw_pass_1 = bm
	p.material_override = _unshaded(Color.WHITE)
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_after(p, lifetime + 0.4)
	return p

# --- melee ------------------------------------------------------------------

static func slash_arc(target: Combatant, color: Color, to_scale: float) -> void:
	var w := world()
	if w == null:
		return
	var mi := _quad(Vector2(1.0, 0.35), color)
	w.add_child(mi)
	mi.global_position = target.hit_world_position() + Vector3(0, 0, 0.6)
	mi.rotation_degrees.z = RNG.randf_range(-30.0, 30.0)
	mi.scale = Vector3.ZERO
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * to_scale, 0.22)
	tw.tween_method(func(a: float) -> void:
			(mi.material_override as StandardMaterial3D).albedo_color = Color(color, a),
		1.0, 0.0, 0.22)
	tw.chain().tween_callback(mi.queue_free)

static func claw_arc(target: Combatant) -> void:
	var w := world()
	if w == null:
		return
	var root := Node3D.new()
	w.add_child(root)
	root.global_position = target.hit_world_position() + Vector3(0, 0, 0.6)
	root.scale = Vector3.ZERO
	for i: int in range(3):
		var blade := _quad(Vector2(1.0, 0.10), Tuning.C_SHADOW_BODY)
		root.add_child(blade)
		blade.position = Vector3(0, 0.22 * (float(i) - 1.0), 0.0)
		blade.rotation_degrees.z = -18.0
		var edge := _quad(Vector2(1.0, 0.03), Tuning.C_SHADOW_EYES)
		root.add_child(edge)
		edge.position = Vector3(0, 0.22 * (float(i) - 1.0) - 0.055, 0.01)
		edge.rotation_degrees.z = -18.0
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(root, "scale", Vector3.ONE * 1.2, 0.25)
	tw.tween_method(Callable(BattleVfx, "_fade_children").bind(root), 1.0, 0.0, 0.25)
	tw.chain().tween_callback(root.queue_free)

static func _fade_children(alpha: float, root: Node3D) -> void:
	if not is_instance_valid(root):
		return
	for child: Node in root.get_children():
		var m := (child as MeshInstance3D).material_override as StandardMaterial3D
		m.albedo_color.a = alpha

static func dust_puff(target: Combatant, count: int) -> void:
	dust_puff_at(target.global_position + Vector3(0, 0.06, 0.3), count)

static func dust_puff_at(pos: Vector3, count: int) -> void:
	var w := world()
	if w == null:
		return
	_burst(w, pos, count, Color(Tuning.C_GROUND, 0.9), Tuning.C_GROUND, 0.5, 1.4, 0.09)

static func smoke_burst(source: Combatant) -> void:
	var wisps := source.rig.get_node_or_null("SmokeWisps")
	if wisps == null:
		return
	(wisps as GPUParticles3D).amount_ratio = 1.0
	var t := source.get_tree().create_timer(0.3)
	await t.timeout
	if is_instance_valid(wisps):
		(wisps as GPUParticles3D).amount_ratio = 0.5

static func death_burst(c: Combatant) -> void:
	var w := world()
	if w == null:
		return
	_burst(w, c.hit_world_position(), 16, Color(c.stats.body_color, 1.0),
		c.stats.body_color, 0.7, 2.4, 0.10)

# --- blink step (melee teleport) --------------------------------------------
## A melee attacker does not run at its target across the field, it blinks to
## it. The effect is three beats, and each one exists to answer a question the
## player would otherwise ask:
##
##   out    - "where did it go?"      a ground ring snaps outward, the figure
##                                    dissolves upward into motes, and a light
##                                    column marks the spot it left.
##   trail  - "how did it get there?" a ground streak plus a row of fading
##                                    afterimages draws the actual path, so
##                                    the move reads as travel, not a cut.
##   in     - "what just arrived?"    a ring implodes onto the landing spot and
##                                    the figure reforms out of it.
##
## Origin and destination are both passed in because the combatant has usually
## already been moved by the time the trail is drawn.

static func blink_out(c: Combatant, color: Color) -> void:
	var w := world()
	if w == null or not is_instance_valid(c):
		return
	var foot := c.global_position

	var ring := _ring(0.16, 0.30, Color(color, 0.95))
	w.add_child(ring)
	ring.global_position = foot + Vector3(0, 0.04, 0)
	ring.scale = Vector3(0.4, 0.4, 0.4)
	var rt := ring.create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector3(3.4, 1.0, 3.4), Tuning.TELEPORT_OUT_TIME * 1.6)
	rt.tween_method(func(a: float) -> void: _set_alpha(ring, color, a),
		0.95, 0.0, Tuning.TELEPORT_OUT_TIME * 1.6)
	rt.chain().tween_callback(ring.queue_free)

	# The column is what makes the departure read as "upward", which is what
	# stops it looking like the model was simply hidden.
	var col := CylinderMesh.new()
	col.top_radius = 0.30
	col.bottom_radius = 0.42
	col.height = 2.4
	col.radial_segments = 10
	var shaft := MeshInstance3D.new()
	shaft.mesh = col
	var sm := _unshaded(Color(color, 0.7))
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shaft.material_override = sm
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(shaft)
	shaft.global_position = foot + Vector3(0, 1.2, 0)
	var st := shaft.create_tween().set_parallel(true)
	st.tween_property(shaft, "scale", Vector3(0.15, 1.9, 0.15), Tuning.TELEPORT_OUT_TIME * 1.5)
	st.tween_method(func(a: float) -> void: _set_alpha(shaft, color, a),
		0.7, 0.0, Tuning.TELEPORT_OUT_TIME * 1.5)
	st.chain().tween_callback(shaft.queue_free)

	_burst(w, foot + Vector3(0, 0.9, 0), 20, Color(color, 1.0), color, 0.45, 2.6, 0.07,
		Vector3(0, 2.4, 0))                       # motes rise, they do not fall

static func blink_in(c: Combatant, color: Color) -> void:
	var w := world()
	if w == null or not is_instance_valid(c):
		return
	var foot := c.global_position

	# Imploding, not expanding - the mirror of blink_out's ring, which is what
	# ties the two ends of the move together.
	var ring := _ring(0.16, 0.30, Color(color, 0.0))
	w.add_child(ring)
	ring.global_position = foot + Vector3(0, 0.04, 0)
	ring.scale = Vector3(3.6, 1.0, 3.6)
	var rt := ring.create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector3(0.5, 0.5, 0.5), Tuning.TELEPORT_IN_TIME * 1.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	rt.tween_method(func(a: float) -> void: _set_alpha(ring, color, a),
		0.1, 1.0, Tuning.TELEPORT_IN_TIME * 1.3)
	rt.chain().tween_callback(ring.queue_free)

	var flash := _billboard(Vector2(1.7, 1.7), Color(color, 0.85))
	w.add_child(flash)
	flash.global_position = foot + Vector3(0, 1.0, 0)
	flash.scale = Vector3.ZERO
	var ft := flash.create_tween().set_parallel(true)
	ft.tween_property(flash, "scale", Vector3.ONE * 1.5, 0.16)
	ft.tween_method(func(a: float) -> void: _set_alpha(flash, color, a), 0.85, 0.0, 0.16)
	ft.chain().tween_callback(flash.queue_free)

	dust_puff_at(foot + Vector3(0, 0.05, 0), 10)

## The path itself: a bright streak along the ground plus TELEPORT_GHOSTS
## afterimages of the figure, each fading on a stagger so the eye reads the
## direction of travel rather than a row of static copies.
static func blink_trail(from: Vector3, to: Vector3, color: Color) -> void:
	var w := world()
	if w == null:
		return
	var flat := to - from
	flat.y = 0.0
	var dist := flat.length()
	if dist < 0.05:
		return

	var streak := _quad(Vector2(dist, 0.32), Color(color, 0.75))
	(streak.material_override as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	w.add_child(streak)
	streak.global_position = from.lerp(to, 0.5) + Vector3(0, 0.05, 0)
	streak.rotation = Vector3(-PI * 0.5, atan2(-flat.z, flat.x), 0.0)
	var stw := streak.create_tween().set_parallel(true)
	stw.tween_property(streak, "scale", Vector3(1.0, 0.15, 1.0), Tuning.TELEPORT_GHOST_FADE)
	stw.tween_method(func(a: float) -> void: _set_alpha(streak, color, a),
		0.8, 0.0, Tuning.TELEPORT_GHOST_FADE)
	stw.chain().tween_callback(streak.queue_free)

	# The afterimages are tapered COLUMNS, not billboarded quads. A flat quad
	# seen from a camera 55 degrees above it is a hard-edged rectangle lying at
	# an angle to the streak, and five of them in a row read as a staircase of
	# glowing boxes rather than as a figure smearing through space. A column has
	# real form from any angle, and at roughly a character's width and height it
	# reads as the shape of the person who just left.
	for i: int in range(Tuning.TELEPORT_GHOSTS):
		var t := (float(i) + 1.0) / float(Tuning.TELEPORT_GHOSTS + 1)
		var body := CylinderMesh.new()
		body.top_radius = 0.10
		body.bottom_radius = 0.26
		body.height = 1.55
		body.radial_segments = 8
		body.rings = 1
		var ghost := MeshInstance3D.new()
		ghost.mesh = body
		var gm := _unshaded(Color(color, 0.5))
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		ghost.material_override = gm
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.add_child(ghost)
		ghost.global_position = from.lerp(to, t) + Vector3(0, 0.80, 0)
		# Later ghosts hold slightly longer, so the smear resolves toward the
		# destination instead of collapsing evenly.
		var life: float = Tuning.TELEPORT_GHOST_FADE * (0.55 + 0.45 * t)
		var gt := ghost.create_tween().set_parallel(true)
		gt.tween_method(func(a: float) -> void: _set_alpha(ghost, color, a), 0.5, 0.0, life)
		gt.tween_property(ghost, "scale", Vector3(0.45, 1.2, 0.45), life)
		gt.chain().tween_callback(ghost.queue_free)

# --- priest / slot lightning ------------------------------------------------

static func darken_pass(source: Combatant) -> void:
	var w := world()
	if w == null:
		return
	var env: Environment = (w.get_node("WorldEnvironment") as WorldEnvironment).environment
	var tw := source.create_tween()
	tw.tween_property(env, "adjustment_brightness", 0.55, 0.12)
	tw.tween_interval(0.18)
	tw.tween_property(env, "adjustment_brightness", 1.0, 0.25)

static func warning_glow(target: Combatant) -> void:
	var w := world()
	if w == null:
		return
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = _unshaded(Color(Tuning.C_LIGHTNING, 0.6))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(mi)
	mi.global_position = target.hit_world_position() + Vector3(0, 0.7, 0)
	mi.scale = Vector3.ZERO
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.20)
	tw.tween_property(mi, "scale", Vector3.ZERO, 0.15)
	tw.tween_callback(mi.queue_free)

## The jagged bolt of spec 9.3, reused verbatim by the slot's lightning payout
## (spec 16.5) - minus the darkening pass, which the slot never runs.
static func lightning_bolt(_director, target: Combatant, color: Color) -> void:
	var w := world()
	if w == null or target == null:
		return
	var end := target.hit_world_position()
	var start := Vector3(end.x, 5.2, end.z)

	var points: Array[Vector3] = []
	var segments := 6
	for i: int in range(segments + 1):
		var t := float(i) / float(segments)
		var p := start.lerp(end, t)
		if i > 0 and i < segments:
			p.x += RNG.randf_range(-0.22, 0.22)
			p.z += RNG.randf_range(-0.22, 0.22)
		points.append(p)

	var core := _ribbon(points, 0.14, Color.WHITE)
	var glow := _ribbon(points, 0.26, color)
	w.add_child(glow)
	w.add_child(core)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 8.0
	light.omni_range = 5.0
	w.add_child(light)
	light.global_position = end

	var flash := _quad(Vector2(1.0, 1.0), Color(Color.WHITE, 0.9))
	w.add_child(flash)
	flash.global_position = Vector3(end.x, 0.02, end.z)
	flash.rotation_degrees.x = -90.0
	flash.scale = Vector3.ONE * 0.3

	_burst(w, end, 24, Color(color, 1.0), color, 0.5, 3.0, 0.08)

	var tw := core.create_tween().set_parallel(true)
	tw.tween_method(func(a: float) -> void:
			if is_instance_valid(core):
				(core.material_override as StandardMaterial3D).albedo_color = Color(Color.WHITE, a)
			if is_instance_valid(glow):
				(glow.material_override as StandardMaterial3D).albedo_color = Color(color, a * 0.8),
		1.0, 0.0, 0.28)
	tw.tween_property(light, "light_energy", 0.0, 0.30)
	tw.tween_property(flash, "scale", Vector3.ONE * 2.0, 0.30)
	tw.tween_method(func(a: float) -> void:
			if is_instance_valid(flash):
				(flash.material_override as StandardMaterial3D).albedo_color = Color(Color.WHITE, a),
		0.9, 0.0, 0.30)
	tw.chain().tween_callback(func() -> void:
		for n: Node in [core, glow, light, flash]:
			if is_instance_valid(n):
				n.queue_free())

static func _ribbon(points: Array[Vector3], width: float, color: Color) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p: Vector3 in points:
		im.surface_set_normal(Vector3(0, 0, 1))
		im.surface_add_vertex(p + Vector3(-width * 0.5, 0, 0))
		im.surface_set_normal(Vector3(0, 0, 1))
		im.surface_add_vertex(p + Vector3(width * 0.5, 0, 0))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = _unshaded(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

# --- projectiles ------------------------------------------------------------

static func arrow_sparks(pos: Vector3) -> void:
	var w := world()
	if w == null:
		return
	_burst(w, pos, 8, Color(Tuning.C_PRIEST_CLOTH, 1.0), Tuning.C_PRIEST_CLOTH, 0.35, 2.0, 0.05)

## Where an aimed spell lands. Deliberately lighter than explosion(): the
## priest's primary fires every couple of seconds, so its impact has to read
## instantly without dominating the frame the way a bomb arrow should.
static func magic_burst(pos: Vector3, color: Color) -> void:
	var w := world()
	if w == null:
		return
	var s := SphereMesh.new()
	s.radius = 0.4
	s.height = 0.8
	s.radial_segments = 10
	s.rings = 6
	var shell := MeshInstance3D.new()
	shell.mesh = s
	var m := _unshaded(Color(color, 0.85))
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shell.material_override = m
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(shell)
	shell.global_position = pos
	shell.scale = Vector3.ONE * 0.3

	var ring := _ring(0.2, 0.34, Color(color, 0.9))
	w.add_child(ring)
	ring.global_position = Vector3(pos.x, 0.05, pos.z)
	ring.scale = Vector3(0.4, 0.4, 0.4)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.5
	light.omni_range = 3.4
	w.add_child(light)
	light.global_position = pos

	_burst(w, pos, 18, Color(color, 1.0), color, 0.45, 2.8, 0.07)

	var tw := shell.create_tween().set_parallel(true)
	tw.tween_property(shell, "scale", Vector3.ONE * 1.9, 0.26)
	tw.tween_method(func(a: float) -> void: _set_alpha(shell, color, a), 0.85, 0.0, 0.26)
	tw.tween_property(ring, "scale", Vector3(2.6, 1.0, 2.6), 0.30)
	tw.tween_method(func(a: float) -> void: _set_alpha(ring, color, a), 0.9, 0.0, 0.30)
	tw.tween_property(light, "light_energy", 0.0, 0.28)
	tw.chain().tween_callback(func() -> void:
		for n: Node in [shell, ring, light]:
			if is_instance_valid(n):
				n.queue_free())

static func explosion(pos: Vector3) -> void:
	var w := world()
	if w == null:
		return
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	var shell := MeshInstance3D.new()
	shell.mesh = s
	shell.material_override = _unshaded(Color(Tuning.C_GOLD, 0.9))
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(shell)
	shell.global_position = pos
	shell.scale = Vector3.ONE * 0.2

	var light := OmniLight3D.new()
	light.light_color = Tuning.C_GOLD
	light.light_energy = 6.0
	light.omni_range = 4.0
	w.add_child(light)
	light.global_position = pos

	_burst(w, pos, 30, Color(Tuning.C_DANGER, 1.0), Tuning.C_GOLD, 0.6, 4.0, 0.10)

	var tw := shell.create_tween().set_parallel(true)
	tw.tween_property(shell, "scale", Vector3.ONE * 2.6, 0.30)
	tw.tween_method(func(a: float) -> void:
			if is_instance_valid(shell):
				(shell.material_override as StandardMaterial3D).albedo_color = Color(Tuning.C_GOLD, a),
		0.9, 0.0, 0.30)
	tw.tween_property(light, "light_energy", 0.0, 0.30)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(shell):
			shell.queue_free()
		if is_instance_valid(light):
			light.queue_free())

	var w3 := world()
	if w3 != null and w3.has_method("shake"):
		w3.call("shake", 0.06, 0.20)

# --- overlay pass-throughs --------------------------------------------------

static func defend_icon(c: Combatant, duration: float) -> void:
	var o: Variant = overlay()
	if o != null:
		o.spawn_status_icon(c, "defend", duration)

static func heal_icon(c: Combatant, amount: int) -> void:
	var o: Variant = overlay()
	if o != null:
		o.spawn_status_icon(c, "heal", 0.70)
		o.spawn_number(c, "+%d" % amount, Tuning.C_HEAL)

static func gold_burst(pos: Vector3) -> void:
	var w := world()
	if w == null:
		return
	_burst(w, pos, 40, Color(Tuning.C_GOLD, 1.0), Tuning.C_GOLD, 1.0, 3.5, 0.09,
		Vector3(0, -4.0, 0))
