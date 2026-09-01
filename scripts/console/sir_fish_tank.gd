extends SubViewportContainer
## Sir Fish's tank (spec 17.7). A glass bowl bolted into the console's resource
## strip, and instanced a second time at 2x in the run summary's header
## (spec 18.2).
##
## [move-elements-to-editor] The bowl used to be assembled in _ready(); it is
## authored in sir_fish_tank.tscn now, under FishViewport/Tank:
##
##     WaterBackdrop  lit disc BEHIND the fish. The viewport is transparent_bg,
##                    so without it the glass tints straight onto the console's
##                    near-black panel and the tank reads as a dark blob with a
##                    fish-shaped smudge in it.
##     Glass          the bowl itself, on water.gdshader (depth_draw_never, so
##                    the fish reads through it).
##     Base/Gravel    gold stand and gravel bed.
##     Plaque         + PlaqueText, a Label3D so no font asset is ever baked
##                    into a mesh (spec 23.5).
##
## Nothing about that needed to be code - each instance of this scene gets its
## own copy of the authored children exactly as it got its own built ones, and
## every radius, colour and offset is now inspector-editable.
##
## [smoothness pass] FishViewport used to carry render_target_update_mode =
## UPDATE_ALWAYS - a second full 3D world (own_world_3d = true, its own camera
## and light) re-rendered every single frame regardless of whether the fish
## was doing anything, which on a tile-based mobile GPU is a whole extra
## render-target bind and tile flush 60 times a second. The tank is
## decorative background motion, not gameplay, so it is throttled to
## REFRESH_HZ here instead - visually indistinguishable at a glance, and it
## also goes fully idle the moment a modal or another screen covers it.

## How often the tank actually re-renders. Anything above ~15-20 reads as
## smooth motion for a slow-swimming fish; higher just spends frame budget
## nobody notices, which is the exact cost this pass is trying to claw back.
const REFRESH_HZ := 20.0

## [perf] How long after _ready() the tank is allowed to draw its first frame.
##
## This scene comes up as part of the console, which means its first render
## would otherwise land on the single heaviest frame in the game: the one where
## main.tscn is instantiated, the party spawns, and - on a cold GPU program
## cache - dozens of shader programs link. Adding a SECOND 3D world to that
## frame (own_world_3d, its own camera, light and render target) is the one
## cost here that is pure decoration, so it waits for the expensive frames to
## pass. Half a second is comfortably past them and far too short to notice on
## an ornament that idles at REFRESH_HZ anyway.
const FIRST_RENDER_DELAY := 0.5

@onready var viewport: SubViewport = $FishViewport

## False until FIRST_RENDER_DELAY has elapsed. The refresh timer starts ticking
## immediately (at 20 Hz its first tick is only 50 ms away, nowhere near enough
## deferral on its own), so the gate has to live in the tick, not in the timer.
var _armed: bool = false

func _ready() -> void:
	# Starts DISABLED rather than UPDATE_ONCE - see FIRST_RENDER_DELAY.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var timer := Timer.new()
	timer.wait_time = 1.0 / REFRESH_HZ
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(_on_refresh_tick)

	await get_tree().create_timer(FIRST_RENDER_DELAY).timeout
	_armed = true

func _on_refresh_tick() -> void:
	# Skipping the re-render while the container itself isn't visible (e.g. a
	# modal covering the console) means a covered tank costs nothing at all,
	# not even the throttled rate.
	#
	# UPDATE_ONCE renders exactly one frame and then reverts itself to disabled
	# (Godot's own behaviour), so this tick is the only thing keeping the tank
	# moving - not a fallback for some other update mode.
	if _armed and is_visible_in_tree():
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
