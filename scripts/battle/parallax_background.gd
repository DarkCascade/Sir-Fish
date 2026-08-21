extends Node3D
## Five faked-parallax layers (spec 7.4). An orthographic camera gives no free
## parallax, so depth is sold purely by scroll speed.
##
## [v3, V15] Layers 1-3 (Hills/FarTrees/NearTrees) are generated here from a
## periodic profile (ParallaxProfiles) and baked to one shared SurfaceTool mesh
## per layer - seamless by construction (spec 7.5). Layers 4-5 (Ground/Brush)
## stay as placeholder procedural geometry until the Blender pass (M8d, spec
## 23.4) and keep their pre-v3 per-tile build. tile_width is per-layer now,
## not a single @export: 36.0 for the generated layers, 12.0 for the modelled
## ones (spec 5.8, 7.4.1) - a slow layer needs a long period so its repeat
## isn't visible; a fast one does not. Do NOT name any parameter `scale` here -
## it shadows Node3D.scale.

const PROC_LAYERS: Array[String] = ["LayerHills", "LayerFarTrees", "LayerNearTrees"]

var scroll_speed: float = 0.0            # 0 = stopped; RunController tweens this

var _layers: Array[Node3D] = []

func _ready() -> void:
	for child: Node in get_children():
		if child is Node3D:
			_layers.append(child as Node3D)
	_build_tiles()

func _process(delta: float) -> void:
	if is_zero_approx(scroll_speed):
		return
	for layer: Node3D in _layers:
		var mult: float = float(layer.get_meta("speed_mult", 1.0))
		var w: float = float(layer.get_meta("tile_width", Tuning.PARALLAX_TILE_WIDTH_MODEL))
		for tile: Node3D in layer.get_children():
			tile.position.x -= scroll_speed * mult * delta
			if tile.position.x <= -w:
				tile.position.x += w * float(Tuning.PARALLAX_TILE_COPIES)

## Puts every tile back where it started (spec 18.3 step 4). Never rebuilds the
## meshes - they are deterministic (spec 7.5.3), so rebuilding on every retry
## would be pure waste.
func reset_tiles() -> void:
	for layer: Node3D in _layers:
		var w: float = float(layer.get_meta("tile_width", Tuning.PARALLAX_TILE_WIDTH_MODEL))
		var i: int = 0
		for tile: Node3D in layer.get_children():
			tile.position.x = -w + w * float(i)
			i += 1

## [v3] Advances every layer's tiles by `units` world units at its own speed
## multiplier, wrapping normally, without touching scroll_speed or the run
## state. Exists purely to drive Debug's `parallax` verb (spec 19.2) - a tile
## boundary on layer 1 sits far off-screen and would otherwise take longer
## than the whole demo's travel time to reach naturally.
func advance_tiles(units: float) -> void:
	for layer: Node3D in _layers:
		var mult: float = float(layer.get_meta("speed_mult", 1.0))
		var w: float = float(layer.get_meta("tile_width", Tuning.PARALLAX_TILE_WIDTH_MODEL))
		for tile: Node3D in layer.get_children():
			tile.position.x -= units * mult
			while tile.position.x <= -w:
				tile.position.x += w * float(Tuning.PARALLAX_TILE_COPIES)

# --- tile construction --------------------------------------------------------

func _tile_width_for(layer_name: StringName) -> float:
	return Tuning.PARALLAX_TILE_WIDTH_PROC if String(layer_name) in PROC_LAYERS \
		else Tuning.PARALLAX_TILE_WIDTH_MODEL

func _build_tiles() -> void:
	for layer: Node3D in _layers:
		for old: Node in layer.get_children():
			old.free()
		var w := _tile_width_for(layer.name)
		layer.set_meta("tile_width", w)
		if String(layer.name) in PROC_LAYERS:
			_build_proc_layer(layer, w)
		else:
			for i: int in range(Tuning.PARALLAX_TILE_COPIES):
				var tile := Node3D.new()
				tile.name = "Tile%d" % i
				tile.position.x = -w + w * float(i)
				layer.add_child(tile)
				_populate_legacy_tile(layer.name, tile, i, w)

## Layers 1-3 (spec 7.5.3). R1: one baked Mesh per layer, the SAME resource
## instanced three times - variety comes from richness within one tile, never
## from per-tile variation, because per-tile variation is exactly what
## guarantees a seam at every join (spec 7.5.1/7.5.2 R1). R4: exactly one
## MeshInstance3D per tile, which collapses ~111 draw calls to 9 (spec 7.5.3).
func _build_proc_layer(layer: Node3D, w: float) -> void:
	var mesh: Mesh
	var color: Color
	match String(layer.name):
		"LayerHills":
			mesh = _build_hills_mesh(w)
			color = Tuning.C_FAR_HILLS
		"LayerFarTrees":
			mesh = _build_trees_mesh(String(layer.name), w, 1.7, 0.55, 21)
			color = Tuning.C_MID_TREES
		"LayerNearTrees":
			mesh = _build_trees_mesh(String(layer.name), w, 2.6, 0.85, 15)
			color = Tuning.C_NEAR_TREES
		_:
			return
	# No outline next_pass on these layers: an inked far hill fights the
	# flat-silhouette read (spec 7.5.3).
	var mat := CelMaterials.flat(color)
	for i: int in range(Tuning.PARALLAX_TILE_COPIES):
		var tile := Node3D.new()
		tile.name = "Tile%d" % i
		tile.position.x = -w + w * float(i)
		layer.add_child(tile)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tile.add_child(mi)

