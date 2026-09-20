class_name ChargeMeter
extends Control
## [specials] One hero's special charge meter: the pip row in the tab under an
## invoker button (P7). Styled off the Meshy prototype - glowing gold dots in a
## dark plate with a thin gold rim.
##
## Drawn rather than textured, for the reason CLAUDE.md gives: pips are simple
## primitives that must stay parametric at runtime (they light, dim, partially
## fill and pulse), and a baked image loses all of that. The button's own glass
## dome and its neon glyph are the opposite case and want real art.
##
## Reads GameState.special_charges through EventBus.special_charges_changed, so
## it needs no per-frame polling and no reference to the battle at all - set
## `hero_class` in the inspector and it tracks that hero for the rest of the run.

## Which hero's meter this is. Authored per button in the editor rather than
## passed in code (CLAUDE.md: prefer inspector properties), so the tray's three
## buttons are three scene instances differing by one field.
@export var hero_class: StringName = &"":
	set(value):
		hero_class = value
		_refresh()

## Draws the plate behind the pips. Off for a meter sitting on an existing dark
## surface, on when it needs its own tab like the prototype's.
@export var show_plate: bool = true

## Pip radius as a fraction of the row's height. The prototype's dots are round
## and generously spaced rather than crowding their tab.
const PIP_RADIUS_FRACTION := 0.34
const PLATE_CORNER := 10.0

var _charge: int = 0
var _pulse: Tween = null

func _ready() -> void:
	EventBus.special_charges_changed.connect(_on_charges_changed)
	resized.connect(queue_redraw)
	_refresh()

func _refresh() -> void:
	_charge = GameState.special_charge(hero_class) if hero_class != &"" else 0
	queue_redraw()

func _on_charges_changed(changed_class: StringName, charges: int, _cost: int) -> void:
	if changed_class != hero_class:
		return
	# Explicitly typed: an autoload member is a Variant to the parser, so `:=`
	# here fails to infer (CLAUDE.md pitfall 2). The headless suite compiled it
	# anyway; the editor did not.
	var was_ready: bool = _charge >= Tuning.SPECIAL_CHARGE_COST
	_charge = charges
	queue_redraw()
	# A meter that has just filled announces itself once; one that was spent
	# stops pulsing rather than being left mid-tween.
	if not was_ready and is_ready():
		_start_pulse()
	elif was_ready and not is_ready():
		_stop_pulse()

func is_ready() -> bool:
	return _charge >= Tuning.SPECIAL_CHARGE_COST

# --- the pip mapping ----------------------------------------------------------

## How many pips are FULLY lit at `charge`, and how far the next one has filled
## (0.0-1.0). Static and pure so the mapping is testable without a viewport -
## the drawing below is the only other thing that knows about pips.
##
## Returns Vector2(lit_count, partial_fraction). At full charge every pip is lit
## and the fraction is 0: there is no fourth pip to be filling.
static func lit_pips(charge: int, cost: int, pips: int) -> Vector2:
	if pips <= 0 or cost <= 0:
		return Vector2.ZERO
	if charge >= cost:
		return Vector2(float(pips), 0.0)
	var exact: float = clampf(float(charge) / float(cost), 0.0, 1.0) * float(pips)
	var lit: float = floorf(exact)
	return Vector2(lit, exact - lit)

# --- drawing ------------------------------------------------------------------

func _draw() -> void:
	var pips: int = Tuning.SPECIAL_PIP_COUNT
	if pips <= 0:
		return
	if show_plate:
		_draw_plate()
	var split := lit_pips(_charge, Tuning.SPECIAL_CHARGE_COST, pips)
	var lit := int(split.x)
	var radius := size.y * PIP_RADIUS_FRACTION
	var step := (size.x - radius * 2.0) / maxf(float(pips - 1), 1.0)
	for i: int in range(pips):
		var c := Vector2(radius + float(i) * step, size.y * 0.5)
		if i < lit:
			_draw_pip_lit(c, radius)
		else:
			_draw_pip_socket(c, radius)
			if i == lit and split.y > 0.0:
				_draw_pip_partial(c, radius, split.y)

## The tab the pips sit in: a dark plate with the same thin gold rim the button
## above it carries, so the two read as one piece of hardware. A StyleBoxFlat
## rather than draw_rect(), because draw_rect cannot round a corner and the
## prototype's tab is rounded - square corners read as a debug box.
func _draw_plate() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Tuning.C_PLUM_VOID
	box.border_color = Color(Tuning.C_GOLD, 0.75)
	box.set_border_width_all(2)
	box.set_corner_radius_all(int(PLATE_CORNER))
	draw_style_box(box, Rect2(Vector2.ZERO, size))

## A spent pip: an empty socket. Solid, not an outline - the same reading the
## upgrade card's pips settled on, that a player must be able to count what is
## LEFT at a glance, and a hairline reads as absence rather than as a slot.
func _draw_pip_socket(c: Vector2, r: float) -> void:
	draw_circle(c, r, Color(Tuning.C_GOLD_DARK, 0.55))
	draw_circle(c, r * 0.72, Tuning.C_PLUM_VOID)

## A charged pip: gold, lit from above like everything else in this console,
## wrapped in the soft halo the prototype's dots carry.
func _draw_pip_lit(c: Vector2, r: float) -> void:
	draw_circle(c, r * 1.70, Color(Tuning.C_GOLD, 0.10))
	draw_circle(c, r * 1.42, Color(Tuning.C_GOLD, 0.20))
	draw_circle(c, r * 1.16, Color(Tuning.C_GOLD, 0.30))
	draw_circle(c, r, Tuning.C_GOLD_DARK)
	draw_circle(c, r * 0.82, Tuning.C_GOLD)
	# The top facet, matching the upgrade pips and the cabinet's bevels.
	draw_circle(c - Vector2(0, r * 0.26), r * 0.40, Tuning.C_GOLD_BRIGHT)

## The pip currently filling, as a wedge sweeping clockwise from twelve o'clock.
## This is what keeps three pips honest about a ten-charge meter: without it a
## player crossing from 3 charges to 6 would see nothing move.
func _draw_pip_partial(c: Vector2, r: float, fraction: float) -> void:
	var f := clampf(fraction, 0.0, 1.0)
	if f <= 0.0:
		return
	var points := PackedVector2Array([c])
	var steps := maxi(3, int(ceilf(f * 24.0)))
	for i: int in range(steps + 1):
		var t := -PI * 0.5 + TAU * f * (float(i) / float(steps))
		points.append(c + Vector2(cos(t), sin(t)) * r * 0.82)
	draw_colored_polygon(points, Color(Tuning.C_GOLD, 0.85))

# --- the ready pulse ----------------------------------------------------------

## A full meter breathes, so a player who is not watching the tab still catches
## that something became available. Stopped explicitly on spend - a tween left
## running would keep a spent meter glowing.
func _start_pulse() -> void:
	_stop_pulse()
	_pulse = create_tween().set_loops()
	_pulse.tween_property(self, "modulate", Color(1.18, 1.14, 1.0), 0.45) \
		.set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(self, "modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_SINE)

func _stop_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	modulate = Color.WHITE
