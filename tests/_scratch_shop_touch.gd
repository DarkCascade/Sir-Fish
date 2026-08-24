extends Control
## [scratch] Harness for the mobile tap-and-drag scroll check on the shop's Sell
## tab (the Buy tab holds SHOP_ITEMS_FOR_SALE = 3 cards and never overflows).
##
## Mirrors main.tscn's ModalLayer: PROCESS_MODE_ALWAYS, so the modal keeps
## running once ShopModal.open() pauses the tree. Without that the whole thing
## freezes the frame it opens and nothing is testable.

const SHOP := preload("res://scenes/modals/shop_modal.tscn")

## Enough rows to overflow the ~960 px tab body at 180 + 16 per row.
const ROWS := 8

var shop: Control = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.gold = 500
	GameState.inventory.clear()
	for i: int in ROWS:
		GameState.add_item(Itemizer.generate_item())

	shop = SHOP.instantiate()
	add_child(shop)

	var enc := EncounterDef.new()
	enc.type = EncounterDef.Type.SHOP
	await get_tree().process_frame
	shop.open(enc)
	shop.tabs.current_tab = 1
	print("[harness] inventory=%d rows, gold=%d" % [GameState.inventory.size(), GameState.gold])
	# ScrollContainer's touch-drag branch is gated on this; if it reads false the
	# gesture is dead code on this platform no matter what the deadzone says.
	print("[harness] touchscreen_available=%s emulating_touch_from_mouse=%s" % [
		DisplayServer.is_touchscreen_available(),
		Input.is_emulating_touch_from_mouse()])

## Coordinates are the first Sell row's own layout (buttons at y 739-818) and go
## stale if the row geometry changes - re-read them with find_ui_elements rather
## than trusting these numbers after a resize.
##
## 1 = 60 px drag starting AND ending inside SellButton - the case that matters,
##     since a flick that leaves the button was always cancelled on release.
## 2 = same drag on the row body, clear of every button (the control).
## 3 = 12 px nudge on SellButton, deliberately under scroll_deadzone: still a tap,
##     so this one is EXPECTED to sell.
## 4 = dead-still tap on SellButton - must still sell.
## 5 = dead-still tap on CompareButton - must still open the flyout.
## 6 = switch to the Buy tab.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.is_pressed() and not event.is_echo()):
		return
	match (event as InputEventKey).keycode:
		KEY_1: run_touch_drag(815, 810, 750, 5)
		KEY_2: run_touch_drag(400, 900, 700, 5)
		KEY_3: run_touch_drag(815, 800, 788, 2)
		KEY_4: run_touch_drag(815, 778, 778, 1)   # dead-still tap on SellButton
		KEY_5: run_touch_drag(227, 778, 778, 1)   # dead-still tap on CompareButton
		KEY_6: shop.tabs.current_tab = 0

func _scroll_v() -> int:
	if shop == null:
		return -1
	var sc := shop.get_node_or_null("Panel/Layout/Tabs/Sell/Scroll") as ScrollContainer
	return sc.scroll_vertical if sc != null else -1

## Real InputEventScreenTouch/Drag, one per frame. The MCP mouse simulation goes
## in as mouse events, which never become ScreenDrag no matter what
## emulate_touch_from_mouse says - so a mouse-driven test measures the mouse path
## and tells us nothing about the gesture we are actually shipping.
func run_touch_drag(x: float, y_from: float, y_to: float, steps: int) -> void:
	var before_items := GameState.inventory.size()
	var before_gold := GameState.gold
	var before_scroll := _scroll_v()

	var t := InputEventScreenTouch.new()
	t.index = 0
	t.pressed = true
	t.position = Vector2(x, y_from)
	Input.parse_input_event(t)
	await get_tree().process_frame

	var prev := Vector2(x, y_from)
	for i: int in range(1, steps + 1):
		var pos := Vector2(x, lerpf(y_from, y_to, float(i) / float(steps)))
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = pos
		d.relative = pos - prev
		Input.parse_input_event(d)
		prev = pos
		await get_tree().process_frame

	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = Vector2(x, y_to)
	Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().process_frame

	print("[harness] drag x=%d %d->%d | items %d->%d | gold %d->%d | scroll %d->%d" % [
		x, y_from, y_to,
		before_items, GameState.inventory.size(),
		before_gold, GameState.gold,
		before_scroll, _scroll_v()])
