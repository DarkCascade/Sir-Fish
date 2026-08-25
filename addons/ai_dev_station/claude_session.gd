@tool
extends Node

## Owns one long-lived `claude` CLI process and speaks its stream-json protocol.
##
## The CLI is launched with `--input-format stream-json --output-format stream-json`,
## which keeps a single process alive across many turns: we write newline-delimited
## JSON user messages to its stdin and read newline-delimited JSON events from stdout.
##
## The CLI has no `--cwd` flag and `OS.execute_with_pipe()` cannot set a working
## directory, so we generate a tiny launcher shim that `cd`s into the project first.
## The shim carries the whole command line, which means no user text ever reaches a
## shell command line -- prompts travel over stdin as JSON.

signal started(init_info: Dictionary)
signal status_changed(status: String)
signal text_delta(text: String)
signal thinking_delta(text: String)
signal text_block_finished()
signal assistant_message(text: String)
signal tool_started(tool_id: String, tool_name: String)
signal tool_input_ready(tool_id: String, tool_name: String, input: Dictionary)
signal tool_result(tool_id: String, text: String, is_error: bool)
signal turn_summary(text: String)
signal turn_finished(result: Dictionary)
signal permission_requested(request_id: String, tool_name: String, input: Dictionary)
signal notice(text: String, severity: int)
signal exited(graceful: bool)

const SEV_INFO := 0
const SEV_WARN := 1
const SEV_ERROR := 2

const READ_CHUNK := 65536
const MAX_CHUNKS_PER_POLL := 64
const NEWLINE := 10

## Tools whose use means files on disk may have changed.
const MUTATING_TOOLS := ["Edit", "Write", "MultiEdit", "NotebookEdit", "Bash", "Task"]

var session_id: String = ""
var last_init: Dictionary = {}
var mutated_files: bool = false

var _pid: int = -1
var _stdio: FileAccess = null
var _stderr: FileAccess = null
var _rx := PackedByteArray()
var _rx_err := PackedByteArray()
var _running := false
var _turn_active := false
var _stopping := false

# Per-message streaming assembly, keyed by content block index.
var _block_kind := {}
var _block_tool_id := {}
var _block_tool_name := {}
var _block_tool_json := {}


func is_running() -> bool:
	return _running


func is_turn_active() -> bool:
	return _turn_active


static func new_uuid() -> String:
	var b := PackedByteArray()
	b.resize(16)
	for i in 16:
		b[i] = randi() & 0xFF
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	var hex := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
		hex.substr(16, 4), hex.substr(20, 12),
	]


## Locate the claude binary. Returns "" when it cannot be found.
static func autodetect_executable() -> String:
	var is_win := OS.get_name() == "Windows"
	var probe := "where" if is_win else "which"
	var out: Array = []
	if OS.execute(probe, PackedStringArray(["claude"]), out, false) == 0 and not out.is_empty():
		for raw: String in str(out[0]).split("\n"):
			var line := raw.strip_edges()
			if line.is_empty():
				continue
			# Prefer a real executable over a .cmd/.ps1 npm shim.
			if is_win and not line.to_lower().ends_with(".exe"):
				continue
			return line
	var home := OS.get_environment("USERPROFILE" if is_win else "HOME")
	for candidate: String in [
		home.path_join(".local/bin/claude.exe"),
		home.path_join(".local/bin/claude"),
		"/usr/local/bin/claude",
		"/opt/homebrew/bin/claude",
	]:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


