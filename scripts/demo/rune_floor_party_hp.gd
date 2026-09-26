extends Control
## [rune floor demo] Hero health, in the thumb dock under each hero's invoker -
## ranger left, warrior middle, mage right, the tray's own fixed order. In the
## shipped console this is the status strip's PartyBars; the Rune Floor puts it
## where the thumb already is, so the field above carries only the enemies' bars.

const FONT := preload("res://assets/fonts/Baloo2-Variable.ttf")

## Each class's bar centre, in this control's own x.
@export var centres: Dictionary = { &"ranger": 269.0, &"warrior": 540.0, &"mage": 811.0 }
@export var bar_size: Vector2 = Vector2(190, 16)
@export var font_size: int = 26

var director = null   # BattleDirector (untyped: custom API)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if director == null:
		return
	for h: Combatant in director.heroes:
		if not is_instance_valid(h) or h.stats == null or not centres.has(h.stats.id):
			continue
		var cx: float = centres[h.stats.id]
		var rect := Rect2(Vector2(cx - bar_size.x * 0.5, 0.0), bar_size)
		draw_rect(rect.grow(3.0), Tuning.C_INK)
		var alive := h.is_alive()
		var f := clampf(h.hp_fraction(), 0.0, 1.0) if alive else 0.0
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * f, rect.size.y)), Tuning.C_DANGER)
		var text := "%d / %d" % [h.current_hp, h.max_hp] if alive else "down"
		var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var at := Vector2(cx - width * 0.5, rect.end.y + font_size + 2.0)
		draw_string_outline(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Tuning.C_INK)
		draw_string(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			Tuning.C_TEXT if alive else Tuning.C_TEXT_DIM)
