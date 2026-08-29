extends Control
## The 2D layer that sits exactly over the battle SubViewport. Because
## BattleView and BattleOverlay are the same size at the same position, a point
## from camera.unproject_position() maps 1:1 into local coordinates with no
## extra transform (spec 3.3).

const BARS_SCENE := preload("res://scenes/overlay/combatant_bars.tscn")
const CHUNK_SCENE := preload("res://scenes/overlay/floating_health_chunk.tscn")
const NUMBER_SCENE := preload("res://scenes/overlay/damage_number.tscn")
const ICON_SCENE := preload("res://scenes/overlay/status_icon.tscn")

@onready var bars_layer: Control = $BarsLayer
@onready var floating_layer: Control = $FloatingLayer
@onready var vfx_layer: Control = $VfxLayer

var _bars: Dictionary = {}          # Combatant -> CombatantBars
var _camera: Camera3D = null

## Set by the slot machine while it applies lightning damage, so those numbers
## read in lightning blue rather than danger red (spec 11.4).
var number_color_override: Variant = null

## Spec 9.7 / 11.4 anti-overlap. Three 42 px numbers with 6 px outlines landing
## in the same two frames inside a 640 px viewport is unreadable, and legibility
## is pillar 1. Numbers spawned inside this window count as one burst and are
## fanned out from centre.
const BURST_WINDOW := 0.25
var _burst_count: int = 0
var _burst_timer: float = 0.0

func _ready() -> void:
	EventBus.combatant_spawned.connect(_on_spawned)
	EventBus.combatant_damaged.connect(_on_damaged)
	EventBus.combatant_healed.connect(_on_healed)
	EventBus.combatant_died.connect(_on_died)

func _process(delta: float) -> void:
	if _burst_timer > 0.0:
		_burst_timer = maxf(0.0, _burst_timer - delta)
		if _burst_timer == 0.0:
			_burst_count = 0
	var cam := _get_camera()
	if cam == null:
		return
	for c: Variant in _bars.keys():
		if not is_instance_valid(c):
			_bars.erase(c)
			continue
		var combatant: Combatant = c
		var bars: Variant = _bars[c]
		if not is_instance_valid(bars):
			_bars.erase(c)
			continue
		var world_pos := combatant.bar_world_position()
		var vp := cam.unproject_position(world_pos)
		# Hero bars are wide enough to hang off the viewport when a hero stands
		# near an edge, and a clipped name chip or a clipped HP number is worse
		# than a bar that is a few pixels off-centre (pillar 1).
		var new_pos := Vector2(
			clampf(vp.x - bars.size.x * 0.5, 0.0, maxf(size.x - bars.size.x, 0.0)),
			vp.y - bars.size.y * 0.5)
		# Writing Control.position dirties layout even when the value hasn't
		# actually moved, and most frames an idle combatant hasn't (smoothness
		# pass, spec 16.4-adjacent). Most combatants sit still between actions,
		# so this skips the write on nearly every frame nobody is animating.
		if not bars.position.is_equal_approx(new_pos):
			bars.position = new_pos
		bars.visible = not cam.is_position_behind(world_pos)
		bars.refresh()

func _get_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	var world := get_tree().get_first_node_in_group("battle_world")
	if world == null:
		return null
	_camera = world.get_node_or_null("BattleCamera") as Camera3D
	return _camera

func screen_position(world_pos: Vector3) -> Vector2:
	var cam := _get_camera()
	if cam == null:
		return Vector2.ZERO
	return cam.unproject_position(world_pos)

# --- bars -------------------------------------------------------------------

## Enemies only. A hero's bars live in the console's party strip (party_bars.gd),
## where three of them sit still and read as a roster; over the battlefield they
## were a third row of numbers drifting around with the characters.
func _on_spawned(c: Node) -> void:
	var combatant := c as Combatant
	if combatant == null or combatant.is_hero or _bars.has(combatant):
		return
	var bars = BARS_SCENE.instantiate()
	bars_layer.add_child(bars)
	bars.setup(combatant)
	bars.set_health_fraction(combatant.hp_fraction())
	bars.pop_in()
	_bars[combatant] = bars

