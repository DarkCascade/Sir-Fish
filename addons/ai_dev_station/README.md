# AI Dev Station

A Godot 4 editor plugin that docks a live Claude Code session beside the editor,
so the AI and the scene tree share one window instead of two tiled ones.

## Enabling

1. **Project > Project Settings > Plugins** and tick **AI Dev Station**.
2. The plugin auto-detects the `claude` binary. If it can't find one, set
   **Editor > Editor Settings > AI Dev Station > Claude Executable** to its full path.

The panel appears in the right-hand dock by default. **Dock Location** in Editor
Settings moves it to either side dock or the bottom panel; it re-docks live.
`Ctrl+Alt+A` focuses the input from anywhere in the editor.

## What it does

- **Streams a real session.** One long-lived `claude` process per session, spoken
  to over stream-json. Text arrives token by token; tool calls appear as
  collapsible rows with a ✓/✗ and their full output.
- **Runs in your project directory**, so `CLAUDE.md`, your MCP servers, skills and
  slash commands all resolve exactly as they do in a terminal.
- **Attaches editor context.** The `Scene` / `Selection` / `Script` toggles prepend
  the open scene's node tree, the selected nodes, or the script and caret line to
  your message. This is the part a tiled terminal can't do.
- **Re-imports after edits.** When a turn used a file-mutating tool, the plugin
  calls `EditorFileSystem.scan()` so Godot picks up Claude's changes without an
  alt-tab.
- **Model / permission mode** are switchable from the toolbar; they apply to the
  next session, so press **Restart** after changing one.
- `res://` paths in Claude's replies are clickable and open the scene or script.

## Architecture

| File | Role |
| --- | --- |
| `plugin.gd` | `EditorPlugin`: docking, Editor Settings, shortcut |
| `station_dock.gd` | The panel — transcript, input, tool rows, wiring |
| `claude_session.gd` | Subprocess lifecycle + stream-json protocol |
| `editor_context.gd` | Scene / selection / script → prompt context block |
| `markdown.gd` | Markdown → BBCode for the transcript |
| `settings.gd` | Editor Settings registration |

### Two CLI behaviours worth knowing

Both were found by testing against the real binary, and the code depends on them:

1. **The CLI stays silent until it receives its first input message.** The
   `system/init` event arrives *in response to* input, not at spawn. So a session
   counts as ready as soon as the process is up — waiting for `init` before
   sending deadlocks.
2. **There is no `--cwd` flag**, and `OS.execute_with_pipe()` cannot set a working
   directory. The plugin therefore writes a launcher shim to
   `user://ai_dev_station/launch.cmd` (or `launch.sh`) that `cd`s into the project
   and then execs `claude`. The shim carries the entire command line and takes no
   arguments of its own, which means **no prompt text ever touches a shell command
   line** — user input travels only as JSON over stdin.

On Windows the shim is hosted by `cmd.exe /d /c` deliberately *without* `/s`:
with `/s`, cmd strips the quote pair around the shim path and splits it at the
first space, which breaks any project whose user-data path contains one.

### Permission modes

The panel renders an Allow/Deny row if the CLI asks for permission, but the
default is `acceptEdits`, which doesn't prompt. `manual` and `dontAsk` may stall
waiting on a prompt this panel cannot always render — prefer `acceptEdits`,
`plan`, or `auto`.

## Requirements

- Godot 4.4+ (needs the non-blocking form of `OS.execute_with_pipe`). Developed
  and tested on 4.7.
- Claude Code CLI on `PATH` or configured explicitly. Tested against 2.1.205.

## Limitations

- This is not a terminal emulator. Godot has no PTY, so the interactive Claude
  TUI can't be embedded; the panel is a native client for the same session
  instead. Anything needing the real TUI still wants a terminal.
- `Extra CLI Args` in Editor Settings is split on spaces, so arguments containing
  spaces aren't supported there.
