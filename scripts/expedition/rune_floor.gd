class_name RuneFloor
extends Node3D
## [expedition phase II] The slot board, on the battlefield between the party
## and the enemies. It does not run a slot of its own: it mirrors the real
## SlotMachine (hidden, off-screen) through that machine's board_dealt /
## reel_stopped / lines_won / cell_resolved signals, so every rule - the bag,
## the draw, the paylines, owner swings, charge - is the shipped one.
##
## Row 0 is the far row, nearest the enemies; column 0 is the party's left.
## Each cell is a stone tile with a carved rune. A dealt icon stands up out of
## it as a billboard (the real SlotSymbol drawing, rendered through a small
## SubViewport, so the glyph, coin and value number match the cabinet exactly),
## and the rune glows in the icon OWNER's colour. A winning line becomes a
## trench of light, and every resolution sends a mote from the tile to the hero
## it feeds.

const ICON_PX := 192
const LABEL_FONT := preload("res://assets/fonts/Baloo2-Variable.ttf")

@export var cell_size: float = 1.5
@export var tile_gap: float = 0.12
## How high a dealt icon stands above its tile, and how big it is, in metres.
@export var icon_height: float = 0.7
@export var icon_size: float = 1.15
## Seconds between face changes on a spinning column.
@export var spin_flicker: float = 0.07
## Seconds the board takes to unfold on arrival and to fold away once a fight
## is won (PRD §5.2).
@export var unfold_time: float = 0.45
@export var fold_time: float = 0.35

@export_group("Palette")
@export var slab_color: Color = Color("0f2322")
@export var tile_color: Color = Color("1f3d3c")
@export var rim_color: Color = Tuning.C_GOLD
@export var carve_color: Color = Color("35524e")
@export var warrior_rune: Color = Color("6f95d8")
@export var ranger_rune: Color = Color("5fc27a")
@export var mage_rune: Color = Color("a07cf7")

var director = null   # BattleDirector (untyped: custom API)

var _cells: Array[Dictionary] = []
var _board: Array = []
var _spinning: Array[bool] = [false, false, false]
var _flicker_left: float = 0.0
var _beams: Array[Node3D] = []
var _glow_tex: GradientTexture2D
var _shown: bool = true
var _fold: Tween

func _ready() -> void:
	var world = get_parent()
	transform = Transform3D(world.field_basis(), world.grid_centre())
	_glow_tex = _make_glow_texture()
	_build_slab()
	for i: int in range(Tuning.SLOT_BOARD_CELLS):
		_cells.append(_build_cell(i))
	EventBus.combat_ended.connect(_on_combat_ended)
	set_process(false)

## Hooked up by the presentation (or the looping demo) once the hidden
## SlotMachine and the director both exist.
func bind(slot, a_director) -> void:
	director = a_director
	slot.board_dealt.connect(_on_board_dealt)
	slot.reel_stopped.connect(_on_reel_stopped)
	slot.lines_won.connect(_on_lines_won)
	slot.cell_resolved.connect(_on_cell_resolved)

func cell_local(index: int) -> Vector3:
	@warning_ignore("integer_division")
	var row := index / 3
	var col := index % 3
	return Vector3(float(col - 1) * cell_size, 0.0, float(row - 1) * cell_size)

func cell_world(index: int) -> Vector3:
	return to_global(cell_local(index))

# --- construction ---------------------------------------------------------------

func _build_slab() -> void:
	var span := cell_size * 3.0 + 0.5
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(span, 0.16, span)
	slab.mesh = box
	slab.material_override = CelMaterials.cel_opaque(slab_color, Color.BLACK, 0.0, 0.015)
	add_child(slab)
	slab.position = Vector3(0, 0.0, 0)
	var rim_mat := CelMaterials.cel_opaque(rim_color, rim_color, 0.35, 0.0)
	var half := span * 0.5
	for edge: Array in [[Vector3(span + 0.16, 0.08, 0.16), Vector3(0, 0.06, -half)],
			[Vector3(span + 0.16, 0.08, 0.16), Vector3(0, 0.06, half)],
			[Vector3(0.16, 0.08, span), Vector3(-half, 0.06, 0)],
			[Vector3(0.16, 0.08, span), Vector3(half, 0.06, 0)]]:
		var rim := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = edge[0]
		rim.mesh = rb
		rim.material_override = rim_mat
		add_child(rim)
		rim.position = edge[1]

