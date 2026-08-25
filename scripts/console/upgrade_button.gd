extends Button
## One purchasable slot upgrade (spec 17.6). 340 wide, height set by the tray.
##
## Re-evaluates on gold_changed and upgrade_purchased, exactly as the shop cards
## do - purchases, sales, slot payouts and other upgrades all move gold.
##
## [presentation redesign S8] Parchment, not stone - the only parchment surface
## in the console. Local StyleBoxFlat overrides on the node so ONLY these three
## cards go parchment; every other Button in the game keeps the global blue theme.
##
## [move-elements-to-editor] Everything with a position or a colour now lives in
## upgrade_button.tscn: the four parchment button faces, the medallion box, the
## pip row, the coin (a plain TextureRect), and the blurb's ink. What is left
## here is the two _draw() callbacks the inspector cannot express - the
## per-upgrade medallion and the per-level pip row - plus the state logic.
##
## [ui-project-longshot] Measured off the concept board, which gives the cards
## roughly a third of the console's height instead of the sixth they had. The
## card was 178 tall with a 52 px title overflowing its own box; it is 326 now
## and everything on it has room to sit where the board puts it: medallion and
## title on one line at the top, blurb under them, pips floating in the middle,
## price plate pinned to the bottom.

## Title auto-fit range - see _fit_title(). MAX is the size the board's titles
## read at; MIN is the floor past which a name would be smaller than its own
## blurb, at which point the card is wrong in some other way.
const TITLE_FONT_MAX := 42
const TITLE_FONT_MIN := 26
const TITLE_RIGHT_MARGIN := 16.0

var id: StringName = &""

## Every child is authored in upgrade_button.tscn. Icon and Pips are plain
## Controls whose _draw() this script supplies (a per-upgrade medallion and a
## per-level pip row - see _draw_icon/_draw_pips); Coin is a TextureRect and
## needs nothing from here but its visibility.
@onready var _title: Label = $Title
@onready var _blurb: Label = $Blurb
@onready var _cost: Label = $Cost
@onready var _icon: Control = $Icon
@onready var _pips: Control = $Pips
@onready var _coin: TextureRect = $Coin
var _pulse: Tween = null

## Called by the tray straight after instancing - which is before _ready(), so
## the id is stashed and the card is filled in once its children exist.
func setup(upgrade_id: StringName) -> void:
	id = upgrade_id
	if is_node_ready():
		_apply_definition()
		refresh()

func _ready() -> void:
	pressed.connect(_on_pressed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)
	EventBus.run_started.connect(refresh)
	_icon.draw.connect(_draw_icon)
	_icon.resized.connect(_icon.queue_redraw)
	_pips.draw.connect(_draw_pips)
	_pips.resized.connect(_pips.queue_redraw)
	if id != &"":
		_apply_definition()
		refresh()

## The one piece of the card that is per-upgrade text rather than layout. The
## .tscn carries a dummy title/blurb/price so the card reads correctly in the
## editor; this overwrites them with the real definition.
func _apply_definition() -> void:
	_title.text = String(Upgrades.DEFS[id]["name"])
	_fit_title()

## Shrinks the title's font until the name fits on ONE line in the box the
## .tscn gives it.
##
## The board puts every card's title on a single line beside its medallion, and
## the three names are very different lengths ("Fat Purse" against "Quick
## Reels"): at any single authored size either the short names look undersized
## or the long ones wrap and clip. Godot's Label has no auto-shrink, so this
## measures and steps down - three or four iterations at most, once per card at
## build time.
## The width is derived from the CARD (its authored custom_minimum_size), never
## read off the label.
##
## _title.size.x is not the label's box - a non-wrapping Label reports a
## minimum size of its own rendered text, and Control clamps size up to that,
## so a label whose text overflows reports the OVERFLOWING width. Measuring
## against it asks "does this text fit inside itself", which is always yes, and
## the first version of this function shrank nothing for exactly that reason.
func _fit_title() -> void:
	var available := custom_minimum_size.x - _title.position.x - TITLE_RIGHT_MARGIN
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
##
## The row is measured off the Pips node's own box: a pip is as tall as the box
## and the whole row spreads to fill its width, so dragging Pips wider in the
## editor spaces the pips out instead of leaving them bunched at the left.
func _draw_pips() -> void:
	var level := Upgrades.level(id)
	var pip := _pips.size.y
	var step := (_pips.size.x - pip) / maxf(float(Tuning.UPGRADE_MAX_LEVEL - 1), 1.0)
	for i: int in range(Tuning.UPGRADE_MAX_LEVEL):
		var c := Vector2(float(i) * step + pip * 0.5, pip * 0.5)
		if i < level:
			_pips.draw_colored_polygon(_diamond(c, pip * 0.5), Tuning.C_GOLD_DARK)
			_pips.draw_colored_polygon(_diamond(c, pip * 0.38), Tuning.C_GEM)
			# The lit upper facet, matching OrnateFrame's gems and its bevels -
			# everything in this console is lit from above.
			var r := pip * 0.38
			_pips.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r), c + Vector2(r * 0.55, -r * 0.42), c,
				c + Vector2(-r * 0.55, -r * 0.42),
			]), Tuning.C_GEM_BRIGHT)
		else:
			_pips.draw_colored_polygon(_diamond(c, pip * 0.5), Color(Tuning.C_INK, 0.22))
			_pips.draw_colored_polygon(_diamond(c, pip * 0.36), Color(Tuning.C_INK, 0.13))

func _diamond(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0),
	])

## Per-upgrade medallion, arcane disc with a gold ring. quick_reels gets three
## small dots (a reel's blank/blank/blank readout); overcharge and fat_purse
## reuse the slot's own bolt/star glyphs, since they ARE the same effect the
## card is describing.
## Sized off the Icon node's own box rather than a constant, so resizing the
## medallion in the editor actually resizes the medallion.
func _draw_icon() -> void:
	var d := minf(_icon.size.x, _icon.size.y)
	var c := _icon.size * 0.5
	# A struck medallion, not a flat disc: gold rim, dark field, and a highlight
	# arc across the top-left of the rim so it sits proud of the card face.
	_icon.draw_circle(c, d * 0.5, Tuning.C_GOLD_DARK)
	_icon.draw_circle(c, d * 0.42, Tuning.C_ARCANE_DEEP)
	_icon.draw_arc(c, d * 0.46, 0.0, TAU, 28, Tuning.C_GOLD, 3.0)
	_icon.draw_arc(c, d * 0.46, PI * 0.85, PI * 1.75, 16, Tuning.C_GOLD_BRIGHT, 3.0)
	match id:
		&"overcharge":
			var poly := PackedVector2Array()
			for p: Vector2 in SlotSymbol.BOLT:
				poly.append(c + (p - Vector2(0.5, 0.5)) * d * 0.62)
			_icon.draw_colored_polygon(poly, Tuning.C_ARCANE_BRIGHT)
		&"fat_purse":
			var poly := PackedVector2Array()
			for p: Vector2 in SlotSymbol.STAR:
				poly.append(c + (p - Vector2(0.5, 0.5)) * d * 0.68)
			_icon.draw_colored_polygon(poly, Tuning.C_GOLD_BRIGHT)
		_:   # quick_reels
			for i: int in range(3):
				var dc := c + Vector2((float(i) - 1.0) * d * 0.24, 0.0)
				_icon.draw_circle(dc, d * 0.09, Tuning.C_GOLD_BRIGHT)

# --- state ------------------------------------------------------------------

func refresh() -> void:
	if id == &"" or not is_node_ready():
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
