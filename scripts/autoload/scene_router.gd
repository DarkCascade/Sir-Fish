extends Node
## [town] Scene routing (spec 3.1). Autoload `SceneRouter`, registered after
## SaveGame and before Hud so Hud - the heavier node, and the one go() calls
## into - is freed last.
##
## go() fades through Hud's Transition rect, swaps the scene with
## change_scene_to_file() (which keeps the autoloads alive and frees the old
## current_scene for us), then fades back. It is await-able so spec 8.5's
## failure flow can present a modal only once the destination is actually up.
##
## Nothing sibling-autoload is referenced in _ready()/_init() here - there are
## none - so test_autoload_safety.gd's lint passes. go()'s Hud reference is
## fine: it is not a lifecycle method.

enum Place { TOWN, INN, BLACKSMITH, MAYOR, QUEST }

## Every Place must have an entry (test_scene_router.gd asserts totality). All
## five scenes exist as of step 10; go()'s missing-path bail stays anyway - a
## typo'd path would otherwise soft-lock behind an opaque rect (spec 3.1).
const PATHS := {
	Place.TOWN:       "res://scenes/town/town.tscn",
	Place.INN:        "res://scenes/town/inn.tscn",
	Place.BLACKSMITH: "res://scenes/town/blacksmith.tscn",
	Place.MAYOR:      "res://scenes/town/mayor_office.tscn",
	Place.QUEST:      "res://scenes/main.tscn",
}

## Fade half-durations. No Tuning constant: this is chrome timing, not a
## gameplay number, and it lives at exactly one call site.
const FADE_TIME := 0.18

var place: Place = Place.TOWN
var _routing: bool = false

## Fades out, swaps to `to`, fades back in. Ignored (not queued) if a route is
## already in flight - go() is called from await-ing flows (spec 8.5) and a
## second call mid-transition must not stack.
##
## [day-night] `fade_out` / `fade_in` override the FADE_TIME default per call -
## the night's 1.5 s fade IS the route home (day/night spec §6.3). `force` skips
## the `to == place` early-out, which the §8.2 resume path needs: it routes
## TOWN -> TOWN to get the fade, and without `force` that fade is dropped.
func go(to: Place, fade_out: float = FADE_TIME, fade_in: float = FADE_TIME,
		force: bool = false) -> void:
	if _routing:
		return
	# Missing-path bail (spec 3.1): change_scene_to_file() on an absent path
	# returns ERR_CANT_OPEN and queues no swap, so a go() that had already faded
	# to black would await a swap that never comes - opaque rect, input blocked,
	# _routing stuck true. Check before touching the rect.
	var target: String = PATHS.get(to, "")
	if target.is_empty() or not ResourceLoader.exists(target):
		push_warning("SceneRouter.go(): no scene for Place %d (%s) - staying put" % [to, target])
		return
	if to == place and not force:
		return

	_routing = true
	var rect: ColorRect = Hud.transition
	rect.mouse_filter = Control.MOUSE_FILTER_STOP

	var fade_out_tw := create_tween()
	fade_out_tw.tween_property(rect, "modulate:a", 1.0, fade_out)
	await fade_out_tw.finished

	get_tree().change_scene_to_file(target)
	await get_tree().tree_changed        # the swap is deferred to frame end
	await get_tree().process_frame       # let the incoming scene's _ready() settle

	# Assigned after the swap settles - so it TRAILS the incoming scene's _ready()
	# (which is why every routed scene re-asserts its own place in _ready(),
	# step-5 Q8) - but still before the fade-out finishes, so `place` is correct
	# by the time the screen is visible again.
	place = to

	var fade_in_tw := create_tween()
	fade_in_tw.tween_property(rect, "modulate:a", 0.0, fade_in)
	await fade_in_tw.finished

	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_routing = false
