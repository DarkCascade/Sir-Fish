extends Button
## One purchasable slot upgrade (spec 17.6). 340 wide, height set by the tray.
##
## Re-evaluates on gold_changed and upgrade_purchased, exactly as the shop cards
## do - purchases, sales, slot payouts and other upgrades all move gold.
##
## [presentation redesign S8] Parchment, not stone - the only parchment surface
## in the console. Local StyleBoxFlat overrides here so ONLY these three cards
## go parchment; every other Button in the game keeps the global blue theme.

## [ui-project-longshot] Measured off the concept board, which gives the cards
## roughly a third of the console's height instead of the sixth they had. The
## card was 178 tall with a 52 px title overflowing its own box; it is 326 now
## and everything on it has room to sit where the board puts it: medallion and
## title on one line at the top, blurb under them, pips floating in the middle,
## price plate pinned to the bottom.
const PIP := 22.0
const PIP_GAP := 14.0
const ICON_SIZE := 50.0
const PLATE_HEIGHT := 52.0
const CARD_WIDTH := 340.0
## How far the pip row floats above the price plate. The board leaves a clear
## band of empty stone between the blurb and the pips - the card is not full,
## and that emptiness is what makes it read as a carved tablet rather than a
## tooltip.
const PIP_BASELINE := -108.0

## Title auto-fit range - see _fit_title(). MAX is the size the board's titles
## read at; MIN is the floor past which a name would be smaller than its own
## blurb, at which point the card is wrong in some other way.
const TITLE_FONT_MAX := 42
const TITLE_FONT_MIN := 26
const TITLE_RIGHT_MARGIN := 16.0

## Coin + Cost read as one centred unit: the coin sits COIN_GAP left of
## Cost's own box, and Cost's text is centre-aligned within that box (see
## upgrade_button.tscn) rather than following the number's actual width, so
## the pair stays visually centred whether the price is "50" or "999".
const COIN_SIZE := 34.0
const COIN_GAP := 8.0
const COST_BOX_WIDTH := 120.0
## DisplayLabel's serifed numerals sit visually low within their line box -
## Godot centres on font ascent/descent, not glyph ink - so both the coin and
## Cost's text (offset by the same amount in the .tscn) are nudged up this
## much to actually look centred on the price plate.
const COST_VERTICAL_NUDGE := 4.0

var id: StringName = &""

## Title/Blurb/Cost/Plate are authored in upgrade_button.tscn - fixed style and
## position, and (for Cost/Plate) bottom anchors instead of the manual resize
## math _relayout() used to do. Icon/Pips/Coin stay script-built: each draws
## itself with a per-id or per-level _draw() callback that the inspector can't
## express (see _draw_icon/_draw_pips/_draw_coin below).
@onready var _title: Label = $Title
@onready var _blurb: Label = $Blurb
@onready var _cost: Label = $Cost
var _icon: Control
var _pips: Control
var _coin: Control
var _pulse: Tween = null

func setup(upgrade_id: StringName) -> void:
	id = upgrade_id
	_build()
	refresh()

func _ready() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, 326)
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
	if _icon != null:
		return
	var def: Dictionary = Upgrades.DEFS[id]

	_icon = Control.new()
	_icon.position = Vector2(18, 18)
	_icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.draw.connect(_draw_icon)
	add_child(_icon)

	_title.text = String(def["name"])
	_fit_title()

	_blurb.add_theme_color_override("font_color", Color(Tuning.C_INK, 0.78))
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD

	# Pips and coin hang from the bottom, same as Cost/Plate in the .tscn - set
	# via anchors here (bottom-left corner) rather than positioned by hand, so
	# the card survives the tray being given a different height without a
	# _relayout() to re-run the math. Both are centred on the card width.
	var pips_w := PIP * Tuning.UPGRADE_MAX_LEVEL + PIP_GAP * (Tuning.UPGRADE_MAX_LEVEL - 1)
	var pips_left := (CARD_WIDTH - pips_w) * 0.5
	_pips = Control.new()
	_pips.anchor_top = 1.0
	_pips.anchor_bottom = 1.0
	_pips.offset_left = pips_left
	_pips.offset_top = PIP_BASELINE
	_pips.offset_right = pips_left + pips_w
	_pips.offset_bottom = PIP_BASELINE + PIP
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.draw.connect(_draw_pips)
	add_child(_pips)

	# Coin + Cost's box together are COIN_SIZE + COIN_GAP + COST_BOX_WIDTH wide;
	# centring that whole span puts the coin this far from the card's left edge.
	var price_left := (CARD_WIDTH - (COIN_SIZE + COIN_GAP + COST_BOX_WIDTH)) * 0.5
	_coin = Control.new()
	_coin.anchor_top = 1.0
	_coin.anchor_bottom = 1.0
	_coin.offset_left = price_left
	_coin.offset_top = -(PLATE_HEIGHT - 3.0) - COST_VERTICAL_NUDGE
	_coin.offset_right = price_left + COIN_SIZE
	_coin.offset_bottom = -(PLATE_HEIGHT - 3.0) - COST_VERTICAL_NUDGE + COIN_SIZE
	_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin.draw.connect(_draw_coin)
	add_child(_coin)

