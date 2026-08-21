extends Control
## Procedurally drawn status overlay: the warrior's defend shield and the
## priest's heal plus (spec 17.5). No image files anywhere in this game.

# PackedVector2Array literals are not constant expressions in GDScript.
static var SHIELD := PackedVector2Array([
	Vector2(0.5, 0.12), Vector2(0.82, 0.26), Vector2(0.82, 0.55),
	Vector2(0.5, 0.88), Vector2(0.18, 0.55), Vector2(0.18, 0.26),
])

@export var kind: String = "defend"

## Every icon registers the combatant it belongs to, so cancel_all_effects() can
## free it the instant that combatant dies (spec 8.5 / Q15). v1 let the warrior's
## defend shield play out its full 4 seconds over a corpse.
var owner_combatant: Combatant = null

func setup(icon_kind: String, a_owner: Combatant = null) -> void:
	kind = icon_kind
	owner_combatant = a_owner
	if a_owner != null:
		a_owner.register_status_icon(self)
	size = Vector2(140, 140)
	pivot_offset = size * 0.5
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	if kind == "defend":
		draw_circle(c, Tuning.ICON_DEFEND_RADIUS, Color(Tuning.C_DEFEND, Tuning.ICON_DEFEND_FILL_ALPHA))
		draw_arc(c, Tuning.ICON_DEFEND_RADIUS, 0.0, TAU, 48, Tuning.C_TEXT, Tuning.ICON_RING_WIDTH)
		draw_colored_polygon(_scaled(SHIELD, c, Tuning.ICON_DEFEND_GLYPH_BOX), Tuning.C_TEXT)
	else:
		draw_circle(c, Tuning.ICON_HEAL_RADIUS, Color(Tuning.C_HEAL, Tuning.ICON_HEAL_FILL_ALPHA))
		draw_arc(c, Tuning.ICON_HEAL_RADIUS, 0.0, TAU, 48, Color(Tuning.C_HEAL, 0.9), Tuning.ICON_RING_WIDTH)
		draw_colored_polygon(_scaled(SlotSymbol.PLUS, c, Tuning.ICON_HEAL_GLYPH_BOX), Color(Tuning.C_HEAL, 0.75))

static func _scaled(points: PackedVector2Array, center: Vector2, box: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(center + (p - Vector2(0.5, 0.5)) * box)
	return out

## Defend: fade in, pulse for the whole buff, fade out (spec 9.1).
func play_defend(duration: float) -> void:
	modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.15)

	var pulse := create_tween().set_loops(int(ceil(duration)))
	pulse.tween_property(self, "scale", Vector2(1.12, 1.12), 0.5) \
		.set_trans(Tween.TRANS_SINE)
	pulse.tween_property(self, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)

	await get_tree().create_timer(duration).timeout
	if not is_instance_valid(self):
		return
	var out := create_tween()
	out.tween_property(self, "modulate:a", 0.0, 0.25)
	out.tween_callback(queue_free)

## Heal: shrinks while fading out (spec 9.3).
func play_heal() -> void:
	modulate.a = 1.0
	scale = Vector2.ONE
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.55, 0.55), 0.70) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.70) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)
