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

# --- shader warm-up (spec smoothness pass, suggestion 1) --------------------
## Every StandardMaterial3D this file builds is one of three feature
## combinations - see _unshaded/_billboard/_ring below - and on the
## Compatibility (WebGL2) backend the web build ships with, each distinct
## combination is its own compiled shader variant. Until now the first frame
## that needed a given combination was whichever spell or blink happened to
## fire it first mid-combat - the 402ms and 352ms freezes the smoothness
## analysis measured at the first lightning strike and the first blink.
##
## This renders one throwaway, sub-pixel instance of each combination (plus
## the ParticleProcessMaterial every _burst() call shares) so the compiles
## land once, here, instead of on the first real cast. It has to actually be
## drawn - Godot compiles a variant lazily on the frame something using it is
## rasterized, not merely when the material is constructed - so the warm-up
## rig is placed in view at a scale of 0.001, not disabled or frustum-culled,
## and freed two frames later once the draw has happened.
static func warm_up(parent: Node3D) -> void:
	if parent == null:
		return
	var rig := Node3D.new()
	rig.name = &"VfxWarmup"
	parent.add_child(rig)
	rig.scale = Vector3.ONE * 0.001

	rig.add_child(_quad(Vector2.ONE, Color.WHITE))         # base: unshaded+alpha
	rig.add_child(_billboard(Vector2.ONE, Color.WHITE))    # + billboard + add-blend
	rig.add_child(_ring(0.1, 0.2, Color.WHITE))             # + add-blend (no billboard)
	_burst(Vector3.ZERO, 1, Color.WHITE, Color.WHITE, 0.05, 0.1)

	var t := _tree()
	if t != null:
		await t.process_frame
		await t.process_frame
	if is_instance_valid(rig):
		rig.queue_free()

# --- shared meshes (spec smoothness pass, suggestion 2) ---------------------
## The vertex data for these shapes depends on nothing but the handful of
## fixed dimensions every call site already hard-codes (a ring is always
## 0.16/0.30 or 0.2/0.34, a ghost cylinder is always the same silhouette), so
## building it fresh on every cast was buying nothing but a repeat GPU buffer
## upload. Keying a cache off those dimensions means the mesh is built once
## per distinct shape, ever, the same way warm_up() above makes shader
## *variants* the unit of cost instead of shader *instances*. Colour and alpha
## stay off this cache and stay per-material - those genuinely differ and
## animate call to call.
##
## Safe to key indefinitely because every caller below passes literal
## constants, never a runtime-computed value (the one shape that does vary
## continuously - the blink-trail streak's length - deliberately does not use
## this cache; see _quad()'s `cache` parameter).
static var _mesh_cache: Dictionary = {}   # key:String -> Mesh

static func _cached_mesh(key: String, builder: Callable) -> Mesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = builder.call()
	return _mesh_cache[key]

static func _quad_mesh(size: Vector2) -> QuadMesh:
	return _cached_mesh("quad:%s" % size, func() -> QuadMesh:
		var q := QuadMesh.new()
		q.size = size
		return q) as QuadMesh

static func _torus_mesh(inner: float, outer: float) -> TorusMesh:
	return _cached_mesh("torus:%s:%s" % [inner, outer], func() -> TorusMesh:
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 24
		t.ring_segments = 6
		return t) as TorusMesh

static func _cylinder_mesh(top_r: float, bottom_r: float, height: float,
		radial_segments: int, rings: int = 0) -> CylinderMesh:
	return _cached_mesh("cyl:%s:%s:%s:%s:%s" % [top_r, bottom_r, height, radial_segments, rings],
		func() -> CylinderMesh:
			var c := CylinderMesh.new()
			c.top_radius = top_r
			c.bottom_radius = bottom_r
			c.height = height
			c.radial_segments = radial_segments
			c.rings = rings
			return c) as CylinderMesh

static func _sphere_mesh(radius: float, height: float, radial_segments: int = 32,
		rings: int = 16) -> SphereMesh:
	return _cached_mesh("sph:%s:%s:%s:%s" % [radius, height, radial_segments, rings],
		func() -> SphereMesh:
			var s := SphereMesh.new()
			s.radius = radius
			s.height = height
			s.radial_segments = radial_segments
			s.rings = rings
			return s) as SphereMesh

static func _box_mesh(size: float) -> BoxMesh:
	return _cached_mesh("box:%s" % size, func() -> BoxMesh:
		var b := BoxMesh.new()
		b.size = Vector3.ONE * size
		return b) as BoxMesh

