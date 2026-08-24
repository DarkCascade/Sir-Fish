## Autoload injected by Godot MCP Pro plugin at runtime.
## Monitors for screenshot requests from the editor and captures the game viewport.
extends Node

const REQUEST_PATH := "user://mcp_screenshot_request"
const SCREENSHOT_PATH := "user://mcp_screenshot.png"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# [Sir Fish, ui-project-longshot] This service polls the filesystem once per
	# frame and only ever has an editor on the other end of that poll, but the
	# plugin registers it as a plain autoload - so it shipped in the exported
	# build too, statting user:// 60 times a second. On the web export user://
	# is IndexedDB behind Emscripten's synchronous FS shim, which made this (and
	# its two sibling services) a measurable per-frame main-thread cost on
	# phones. has_feature("editor") is false in any exported build.
	#
	# NOTE: addons/ is vendored; re-installing Godot MCP Pro will overwrite this
	# guard and it has to be re-applied.
	set_process(OS.has_feature("editor"))


func _process(_delta: float) -> void:
	if FileAccess.file_exists(REQUEST_PATH):
		_take_screenshot()


func _take_screenshot() -> void:
	# Delete request file immediately to avoid re-triggering
	DirAccess.remove_absolute(REQUEST_PATH)

	# Wait one frame so the viewport has a fully rendered image
	# process_always=true (default) so the timer ticks even when tree is paused
	await get_tree().create_timer(0.05).timeout

	var viewport := get_viewport()
	if viewport == null:
		return

	var image := viewport.get_texture().get_image()
	if image == null:
		return

	image.save_png(SCREENSHOT_PATH)
