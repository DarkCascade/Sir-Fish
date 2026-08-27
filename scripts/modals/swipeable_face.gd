extends PanelContainer
## Shared swipe-to-reveal-action layer for the shop's Buy and Sell cards.
## Lives on the "Face" node (see shop_buy_card.tscn / shop_sell_row.tscn) and
## slides itself left to expose the "Compare" lane in the sibling ActionLayer,
## which it finds by name so both scenes can wire it up identically.
##
## Buying/selling stay a single deliberate tap on their own full-width bar -
## never a drag - an accidental spend or sale is the worst failure mode a shop
## can have. This is the one drag gesture the cards use, and it only ever
## reveals a Compare button that itself still requires a tap.

signal action_triggered()

const REVEAL_WIDTH := 184.0
const OPEN_THRESHOLD := REVEAL_WIDTH * 0.5
const DRAG_SLOP := 8.0   # px of finger travel before a press commits to a swipe, not a tap

var _face_offset: float = 0.0   # 0 = closed, -REVEAL_WIDTH = fully open
var _revealed: bool = false
var _dragging: bool = false
var _drag_committed: bool = false
var _drag_start := Vector2.ZERO
var _drag_start_offset: float = 0.0
var _reveal_tween: Tween = null

@onready var _action_button: Button = get_parent().get_node("ActionLayer/ActionButton")

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	_action_button.pressed.connect(_on_action_pressed)

## A one-time swipe-and-back to teach the gesture exists, without a word of
## text. Callers gate how often this fires (see shop_buy_card.gd/
## shop_sell_row.gd's own per-class "taught" flags).
func peek() -> void:
	if _dragging or _revealed:
		return
	var t := create_tween()
	t.tween_property(self, "position:x", -70.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position:x", 0.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func close() -> void:
	_snap(false)

## For a card that is about to fade out and be freed (a sale leaving the
## list): closes the reveal and hides the ActionLayer behind this control
## outright, rather than leaving it merely closed. Fading the WHOLE card via
## `modulate` (see shop_sell_row.gd's departure tween) reduces every layer's
## alpha together, including this opaque-looking Face - at a shared partial
## alpha, Face no longer fully occludes whatever sits behind it, so the
## "Compare" panel would otherwise bleed through for the length of the fade.
func lock_closed() -> void:
	if _reveal_tween != null:
		_reveal_tween.kill()
	_dragging = false
	_revealed = false
	_face_offset = 0.0
	position.x = 0.0
	get_parent().get_node("ActionLayer").visible = false

## position arrives local to this control - and this control is exactly what
## the drag slides. Reading deltas in that frame is a feedback loop: as it
## moves, the same fingertip reports a different local x, damping the drag to
## a fraction of the real finger travel. Converting through its own transform
## recovers the finger's true position regardless of how far it has already
## moved, breaking the loop.
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		var pressed: bool = event.pressed
		if pressed:
			_dragging = true
			_drag_committed = false
			_drag_start = get_global_transform() * event.position
			_drag_start_offset = _face_offset
			if _reveal_tween != null:
				_reveal_tween.kill()
		elif _dragging:
			_dragging = false
			if _drag_committed:
				_snap(_face_offset < -OPEN_THRESHOLD)
			elif _revealed:
				_snap(false)   # a plain tap while open just dismisses it
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and _dragging:
		var gpos: Vector2 = get_global_transform() * event.position
		var dx: float = gpos.x - _drag_start.x
		if not _drag_committed and absf(dx) > DRAG_SLOP:
			_drag_committed = true
		if _drag_committed:
			_face_offset = clampf(_drag_start_offset + dx, -REVEAL_WIDTH, 0.0)
			position.x = _face_offset

func _snap(open: bool) -> void:
	_revealed = open
	_face_offset = -REVEAL_WIDTH if open else 0.0
	if _reveal_tween != null:
		_reveal_tween.kill()
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(self, "position:x", _face_offset, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_action_pressed() -> void:
	action_triggered.emit()
	_snap(false)
