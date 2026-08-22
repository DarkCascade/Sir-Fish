class_name CelMaterials
extends RefCounted
## Factory for the two shader materials every 3D thing in the game uses.
##
## Spec 6.2 offers two options for fading characters out. We take the
## "always-transparent variant" it recommends: cel_shade.gdshader declares
## blend_mix, so a single material can fade without a swap. The scene has far
## fewer than 40 meshes, so the sorting cost is irrelevant.

const CEL_SHADER := preload("res://assets/shaders/cel_shade.gdshader")
const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")
const SMOKE_SHADER := preload("res://assets/shaders/smoke.gdshader")
const FLAT_SHADER := preload("res://assets/shaders/parallax_layer.gdshader")

## A cel-shaded material with the inverted-hull outline attached as next_pass.
static func cel(albedo: Color, emission: Color = Color.BLACK, emission_strength: float = 0.0,
		outline_width: float = 0.018) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CEL_SHADER
	mat.set_shader_parameter("albedo", albedo)
	mat.set_shader_parameter("band_count", 3.0)
	mat.set_shader_parameter("shadow_tint", Color(0.45, 0.52, 0.78, 1.0))
	mat.set_shader_parameter("rim_amount", 0.35)
	mat.set_shader_parameter("rim_color", Color.WHITE)
	mat.set_shader_parameter("emission_color", emission)
	mat.set_shader_parameter("emission_strength", emission_strength)
	mat.set_shader_parameter("alpha", 1.0)
	if outline_width > 0.0:
		mat.next_pass = outline(outline_width)
	return mat

static func outline(width: float = 0.018) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = OUTLINE_SHADER
	mat.set_shader_parameter("outline_color", Tuning.C_INK)
	mat.set_shader_parameter("outline_width", width)
	return mat

static func smoke(color: Color = Tuning.C_SHADOW_BODY) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SMOKE_SHADER
	mat.set_shader_parameter("smoke_color", color)
	mat.set_shader_parameter("speed", 0.35)
	mat.set_shader_parameter("edge_softness", 0.55)
	mat.set_shader_parameter("alpha", 1.0)
	return mat

## Flat unshaded colour - parallax layers and VFX quads.
static func flat(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FLAT_SHADER
	mat.set_shader_parameter("layer_color", color)
	mat.set_shader_parameter("alpha", 1.0)
	return mat

## Fades every mesh under `root`, so a whole character or prop goes with one
## call. Works on both material families the game now renders with: the
## shader materials built in this file, and the StandardMaterial3D an
## imported .glb arrives with (spec 6.2 - nothing reassigns those any more,
## so fading has to reach them where they are).
static func set_alpha(root: Node, value: float) -> void:
	for mi: MeshInstance3D in _all_mesh_instances(root):
		var mat := _fx_material(mi)
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("alpha", value)
			var np: Material = (mat as ShaderMaterial).next_pass
			if np is ShaderMaterial:
				# The outline shader carries its own alpha uniform (spec 6.3 /
				# Q16), so the ink fades together with the body. outline_width is
				# never touched at runtime: scaling it read as the model shrinking
				# inside a solid silhouette rather than as a fade.
				(np as ShaderMaterial).set_shader_parameter("alpha", value)
		elif mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			var albedo: Color = bm.albedo_color
			albedo.a = value
			bm.albedo_color = albedo
			# An opaque material ignores albedo alpha entirely, so the blend
			# mode has to be switched on for the fade and switched back off
			# afterwards - leaving every corpse-faded mesh permanently in the
			# transparent pass would change how the whole party sorts against
			# the layer-5 brush for the rest of the run.
			if value < 1.0:
				bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			else:
				bm.transparency = bm.get_meta(&"base_transparency",
					BaseMaterial3D.TRANSPARENCY_DISABLED)

## Argument order flipped for use with Tween.tween_method(...).bind(root).
static func set_alpha_on(value: float, root: Node) -> void:
	set_alpha(root, value)

## Flashes every mesh under `root` to `color` and back over `duration`.
static func flash(root: Node, color: Color, duration: float) -> void:
	var scene_tree := root.get_tree()
	if scene_tree == null:
		return
	var mats: Array = []
	for mi: MeshInstance3D in _all_mesh_instances(root):
		var mat := _fx_material(mi)
		# The base colour is remembered once, on the material itself. Reading
		# the live albedo instead would latch the flash colour in whenever two
		# flashes overlap - which in a busy fight leaves everyone permanently
		# white.
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader == CEL_SHADER:
			var sm := mat as ShaderMaterial
			if not sm.has_meta(&"base_albedo"):
				sm.set_meta(&"base_albedo", sm.get_shader_parameter("albedo"))
			sm.set_shader_parameter("albedo", color)
			mats.append(sm)
		elif mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			if not bm.has_meta(&"base_albedo"):
				bm.set_meta(&"base_albedo", bm.albedo_color)
				bm.set_meta(&"base_albedo_texture", bm.albedo_texture)
			# The texture comes off for the duration. A flash is a flat
			# colour by design, and albedo_color MULTIPLIES the map on a
			# StandardMaterial3D - so a near-white flash over the warrior's
			# atlas would leave him looking exactly as he did, which is the one
			# thing a hit flash must never do.
			bm.albedo_texture = null
			var flash_color := color
			flash_color.a = bm.albedo_color.a    # never fight an in-flight fade
			bm.albedo_color = flash_color
			mats.append(bm)
	if mats.is_empty():
		return
	await scene_tree.create_timer(duration).timeout
	for m: Variant in mats:
		if not is_instance_valid(m):
			continue
		if m is ShaderMaterial:
			var sm := m as ShaderMaterial
			sm.set_shader_parameter("albedo", sm.get_meta(&"base_albedo"))
		elif m is BaseMaterial3D:
			var bm := m as BaseMaterial3D
			var restored: Color = bm.get_meta(&"base_albedo")
			restored.a = bm.albedo_color.a
			bm.albedo_color = restored
			bm.albedo_texture = bm.get_meta(&"base_albedo_texture")

## The material flash/fade may write to, per MeshInstance3D.
##
## For anything this file built, that is the override already on the node.
## For an imported surface it is a DUPLICATE of the arriving material,
## installed as `material_override` on first use and cached on the node: a
## .glb's materials are shared resources, so the two orcs, or any two heroes
## sharing an atlas, would otherwise flash and fade as one. The duplicate is
## shallow - it keeps pointing at the same textures.
static func _fx_material(mi: MeshInstance3D) -> Material:
	var mat := mi.material_override
	if mat != null:
		return mat
	if mi.has_meta(&"fx_material"):
		return mi.get_meta(&"fx_material") as Material
	var src := mi.get_active_material(0)
	if src == null:
		return null
	var copy := src.duplicate() as Material
	if copy is BaseMaterial3D:
		(copy as BaseMaterial3D).set_meta(&"base_transparency",
			(copy as BaseMaterial3D).transparency)
	mi.material_override = copy
	mi.set_meta(&"fx_material", copy)
	return copy

static func _all_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root == null:
		return out
	if root is MeshInstance3D:
		out.append(root as MeshInstance3D)
	for child: Node in root.get_children():
		out.append_array(_all_mesh_instances(child))
	return out