# --- pooling (spec smoothness pass, suggestion 2) ---------------------------
## Ghosts, lightning ribbons and burst particles are the highest-churn effects
## in the file - a single melee round trip allocates and frees ten ghost
## meshes and four particle systems, each with its own process material and
## gradient texture, and that repeats every attack for the length of a fight.
## Pooling by "kind" keeps a free list of already-built nodes per kind instead
## of new()/queue_free() on every use: acquire() pulls a node from the list
## (building one, once, the first time a kind is needed) and _release_after()
## hides it and returns it to the list instead of freeing it.
##
## Everything pooled lives permanently under _pool_parent(), a plain Node3D at
## the battle world's origin - callers only ever set global_position, so which
## Node3D happens to parent a pooled effect is invisible to the result. A
## fresh battle world (new encounter, new run) invalidates the old pool root
## along with it; is_instance_valid() in acquire() discards the now-dead
## entries instead of handing back a freed node.
static var _pool_root: Node3D = null
static var _pool_free: Dictionary = {}   # kind:String -> Array[Node]

static func _pool_parent() -> Node3D:
	if _pool_root != null and is_instance_valid(_pool_root):
		return _pool_root
	var w := world()
	if w == null:
		return null
	_pool_root = Node3D.new()
	_pool_root.name = &"VfxPool"
	w.add_child(_pool_root)
	_pool_free.clear()   # the old root's nodes died with it; stop tracking them
	return _pool_root

## Every acquired node comes back already parented and already invisible-until-
## the-caller-says-otherwise is NOT guaranteed - callers are responsible for
## setting `visible = true` and resetting every property their tween touches
## (colour, alpha, scale...) before use, since a reused node still carries
## whatever end state its last use tweened it to.
static func _acquire(kind: String, builder: Callable) -> Node:
	var list: Array = _pool_free.get(kind, [])
	while not list.is_empty():
		var n: Node = list.pop_back()
		if is_instance_valid(n):
			return n
	var made: Node = builder.call()
	made.set_meta(&"vfx_pool_kind", kind)
	var parent := _pool_parent()
	if parent != null:
		parent.add_child(made)
	return made

static func _release(n: Node) -> void:
	if not is_instance_valid(n):
		return
	n.visible = false
	if n is GPUParticles3D:
		(n as GPUParticles3D).emitting = false
	var kind: String = n.get_meta(&"vfx_pool_kind", "")
	var list: Array = _pool_free.get(kind, [])
	list.append(n)
	_pool_free[kind] = list

static func _release_after(n: Node, seconds: float) -> void:
	var t: SceneTree = n.get_tree()
	if t == null:
		return
	await t.create_timer(seconds).timeout
	_release(n)

# --- generic builders -------------------------------------------------------

static func _unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m

