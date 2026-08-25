@tool
extends RefCounted

## Editor Settings registration. Everything the station can be tuned with shows
## up under Editor > Editor Settings > AI Dev Station.

const PREFIX := "ai_dev_station/"

const K_EXE := PREFIX + "claude_executable"
const K_DOCK := PREFIX + "dock_location"
const K_MODEL := PREFIX + "default_model"
const K_MODE := PREFIX + "default_permission_mode"
const K_RESCAN := PREFIX + "auto_rescan_filesystem"
const K_FONT := PREFIX + "transcript_font_size"
const K_THINKING := PREFIX + "show_thinking"
const K_EXTRA := PREFIX + "extra_cli_args"
const K_AUTOSTART := PREFIX + "autostart_session"

const MODELS := "default,fable,opus,sonnet,haiku"
const MODES := "acceptEdits,plan,auto,bypassPermissions,dontAsk,manual"
const DOCK_NAMES := "Right (upper),Right (lower),Left (upper),Left (lower),Bottom panel"

const DOCK_BOTTOM := 4

const _SESSION_SCRIPT := preload("res://addons/ai_dev_station/claude_session.gd")


static func editor_settings() -> EditorSettings:
	return EditorInterface.get_editor_settings()


static func ensure_defaults() -> void:
	var es := editor_settings()
	_define(es, K_EXE, "", TYPE_STRING, PROPERTY_HINT_GLOBAL_FILE, "")
	_define(es, K_DOCK, 0, TYPE_INT, PROPERTY_HINT_ENUM, DOCK_NAMES)
	_define(es, K_MODEL, "default", TYPE_STRING, PROPERTY_HINT_ENUM, MODELS)
	_define(es, K_MODE, "acceptEdits", TYPE_STRING, PROPERTY_HINT_ENUM, MODES)
	_define(es, K_RESCAN, true, TYPE_BOOL, PROPERTY_HINT_NONE, "")
	_define(es, K_FONT, 13, TYPE_INT, PROPERTY_HINT_RANGE, "9,24,1")
	_define(es, K_THINKING, false, TYPE_BOOL, PROPERTY_HINT_NONE, "")
	_define(es, K_EXTRA, "", TYPE_STRING, PROPERTY_HINT_NONE, "")
	_define(es, K_AUTOSTART, true, TYPE_BOOL, PROPERTY_HINT_NONE, "")

	# One-time autodetect so the plugin works the moment it is enabled.
	if str(es.get_setting(K_EXE)).strip_edges().is_empty():
		var found := _SESSION_SCRIPT.autodetect_executable()
		if not found.is_empty():
			es.set_setting(K_EXE, found)


static func _define(es: EditorSettings, key: String, default: Variant, type: int, hint: int, hint_string: String) -> void:
	if not es.has_setting(key):
		es.set_setting(key, default)
	es.set_initial_value(key, default, false)
	es.add_property_info({
		"name": key,
		"type": type,
		"hint": hint,
		"hint_string": hint_string,
	})


static func get_value(key: String, fallback: Variant) -> Variant:
	var es := editor_settings()
	if es == null or not es.has_setting(key):
		return fallback
	return es.get_setting(key)


static func set_value(key: String, value: Variant) -> void:
	var es := editor_settings()
	if es != null:
		es.set_setting(key, value)
