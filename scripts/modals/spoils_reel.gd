class_name SpoilsReel
extends VBoxContainer
## [party-wipe-consequences] One column of the run summary's spoils machine: a
## caption ("Gold"), a one-cell reel window, and the word it landed on.
##
## Deliberately its own small machine rather than a second SlotMachine: the
## cabinet's reels are three-cell scoring columns wired to the bag, the payline
## and combat resolution, none of which applies here. All this shares with them
## is the decelerate-and-thunk feel, which lives in spoils_reel_window.gd.

@onready var caption: Label = $Caption
@onready var window: Control = $Window
@onready var result: Label = $Result

var outcome: Spoils.Outcome = Spoils.Outcome.KEEP

func setup(category: Spoils.Category, victory: bool) -> void:
	caption.text = Spoils.caption(category)
	result.text = ""
	result.modulate.a = 0.0
	window.set_victory(victory)

func start_spin() -> void:
	window.start_spin()

## Lands on `value` and pops the word in under it. Awaitable - the modal spins
## the four reels together and stops them left to right.
func stop_on(value: Spoils.Outcome) -> void:
	outcome = value
	await window.stop_on(value).finished

	result.text = Spoils.label(value)
	result.add_theme_color_override("font_color", Spoils.color(value))
	result.pivot_offset = result.size * 0.5
	result.scale = Vector2(1.5, 1.5)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(result, "modulate:a", 1.0, 0.18)
	tw.tween_property(result, "scale", Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
