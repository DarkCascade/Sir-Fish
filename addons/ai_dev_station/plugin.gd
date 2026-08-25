@tool
extends EditorPlugin

## AI Dev Station -- docks a live Claude Code session next to the editor.

const StationDock := preload("res://addons/ai_dev_station/station_dock.gd")
const Settings := preload("res://addons/ai_dev_station/settings.gd")

const DOCK_SLOTS := [
	DOCK_SLOT_RIGHT_UL,
	DOCK_SLOT_RIGHT_BL,
	DOCK_SLOT_LEFT_UL,
	DOCK_SLOT_LEFT_BL,
]

var _dock: Control
var _bottom_button: Button
var _in_bottom_panel := false
var _mounted_at := -1
var _shortcut: Shortcut


func _enter_tree() -> void:
	Settings.ensure_defaults()

	_dock = StationDock.new()
	_dock.name = "Claude"
	_mount(int(Settings.get_value(Settings.K_DOCK, 0)))

	_shortcut = _make_shortcut()
	add_tool_menu_item("Focus AI Dev Station", _focus_station)

	var es := Settings.editor_settings()
	if es != null and not es.settings_changed.is_connected(_on_settings_changed):
		es.settings_changed.connect(_on_settings_changed)


func _exit_tree() -> void:
	var es := Settings.editor_settings()
	if es != null and es.settings_changed.is_connected(_on_settings_changed):
		es.settings_changed.disconnect(_on_settings_changed)

	remove_tool_menu_item("Focus AI Dev Station")
	_unmount()
	if is_instance_valid(_dock):
		_dock.queue_free()
	_dock = null


func _get_plugin_name() -> String:
	return "AI Dev Station"


func _mount(location: int) -> void:
	if not is_instance_valid(_dock):
		return
	_mounted_at = location
	if location == Settings.DOCK_BOTTOM:
		_bottom_button = add_control_to_bottom_panel(_dock, "Claude")
		_in_bottom_panel = true
	else:
		var slot: int = DOCK_SLOTS[clampi(location, 0, DOCK_SLOTS.size() - 1)]
		add_control_to_dock(slot, _dock)
		_in_bottom_panel = false


func _unmount() -> void:
	if not is_instance_valid(_dock):
		return
	if _in_bottom_panel:
		remove_control_from_bottom_panel(_dock)
		_bottom_button = null
	else:
		remove_control_from_docks(_dock)


func _on_settings_changed() -> void:
	var wanted := int(Settings.get_value(Settings.K_DOCK, 0))
	if wanted == _mounted_at:
		return
	_mounted_at = wanted
	_unmount()
	_mount(wanted)


func _make_shortcut() -> Shortcut:
	var event := InputEventKey.new()
	event.keycode = KEY_A
	event.ctrl_pressed = true
	event.alt_pressed = true
	var sc := Shortcut.new()
	sc.events = [event]
	return sc


func _shortcut_input(event: InputEvent) -> void:
	if _shortcut != null and _shortcut.matches_event(event) and event.is_pressed() and not event.is_echo():
		_focus_station()
		get_viewport().set_input_as_handled()


func _focus_station() -> void:
	if not is_instance_valid(_dock):
		return
	if _in_bottom_panel:
		make_bottom_panel_item_visible(_dock)
	_dock.focus_input()
