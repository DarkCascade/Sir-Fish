@tool
extends VBoxContainer

## The AI Dev Station panel: a live Claude Code session rendered as native Godot
## UI, sitting alongside the editor instead of in a separate terminal window.

const Session := preload("res://addons/ai_dev_station/claude_session.gd")
const Markdown := preload("res://addons/ai_dev_station/markdown.gd")
const EditorCtx := preload("res://addons/ai_dev_station/editor_context.gd")
const Settings := preload("res://addons/ai_dev_station/settings.gd")

const COL_USER := Color("#7aa2f7")
const COL_ASSISTANT := Color("#9ece6a")
const COL_TOOL := Color("#e0af68")
const COL_ERROR := Color("#f7768e")
const COL_MUTED := Color("#787c99")
const COL_THINKING := Color("#bb9af7")

const TOOL_SUMMARY_KEYS := [
	"file_path", "path", "notebook_path", "command", "pattern",
	"query", "url", "description", "prompt", "skill",
]

var _session: Node
var _project_dir := ""

# Chrome
var _status_dot: Label
var _status_label: Label
var _model_btn: OptionButton
var _mode_btn: OptionButton
var _interrupt_btn: Button
var _restart_btn: Button
var _menu_btn: MenuButton
var _banner: PanelContainer
var _banner_label: RichTextLabel
var _scroll: ScrollContainer
var _feed: VBoxContainer
var _ctx_scene: CheckBox
var _ctx_selection: CheckBox
var _ctx_script: CheckBox
var _input: TextEdit
var _send_btn: Button
var _footer: Label

# Streaming state
var _text_label: RichTextLabel = null
var _text_raw := ""
var _think_label: RichTextLabel = null
var _think_raw := ""
var _got_text := false
var _tools := {}
var _needs_scroll := false
var _pending_prompt := ""


func _ready() -> void:
	name = "Claude"
	_project_dir = EditorCtx.project_dir()
	_build_ui()

	_session = Session.new()
	_session.name = "ClaudeSession"
	add_child(_session)
	_session.started.connect(_on_started)
	_session.status_changed.connect(_on_status_changed)
	_session.text_delta.connect(_on_text_delta)
	_session.thinking_delta.connect(_on_thinking_delta)
	_session.text_block_finished.connect(_finalize_text_block)
	_session.assistant_message.connect(_on_assistant_message)
	_session.tool_started.connect(_on_tool_started)
	_session.tool_input_ready.connect(_on_tool_input_ready)
	_session.tool_result.connect(_on_tool_result)
	_session.turn_summary.connect(_on_turn_summary)
	_session.turn_finished.connect(_on_turn_finished)
	_session.permission_requested.connect(_on_permission_requested)
	_session.notice.connect(_on_notice)
	_session.exited.connect(_on_exited)

	set_process(true)
	_refresh_controls()

	if bool(Settings.get_value(Settings.K_AUTOSTART, true)):
		_start_session()
	else:
		_set_status("idle", COL_MUTED)
		_add_system_line("Type a message to open a session in %s." % _project_dir, COL_MUTED)


func _exit_tree() -> void:
	if _session != null and _session.is_running():
		_session.stop()


func _process(_delta: float) -> void:
	if _needs_scroll:
		_needs_scroll = false
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


# --------------------------------------------------------------------------
# UI construction
# --------------------------------------------------------------------------