## cfg keys: executable, project_dir, model, permission_mode, resume_id, extra_args
func start(cfg: Dictionary) -> bool:
	if _running:
		return true

	var exe := str(cfg.get("executable", "")).strip_edges()
	if exe.is_empty() or not FileAccess.file_exists(exe):
		notice.emit("Claude executable not found (%s). Set it in Editor Settings > AI Dev Station." % exe, SEV_ERROR)
		return false

	var project_dir := str(cfg.get("project_dir", ProjectSettings.globalize_path("res://")))
	project_dir = project_dir.trim_suffix("/").trim_suffix("\\")

	var resume_id := str(cfg.get("resume_id", "")).strip_edges()
	session_id = resume_id if not resume_id.is_empty() else new_uuid()

	var args := PackedStringArray([
		"-p",
		"--input-format", "stream-json",
		"--output-format", "stream-json",
		"--verbose",
		"--include-partial-messages",
	])
	if resume_id.is_empty():
		args.append_array(PackedStringArray(["--session-id", session_id]))
	else:
		args.append_array(PackedStringArray(["--resume", resume_id]))

	var model := str(cfg.get("model", "")).strip_edges()
	if not model.is_empty() and model != "default":
		args.append_array(PackedStringArray(["--model", model]))

	var mode := str(cfg.get("permission_mode", "")).strip_edges()
	if not mode.is_empty():
		args.append_array(PackedStringArray(["--permission-mode", mode]))

	for extra: String in str(cfg.get("extra_args", "")).split(" ", false):
		var trimmed := extra.strip_edges()
		if not trimmed.is_empty():
			args.append(trimmed)

	var shim := _write_shim(exe, project_dir, args)
	if shim.is_empty():
		return false

	var host := ""
	var host_args := PackedStringArray()
	if OS.get_name() == "Windows":
		# CreateProcess cannot run a .cmd directly, so cmd.exe hosts the shim.
		# Deliberately no /s: with exactly two quotes around a path that contains
		# whitespace, cmd preserves them and the shim resolves. /s would strip
		# that pair and split "...\app_userdata\Sir Fish\..." at the space.
		# The shim takes no arguments of its own, so there is nothing else to quote.
		host = "cmd.exe"
		host_args = PackedStringArray(["/d", "/c", shim])
	else:
		host = "/bin/sh"
		host_args = PackedStringArray([shim])

	var res: Dictionary = OS.execute_with_pipe(host, host_args, false)
	if res.is_empty() or not res.has("pid"):
		notice.emit("Could not spawn the Claude process (execute_with_pipe failed).", SEV_ERROR)
		return false

	_pid = int(res["pid"])
	_stdio = res.get("stdio")
	_stderr = res.get("stderr")
	_rx.clear()
	_rx_err.clear()
	_running = true
	_stopping = false
	_turn_active = false
	mutated_files = false
	set_process(true)
	return true


func _write_shim(exe: String, project_dir: String, args: PackedStringArray) -> String:
	var dir := "user://ai_dev_station"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var is_win := OS.get_name() == "Windows"
	var path := dir.path_join("launch.cmd" if is_win else "launch.sh")

	var quoted := PackedStringArray()
	for a: String in args:
		quoted.append(('"%s"' % a) if is_win else ("'%s'" % _sq(a)))
	var arg_line := " ".join(quoted)

	var body := ""
	if is_win:
		body = "@echo off\r\nchcp 65001 >nul\r\ncd /d \"%s\"\r\n\"%s\" %s\r\n" % [
			project_dir.replace("/", "\\"), exe.replace("/", "\\"), arg_line,
		]
	else:
		body = "#!/bin/sh\ncd '%s' || exit 1\nexec '%s' %s\n" % [
			_sq(project_dir), _sq(exe), arg_line,
		]

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		notice.emit("Could not write launcher shim to %s." % path, SEV_ERROR)
		return ""
	f.store_string(body)
	f.close()
	var abs := ProjectSettings.globalize_path(path)
	# globalize_path yields forward slashes; cmd.exe reads a leading "/" as a switch.
	return abs.replace("/", "\\") if is_win else abs


## Escape a value for POSIX single-quoted context.
func _sq(value: String) -> String:
	return value.replace("'", "'\\''")


func send_user_text(text: String) -> bool:
	if not _running or _stdio == null:
		return false
	var payload := {
		"type": "user",
		"message": {"role": "user", "content": [{"type": "text", "text": text}]},
	}
	_write_line(JSON.stringify(payload))
	_turn_active = true
	return true


