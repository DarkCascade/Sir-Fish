extends Button
## One purchasable slot upgrade (spec 17.6). 340 wide, height set by the tray.
##
## Re-evaluates on gold_changed and upgrade_purchased, exactly as the shop cards
## do - purchases, sales, slot payouts and other upgrades all move gold.
##
## [presentation redesign S8] Parchment, not stone - the only parchment surface
## in the console. Local StyleBoxFlat overrides here so ONLY these three cards
## go parchment; every other Button in the game keeps the global blue theme.

const PIP := 20.0
const PIP_GAP := 10.0
const ICON_SIZE := 40.0
const PLATE_HEIGHT := 46.0

var id: StringName = &""

var _title: Label
var _blurb: Label
var _icon: Control
var _pips: Control
var _plate: OrnateFrame
var _cost: Label
var _coin: Control
var _pulse: Tween = null

func setup(upgrade_id: StringName) -> void:
	id = upgrade_id
	_build()
	refresh()

func _ready() -> void:
	custom_minimum_size = Vector2(340, 236)
	resized.connect(_relayout)
	pressed.connect(_on_pressed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)
	EventBus.run_started.connect(refresh)
	_apply_parchment_styles()

## Parchment gradient (top C_PARCHMENT, bottom C_PARCHMENT_SHADE) via a
## StyleBoxFlat's own corner-to-corner bg color isn't supported directly, so
## the shade is approximated with a slightly darker single fill per state -
## still reads as parchment against the stone console, which is the goal.
func _apply_parchment_styles() -> void:
	var normal := _plate_style(Tuning.C_PARCHMENT, Tuning.C_GOLD_DARK)
	var hover := _plate_style(Tuning.C_PARCHMENT.lightened(0.06), Tuning.C_GOLD)
	var pressed_style := _plate_style(Tuning.C_PARCHMENT_SHADE, Tuning.C_GOLD_DARK)
	var disabled_style := _plate_style(Tuning.C_PARCHMENT_SHADE.darkened(0.15), Color("6B6558"))
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed_style)
	add_theme_stylebox_override("disabled", disabled_style)

func _plate_style(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_border_width_all(3)
	box.border_color = border
	box.set_corner_radius_all(10)
	box.content_margin_left = 16.0
	box.content_margin_top = 12.0
	box.content_margin_right = 16.0
	box.content_margin_bottom = 12.0
	return box

func _build() -> void:
	if _title != null:
		return
	var def: Dictionary = Upgrades.DEFS[id]

	_icon = Control.new()
	_icon.position = Vector2(14, 12)
	_icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.draw.connect(_draw_icon)
	add_child(_icon)

	_title = Label.new()
	_title.theme_type_variation = &"PlateLabel"        # ink, no outline (S8.2)
	_title.position = Vector2(64, 14)
	_title.add_theme_font_size_override("font_size", 28)
	_title.text = String(def["name"])
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_blurb = Label.new()
	_blurb.position = Vector2(16, 58)
	_blurb.custom_minimum_size = Vector2(308, 0)
	_blurb.add_theme_font_size_override("font_size", 22)
	_blurb.add_theme_color_override("font_color", Color(Tuning.C_INK, 0.78))
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
	_blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_blurb)

	_pips = Control.new()
	_pips.position = Vector2(16, size.y - 96)
	_pips.custom_minimum_size = Vector2(
		PIP * Tuning.UPGRADE_MAX_LEVEL + PIP_GAP * (Tuning.UPGRADE_MAX_LEVEL - 1), PIP)
	_pips.size = _pips.custom_minimum_size
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.draw.connect(_draw_pips)
	add_child(_pips)

	_plate = OrnateFrame.new()
	_plate.position = Vector2(12, size.y - PLATE_HEIGHT - 10)
	_plate.size = Vector2(316, PLATE_HEIGHT)
	_plate.border = 4.0
	_plate.corner_radius = 10.0
	_plate.inset_well = true
	_plate.edge_diamonds = false
	add_child(_plate)
	move_child(_plate, 0)   # behind coin/cost, drawn first

	_coin = Control.new()
	_coin.position = Vector2(26, size.y - PLATE_HEIGHT + 3)
	_coin.size = Vector2(28, 28)
	_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin.draw.connect(_draw_coin)
	add_child(_coin)

	_cost = Label.new()
	_cost.theme_type_variation = &"DisplayLabel"
	_cost.position = Vector2(62, size.y - PLATE_HEIGHT - 2)
	_cost.add_theme_font_size_override("font_size", 32)
	_cost.add_theme_color_override("font_color", Tuning.C_TEXT_GOLD)
	_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cost)

## Title/icon/blurb hang from the top, the price plate and pips from the
## bottom, so the card survives the tray being given a different height.
func _relayout() -> void:
	if _pips == null:
		return
	_pips.position = Vector2(16, size.y - 96)
	_plate.position = Vector2(12, size.y - PLATE_HEIGHT - 10)
	_coin.position = Vector2(26, size.y - PLATE_HEIGHT + 3)
	_cost.position = Vector2(62, size.y - PLATE_HEIGHT - 2)