func _build_ui() -> void:
	add_theme_constant_override("separation", 4)
	custom_minimum_size = Vector2(320, 260)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)

	_status_dot = Label.new()
	_status_dot.text = "●"
	bar.add_child(_status_dot)

	_status_label = Label.new()
	_status_label.text = "starting"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.clip_text = true
	bar.add_child(_status_label)

	_model_btn = OptionButton.new()
	_model_btn.tooltip_text = "Model for new sessions"
	for m: String in Settings.MODELS.split(","):
		_model_btn.add_item(m)
	_select_by_text(_model_btn, str(Settings.get_value(Settings.K_MODEL, "default")))
	_model_btn.item_selected.connect(func(_i: int) -> void:
		Settings.set_value(Settings.K_MODEL, _model_btn.get_item_text(_model_btn.selected))
		_add_system_line("Model set to %s -- takes effect on the next session (Restart)." % _model_btn.get_item_text(_model_btn.selected), COL_MUTED))
	bar.add_child(_model_btn)

	_mode_btn = OptionButton.new()
	_mode_btn.tooltip_text = "Permission mode for new sessions"
	for m: String in Settings.MODES.split(","):
		_mode_btn.add_item(m)
	_select_by_text(_mode_btn, str(Settings.get_value(Settings.K_MODE, "acceptEdits")))
	_mode_btn.item_selected.connect(func(_i: int) -> void:
		Settings.set_value(Settings.K_MODE, _mode_btn.get_item_text(_mode_btn.selected))
		_add_system_line("Permission mode set to %s -- takes effect on the next session (Restart)." % _mode_btn.get_item_text(_mode_btn.selected), COL_MUTED))
	bar.add_child(_mode_btn)

	_interrupt_btn = Button.new()
	_interrupt_btn.text = "Stop"
	_interrupt_btn.tooltip_text = "Interrupt the current turn"
	_interrupt_btn.pressed.connect(func() -> void: _session.interrupt())
	bar.add_child(_interrupt_btn)

	_restart_btn = Button.new()
	_restart_btn.text = "Restart"
	_restart_btn.tooltip_text = "End this session and open a fresh one"
	_restart_btn.pressed.connect(_on_restart_pressed)
	bar.add_child(_restart_btn)

	_menu_btn = MenuButton.new()
	_menu_btn.text = "..."
	var popup := _menu_btn.get_popup()
	popup.add_item("Clear transcript", 0)
	popup.add_item("Copy session ID", 1)
	popup.add_item("Resume last session", 2)
	popup.add_separator()
	popup.add_item("Rescan filesystem now", 3)
	popup.add_item("Open Editor Settings", 4)
	popup.id_pressed.connect(_on_menu_id)
	bar.add_child(_menu_btn)

	_banner = PanelContainer.new()
	_banner.visible = false
	_banner.add_theme_stylebox_override("panel", _stylebox(Color(0.45, 0.15, 0.2, 0.35), COL_ERROR))
	_banner_label = _make_rich(true)
	_banner.add_child(_banner_label)
	add_child(_banner)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_feed = VBoxContainer.new()
	_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed.add_theme_constant_override("separation", 6)
	_scroll.add_child(_feed)

	var ctx := HBoxContainer.new()
	ctx.add_theme_constant_override("separation", 8)
	add_child(ctx)
	var ctx_label := Label.new()
	ctx_label.text = "Attach:"
	ctx_label.add_theme_color_override("font_color", COL_MUTED)
	ctx.add_child(ctx_label)
	_ctx_scene = _make_check(ctx, "Scene", "Prepend the open scene's node tree to the prompt")
	_ctx_selection = _make_check(ctx, "Selection", "Prepend the selected nodes to the prompt")
	_ctx_script = _make_check(ctx, "Script", "Prepend the script open in the script editor")

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 4)
	add_child(input_row)

	_input = TextEdit.new()
	_input.placeholder_text = "Ask Claude about this project...  (Enter to send, Shift+Enter for a newline)"
	_input.custom_minimum_size = Vector2(0, 76)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_input.gui_input.connect(_on_input_gui_input)
	input_row.add_child(_input)

	_send_btn = Button.new()
	_send_btn.text = "Send"
	_send_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_send_btn.pressed.connect(_send_current_input)
	input_row.add_child(_send_btn)

	_footer = Label.new()
	_footer.text = ""
	_footer.add_theme_color_override("font_color", COL_MUTED)
	_footer.add_theme_font_size_override("font_size", _meta_font_size())
	_footer.clip_text = true
	add_child(_footer)