## `cache` shares the underlying QuadMesh across every call with the same
## size (see _quad_mesh() above); pass false for a size that is computed at
## call time rather than a fixed constant (blink_trail's streak is the only
## one - its length depends on the distance travelled, which never repeats
## exactly, so caching it would just grow the cache forever for no reuse).
static func _quad(size: Vector2, color: Color, cache: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if cache:
		mi.mesh = _quad_mesh(size)
	else:
		var q := QuadMesh.new()
		q.size = size
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
	var mi := MeshInstance3D.new()
	mi.mesh = _torus_mesh(inner, outer)
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

## The single highest-churn effect in the file before pooling: four calls per
## melee round trip, each previously building a brand-new GPUParticles3D, a
## brand-new ParticleProcessMaterial, a brand-new Gradient plus the
## GradientTexture1D it uploads to the GPU, and a brand-new BoxMesh. Only the
## colour ramp, velocity range, gravity, lifetime, amount and box size differ
## call to call - the emission shape, direction and spread never do - so a
## pooled particle system just has those fields rewritten on every acquire
## instead of the whole node graph rebuilt.
static func _burst(pos: Vector3, count: int, color_a: Color,
		color_b: Color, lifetime: float, velocity: float, mesh_size: float = 0.07,
		gravity: Vector3 = Vector3(0, -2.0, 0)) -> GPUParticles3D:
	var p := _acquire("burst", func() -> GPUParticles3D:
		var particles := GPUParticles3D.new()
		particles.one_shot = true
		particles.explosiveness = 1.0
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.12
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 180.0
		pm.scale_min = 0.6
		pm.scale_max = 1.2
		var grad := Gradient.new()
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		pm.color_ramp = gt
		particles.process_material = pm
		particles.material_override = _unshaded(Color.WHITE)
		return particles) as GPUParticles3D

	var pm := p.process_material as ParticleProcessMaterial
	pm.initial_velocity_min = velocity * 0.5
	pm.initial_velocity_max = velocity
	pm.gravity = gravity
	var grad: Gradient = (pm.color_ramp as GradientTexture1D).gradient
	grad.set_color(0, color_a)
	grad.set_color(1, Color(color_b, 0.0))
	p.amount = maxi(1, count)
	p.lifetime = lifetime
	p.draw_pass_1 = _box_mesh(mesh_size)

	p.visible = true
	p.global_position = pos
	p.restart()   # clears any particles left over from the last use of this node
	p.emitting = true
	_release_after(p, lifetime + 0.4)
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
	_burst(pos, count, Color(Tuning.C_GROUND, 0.9), Tuning.C_GROUND, 0.5, 1.4, 0.09)

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
	_burst(c.hit_world_position(), 16, Color(c.stats.body_color, 1.0),
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
	var shaft := MeshInstance3D.new()
	shaft.mesh = _cylinder_mesh(0.30, 0.42, 2.4, 10)
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

	_burst(foot + Vector3(0, 0.9, 0), 20, Color(color, 1.0), color, 0.45, 2.6, 0.07,
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

	# Not cached: dist is a runtime distance between two arbitrary positions,
	# so it is (almost) never the same value twice - see _quad()'s doc.
	var streak := _quad(Vector2(dist, 0.32), Color(color, 0.75), false)
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
	#
	# Pooled (spec smoothness pass, suggestion 2): always exactly
	# TELEPORT_GHOSTS, always the same mesh, twice per attack - the doc's
	# "obvious first candidate". Every animated property (scale, alpha) is
	# reset below before this ghost's tween starts, since a pooled node still
	# carries whatever its last use tweened it to.
	for i: int in range(Tuning.TELEPORT_GHOSTS):
		var t := (float(i) + 1.0) / float(Tuning.TELEPORT_GHOSTS + 1)
		var ghost := _acquire("ghost", func() -> MeshInstance3D:
			var mi := MeshInstance3D.new()
			mi.mesh = _cylinder_mesh(0.10, 0.26, 1.55, 8, 1)
			mi.material_override = _unshaded(Color.WHITE)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return mi) as MeshInstance3D
		var gm := ghost.material_override as StandardMaterial3D
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		gm.albedo_color = Color(color, 0.5)
		ghost.visible = true
		ghost.scale = Vector3.ONE
		ghost.global_position = from.lerp(to, t) + Vector3(0, 0.80, 0)
		# Later ghosts hold slightly longer, so the smear resolves toward the
		# destination instead of collapsing evenly.
		var life: float = Tuning.TELEPORT_GHOST_FADE * (0.55 + 0.45 * t)
		var gt := ghost.create_tween().set_parallel(true)
		gt.tween_method(func(a: float) -> void: _set_alpha(ghost, color, a), 0.5, 0.0, life)
		gt.tween_property(ghost, "scale", Vector3(0.45, 1.2, 0.45), life)
		gt.chain().tween_callback(Callable(BattleVfx, "_release").bind(ghost))

# --- mage / slot lightning ---------------------------------------------------

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
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere_mesh(0.5, 1.0)
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
##
## The core and glow ribbons are pooled (spec smoothness pass, suggestion 2):
## each strike's jagged path is unique, so the underlying ImmediateMesh cannot
## be shared the way the fixed-parameter shapes above are, but the mesh
## *object*, its material and the node can be - clear_surfaces() plus a fresh
## surface_begin/surface_end rewrites the geometry in place instead of
## allocating a new GPU buffer on every strike, which the slot's lightning
## payout can trigger often enough to matter.
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

	_burst(end, 24, Color(color, 1.0), color, 0.5, 3.0, 0.08)

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
		_release(core)
		_release(glow)
		for n: Node in [light, flash]:
			if is_instance_valid(n):
				n.queue_free())

static func _ribbon(points: Array[Vector3], width: float, color: Color) -> MeshInstance3D:
	var mi := _acquire("ribbon", func() -> MeshInstance3D:
		var node := MeshInstance3D.new()
		node.mesh = ImmediateMesh.new()
		node.material_override = _unshaded(Color.WHITE)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return node) as MeshInstance3D

	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p: Vector3 in points:
		im.surface_set_normal(Vector3(0, 0, 1))
		im.surface_add_vertex(p + Vector3(-width * 0.5, 0, 0))
		im.surface_set_normal(Vector3(0, 0, 1))
		im.surface_add_vertex(p + Vector3(width * 0.5, 0, 0))
	im.surface_end()

	(mi.material_override as StandardMaterial3D).albedo_color = Color(color, 1.0)
	mi.visible = true
	return mi

# --- projectiles ------------------------------------------------------------

static func arrow_sparks(pos: Vector3) -> void:
	_burst(pos, 8, Color(Tuning.C_MAGE_CLOTH, 1.0), Tuning.C_MAGE_CLOTH, 0.35, 2.0, 0.05)

## Where an aimed spell lands. Deliberately lighter than explosion(): the
## mage's primary fires every couple of seconds, so its impact has to read
## instantly without dominating the frame the way a bomb arrow should.
static func magic_burst(pos: Vector3, color: Color) -> void:
	var w := world()
	if w == null:
		return
	var shell := MeshInstance3D.new()
	shell.mesh = _sphere_mesh(0.4, 0.8, 10, 6)
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

	_burst(pos, 18, Color(color, 1.0), color, 0.45, 2.8, 0.07)

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
	var shell := MeshInstance3D.new()
	shell.mesh = _sphere_mesh(0.5, 1.0)
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

	_burst(pos, 30, Color(Tuning.C_DANGER, 1.0), Tuning.C_GOLD, 0.6, 4.0, 0.10)

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
	_burst(pos, 40, Color(Tuning.C_GOLD, 1.0), Tuning.C_GOLD, 1.0, 3.5, 0.09,
		Vector3(0, -4.0, 0))