func _build_cell(index: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Cell%d" % index
	add_child(root)
	root.position = cell_local(index)

	var tile := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(cell_size - tile_gap, 0.1, cell_size - tile_gap)
	tile.mesh = tb
	var tile_mat := CelMaterials.cel_opaque(tile_color, Color.BLACK, 0.0, 0.0)
	tile.material_override = tile_mat
	root.add_child(tile)
	tile.position = Vector3(0, 0.1, 0)

	var carve := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = cell_size * 0.23
	torus.outer_radius = cell_size * 0.27
	torus.rings = 24
	torus.ring_segments = 4
	carve.mesh = torus
	var carve_mat := StandardMaterial3D.new()
	carve_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	carve_mat.albedo_color = carve_color
	carve.material_override = carve_mat
	root.add_child(carve)
	carve.position = Vector3(0, 0.15, 0)
	carve.scale = Vector3(1, 0.2, 1)

	var glow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * cell_size * 1.1
	glow.mesh = quad
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.albedo_texture = _glow_tex
	glow_mat.albedo_color = Color(0, 0, 0, 0)
	glow_mat.no_depth_test = false
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.material_override = glow_mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)
	glow.position = Vector3(0, 0.17, 0)
	glow.rotation.x = -PI * 0.5

	var viewport := SubViewport.new()
	viewport.size = Vector2i(ICON_PX, ICON_PX)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(viewport)
	var symbol := SlotSymbol.new()
	symbol.tile_style = null
	symbol.box_fraction = 0.96
	symbol.number_fraction = 0.36
	viewport.add_child(symbol)
	symbol.size = Vector2(ICON_PX, ICON_PX)

	var sprite := Sprite3D.new()
	sprite.texture = viewport.get_texture()
	sprite.pixel_size = icon_size / float(ICON_PX)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.double_sided = true
	sprite.render_priority = 2
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.visible = false
	root.add_child(sprite)
	sprite.position = Vector3(0, icon_height, 0)

	return { "root": root, "tile_mat": tile_mat, "glow_mat": glow_mat,
		"viewport": viewport, "symbol": symbol, "sprite": sprite }

func _make_glow_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t

# --- shown / folded ------------------------------------------------------------