func _make_check(parent: Control, text: String, tooltip: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.tooltip_text = tooltip
	parent.add_child(cb)
	return cb


## Secondary/meta text -- system lines, block headers, tool rows, the footer --
## all share this one size instead of a handful of ad hoc pixel values, and it
## scales with the user's transcript font size setting like the message body does.
func _meta_font_size() -> int:
	return maxi(8, int(Settings.get_value(Settings.K_FONT, 13)) - 3)


func _make_rich(bbcode: bool) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = bbcode
	r.fit_content = true
	r.selection_enabled = true
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", int(Settings.get_value(Settings.K_FONT, 13)))
	r.add_theme_font_size_override("mono_font_size", int(Settings.get_value(Settings.K_FONT, 13)) - 1)
	r.meta_clicked.connect(_on_meta_clicked)
	return r


func _stylebox(bg: Color, accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = accent
	sb.border_width_left = 3
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_right = 3
	return sb


func _select_by_text(btn: OptionButton, text: String) -> void:
	for i in btn.item_count:
		if btn.get_item_text(i) == text:
			btn.selected = i
			return


# --------------------------------------------------------------------------
# Session lifecycle
# --------------------------------------------------------------------------

func _start_session(resume_id: String = "") -> void:
	var exe := str(Settings.get_value(Settings.K_EXE, "")).strip_edges()
	if exe.is_empty():
		exe = Session.autodetect_executable()
		if not exe.is_empty():
			Settings.set_value(Settings.K_EXE, exe)
	if exe.is_empty() or not FileAccess.file_exists(exe):
		_show_banner("Claude CLI not found. Install it, then set [b]Editor Settings > AI Dev Station > Claude Executable[/b] to the full path of the [code]claude[/code] binary.")
		_set_status("no CLI", COL_ERROR)
		return
	_hide_banner()
	_set_status("starting", COL_TOOL)
	var ok: bool = _session.start({
		"executable": exe,
		"project_dir": _project_dir,
		"model": _model_btn.get_item_text(_model_btn.selected),
		"permission_mode": _mode_btn.get_item_text(_mode_btn.selected),
		"resume_id": resume_id,
		"extra_args": str(Settings.get_value(Settings.K_EXTRA, "")),
	})
	if not ok:
		_set_status("failed to start", COL_ERROR)
		_refresh_controls()
		return

	# The CLI stays silent until its first input message -- the `init` event only
	# arrives in response to one. So the session counts as ready the moment the
	# process is up, and anything already typed goes out now.
	_set_status("ready", COL_ASSISTANT)
	_refresh_controls()
	if not _pending_prompt.is_empty():
		var queued := _pending_prompt
		_pending_prompt = ""
		_dispatch(queued)


func _on_restart_pressed() -> void:
	if _session.is_running():
		_session.stop()
	_add_system_line("--- new session ---", COL_MUTED)
	_start_session()


## Arrives with the first turn, not at spawn time -- see _start_session().
func _on_started(info: Dictionary) -> void:
	var servers := PackedStringArray()
	for s: Variant in info.get("mcp_servers", []):
		if s is Dictionary and str((s as Dictionary).get("status", "")) == "connected":
			servers.append(str((s as Dictionary).get("name", "")))
	var parts := PackedStringArray()
	parts.append("model %s" % str(info.get("model", "?")))
	parts.append("mode %s" % str(info.get("permissionMode", "?")))
	if not servers.is_empty():
		parts.append("MCP: %s" % ", ".join(servers))
	_add_system_line("Session %s -- %s" % [str(info.get("session_id", "")).left(8), " | ".join(parts)], COL_MUTED)
	Settings.set_value(Settings.PREFIX + "last_session_id", str(info.get("session_id", "")))
	_refresh_controls()


func _on_exited(graceful: bool) -> void:
	_finalize_text_block()
	_set_status("stopped" if graceful else "exited", COL_MUTED if graceful else COL_ERROR)
	if not graceful:
		_add_system_line("The Claude process exited. Press Restart to reconnect.", COL_ERROR)
	_refresh_controls()


func _refresh_controls() -> void:
	var running: bool = _session != null and _session.is_running()
	var turn: bool = running and _session.is_turn_active()
	_interrupt_btn.disabled = not turn
	_send_btn.disabled = not running
	_send_btn.text = "Working" if turn else "Send"


func _on_status_changed(status: String) -> void:
	match status:
		"requesting":
			_set_status("thinking", COL_TOOL)
		"idle", "":
			_set_status("ready", COL_ASSISTANT)
		_:
			_set_status(status, COL_TOOL)
	_refresh_controls()


func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_dot.add_theme_color_override("font_color", color)


# --------------------------------------------------------------------------
# Sending
# --------------------------------------------------------------------------

func _on_input_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		if key.shift_pressed:
			return
		accept_event()
		_send_current_input()


func _send_current_input() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	_input.text = ""
	if not _session.is_running():
		_pending_prompt = text
		_add_system_line("Session not running -- starting one and queueing your message.", COL_MUTED)
		_start_session()
		return
	_dispatch(text)


func _dispatch(text: String) -> void:
	var context := EditorCtx.build({
		"scene": _ctx_scene.button_pressed,
		"selection": _ctx_selection.button_pressed,
		"script": _ctx_script.button_pressed,
	})
	_add_user_message(text, not context.is_empty())
	var payload := text if context.is_empty() else "%s\n\n%s" % [context, text]
	if _session.send_user_text(payload):
		_set_status("thinking", COL_TOOL)
	_refresh_controls()


# --------------------------------------------------------------------------
# Transcript rendering
# --------------------------------------------------------------------------

func _append(control: Control) -> void:
	var stick := _at_bottom()
	_feed.add_child(control)
	if stick:
		_needs_scroll = true


func _at_bottom() -> bool:
	var sb := _scroll.get_v_scroll_bar()
	return sb.value >= sb.max_value - sb.page - 24.0


func _block(accent: Color, bg: Color, header: String) -> RichTextLabel:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _stylebox(bg, accent))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	if not header.is_empty():
		var head := Label.new()
		head.text = header
		head.add_theme_color_override("font_color", accent)
		head.add_theme_font_size_override("font_size", _meta_font_size())
		box.add_child(head)
	var body := _make_rich(true)
	box.add_child(body)
	_append(panel)
	return body


func _add_user_message(text: String, with_context: bool) -> void:
	var header := "you" if not with_context else "you  (+ editor context)"
	var body := _block(COL_USER, Color(0.18, 0.22, 0.34, 0.35), header)
	body.append_text(Markdown.to_bbcode(text))


func _add_system_line(text: String, color: Color) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.selection_enabled = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", _meta_font_size())
	label.append_text("[color=#%s]%s[/color]" % [color.to_html(false), Markdown.escape(text)])
	_append(label)


func _on_text_delta(text: String) -> void:
	_got_text = true
	if _text_label == null:
		_text_raw = ""
		_text_label = _block(COL_ASSISTANT, Color(0.15, 0.24, 0.16, 0.28), "claude")
	_text_raw += text
	# Append as literal text while streaming; half-written markdown would
	# otherwise render as broken BBCode.
	_text_label.add_text(text)
	if _at_bottom():
		_needs_scroll = true


func _finalize_text_block() -> void:
	if _text_label == null:
		return
	_text_label.clear()
	_text_label.append_text(Markdown.to_bbcode(_text_raw))
	_text_label = null
	_text_raw = ""
	_finalize_thinking()


func _on_thinking_delta(text: String) -> void:
	if not bool(Settings.get_value(Settings.K_THINKING, false)):
		return
	if _think_label == null:
		_think_raw = ""
		_think_label = _block(COL_THINKING, Color(0.22, 0.17, 0.30, 0.25), "thinking")
		_think_label.modulate.a = 0.75
	_think_raw += text
	_think_label.add_text(text)


func _finalize_thinking() -> void:
	_think_label = null
	_think_raw = ""


func _on_assistant_message(text: String) -> void:
	# Fallback for builds that do not emit partial-message deltas.
	if not _got_text and not text.strip_edges().is_empty():
		var body := _block(COL_ASSISTANT, Color(0.15, 0.24, 0.16, 0.28), "claude")
		body.append_text(Markdown.to_bbcode(text))
	_got_text = false


func _on_tool_started(tool_id: String, tool_name: String) -> void:
	_finalize_text_block()

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _stylebox(Color(0.28, 0.22, 0.10, 0.28), COL_TOOL))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)

	var toggle := Button.new()
	toggle.text = "+"
	toggle.flat = true
	toggle.custom_minimum_size = Vector2(18, 0)
	toggle.tooltip_text = "Show the tool result"
	head.add_child(toggle)

	var name_label := Label.new()
	name_label.text = _display_tool_name(tool_name)
	name_label.add_theme_color_override("font_color", COL_TOOL)
	name_label.add_theme_font_size_override("font_size", _meta_font_size())
	head.add_child(name_label)

	var summary := Label.new()
	summary.text = "..."
	summary.clip_text = true
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_color_override("font_color", COL_MUTED)
	summary.add_theme_font_size_override("font_size", _meta_font_size())
	head.add_child(summary)

	var state := Label.new()
	state.text = "…"
	state.add_theme_color_override("font_color", COL_MUTED)
	state.add_theme_font_size_override("font_size", _meta_font_size())
	head.add_child(state)

	var body := _make_rich(true)
	body.visible = false
	box.add_child(body)

	toggle.pressed.connect(func() -> void:
		body.visible = not body.visible
		toggle.text = "-" if body.visible else "+")

	_tools[tool_id] = {"summary": summary, "state": state, "body": body, "toggle": toggle}
	_append(panel)


