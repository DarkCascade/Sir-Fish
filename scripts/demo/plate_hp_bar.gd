extends Control
class_name PlateHpBar
## [rune floor dock] A hero plate's health bar: a thick rounded bar with the
## numbers printed inside it, sized to read on a phone (design A of the dock
## mockups - the numbers are 36 px here, 13 pt on a 390 pt phone). HeroPlate
## feeds it every frame; the bar only draws.

## Baloo 2 at wght 800 - the demo scene assigns it.
@export var font: Font
@export var font_size: int = 36
@export var outline_size: int = 8
@export var corner_radius: int = 14
@export var border_width: int = 3
## At or below this fraction the bar reads as in danger: a red rim and a red
## tint on the numbers.
@export var low_fraction: float = 0.3

var current_hp: int = 0
var max_hp: int = 1
var alive: bool = true

func set_values(current: int, maximum: int, is_alive: bool) -> void:
	if current == current_hp and maximum == max_hp and is_alive == alive:
		return
	current_hp = current
	max_hp = maximum
	alive = is_alive
	queue_redraw()

func _draw() -> void:
	var frac := clampf(float(current_hp) / float(maxi(max_hp, 1)), 0.0, 1.0) if alive else 0.0
	var low := alive and frac <= low_fraction

	var track := StyleBoxFlat.new()
	track.bg_color = Color("2a0c10") if low else Color("0a0710")
	track.border_color = Tuning.C_DANGER if low else Color.BLACK
	track.set_border_width_all(border_width)
	track.set_corner_radius_all(corner_radius)
	draw_style_box(track, Rect2(Vector2.ZERO, size))

	if frac > 0.0:
		var inner := Rect2(Vector2.ONE * border_width, size - Vector2.ONE * border_width * 2.0)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Tuning.C_DANGER
		fill.set_corner_radius_all(maxi(corner_radius - border_width, 0))
		draw_style_box(fill, Rect2(inner.position, Vector2(maxf(inner.size.x * frac, 1.0), inner.size.y)))

	if font == null:
		return
	var text := "%d / %d" % [current_hp, max_hp] if alive else "Down"
	var colour := Color("FFC2C5") if low else (Tuning.C_TEXT if alive else Tuning.C_TEXT_DIM)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var at := Vector2((size.x - width) * 0.5, (size.y + ascent - descent) * 0.5)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, Tuning.C_INK)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