## Shrinks the title's font until the name fits on ONE line in the box the
## .tscn gives it.
##
## The board puts every card's title on a single line beside its medallion, and
## the three names are very different lengths ("Fat Purse" against "Quick
## Reels"): at any single authored size either the short names look undersized
## or the long ones wrap and clip. Godot's Label has no auto-shrink, so this
## measures and steps down - three or four iterations at most, once per card at
## build time.
## The width is derived from the CARD, never read off the label.
##
## _title.size.x is not the label's box - a non-wrapping Label reports a
## minimum size of its own rendered text, and Control clamps size up to that,
## so a label whose text overflows reports the OVERFLOWING width. Measuring
## against it asks "does this text fit inside itself", which is always yes, and
## the first version of this function shrank nothing for exactly that reason.
func _fit_title() -> void:
	var available := CARD_WIDTH - _title.position.x - TITLE_RIGHT_MARGIN
	var font := _title.get_theme_font("font")
	var px := TITLE_FONT_MAX
	while px > TITLE_FONT_MIN:
		if font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= available:
			break
		px -= 2
	_title.add_theme_font_size_override("font_size", px)

## Diamond pips. UPGRADE_MAX_LEVEL-driven, never hardcoded (S0.3).
##
## [ui-project-longshot] Both states are now SOLID, which is the board's
## reading: a spent level is a blue gem set in the stone, an unspent one is the
## empty grey socket it will go into. The old empty state was a hairline
## outline, which at this size read as absence rather than as a slot - the
## player could not see at a glance how many levels were left, only how many
## were taken.
func _draw_pips() -> void:
	var level := Upgrades.level(id)
	for i: int in range(Tuning.UPGRADE_MAX_LEVEL):
		var cx := float(i) * (PIP + PIP_GAP) + PIP * 0.5
		var c := Vector2(cx, PIP * 0.5)
		if i < level:
			_pips.draw_colored_polygon(_diamond(c, PIP * 0.5), Tuning.C_GOLD_DARK)
			_pips.draw_colored_polygon(_diamond(c, PIP * 0.38), Tuning.C_GEM)
			# The lit upper facet, matching OrnateFrame's gems and its bevels -
			# everything in this console is lit from above.
			var r := PIP * 0.38
			_pips.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r), c + Vector2(r * 0.55, -r * 0.42), c,
				c + Vector2(-r * 0.55, -r * 0.42),
			]), Tuning.C_GEM_BRIGHT)
		else:
			_pips.draw_colored_polygon(_diamond(c, PIP * 0.5), Color(Tuning.C_INK, 0.22))
			_pips.draw_colored_polygon(_diamond(c, PIP * 0.36), Color(Tuning.C_INK, 0.13))

func _diamond(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0),
	])

func _draw_coin() -> void:
	_coin.draw_texture_rect(SlotSymbol.TEX_GOLD, Rect2(Vector2.ZERO, _coin.size), false)

## Per-upgrade medallion, arcane disc with a gold ring. quick_reels gets three
## small dots (a reel's blank/blank/blank readout); overcharge and fat_purse
## reuse the slot's own bolt/star glyphs, since they ARE the same effect the
## card is describing.
func _draw_icon() -> void:
	var c := ICON_SIZE * 0.5 * Vector2.ONE
	# A struck medallion, not a flat disc: gold rim, dark field, and a highlight
	# arc across the top-left of the rim so it sits proud of the card face.
	_icon.draw_circle(c, ICON_SIZE * 0.5, Tuning.C_GOLD_DARK)
	_icon.draw_circle(c, ICON_SIZE * 0.42, Tuning.C_ARCANE_DEEP)
	_icon.draw_arc(c, ICON_SIZE * 0.46, 0.0, TAU, 28, Tuning.C_GOLD, 3.0)
	_icon.draw_arc(c, ICON_SIZE * 0.46, PI * 0.85, PI * 1.75, 16, Tuning.C_GOLD_BRIGHT, 3.0)
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
	if _icon == null:
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
