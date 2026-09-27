"""PreToolUse guard for the godot-ai MCP server (issue #222).

Ports the deny list Sir Fish kept for Godot MCP Pro. Pro had one tool per
destructive action, so plain permission rules could name them. godot-ai folds
actions into `*_manage` tools that take an `op`, and `batch_execute` runs
internal plugin commands by name, so permission rules alone cannot tell a
delete from a create. This reads the tool input and denies the same actions:

    Pro tool                 godot-ai equivalent
    delete_node              node_manage op=delete
    delete_scene             filesystem_manage op=delete/delete_file on a scene
    remove_animation         animation_manage op=delete
    remove_autoload          autoload_manage op=remove
    export_project           export_manage op=run_export,
                             headless_manage op=export_project_cli
    tilemap_clear            tilemap_manage op=clear/tilemap_clear

Pro's two AnimationTree state-machine removals have no godot-ai equivalent.
Anything else passes through to the normal permission flow.
"""

import json
import sys

DENIED_OPS = {
    "mcp__godot-ai__node_manage": {"delete"},
    "mcp__godot-ai__animation_manage": {"delete"},
    "mcp__godot-ai__autoload_manage": {"remove"},
    "mcp__godot-ai__export_manage": {"run_export"},
    "mcp__godot-ai__headless_manage": {"export_project_cli"},
    "mcp__godot-ai__tilemap_manage": {"clear", "tilemap_clear"},
}

# filesystem_manage deletes are denied only for scenes, as Pro's delete_scene was.
SCENE_DELETE_OPS = {"delete", "delete_file"}

# batch_execute sub-commands use the plugin's internal names.
DENIED_BATCH_COMMANDS = {
    "delete_node",
    "animation_delete",
    "remove_autoload",
    "export_run_export",
    "headless_export_project_cli",
    "tilemap_clear",
}


def _is_scene(path) -> bool:
    return isinstance(path, str) and path.lower().endswith((".tscn", ".scn"))


def _reason(tool: str, input_: dict):
    if tool in DENIED_OPS and input_.get("op") in DENIED_OPS[tool]:
        return f"{tool} op={input_.get('op')}"
    if tool == "mcp__godot-ai__filesystem_manage" and input_.get("op") in SCENE_DELETE_OPS:
        # godot-ai also accepts op parameters flat, beside `op`, instead of in `params`.
        params = input_.get("params") or {}
        path = params.get("path") if isinstance(params, dict) else None
        path = path or input_.get("path")
        if _is_scene(path):
            return f"deleting the scene {path}"
    if tool == "mcp__godot-ai__batch_execute":
        for item in input_.get("commands") or []:
            if not isinstance(item, dict):
                continue
            command = item.get("command")
            params = item.get("params") if isinstance(item.get("params"), dict) else {}
            if command in DENIED_BATCH_COMMANDS:
                return f"batch_execute sub-command {command}"
            if command == "delete_file" and _is_scene(params.get("path")):
                return f"batch_execute deleting the scene {params.get('path')}"
    return None


def main() -> None:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        return
    input_ = event.get("tool_input") or {}
    if not isinstance(input_, dict):
        return
    reason = _reason(event.get("tool_name", ""), input_)
    if reason is None:
        return
    json.dump({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                f"Blocked by .claude/hooks/godot_ai_guard.py: {reason}. Sir Fish denies "
                "destructive editor actions through MCP; ask the user to do it, or edit "
                "the file on disk with git to back it."
            ),
        }
    }, sys.stdout)


if __name__ == "__main__":
    main()