## Diamond pips: filled = arcane core in a gold ring, empty = faint ink
## diamond outline. UPGRADE_MAX_LEVEL-driven, never hardcoded (S0.3).
func _draw_pips() -> void:
	var level := Upgrades.level(id)
	for i: int in range(Tuning.UPGRADE_MAX_LEVEL):
		var cx := float(i) * (PIP + PIP_GAP) + PIP * 0.5
		var c := Vector2(cx, PIP * 0.5)
		if i < level:
			_pips.draw_colored_polygon(_diamond(c, PIP * 0.5), Tuning.C_GOLD)
			_pips.draw_colored_polygon(_diamond(c, PIP * 0.32), Tuning.C_ARCANE)
		else:
			var pts := _diamond(c, PIP * 0.5)
			pts.append(pts[0])
			_pips.draw_polyline(pts, Color(Tuning.C_INK, 0.35), 2.0)

func _diamond(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0),
	])

func _draw_coin() -> void:
	var c := Vector2(14, 14)
	_coin.draw_circle(c, 12.0, Tuning.C_GOLD)
	_coin.draw_arc(c, 12.0, 0.0, TAU, 20, Tuning.C_CONSOLE_INSET, 2.0)

## Per-upgrade medallion, arcane disc with a gold ring. quick_reels gets three
## small dots (a reel's blank/blank/blank readout); overcharge and fat_purse
## reuse the slot's own bolt/star glyphs, since they ARE the same effect the
## card is describing.
func _draw_icon() -> void:
	var c := ICON_SIZE * 0.5 * Vector2.ONE
	_icon.draw_circle(c, ICON_SIZE * 0.5, Tuning.C_ARCANE_DEEP)
	_icon.draw_arc(c, ICON_SIZE * 0.5, 0.0, TAU, 24, Tuning.C_GOLD, 2.5)
	match id:
		&"overcharge":
			var poly := PackedVector2Array()
			for p: Vector2 in SlotSymbol.BOLT:
				poly.append(c + (p - Vector2(0.5, 0.5)) * ICON_SIZE * 0.62)
			_icon.draw_colored_polygon(poly, Tuning.C_ARCANE_BRIGHT)
		&"fat_purse":
			var poly := PackedVector2Array()
			for p: Vector2 in SlotSymbol.STAR:
				poly.append(c + (p - Vector2(0.5, 0.5)) * ICON_SIZE * 0.68)
			_icon.draw_colored_polygon(poly, Tuning.C_GOLD_BRIGHT)
		_:   # quick_reels
			for i: int in range(3):
				var dc := c + Vector2((float(i) - 1.0) * ICON_SIZE * 0.24, 0.0)
				_icon.draw_circle(dc, ICON_SIZE * 0.09, Tuning.C_GOLD_BRIGHT)

# --- state ------------------------------------------------------------------

func refresh() -> void:
	if _title == null:
		return
	var def: Dictionary = Upgrades.DEFS[id]
	_pips.queue_redraw()

	if Upgrades.is_maxed(id):
		_blurb.text = "%s." % (String(def["blurb"]) % Upgrades.next_effect_percent(id))
		_cost.text = "MAX"
		_cost.add_theme_color_override("font_color", Color("2F6B3E"))
		_coin.visible = false
		disabled = true
		modulate = Color.WHITE
		_kill_pulse()
		return

	# The blurb shows the NEXT level's cumulative effect, so the player is reading
	# what they are about to buy rather than what they already have.
	_blurb.text = "%s." % (String(def["blurb"]) % Upgrades.next_effect_percent(id))
	var price := Upgrades.cost(id)
	_cost.text = str(price)
	_cost.add_theme_color_override("font_color", Tuning.C_TEXT_GOLD)
	_coin.visible = true

	var affordable := GameState.gold >= price
	disabled = not affordable
	modulate = Color.WHITE if affordable else Color(0.68, 0.65, 0.6, 1.0)
	if affordable:
		_start_pulse()
	else:
		_kill_pulse()

func _start_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(self, "self_modulate", Color(1.06, 1.03, 0.92), 0.8) \
		.set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(self, "self_modulate", Color.WHITE, 0.8) \
		.set_trans(Tween.TRANS_SINE)

func _kill_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	self_modulate = Color.WHITE

# --- purchase ---------------------------------------------------------------

func _on_pressed() -> void:
	if not Upgrades.buy(id):
		return
	pivot_offset = size * 0.5
	var punch := create_tween()
	punch.tween_property(self, "scale", Vector2(1.06, 1.06), 0.125) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	punch.tween_property(self, "scale", Vector2.ONE, 0.125)
	# The newly-earned pip pops in.
	_pips.pivot_offset = _pips.size * 0.5
	_pips.scale = Vector2(0.6, 0.6)
	var pip_tw := create_tween()
	pip_tw.tween_property(_pips, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_gold_changed(_total: int, _delta: int) -> void:
	refresh()

func _on_upgrade_purchased(_id: StringName, _level: int) -> void:
	refresh()