func _on_tool_input_ready(tool_id: String, tool_name: String, input: Dictionary) -> void:
	var entry: Dictionary = _tools.get(tool_id, {})
	if entry.is_empty():
		return
	(entry["summary"] as Label).text = _tool_summary(tool_name, input)


func _on_tool_result(tool_id: String, text: String, is_error: bool) -> void:
	var entry: Dictionary = _tools.get(tool_id, {})
	if entry.is_empty():
		return
	var state := entry["state"] as Label
	state.text = "✗" if is_error else "✓"
	state.add_theme_color_override("font_color", COL_ERROR if is_error else COL_ASSISTANT)

	var body := entry["body"] as RichTextLabel
	var shown := text
	if shown.length() > 4000:
		shown = shown.left(4000) + "\n... (%d more characters)" % (text.length() - 4000)
	body.clear()
	body.append_text("[code]%s[/code]" % Markdown.escape(shown))
	if is_error:
		body.visible = true
		(entry["toggle"] as Button).text = "-"


func _on_turn_summary(text: String) -> void:
	_set_status(text, COL_ASSISTANT)


func _on_turn_finished(result: Dictionary) -> void:
	_finalize_text_block()
	_tools.clear()

	var cost := float(result.get("total_cost_usd", 0.0))
	var secs := float(result.get("duration_ms", 0)) / 1000.0
	var usage: Dictionary = result.get("usage", {})
	var out_tokens := int(usage.get("output_tokens", 0))
	_footer.text = "session %s  |  %.1fs  |  %d out tok  |  $%.4f this turn  |  %s" % [
		str(_session.session_id).left(8), secs, out_tokens, cost,
		str(result.get("terminal_reason", "")),
	]

	if bool(result.get("is_error", false)):
		var msg := str(result.get("result", "The turn ended with an error."))
		_add_system_line(msg, COL_ERROR)
		_set_status("error", COL_ERROR)
	elif _status_label.text == "thinking":
		_set_status("ready", COL_ASSISTANT)

	if _session.mutated_files and bool(Settings.get_value(Settings.K_RESCAN, true)):
		_rescan_filesystem()
		_session.mutated_files = false

	_refresh_controls()