## A rolling silhouette, periodic in W by construction (spec 7.5.2 R2): every
## harmonic's wavenumber in ParallaxProfiles.HILLS is an integer, so
## sample(-W/2) == sample(+W/2) exactly and three copies join with no seam.
## 288 segments over 36 units clears the 12-segments-per-shortest-wavelength
## rule for HILLS' k_max = 21 (spec 7.5.2).
func _build_hills_mesh(w: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 288
	for i: int in range(segments):
		var t0 := float(i) / float(segments)
		var t1 := float(i + 1) / float(segments)
		var x0 := -w * 0.5 + w * t0
		var x1 := -w * 0.5 + w * t1
		var y0 := ParallaxProfiles.sample(x0, w, ParallaxProfiles.HILLS_BASE, ParallaxProfiles.HILLS)
		var y1 := ParallaxProfiles.sample(x1, w, ParallaxProfiles.HILLS_BASE, ParallaxProfiles.HILLS)
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(x0, ParallaxProfiles.HILLS_FLOOR, 0))
		st.add_vertex(Vector3(x1, ParallaxProfiles.HILLS_FLOOR, 0))
		st.add_vertex(Vector3(x1, y1, 0))
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(x0, ParallaxProfiles.HILLS_FLOOR, 0))
		st.add_vertex(Vector3(x1, y1, 0))
		st.add_vertex(Vector3(x0, y0, 0))
	return st.commit()

## Tree clusters (spec 7.5.3). Jitter first, then clamp so R3 (spec 7.5.2)
## cannot be violated by any combination of jitter and radius roll - a feature
## must lie wholly inside [-W/2, +W/2] including its own half-width. Seeded
## from a script const keyed by layer name only (no tile index, no RNG
## autoload): deterministic across runs and retries, identical across the
## three copies, and never varies with the run seed (spec 7.5.3).
##
## Trunks no longer get a darker second colour (spec 6.1 grants this layer
## exactly one flat colour; the whole mesh, cones and trunks alike, bakes with
## one material).
func _build_trees_mesh(layer_name: String, w: float, height: float,
		radius: float, count: int) -> Mesh:
	var rand := RandomNumberGenerator.new()
	rand.seed = hash("%s-parallax" % layer_name)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(count):
		var x := -w * 0.5 + w * (float(i) + 0.5) / float(count)
		x += rand.randf_range(-0.35, 0.35)
		var h := height * rand.randf_range(0.8, 1.25)
		var r := radius * rand.randf_range(0.85, 1.15)
		x = clampf(x, -w * 0.5 + r, w * 0.5 - r)

		# Two stacked cones read as a conifer even in pure silhouette.
		var lower := CylinderMesh.new()
		lower.top_radius = 0.0
		lower.bottom_radius = r
		lower.height = h * 0.7
		lower.radial_segments = 6
		st.append_from(lower, 0, Transform3D(Basis(), Vector3(x, h * 0.35, 0)))

		var upper := CylinderMesh.new()
		upper.top_radius = 0.0
		upper.bottom_radius = r * 0.7
		upper.height = h * 0.55
		upper.radial_segments = 6
		st.append_from(upper, 0, Transform3D(Basis(), Vector3(x, h * 0.78, 0)))

		var trunk := BoxMesh.new()
		trunk.size = Vector3(r * 0.22, h * 0.3, r * 0.22)
		st.append_from(trunk, 0, Transform3D(Basis(), Vector3(x, h * 0.12, 0)))
	return st.commit()

# --- legacy per-tile placeholder geometry (layers 4-5, until M8d) -----------

func _add_mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3,
		rot_deg: Vector3 = Vector3.ZERO, mesh_scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = CelMaterials.flat(color)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = mesh_scale
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _populate_legacy_tile(layer_name: StringName, tile: Node3D, variant: int, w: float) -> void:
	match String(layer_name):
		"LayerGround":
			_build_ground(tile, variant, w)
		"LayerBrush":
			_build_brush(tile, variant, w)

func _build_ground(tile: Node3D, _variant: int, w: float) -> void:
	var slab := BoxMesh.new()
	slab.size = Vector3(w, 1.2, 8.0)
	_add_mesh(tile, slab, Tuning.C_GROUND, Vector3(0, -0.6, 0))
	# Darker stripe bands so the scroll speed is legible on a flat plane.
	var bands := 6
	for i: int in range(bands):
		var stripe := BoxMesh.new()
		stripe.size = Vector3(w / float(bands) * 0.45, 0.02, 7.6)
		var x := -w * 0.5 + w * (float(i) + 0.5) / float(bands)
		_add_mesh(tile, stripe, Tuning.C_GROUND.darkened(0.18), Vector3(x, 0.01, 0))

func _build_brush(tile: Node3D, variant: int, w: float) -> void:
	var rand := RandomNumberGenerator.new()
	rand.seed = hash("brush-%d" % variant)
	var count := 6
	for i: int in range(count):
		var x := -w * 0.5 + w * (float(i) + 0.5) / float(count)
		x += rand.randf_range(-0.5, 0.5)
		var s := rand.randf_range(0.6, 1.1)
		var bush := SphereMesh.new()
		bush.radius = 0.55 * s
		bush.height = 0.7 * s
		bush.radial_segments = 8
		bush.rings = 4
		_add_mesh(tile, bush, Tuning.C_BRUSH, Vector3(x, 0.12 * s, 0))
		var bush2 := SphereMesh.new()
		bush2.radius = 0.38 * s
		bush2.height = 0.5 * s
		bush2.radial_segments = 8
		bush2.rings = 4
		_add_mesh(tile, bush2, Tuning.C_BRUSH, Vector3(x + 0.45 * s, 0.05 * s, 0.2))