func _on_damaged(target: Node, amount: int, previous_hp: int, new_hp: int) -> void:
	var combatant := target as Combatant
	if combatant == null:
		return
	var bars: Variant = _bars.get(combatant, null)
	if bars != null and is_instance_valid(bars):
		var f_prev := float(previous_hp) / float(maxi(combatant.max_hp, 1))
		var f_new := float(new_hp) / float(maxi(combatant.max_hp, 1))
		var rect: Rect2 = bars.lost_segment_rect(f_prev, f_new)
		bars.set_health_fraction(f_new)
		bars.flash_background()
		_spawn_chunk(rect)
	# Elemental item damage recolours the number to the party's dominant element
	# (spec 11.4 / 13.5). Cosmetic - there are no resistances in the demo.
	var color: Color = number_color_override if number_color_override != null \
		else GameState.element_color()
	_spawn_damage_number(combatant, str(amount), color)

func _spawn_chunk(rect: Rect2) -> void:
	var chunk = CHUNK_SCENE.instantiate()
	floating_layer.add_child(chunk)
	chunk.size = rect.size
	chunk.global_position = rect.position
	chunk.color = Tuning.C_DANGER
	chunk.launch()

func _on_healed(target: Node, _amount: int) -> void:
	var combatant := target as Combatant
	if combatant == null:
		return
	var bars: Variant = _bars.get(combatant, null)
	if bars != null and is_instance_valid(bars):
		bars.tween_health_fraction(combatant.hp_fraction())

func _on_died(c: Node) -> void:
	var combatant := c as Combatant
	var bars: Variant = _bars.get(combatant, null)
	if bars != null and is_instance_valid(bars):
		bars.fade_and_free()
	_bars.erase(combatant)

# --- floating elements ------------------------------------------------------

func _spawn_damage_number(c: Combatant, text: String, color: Color) -> void:
	# 0, +46, -46, +92, ... outward from centre (spec 11.4).
	var n := _burst_count
	_burst_count += 1
	_burst_timer = BURST_WINDOW
	var flip := 1.0 if n % 2 == 1 else -1.0
	var offset_x := Tuning.DAMAGE_NUMBER_SPREAD * float(ceili(float(n) / 2.0)) * flip
	var pos := screen_position(c.bar_world_position()) \
		+ Vector2(offset_x + RNG.randf_range(-30.0, 30.0), -20.0)
	var label = NUMBER_SCENE.instantiate()
	floating_layer.add_child(label)
	label.position = pos
	label.show_number(text, color)

func spawn_number(c: Combatant, text: String, color: Color) -> void:
	_spawn_damage_number(c, text, color)

## Used by the loot chest for its rising item labels (spec 14.2).
func spawn_world_label(world_pos: Vector3, text: String, color: Color,
		font_size: int = 40, rise: float = 120.0, duration: float = 1.2) -> void:
	var label = NUMBER_SCENE.instantiate()
	floating_layer.add_child(label)
	label.position = screen_position(world_pos)
	label.show_number(text, color, font_size, rise, duration)

func spawn_status_icon(c: Combatant, kind: String, duration: float) -> void:
	var icon = ICON_SCENE.instantiate()
	vfx_layer.add_child(icon)
	icon.setup(kind, c)
	icon.position = screen_position(c.hit_world_position()) - icon.size * 0.5
	if kind == "defend":
		icon.play_defend(duration)
	else:
		icon.play_heal()

# --- lifecycle --------------------------------------------------------------

func clear_all() -> void:
	for bars: Variant in _bars.values():
		if is_instance_valid(bars):
			(bars as Node).queue_free()
	_bars.clear()
	for layer: Control in [floating_layer, vfx_layer]:
		for child: Node in layer.get_children():
			child.queue_free()
