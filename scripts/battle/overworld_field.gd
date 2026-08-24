extends Node3D
## The open field the party runs across (overworld prototype). Replaces the
## five faked-parallax layers, which existed only because an orthographic
## side-on camera gives no free parallax. An overhead camera looks at real
## ground, so this is real ground: one large plane plus a few hundred
## decorative props scattered over it.
##
## Scrolling works the way the old parallax did, generalised from "the X axis"
## to "Tuning.RUN_DIR": the party never actually moves, the field slides back
## down the run axis underneath it. Three copies of the scatter are laid end to
## end along that axis and each wraps to the far end when it falls off the near
## one, so the field is endless while the mesh data stays finite.
##
## Every prop is a MultiMesh instance, not a node. The scatter is ~330 props
## and a tree is eight meshes on its own, so a node-per-prop version would be
## ~500 Node3Ds to move every frame; this is one position write per
## MultiMeshInstance per copy instead - a few dozen in total.

## Source art. Bushes and grass blades come out of the brush tile, rocks and
## tufts out of the ground tile - the same two .glb files parallax layers 4-5
## used, so the only new environment asset here is the tree.
const BRUSH_TILE := preload("res://assets/meshes/env_brush.glb")
const GROUND_TILE := preload("res://assets/meshes/env_ground.glb")
const TREE_PROP := preload("res://assets/meshes/env_tree.glb")
## [presentation redesign S10.1] Crystal clusters - authored in Blender,
## coloured emissive in code rather than in the .glb (see _crystal_material()),
## so glow tuning is a Godot-side reload instead of a Blender re-export.
const CRYSTAL_TILE := preload("res://assets/meshes/env_crystal.glb")
## [ui-project-longshot] The rune archway on the horizon. Two mesh prefixes:
## Env_ArchStone* takes a hazed stone material, Env_ArchGlow* an unshaded
## emissive one, so the ring recedes into the fog while the light in it does
## not. See _build_archway().
const ARCH_PROP := preload("res://assets/meshes/env_arch.glb")

## Same reasoning as Tuning.PARALLAX_TILE_COPIES: two copies can leave a gap at
## the far edge for one frame during a wrap, three never can.
const FIELD_COPIES := 3

var scroll_speed: float = 0.0            # 0 = stopped; RunController tweens this

## One entry per distinct source mesh: {copies: Array[MultiMeshInstance3D]}.
var _groups: Array[Dictionary] = []
## How far the field has slid down the run axis, before wrapping.
var _offset: float = 0.0

var _perp: Vector3 = Tuning.RUN_DIR.cross(Vector3.UP).normalized()
## Where the fight's corridor sits on the across axis. Derived from the party
## anchor rather than assumed to be zero: moving along RUN_DIR does not change
## a point's across coordinate, so this one number is the lane BOTH the party
## and the enemy rank stand in, and it is what the scatter has to keep clear.
var _lane: float = Tuning.PARTY_ANCHOR.dot(Tuning.RUN_DIR.cross(Vector3.UP).normalized())

func _ready() -> void:
	_build_ground()
	_build_path()
	_build_scatter()
	_build_backdrop()
	_build_archway()
	_build_motes()

func _process(delta: float) -> void:
	if is_zero_approx(scroll_speed):
		return
	_offset = fposmod(_offset + scroll_speed * delta, Tuning.FIELD_ALONG * float(FIELD_COPIES))
	_apply_offset()

## Puts the field back to its starting offset - the retry path's job (spec
## 18.3 step 4). Never rebuilds the scatter: it is seeded and deterministic, so
## rebuilding it would be pure waste.
func reset_tiles() -> void:
	_offset = 0.0
	_apply_offset()

## The old parallax's `advance_tiles`, kept so Debug's `parallax` verb still
## has something to drive.
func advance_tiles(units: float) -> void:
	_offset = fposmod(_offset + units, Tuning.FIELD_ALONG * float(FIELD_COPIES))
	_apply_offset()