func interrupt() -> void:
	if not _running or _stdio == null:
		return
	_write_line(JSON.stringify({
		"type": "control_request",
		"request_id": new_uuid(),
		"request": {"subtype": "interrupt"},
	}))
	notice.emit("Interrupt sent.", SEV_INFO)


func answer_permission(request_id: String, allow: bool) -> void:
	if not _running or _stdio == null:
		return
	var behavior := {}
	if allow:
		behavior = {"behavior": "allow", "updatedInput": {}}
	else:
		behavior = {"behavior": "deny", "message": "Denied from the Godot dock."}
	_write_line(JSON.stringify({
		"type": "control_response",
		"response": {"subtype": "success", "request_id": request_id, "response": behavior},
	}))


func stop() -> void:
	if not _running:
		return
	_stopping = true
	# Closing stdin is the polite way to end a stream-json session.
	if _stdio != null and _stdio.is_open():
		_stdio.close()
	_kill_tree()
	_finish(true)


func _write_line(line: String) -> void:
	if _stdio == null or not _stdio.is_open():
		return
	_stdio.store_string(line + "\n")
	_stdio.flush()


func _kill_tree() -> void:
	if _pid == -1:
		return
	if OS.get_name() == "Windows":
		# OS.kill() would only reap cmd.exe and orphan claude.exe underneath it.
		var out: Array = []
		OS.execute("taskkill", PackedStringArray(["/T", "/F", "/PID", str(_pid)]), out, false)
	else:
		OS.kill(_pid)
	_pid = -1


func _process(_delta: float) -> void:
	if not _running:
		return
	_pump(false)
	_pump(true)
	if _pid != -1 and not OS.is_process_running(_pid):
		# Drain whatever the process wrote just before exiting.
		_pump(false)
		_pump(true)
		_finish(_stopping)


## PackedByteArray is a value type, so the carry-over buffer is read from and
## written back to the member explicitly -- passing it as an argument would
## accumulate into a copy and silently drop every event split across frames.
func _pump(is_err: bool) -> void:
	var f: FileAccess = _stderr if is_err else _stdio
	if f == null or not f.is_open():
		return

	var buf: PackedByteArray = _rx_err if is_err else _rx
	for _i in MAX_CHUNKS_PER_POLL:
		var chunk := f.get_buffer(READ_CHUNK)
		if chunk.is_empty():
			break
		buf.append_array(chunk)
		if chunk.size() < READ_CHUNK:
			break

	# A newline byte never appears inside a UTF-8 multi-byte sequence, so
	# splitting on the raw byte is safe even when a chunk ends mid-character.
	var lines := PackedStringArray()
	while true:
		var nl := buf.find(NEWLINE)
		if nl == -1:
			break
		lines.append(buf.slice(0, nl).get_string_from_utf8().strip_edges())
		buf = buf.slice(nl + 1)

	if is_err:
		_rx_err = buf
	else:
		_rx = buf

	# Dispatch only after the buffer is committed, so a handler that stops the
	# session cannot leave the carry-over in a half-updated state.
	for line: String in lines:
		if line.is_empty():
			continue
		if is_err:
			notice.emit(line, SEV_WARN)
		else:
			_handle_line(line)


func _handle_line(line: String) -> void:
	var parsed: Variant = JSON.parse_string(line)
	if not (parsed is Dictionary):
		# Non-JSON on stdout is almost always a CLI banner or crash message.
		notice.emit(line, SEV_WARN)
		return
	_handle_event(parsed as Dictionary)


