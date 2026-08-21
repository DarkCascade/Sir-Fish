extends Node
## Parallax layers 1-3 seam verification (spec 7.5.4, V15). [v3, new]
##
## Run headless from the project root:
##     godot --headless --path "C:/Projects/Godot/Sir Fish" res://tests/test_parallax_seam.tscn
##
## Asserts the five guarantees spec 7.5.4 lists: the profile is periodic in W
## (assertion 1), no generated vertex overhangs its tile boundary (assertion
## 2 - the one the pre-v3 `_build_trees` failed), the three tile copies of a
## layer share one Mesh by identity (assertion 3), each tile holds exactly one
## MeshInstance3D (assertion 4), and wrapping by +3W reproduces the same
## world-space silhouette (assertion 5).

const TestSupport := preload("res://tests/test_support.gd")

const PARALLAX_SCENE := preload("res://scenes/battle/parallax_background.tscn")
const PROC_LAYERS := ["LayerHills", "LayerFarTrees", "LayerNearTrees"]

func _ready() -> void:
	var t := TestSupport.new()

	# --- assertion 1: the profile is periodic in W, by construction --------
	for h: Array in ParallaxProfiles.HILLS:
		var k: float = float(h[0])
		t.check(is_equal_approx(k, round(k)), "HILLS wavenumber %s is an exact integer" % str(h[0]))

	var w: float = Tuning.PARALLAX_TILE_WIDTH_PROC
	var left := ParallaxProfiles.sample(-w * 0.5, w, ParallaxProfiles.HILLS_BASE, ParallaxProfiles.HILLS)
	var right := ParallaxProfiles.sample(w * 0.5, w, ParallaxProfiles.HILLS_BASE, ParallaxProfiles.HILLS)
	t.check(absf(left - right) < Tuning.PARALLAX_SEAM_EPSILON,
		"HILLS profile matches at tile edges (left %.6f, right %.6f)" % [left, right])

	# --- assertion 5: periodic beyond one tile - wrapping by +3W reproduces
	# the same world-space silhouette (no per-tile phase to break it) --------
	var copies: float = float(Tuning.PARALLAX_TILE_COPIES)
	var seam_ok := true
	for i: int in range(9):
		var x := -w * 0.5 + w * float(i) / 8.0
		var a := ParallaxProfiles.sample(x, w, ParallaxProfiles.HILLS_BASE, ParallaxProfiles.HILLS)
		var b := ParallaxProfiles.sample(x + w * copies, w, ParallaxProfiles.HILLS_BASE, ParallaxProfiles.HILLS)
		if absf(a - b) >= Tuning.PARALLAX_SEAM_EPSILON:
			seam_ok = false
	t.check(seam_ok, "wrapping a tile by +%dW reproduces the same world-space silhouette" % Tuning.PARALLAX_TILE_COPIES)

	# --- build the real scene and inspect the actual generated geometry ----
	var bg := PARALLAX_SCENE.instantiate()
	add_child(bg)
	await get_tree().process_frame

	var overhang_count := 0
	var shared_mesh_ok := true
	var single_mesh_ok := true

	for layer_name: String in PROC_LAYERS:
		var layer: Node3D = bg.get_node(layer_name)
		var layer_w: float = float(layer.get_meta("tile_width", -1.0))
		t.check(is_equal_approx(layer_w, Tuning.PARALLAX_TILE_WIDTH_PROC),
			"%s tile_width meta is %.1f" % [layer_name, Tuning.PARALLAX_TILE_WIDTH_PROC])

		var meshes: Array[Mesh] = []
		for tile: Node3D in layer.get_children():
			var mesh_instances: Array[Node] = []
			for child: Node in tile.get_children():
				if child is MeshInstance3D:
					mesh_instances.append(child)
			if mesh_instances.size() != 1:
				single_mesh_ok = false
				continue
			var mi := mesh_instances[0] as MeshInstance3D
			meshes.append(mi.mesh)

			# assertion 2: every vertex stays within [-W/2, +W/2] in tile-local space.
			var arrays := mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				if v.x < -layer_w * 0.5 - 0.0001 or v.x > layer_w * 0.5 + 0.0001:
					overhang_count += 1

		# assertion 3: identity, not equality - the SAME Mesh resource object.
		for i: int in range(1, meshes.size()):
			if meshes[i] != meshes[0]:
				shared_mesh_ok = false

	t.check(overhang_count == 0,
		"no generated vertex overhangs its tile boundary (%d found)" % overhang_count)
	t.check(shared_mesh_ok, "all three tile copies of each layer share one Mesh resource (identity)")
	t.check(single_mesh_ok, "each tile holds exactly one MeshInstance3D")

	bg.queue_free()
	t.finish(get_tree(), "test_parallax_seam")