func _apply_offset() -> void:
	var span: float = Tuning.FIELD_ALONG * float(FIELD_COPIES)
	for group: Dictionary in _groups:
		var copies: Array = group["copies"]
		for i: int in range(copies.size()):
			# Copy i sits one field-length further up-run than copy i-1, and the
			# whole stack slides back down -RUN_DIR by _offset. fposmod keeps
			# each copy inside [-FIELD_ALONG, span - FIELD_ALONG).
			var along: float = fposmod(
				float(i) * Tuning.FIELD_ALONG - _offset + Tuning.FIELD_ALONG, span) \
				- Tuning.FIELD_ALONG
			(copies[i] as MultiMeshInstance3D).position = Tuning.RUN_DIR * along

# --- ground -------------------------------------------------------------------

## One flat plane, wide enough to reach past the horizon at this camera tilt.
## It deliberately does NOT scroll: a plane of a single flat colour looks
## identical at every offset, so moving it would be work with no pixels to show
## for it. All the sense of motion comes from the props sliding across it.
##
## The material is a plain OPAQUE StandardMaterial3D, and that is load-bearing -
## do not "make it consistent" by switching it to CelMaterials.cel(). That
## shader is `blend_mix, depth_draw_always` (see cel_shade.gdshader's own note
## on why), so anything using it lands in the TRANSPARENT pass. Transparent
## objects sort back-to-front by their origin, and this plane's origin sits
## right in the middle of the fight - so a cel-shaded ground draws after, and
## on top of, every transparent surface whose origin is further away. The
## shadow monster's smoke shader is `depth_draw_never`, leaving no depth for
## the plane to test against, so it was painted over completely: eyes visible,
## body gone. A one-normal plane gets exactly one flat band out of a cel shader
## anyway, so this costs nothing visually.
func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Tuning.C_GROUND
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(0, -0.01, 0)      # just under the props, to stop z-fighting
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## [ui-project-longshot] The lit path the party runs down. FIELD_CLEAR_RADIUS
## already keeps this corridor free of props (that is what it is for) - until
## now the result was a bald stripe of the same green as everywhere else,
## which read as a gap in the scatter rather than as a road. This paints it.
##
## Like the ground plane it does NOT scroll, and for the same reason: a strip
## of one flat colour looks identical at every offset. The flagstones laid on
## it in _build_scatter() are what actually carry the motion.
##
## Deliberately a hair narrower than FIELD_CLEAR_RADIUS * 2 so the undergrowth
## crowds over the path's edge - a road whose edge exactly meets the treeline
## in a ruler-straight line reads as level geometry, not as a worn trail.
func _build_path() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(Tuning.PATH_WIDTH, Tuning.FIELD_ALONG * float(FIELD_COPIES) * 1.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Tuning.PATH_COLOR
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "Path"
	mi.mesh = plane
	mi.material_override = mat
	# PlaneMesh spans its X by size.x, so rotating X onto the across-axis puts
	# its length onto the run axis - the same yaw convention every prop uses.
	mi.transform = Transform3D(
		Basis(Vector3.UP, Tuning.yaw_along(_perp)),
		_perp * _lane + Vector3(0.0, 0.005, 0.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# --- scatter ------------------------------------------------------------------

func _build_scatter() -> void:
	_groups.clear()
	var rand := RandomNumberGenerator.new()
	rand.seed = Tuning.FIELD_SCATTER_SEED

	# Ground-hugging clutter first; the tree canopies draw over it.
	_scatter(_palette(GROUND_TILE, "Env_Tuft"), Tuning.FIELD_TUFTS, rand, 0.75, 1.5, false)
	_scatter(_palette(BRUSH_TILE, "Env_GrassBlade"), Tuning.FIELD_GRASS, rand, 0.7, 1.6, false)
	_scatter(_palette(GROUND_TILE, "Env_Rock"), Tuning.FIELD_ROCKS, rand, 0.7, 1.9, false)
	_scatter(_palette(BRUSH_TILE, "Env_Bush"), Tuning.FIELD_BUSHES, rand, 0.8, 1.5, true)
	_scatter(_palette(CRYSTAL_TILE, "Env_Crystal"), Tuning.FIELD_CRYSTALS, rand,
		Tuning.CRYSTAL_SCALE_MIN, Tuning.CRYSTAL_SCALE_MAX, true, _crystal_material())
	# A tree is one prop made of eight meshes, so all eight share a single
	# transform list - otherwise a trunk would end up under someone else's canopy.
	_scatter_composite(_palette(TREE_PROP, "Env_Tree"), Tuning.FIELD_TREES, rand)
	# Flagstones go last and INSIDE the corridor - the one thing in the field
	# that ignores FIELD_CLEAR_RADIUS instead of respecting it.
	_scatter_flagstones(_palette(GROUND_TILE, "Env_Rock"), rand)

## Every MeshInstance3D under `scene` whose node name starts with `prefix`, as
## {mesh, material, local}. `local` is the mesh's transform relative to the
## .glb's ROOT, accumulated down the hierarchy - the tree's parts are laid out
## by exactly that transform, and its root empty carries the scale that makes
## the tree 4.6 units tall, so neither can be dropped.
##
## One palette entry per distinct source mesh is also where the variety comes
## from: the brush tile alone ships twelve different bush spheres and the
## ground tile seven different rocks.
##
## `material` reads get_surface_override_material(0), which is null for every
## prop this file uses - none of the source .glbs were ever imported with a
## per-instance override, they carry their colour as the MESH RESOURCE's own
## surface material instead (set in Blender, arrives on the mesh, not the
## node). It is kept as a field anyway rather than dropped, since a future
## source asset that DOES carry an override should still be picked up here
## without this function needing to change. _add_group() already guards on
## it being non-null before using it, and _hazed() (the backdrop's material
## tint) reads straight off the mesh resource instead for exactly this reason.
func _palette(scene: PackedScene, prefix: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var root := scene.instantiate()
	_collect(root, Transform3D.IDENTITY, prefix, out)
	root.free()
	return out

func _collect(node: Node, parent_xform: Transform3D, prefix: String,
		out: Array[Dictionary]) -> void:
	var here := parent_xform
	if node is Node3D:
		here = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and String(node.name).begins_with(prefix):
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			out.append({
				"mesh": mi.mesh,
				"material": mi.get_surface_override_material(0),
				"local": here,
			})
	for child: Node in node.get_children():
		_collect(child, here, prefix, out)

## Scatters `count` props drawn at random from `palette`, one MultiMesh per
## palette entry.
##
## Only the HEIGHT of a source prop's local transform is kept: these props are
## authored sitting on the ground inside their tile, with the mesh centred on
## its own origin, so a bush whose origin is 0.387 up would sink halfway into
## the field if the Y were dropped along with the X and Z.
func _scatter(palette: Array[Dictionary], count: int, rand: RandomNumberGenerator,
		scale_min: float, scale_max: float, shadows: bool,
		override_material: Material = null) -> void:
	if palette.is_empty():
		return
	var buckets: Array[Array] = []
	for _i: int in range(palette.size()):
		buckets.append([])
	for _i: int in range(count):
		var spot: Variant = _spot(rand)
		if spot == null:
			continue
		var pick: int = rand.randi_range(0, palette.size() - 1)
		var flat: float = rand.randf_range(scale_min, scale_max)
		var tall: float = rand.randf_range(scale_min, scale_max)
		var local: Transform3D = palette[pick]["local"]
		# The lift is the SOURCE height, unscaled: composing it through _place()
		# puts it through that transform's own (flat, tall, flat) scale, so
		# pre-multiplying by `tall` here would apply the stretch twice and float
		# the taller props above the ground.
		var lifted := Transform3D(local.basis, Vector3(0.0, local.origin.y, 0.0))
		buckets[pick].append(_place(spot, rand.randf_range(0.0, TAU),
			Vector3(flat, tall, flat)) * lifted)
	for i: int in range(palette.size()):
		if not buckets[i].is_empty():
			_add_group(palette[i], buckets[i], shadows, override_material)

## The tree: one shared placement per planted tree, applied to all eight of its
## meshes through each mesh's own local transform, so the parts stay assembled.
func _scatter_composite(palette: Array[Dictionary], count: int,
		rand: RandomNumberGenerator) -> void:
	if palette.is_empty():
		return
	var placements: Array[Transform3D] = []
	for _i: int in range(count):
		# Trees need more clearance than clutter does: a 4.6-unit canopy sitting
		# on the run corridor would hide the fight underneath it.
		var spot: Variant = _spot(rand, Tuning.FIELD_CLEAR_RADIUS + Tuning.TREE_CLEAR_EXTRA)
		if spot == null:
			continue
		var s: float = 1.0 + rand.randf_range(-Tuning.TREE_SCALE_JITTER, Tuning.TREE_SCALE_JITTER)
		placements.append(_place(spot, rand.randf_range(0.0, TAU),
			Vector3(s, s * rand.randf_range(0.94, 1.10), s)))
	for entry: Dictionary in palette:
		var xforms: Array = []
		for p: Transform3D in placements:
			xforms.append(p * (entry["local"] as Transform3D))
		if not xforms.is_empty():
			_add_group(entry, xforms, true, _shaded(entry["mesh"]))

## [ui-project-longshot] Rocks squashed nearly flat and laid ON the path, the
## only scatter in this file that places props INSIDE the clear corridor
## rather than outside it. They are what makes the path read as travelling:
## the strip itself never moves (see _build_path), so without something on it
## the party would be running on a static ribbon.
##
## The Y scale is the whole trick - the same Env_Rock meshes the field already
## scatters as boulders, flattened to a tenth of their height, read as set
## paving. Their transforms still go through _place() and so still wrap and
## scroll with everything else in _groups.
func _scatter_flagstones(palette: Array[Dictionary], rand: RandomNumberGenerator) -> void:
	if palette.is_empty():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Tuning.PATH_STONE_COLOR
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	var buckets: Array[Array] = []
	for _i: int in range(palette.size()):
		buckets.append([])
	for _i: int in range(Tuning.FIELD_FLAGSTONES):
		# Kept off the very edge of the path, so a stone never juts out from
		# under the undergrowth that overhangs it.
		var across: float = _lane + rand.randf_range(
			-Tuning.PATH_WIDTH * 0.40, Tuning.PATH_WIDTH * 0.40)
		var along: float = rand.randf_range(0.0, Tuning.FIELD_ALONG)
		var pick: int = rand.randi_range(0, palette.size() - 1)
		var flat: float = rand.randf_range(0.55, 1.15)
		buckets[pick].append(_place(Vector2(across, along), rand.randf_range(0.0, TAU),
			Vector3(flat, 0.10, flat * rand.randf_range(0.8, 1.25))))
	for i: int in range(palette.size()):
		if not buckets[i].is_empty():
			_add_group(palette[i], buckets[i], false, mat)

# --- the archway ---------------------------------------------------------------

## [ui-project-longshot] The rune arch on the horizon: the frame's focal point
## and the thing the endless run is nominally running toward.
##
## Fixed in world space and NOT added to _groups, exactly like _build_backdrop's
## treering. The camera never moves in this scene - the near scatter slides
## under it instead - so a landmark pinned up-run stays put on the horizon
## while everything closer streams past it, which is what reads as "still far
## away". Scrolling it would have the party reach and pass through the arch
## every few seconds, which is a different game than this one.
##
## Two prefixes, two materials. Env_ArchStone* is hazed toward the fog like a
## backdrop tree so the masonry sits at its distance; Env_ArchGlow* is
## unshaded emissive so the light in the opening punches through that same fog
## instead of being swallowed by it. That contrast between a receding ring and
## a light that refuses to recede is the entire effect.
func _build_archway() -> void:
	var origin: Vector3 = Tuning.PARTY_ANCHOR + Tuning.RUN_DIR * Tuning.ARCH_DISTANCE
	# Local +X carries the arch's span, so aiming it down the across-axis puts
	# the opening square to the run corridor (see _place's yaw convention).
	var xform := Transform3D(
		Basis(Vector3.UP, Tuning.yaw_along(_perp)).scaled(Vector3.ONE * Tuning.ARCH_SCALE),
		origin)

	var root := Node3D.new()
	root.name = "Archway"
	root.transform = xform
	add_child(root)

	var stone := _archway_stone_material()
	for entry: Dictionary in _palette(ARCH_PROP, "Env_Arch"):
		var mesh: Mesh = entry["mesh"]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = entry["local"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = stone
		root.add_child(mi)

	# The glow parts are collected separately rather than filtered out of the
	# loop above, because _palette() matches on a name PREFIX and "Env_Arch"
	# is a prefix of both - so the pass above has already added them with the
	# stone material, and this pass overwrites those overrides in place.
	var veil := _archway_glow_material()
	for entry: Dictionary in _palette(ARCH_PROP, "Env_ArchGlow"):
		for child: Node in root.get_children():
			var mi := child as MeshInstance3D
			if mi != null and mi.mesh == entry["mesh"]:
				mi.material_override = veil

	# Without this the arch is a bright cut-out with no effect on anything
	# around it. The omni is what puts its light on the ground and the nearest
	# trunks, which is what seats it in the world.
	var lamp := OmniLight3D.new()
	lamp.name = "ArchLight"
	lamp.light_color = Tuning.C_PORTAL
	lamp.light_energy = Tuning.ARCH_LIGHT_ENERGY
	lamp.omni_range = Tuning.ARCH_LIGHT_RANGE
	lamp.shadow_enabled = false
	lamp.position = origin + Vector3(0.0, 3.0, 0.0)
	add_child(lamp)

## The masonry: a flat DARK silhouette, not a hazed distant object.
##
## The obvious treatment - run it through _hazed() like a backdrop tree - was
## the first attempt and it erased the arch completely: the ring sits ~80 units
## out, past everything the fog ramp has to give, so pulling it toward the haze
## as well left stone the exact colour of the sky behind it.
##
## The concept solves this the way a painter would, and so does this: the ring
## is the DARKEST thing on the horizon and the opening the brightest, and the
## silhouette between them is what the eye reads. So the stone opts out of fog
## in the same breath the veil does, and is unshaded at a value below the
## treeline rather than lit.
func _archway_stone_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Tuning.C_NEAR_TREES.lerp(
		Tuning.C_HORIZON_HAZE, Tuning.ARCH_STONE_TINT * 0.35)
	mat.disable_fog = true
	return mat

## Unshaded and emissive, so no light in the scene - and no amount of fog -
## can change what the opening looks like. `disable_fog` is the load-bearing
## line: the arch sits past FOG_DEPTH_END, so without it the veil is fogged to
## the horizon colour and the focal point of the whole frame disappears.
func _archway_glow_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Tuning.C_PORTAL
	mat.emission_enabled = true
	mat.emission = Tuning.C_PORTAL
	mat.emission_energy_multiplier = Tuning.ARCH_GLOW_ENERGY
	mat.disable_fog = true
	return mat

# --- the air -------------------------------------------------------------------

## [ui-project-longshot] Drifting spores. The concept's air is full of them,
## and they are the cheapest depth cue available: motes crossing in front of
## and behind the party are what stop the middle distance reading as a flat
## painted backdrop.
##
## Parented to the field but never scrolled - the emission box is centred on
## the play area and the particles have their own upward drift, so scrolling
## them as well would double the motion.
func _build_motes() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Tuning.C_ARCANE_BRIGHT
	mat.emission_enabled = true
	mat.emission = Tuning.C_ARCANE_BRIGHT
	mat.emission_energy_multiplier = 2.5
	mat.disable_fog = true
	mat.vertex_color_use_as_albedo = true

	var quad := QuadMesh.new()
	quad.size = Vector2(Tuning.MOTE_SIZE, Tuning.MOTE_SIZE)
	quad.material = mat

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Tuning.MOTE_BOX * 0.5
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 35.0
	proc.gravity = Vector3.ZERO
	proc.initial_velocity_min = Tuning.MOTE_DRIFT * 0.35
	proc.initial_velocity_max = Tuning.MOTE_DRIFT
	proc.scale_min = 0.45
	proc.scale_max = 1.6
	# Fading both ends means no mote ever pops into or out of existence, which
	# is what would otherwise give the loop away on a long lifetime.
	var ramp := Gradient.new()
	ramp.set_offset(0, 0.0)
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_offset(1, 1.0)
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.25, Color(1, 1, 1, 1))
	ramp.add_point(0.70, Color(1, 1, 1, 1))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	proc.color_ramp = ramp_tex

	var motes := GPUParticles3D.new()
	motes.name = "Motes"
	motes.amount = Tuning.MOTE_COUNT
	motes.lifetime = 9.0
	motes.preprocess = 9.0            # start mid-loop, not with an empty sky
	motes.draw_pass_1 = quad
	motes.process_material = proc
	motes.visibility_aabb = AABB(-Tuning.MOTE_BOX * 0.5, Tuning.MOTE_BOX)
	motes.position = Tuning.PARTY_ANCHOR + Tuning.RUN_DIR * (Tuning.MOTE_BOX.z * 0.25) \
		+ Vector3(0.0, Tuning.MOTE_BOX.y * 0.35, 0.0)
	add_child(motes)

## A point on the field rectangle in RUN_DIR's frame, or null if every attempt
## landed inside the corridor the fight happens in.
func _spot(rand: RandomNumberGenerator, clearance: float = -1.0) -> Variant:
	var clear: float = Tuning.FIELD_CLEAR_RADIUS if clearance < 0.0 else clearance
	for _attempt: int in range(8):
		var across: float = rand.randf_range(-Tuning.FIELD_ACROSS * 0.5, Tuning.FIELD_ACROSS * 0.5)
		var along: float = rand.randf_range(0.0, Tuning.FIELD_ALONG)
		if absf(across - _lane) >= clear:
			return Vector2(across, along)
	return null

## RUN_DIR-frame coordinates -> the world transform of one planted prop.
func _place(spot: Vector2, yaw: float, prop_scale: Vector3) -> Transform3D:
	var origin: Vector3 = _perp * spot.x + Tuning.RUN_DIR * spot.y
	return Transform3D(Basis(Vector3.UP, yaw).scaled(prop_scale), origin)

# --- background dressing -------------------------------------------------------

## A ring of trees well outside the play area - cheap atmospheric-perspective
## filler for the gap between the last foreground tree and the sky (see
## Tuning.FIELD_TREES_BACKDROP's comment for the full reasoning). A full
## radial ring, not a band ahead along RUN_DIR, so it still frames the shot
## correctly no matter which way the camera ends up facing.
##
## Centred on the CAMERA's ground position, not the world origin - the two
## are about 24 units apart with BattleCamera at (-14, 9, 17), and a ring
## centred on the origin let some instances land as little as MIN_RADIUS
## minus that 24 units from the camera, well inside "near," while pre-tinted
## as if they were far. Centring on the camera is what makes MIN/MAX_RADIUS
## actually mean "this far from the thing doing the looking."
##
## Deliberately not appended to _groups: this is the one part of the field
## that never scrolls. See Tuning.FIELD_TREES_BACKDROP for why that is
## correct rather than an oversight (the camera itself never moves in this
## scene - the near scatter slides under it instead).
func _build_backdrop() -> void:
	var palette := _palette(TREE_PROP, "Env_Tree")
	if palette.is_empty():
		return

	var cam := get_parent().get_node_or_null("BattleCamera") as Camera3D
	var center: Vector3 = Vector3(cam.position.x, 0.0, cam.position.z) if cam != null \
		else Vector3.ZERO

	var rand := RandomNumberGenerator.new()
	# A seed distinct from FIELD_SCATTER_SEED, or every backdrop tree would
	# land at whatever angle the near scatter's first few rolls happened to
	# produce - correlating two rings that are meant to read as unrelated.
	rand.seed = Tuning.FIELD_SCATTER_SEED + 1
	var placements: Array[Transform3D] = []
	for _i: int in range(Tuning.FIELD_TREES_BACKDROP):
		var angle := rand.randf_range(0.0, TAU)
		var radius := rand.randf_range(
			Tuning.FIELD_BACKDROP_MIN_RADIUS, Tuning.FIELD_BACKDROP_MAX_RADIUS)
		var origin := center + Vector3(cos(angle), 0.0, sin(angle)) * radius
		var s: float = 1.0 + rand.randf_range(-Tuning.TREE_SCALE_JITTER, Tuning.TREE_SCALE_JITTER)
		placements.append(Transform3D(
			Basis(Vector3.UP, rand.randf_range(0.0, TAU)) \
				.scaled(Vector3(s, s * rand.randf_range(0.94, 1.10), s)),
			origin))

	for entry: Dictionary in palette:
		var xforms: Array = []
		for p: Transform3D in placements:
			xforms.append(p * (entry["local"] as Transform3D))
		if xforms.is_empty():
			continue
		var mesh: Mesh = entry["mesh"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i: int in range(xforms.size()):
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _hazed(mesh.surface_get_material(0))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

## A duplicate of a tree part's own material, pulled toward the sky/fog colour
## by Tuning.FIELD_BACKDROP_TINT. Real-time depth fog alone still leaves the
## NEAREST instances in this ring looking as saturated as a foreground tree -
## fog reads current camera distance, not "which ring this was planted in" -
## so this pre-tint is what marks the whole ring as far even for the trees
## fog has barely touched yet.
##
## `mat` comes straight off the mesh RESOURCE (surface_get_material), not off
## a MeshInstance3D override - env_tree.glb's parts carry their material this
## way (see _palette()'s own note on why `entry["material"]` is always null
## for every prop in this file), so this is the one place in the field that
## reads a material from that side of the API.
## [ui-project-longshot] A tree part's own material, pulled toward the near-
## black treeline colour by Tuning.TREE_TINT. The counterpart to _hazed(): that
## one pushes the FAR ring toward the sky so it recedes, this one pushes the
## NEAR trees away from it so they read as a dark mass.
##
## Reads off the mesh resource for the same reason _hazed() does - env_tree.glb
## carries its colour on the mesh's surface material, not as a node override
## (see _palette()'s note).
func _shaded(mesh: Mesh) -> Material:
	var mat := mesh.surface_get_material(0)
	if not (mat is BaseMaterial3D):
		return null
	var copy := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
	copy.albedo_color = copy.albedo_color.lerp(Tuning.C_NEAR_TREES, Tuning.TREE_TINT)
	return copy

func _hazed(mat: Material) -> Material:
	if not (mat is BaseMaterial3D):
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Tuning.C_HORIZON_HAZE
		return fallback
	var copy := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
	copy.albedo_color = copy.albedo_color.lerp(Tuning.C_HORIZON_HAZE, Tuning.FIELD_BACKDROP_TINT)
	return copy

func _add_group(entry: Dictionary, xforms: Array, shadows: bool,
		override_material: Material = null) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = entry["mesh"]
	mm.instance_count = xforms.size()
	for i: int in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])

	var copies: Array[MultiMeshInstance3D] = []
	for _i: int in range(FIELD_COPIES):
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm                       # one resource, three instances of it
		if override_material != null:
			mmi.material_override = override_material
		elif entry["material"] != null:
			mmi.material_override = entry["material"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		copies.append(mmi)
	_groups.append({"copies": copies})
	_apply_offset()

## Emissive override for the crystal clusters. A fresh StandardMaterial3D
## rather than anything read off the .glb (S10.1's header): the Blender
## source keeps a plain Principled BSDF with Base Color only, matching every
## other Env_M_* material (spec 23.1) - emission lives here so tuning the
## glow is a Tuning.CRYSTAL_EMISSION_ENERGY edit and a reload, not a Blender
## re-export.
##
## [ui-project-longshot] Emission alone is not a gemstone. A uniform emissive
## fill lights every facet to the same value, so a cut crystal renders as a
## flat pale silhouette - which is exactly what the first pass produced. Three
## things are added here, and all three are needed:
##
##   - a DARK albedo, so unlit faces stay deep blue and the facets separate
##   - a low emission, enough to sit above the fog but not to flatten the form
##   - rim + specular, which is what actually draws the cut edges: the three
##     directional lights catch different facets of every cluster, and that
##     scatter of individual bright faces is what the eye reads as "crystal"
func _crystal_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Tuning.C_ARCANE_DEEP
	mat.emission_enabled = true
	mat.emission = Tuning.C_ARCANE
	mat.emission_energy_multiplier = Tuning.CRYSTAL_EMISSION_ENERGY
	mat.roughness = 0.18
	mat.metallic = 0.25
	mat.metallic_specular = 0.85
	mat.rim_enabled = true
	mat.rim = Tuning.CRYSTAL_RIM
	mat.rim_tint = 0.9
	return mat