func _handle_event(ev: Dictionary) -> void:
	match str(ev.get("type", "")):
		"system":
			match str(ev.get("subtype", "")):
				"init":
					session_id = str(ev.get("session_id", session_id))
					last_init = ev
					started.emit(ev)
				"status":
					status_changed.emit(str(ev.get("status", "")))
				"post_turn_summary":
					var detail := str(ev.get("status_detail", ""))
					if not detail.is_empty():
						turn_summary.emit(detail)
		"stream_event":
			_handle_stream_event(ev.get("event", {}) as Dictionary)
		"assistant":
			var msg: Dictionary = ev.get("message", {})
			assistant_message.emit(_text_of(msg.get("content", [])))
		"user":
			_handle_tool_results(ev.get("message", {}) as Dictionary)
		"result":
			_turn_active = false
			turn_finished.emit(ev)
		"control_request":
			var req: Dictionary = ev.get("request", {})
			if str(req.get("subtype", "")) == "can_use_tool":
				permission_requested.emit(
					str(ev.get("request_id", "")),
					str(req.get("tool_name", "")),
					req.get("input", {}) as Dictionary,
				)
		"rate_limit_event":
			var info: Dictionary = ev.get("rate_limit_info", {})
			if str(info.get("status", "allowed")) != "allowed":
				notice.emit("Rate limit: %s" % str(info.get("status", "")), SEV_WARN)


func _handle_stream_event(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"message_start":
			_block_kind.clear()
			_block_tool_id.clear()
			_block_tool_name.clear()
			_block_tool_json.clear()
		"content_block_start":
			var start_idx := int(e.get("index", 0))
			var cb: Dictionary = e.get("content_block", {})
			var kind := str(cb.get("type", ""))
			_block_kind[start_idx] = kind
			if kind == "tool_use":
				var tid := str(cb.get("id", ""))
				var tname := str(cb.get("name", ""))
				_block_tool_id[start_idx] = tid
				_block_tool_name[start_idx] = tname
				_block_tool_json[start_idx] = ""
				if tname in MUTATING_TOOLS:
					mutated_files = true
				tool_started.emit(tid, tname)
		"content_block_delta":
			var delta_idx := int(e.get("index", 0))
			var d: Dictionary = e.get("delta", {})
			match str(d.get("type", "")):
				"text_delta":
					text_delta.emit(str(d.get("text", "")))
				"thinking_delta":
					thinking_delta.emit(str(d.get("thinking", "")))
				"input_json_delta":
					_block_tool_json[delta_idx] = str(_block_tool_json.get(delta_idx, "")) + str(d.get("partial_json", ""))
		"content_block_stop":
			var stop_idx := int(e.get("index", 0))
			match str(_block_kind.get(stop_idx, "")):
				"tool_use":
					var raw := str(_block_tool_json.get(stop_idx, ""))
					var input: Variant = JSON.parse_string(raw) if not raw.is_empty() else {}
					tool_input_ready.emit(
						str(_block_tool_id.get(stop_idx, "")),
						str(_block_tool_name.get(stop_idx, "")),
						(input as Dictionary) if input is Dictionary else {},
					)
				"text":
					text_block_finished.emit()


func _handle_tool_results(msg: Dictionary) -> void:
	var content: Variant = msg.get("content", [])
	if not (content is Array):
		return
	for item: Variant in content as Array:
		if not (item is Dictionary):
			continue
		var d := item as Dictionary
		if str(d.get("type", "")) != "tool_result":
			continue
		tool_result.emit(
			str(d.get("tool_use_id", "")),
			_text_of(d.get("content", "")),
			bool(d.get("is_error", false)),
		)


## Flatten either a plain string or a list of content blocks into text.
func _text_of(content: Variant) -> String:
	if content is String:
		return content as String
	if not (content is Array):
		return ""
	var chunks := PackedStringArray()
	for item: Variant in content as Array:
		if item is String:
			chunks.append(item as String)
		elif item is Dictionary:
			var d := item as Dictionary
			if str(d.get("type", "")) == "text":
				chunks.append(str(d.get("text", "")))
	return "\n".join(chunks)


func _finish(graceful: bool) -> void:
	if not _running:
		return
	_running = false
	_turn_active = false
	set_process(false)
	if _stdio != null and _stdio.is_open():
		_stdio.close()
	if _stderr != null and _stderr.is_open():
		_stderr.close()
	_stdio = null
	_stderr = null
	_kill_tree()
	exited.emit(graceful)


func _exit_tree() -> void:
	if _running:
		stop()