func _on_permission_requested(request_id: String, tool_name: String, input: Dictionary) -> void:
	_finalize_text_block()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _stylebox(Color(0.30, 0.24, 0.08, 0.40), COL_TOOL))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var label := Label.new()
	label.text = "Allow %s? %s" % [_display_tool_name(tool_name), _tool_summary(tool_name, input)]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)

	var allow := Button.new()
	allow.text = "Allow"
	row.add_child(allow)
	var deny := Button.new()
	deny.text = "Deny"
	row.add_child(deny)

	var answer := func(ok: bool) -> void:
		_session.answer_permission(request_id, ok)
		label.text = "%s %s" % ["Allowed" if ok else "Denied", _display_tool_name(tool_name)]
		allow.queue_free()
		deny.queue_free()
	allow.pressed.connect(answer.bind(true))
	deny.pressed.connect(answer.bind(false))

	_append(panel)


func _on_notice(text: String, severity: int) -> void:
	if severity >= Session.SEV_ERROR:
		_show_banner(Markdown.escape(text))
	_add_system_line(text, COL_ERROR if severity >= Session.SEV_WARN else COL_MUTED)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _display_tool_name(tool_name: String) -> String:
	# mcp__godot-mcp-pro__add_node -> godot-mcp-pro/add_node
	if tool_name.begins_with("mcp__"):
		var parts := tool_name.substr(5).split("__")
		if parts.size() >= 2:
			return "%s/%s" % [parts[0], parts[1]]
	return tool_name


