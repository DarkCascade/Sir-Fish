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

## Same reasoning as Tuning.PARALLAX_TILE_COPIES: two copies can leave a gap at
## the far edge for one frame during a wrap, three never can.
const FIELD_COPIES := 3

var scroll_speed: float = 0.0            # 0 = stopped; RunController tweens this

## One entry per distinct source mesh: {copies: Array[MultiMeshInstance3D]}.
var _groups: Array[Dictionary] = []
## How far the field has slid down the run axis, before wrapping.
var _offset: float = 0.0

var _perp: Vector3 = Tuning.RUN_DIR.cross(Vector3.UP).normalized()

func _ready() -> void:
	_build_ground()
	_build_scatter()

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
	# A tree is one prop made of eight meshes, so all eight share a single
	# transform list - otherwise a trunk would end up under someone else's canopy.
	_scatter_composite(_palette(TREE_PROP, "Env_Tree"), Tuning.FIELD_TREES, rand)

## Every MeshInstance3D under `scene` whose node name starts with `prefix`, as
## {mesh, material, local}. `local` is the mesh's transform relative to the
## .glb's ROOT, accumulated down the hierarchy - the tree's parts are laid out
## by exactly that transform, and its root empty carries the scale that makes
## the tree 4.6 units tall, so neither can be dropped.
##
## One palette entry per distinct source mesh is also where the variety comes
## from: the brush tile alone ships twelve different bush spheres and the
## ground tile seven different rocks.
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
		scale_min: float, scale_max: float, shadows: bool) -> void:
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
			_add_group(palette[i], buckets[i], shadows)

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
		var spot: Variant = _spot(rand, Tuning.FIELD_CLEAR_RADIUS + 1.6)
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
			_add_group(entry, xforms, true)

## A point on the field rectangle in RUN_DIR's frame, or null if every attempt
## landed inside the corridor the fight happens in.
func _spot(rand: RandomNumberGenerator, clearance: float = -1.0) -> Variant:
	var clear: float = Tuning.FIELD_CLEAR_RADIUS if clearance < 0.0 else clearance
	for _attempt: int in range(8):
		var across: float = rand.randf_range(-Tuning.FIELD_ACROSS * 0.5, Tuning.FIELD_ACROSS * 0.5)
		var along: float = rand.randf_range(0.0, Tuning.FIELD_ALONG)
		if absf(across) >= clear:
			return Vector2(across, along)
	return null

## RUN_DIR-frame coordinates -> the world transform of one planted prop.
func _place(spot: Vector2, yaw: float, prop_scale: Vector3) -> Transform3D:
	var origin: Vector3 = _perp * spot.x + Tuning.RUN_DIR * spot.y
	return Transform3D(Basis(Vector3.UP, yaw).scaled(prop_scale), origin)

func _add_group(entry: Dictionary, xforms: Array, shadows: bool) -> void:
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
		if entry["material"] != null:
			mmi.material_override = entry["material"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		copies.append(mmi)
	_groups.append({"copies": copies})
	_apply_offset()