## [expedition phase II] The board's states (PRD §5.2): folded away while the
## party travels, unfolding across the ground on arrival, lit through the fight,
## folding away once it is won and before the drops land. The looping demo never
## calls this, so its board stays out.
func show_board(on: bool, animate: bool) -> void:
	if _fold != null and _fold.is_valid():
		_fold.kill()
	_fold = null
	var flat := Vector3(0.02, 1.0, 0.02)
	if not animate:
		_shown = on
		visible = on
		scale = Vector3.ONE if on else flat
		return
	if on == _shown and visible == on:
		return
	_shown = on
	_fold = create_tween()
	if on:
		visible = true
		scale = flat
		_fold.tween_property(self, "scale", Vector3.ONE, unfold_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_fold.tween_property(self, "scale", flat, fold_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_fold.tween_callback(hide)

func is_shown() -> bool:
	return _shown

# --- colour --------------------------------------------------------------------

func _owner_color(owner_class: StringName) -> Color:
	match owner_class:
		&"warrior": return warrior_rune
		&"ranger": return ranger_rune
		&"mage": return mage_rune
	return rim_color

func _category_color(category: StringName) -> Color:
	match category:
		SlotIcon.CAT_FIRE: return Tuning.C_FIRE
		SlotIcon.CAT_ICE: return Tuning.C_ICE
		SlotIcon.CAT_LIGHTNING: return Color("7fb0ff")
		SlotIcon.CAT_BLOCK: return Tuning.C_DEFEND
		SlotIcon.CAT_CHARGE: return Tuning.C_GOLD_BRIGHT
	return Color("fff1c8")

func _set_glow(index: int, color: Color, strength: float) -> void:
	var mat: StandardMaterial3D = _cells[index]["glow_mat"]
	mat.albedo_color = Color(color.r * strength, color.g * strength, color.b * strength, 1.0) \
		if strength > 0.0 else Color(0, 0, 0, 0)

func _set_tile(index: int, color: Color) -> void:
	(_cells[index]["tile_mat"] as ShaderMaterial).set_shader_parameter("albedo", color)

# --- the spin -------------------------------------------------------------------

func _on_board_dealt(board: Array) -> void:
	_board = board.duplicate()
	_clear_beams()
	for i: int in range(_cells.size()):
		_set_tile(i, tile_color)
		_set_glow(i, Color.BLACK, 0.0)
	_spinning = [true, true, true]
	_flicker_left = 0.0
	set_process(true)

func _process(delta: float) -> void:
	_flicker_left -= delta
	if _flicker_left > 0.0:
		return
	_flicker_left = spin_flicker
	var any := false
	for col: int in range(3):
		if not _spinning[col]:
			continue
		any = true
		for row: int in range(3):
			_show_icon(row * 3 + col, _random_face(), true)
	if not any:
		set_process(false)

## A face for a spinning cell: any non-blank icon dealt this board, so the blur
## shows the party's own icons rather than noise. Cosmetic, so it draws from
## the global generator and never advances the seeded RNG combat reads.
func _random_face() -> Dictionary:
	var faces: Array = _board.filter(func(ic: Dictionary) -> bool: return not SlotIcon.is_blank(ic))
	if faces.is_empty():
		return {}
	return faces[randi() % faces.size()]

func _show_icon(index: int, icon: Dictionary, blurred: bool) -> void:
	var cell := _cells[index]
	var sprite: Sprite3D = cell["sprite"]
	if icon.is_empty() or SlotIcon.is_blank(icon):
		sprite.visible = false
		return
	(cell["symbol"] as SlotSymbol).set_icon(icon)
	(cell["viewport"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	sprite.visible = true
	sprite.modulate = Color(1, 1, 1, 0.45) if blurred else Color.WHITE
	if blurred:
		sprite.position.y = icon_height + 0.35
		sprite.scale = Vector3.ONE * 0.8

func _on_reel_stopped(column: int) -> void:
	_spinning[column] = false
	for row: int in range(3):
		_land(row * 3 + column)

## A column stops: its three icons drop into their runes and the runes light in
## their owners' colours. A blank leaves the carved rune dark.
func _land(index: int) -> void:
	if index >= _board.size():
		return
	var icon: Dictionary = _board[index]
	var sprite: Sprite3D = _cells[index]["sprite"]
	if SlotIcon.is_blank(icon):
		sprite.visible = false
		return
	_show_icon(index, icon, false)
	sprite.scale = Vector3.ONE
	sprite.position.y = icon_height + 1.0
	var tw := sprite.create_tween()
	tw.tween_property(sprite, "position:y", icon_height, 0.3) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_set_glow(index, _owner_color(StringName(icon.get("owner", &""))), 1.1)

func _on_lines_won(wins: Array) -> void:
	for win: Dictionary in wins:
		var cells: Array = win["cells"]
		var color := _category_color(StringName(win["category"]))
		_beam(int(cells[0]), int(cells[cells.size() - 1]), color)
		for idx: int in cells:
			_set_tile(idx, color.darkened(0.55))
	var first: Dictionary = wins[0]
	var text := "%s ×3" % SlotIcon.category_label(StringName(first["category"])) \
		if wins.size() == 1 else "%d lines!" % wins.size()
	var mid_cells: Array = first["cells"]
	_callout(text, _category_color(StringName(first["category"])), cell_world(int(mid_cells[1])))
	var world = get_parent()
	if world != null and world.has_method("shake"):
		world.shake(0.06, 0.25)

## A trench of light along a winning line, from half a cell beyond its first
## tile to half a cell beyond its last.
func _beam(from_index: int, to_index: int, color: Color) -> void:
	var a := cell_local(from_index)
	var b := cell_local(to_index)
	var dir := (b - a).normalized()
	var length := a.distance_to(b) + cell_size * 0.9
	var root := Node3D.new()
	add_child(root)
	root.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), (a + b) * 0.5 + Vector3.UP * 0.19)
	for layer: Array in [[0.12, 3.0, 1.0], [0.55, 1.3, 0.35]]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(layer[0], 0.03, length)
		mi.mesh = box
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(color.r * layer[1], color.g * layer[1], color.b * layer[1], layer[2])
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	root.scale = Vector3(1, 1, 0.05)
	var tw := root.create_tween()
	tw.tween_property(root, "scale:z", 1.0, 0.18).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_beams.append(root)

func _clear_beams() -> void:
	for b: Node3D in _beams:
		if is_instance_valid(b):
			b.queue_free()
	_beams.clear()

## Sir Fish's call, floating up off the winning line.
func _callout(text: String, color: Color, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = LABEL_FONT
	label.font_size = 120
	label.outline_size = 30
	label.outline_modulate = Tuning.C_INK
	label.modulate = color.lightened(0.35)
	label.pixel_size = 0.0065
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 5
	get_parent().add_child(label)
	label.global_position = at + Vector3.UP * 2.0
	label.scale = Vector3.ONE * 0.4
	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.8)
	tw.tween_property(label, "global_position:y", label.global_position.y + 0.8, 0.45)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.45)
	tw.tween_callback(label.queue_free)

# --- resolution -----------------------------------------------------------------

func _on_cell_resolved(index: int) -> void:
	if index >= _board.size():
		return
	var icon: Dictionary = _board[index]
	var sprite: Sprite3D = _cells[index]["sprite"]
	var tw := sprite.create_tween()
	tw.tween_property(sprite, "scale", Vector3.ONE * 1.35, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "scale", Vector3.ONE, 0.14)
	var owner_color := _owner_color(StringName(icon.get("owner", &"")))
	_set_glow(index, owner_color, 2.4)
	var back := create_tween()
	back.tween_interval(0.12)
	back.tween_callback(_set_glow.bind(index, owner_color, 1.1))
	_send_motes(index, icon)

## A mote flies from the tile to whoever the icon feeds: the hero who swings a
## strike or element (its owner, or the DAMAGE executor if the owner is down),
## the owner of a charge coin, or every living hero for a block.
func _send_motes(index: int, icon: Dictionary) -> void:
	if director == null:
		return
	var id := StringName(icon.get("id", &""))
	var kind: int = SlotIcon.kind_of(id)
	var color := _category_color(SlotIcon.category_of(id))
	var targets: Array = []
	if kind == SlotIcon.Kind.BLOCK:
		targets = director.living_heroes()
	else:
		var hero = _living_hero(StringName(icon.get("owner", &"")))
		if hero == null and kind == SlotIcon.Kind.DAMAGE:
			var living: Array = director.living_heroes()
			hero = living[0] if not living.is_empty() else null
		if hero != null:
			targets = [hero]
	var from := cell_world(index) + Vector3.UP * icon_height
	for hero: Variant in targets:
		if is_instance_valid(hero):
			_fly_mote(from, (hero as Combatant).hit_world_position(), color)

func _living_hero(hero_class: StringName) -> Combatant:
	if director == null or hero_class == &"":
		return null
	for h: Combatant in director.living_heroes():
		if h.stats != null and h.stats.id == hero_class:
			return h
	return null

func _fly_mote(from: Vector3, to: Vector3, color: Color) -> void:
	var mote := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	sphere.radial_segments = 8
	sphere.rings = 4
	mote.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r * 3.0, color.g * 3.0, color.b * 3.0, 1.0)
	mote.material_override = mat
	mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mote)
	mote.global_position = from
	var apex := (from + to) * 0.5 + Vector3.UP * 1.6
	var tw := mote.create_tween()
	tw.tween_method(func(t: float) -> void:
			var a := from.lerp(apex, t)
			var b := apex.lerp(to, t)
			mote.global_position = a.lerp(b, t),
		0.0, 1.0, 0.36).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(mote, "scale", Vector3.ONE * 2.2, 0.08)
	tw.tween_callback(mote.queue_free)

# --- between fights -------------------------------------------------------------

## The fight is over: the icons sink back into the stone and the runes go dark.
func _on_combat_ended(_victory: bool) -> void:
	_spinning = [false, false, false]
	set_process(false)
	_clear_beams()
	for i: int in range(_cells.size()):
		var sprite: Sprite3D = _cells[i]["sprite"]
		_set_tile(i, tile_color)
		_set_glow(i, Color.BLACK, 0.0)
		if not sprite.visible:
			continue
		var tw := sprite.create_tween()
		tw.set_parallel(true)
		tw.tween_property(sprite, "position:y", 0.2, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(sprite, "modulate:a", 0.0, 0.4)
		tw.chain().tween_callback(sprite.hide)