func _tool_summary(tool_name: String, input: Dictionary) -> String:
	for key: String in TOOL_SUMMARY_KEYS:
		if input.has(key):
			return _shorten(str(input[key]))
	if input.is_empty():
		return ""
	return _shorten(JSON.stringify(input))


func _shorten(value: String) -> String:
	var s := value.replace("\n", " ").strip_edges()
	# Show project files the way the editor shows them.
	s = s.replace(_project_dir.replace("/", "\\") + "\\", "res://")
	s = s.replace(_project_dir + "/", "res://")
	if s.length() > 110:
		s = s.left(107) + "..."
	return s


func _rescan_filesystem() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.scan()
		_add_system_line("Files changed -- rescanning the project filesystem.", COL_MUTED)


func _show_banner(bbcode: String) -> void:
	_banner_label.clear()
	_banner_label.append_text(bbcode)
	_banner.visible = true


func _hide_banner() -> void:
	_banner.visible = false


func _on_meta_clicked(meta: Variant) -> void:
	var target := str(meta)
	if target.begins_with("res://"):
		if target.get_extension() in ["tscn", "scn"]:
			EditorInterface.open_scene_from_path(target)
		else:
			var res := load(target)
			if res is Script:
				EditorInterface.edit_script(res as Script)
	elif target.begins_with("http"):
		OS.shell_open(target)


func _on_menu_id(id: int) -> void:
	match id:
		0:
			for child: Node in _feed.get_children():
				child.queue_free()
			_text_label = null
			_think_label = null
			_tools.clear()
		1:
			DisplayServer.clipboard_set(str(_session.session_id))
			_add_system_line("Session ID copied: %s" % _session.session_id, COL_MUTED)
		2:
			var last := str(Settings.get_value(Settings.PREFIX + "last_session_id", ""))
			if last.is_empty():
				_add_system_line("No previous session recorded yet.", COL_MUTED)
			else:
				if _session.is_running():
					_session.stop()
				_add_system_line("--- resuming %s ---" % last.left(8), COL_MUTED)
				_start_session(last)
		3:
			_rescan_filesystem()
		4:
			_add_system_line("Open Editor > Editor Settings and search for \"AI Dev Station\".", COL_MUTED)


## Called by the plugin when the user asks to focus the station.
func focus_input() -> void:
	_input.grab_focus()
