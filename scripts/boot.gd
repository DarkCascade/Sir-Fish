extends Node
## [town] The boot scene (spec 3.1). The project's main scene since step 5 -
## main.tscn stopped being it. Loads the profile (or mints and PERSISTS a fresh
## one), paints the HUD's currency plate, then hops to the town.
##
## A scene script, not an autoload, so it may call SaveGame / GameState /
## SceneRouter / EventBus directly in _ready() - test_autoload_safety.gd scans
## autoloads only (step-5 Q11).

func _ready() -> void:
	if not SaveGame.load_profile():
		GameState.new_profile()
		# The ONE place the new-profile fallback is persisted (spec 2.3 -
		# new_profile() itself never saves). This is the line the whole
		# "new_profile() never persists" rule exists to make deliberate.
		SaveGame.save_profile()

	# Autoloads _ready() before this scene, so Hud/CurrencyPlate already painted
	# from GameState's initialiser (gold 0) before load_profile() assigned the
	# real values silently, and nothing on the boot -> TOWN path emits
	# gold_changed. Nudge it with a zero delta - the established pattern
	# (game_state.gd), and a delta of 0 correctly floats no number (spec 3.1 /
	# step-5 Q5).
	EventBus.gold_changed.emit(GameState.gold, 0)
	EventBus.scrap_changed.emit(GameState.scrap, 0)

	# [perf] Compile the expedition's spatial shaders HERE, behind the bar,
	# rather than on the frame the quest button is pressed. A Firefox profile of
	# that transition measured 12.8 s of freeze in two rAF callbacks, 97% of it
	# WebGL program linking - see ShaderWarmup's header, and
	# `design documents/Sir Fish - Shader Link Counting Experiment.md`.
	#
	# This does not make the cold cost smaller, it moves it somewhere a player
	# expects to wait. On a warm GPU program cache it costs almost nothing, so
	# there is no reason to gate it behind an OS.has_feature("web") check: the
	# desktop editor pays single-digit milliseconds for the same safety.
	var warmup := ShaderWarmup.new()
	add_child(warmup)
	warmup.progress.connect(_on_warmup_progress)
	await warmup.run()
	warmup.queue_free()

	# One frame so the tree is done building this scene before we swap it -
	# change_scene_to_file() from inside _ready() otherwise trips "parent node
	# is busy adding/removing children".
	await get_tree().process_frame

	# First hop is un-faded: the screen is already black and Hud is one frame
	# old, so change_scene_to_file() directly rather than through go(), which
	# should never run against a Hud that new (step-5 Q7).
	SceneRouter.place = SceneRouter.Place.TOWN
	get_tree().change_scene_to_file(SceneRouter.PATHS[SceneRouter.Place.TOWN])

## Advances the bar. Driven by a signal rather than polled because each step is
## one blocking program link - the whole point of the yield in ShaderWarmup.run()
## is that this gets a frame to actually paint between them.
func _on_warmup_progress(done: int, total: int) -> void:
	var track: ColorRect = $Loading/Track
	var fill: ColorRect = $Loading/Track/Fill
	fill.size.x = track.size.x * (float(done) / float(maxi(total, 1)))
