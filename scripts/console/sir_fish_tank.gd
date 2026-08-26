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

@onready var viewport: SubViewport = $FishViewport

func _ready() -> void:
	# UPDATE_ONCE renders exactly one frame and then reverts itself to
	# disabled (Godot's own behaviour), so the timer below is the only thing
	# keeping the tank moving - not a fallback for some other update mode.
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var timer := Timer.new()
	timer.wait_time = 1.0 / REFRESH_HZ
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(_on_refresh_tick)

func _on_refresh_tick() -> void:
	# Skipping the re-render while the container itself isn't visible (e.g. a
	# modal covering the console) means a covered tank costs nothing at all,
	# not even the throttled rate.
	if is_visible_in_tree():
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
