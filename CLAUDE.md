# Sir Fish - AI Assistant Instructions

## The Godot MCP server: godot-ai

Sir Fish drives the Godot editor through **godot-ai** (the add-on in `addons/godot_ai`,
pinned to release 5.0.45). It replaced Godot MCP Pro on 2026-09-27 (#222). Why, and what
the evaluation found, is in the backlog doc under decision 10.5.

Its tools arrive deferred: load them with ToolSearch before calling. Most actions are
grouped into `*_manage` tools that take `{"op": "<verb>", "params": {...}}`; each tool's
description lists its ops.

### Connecting

- The Godot editor must be open with the plugin enabled. The plugin starts the local
  server (HTTP 8000, WebSocket 9500, localhost only), and Claude Code attaches through the
  user-scoped `godot-ai` entry. That entry runs the server from a local checkout,
  `C:/Projects/Godot/Godot-MCP_bebabin/.venv/Scripts/pythonw.exe -m godot_ai attach`,
  so `session_manage` reports `server_launch_mode: dev_venv`. Keep the checkout on the
  `v5.0.45` tag with no local changes, so the server matches the pinned addon.
- `session_manage(op="list")` shows each editor session with its readiness and the server
  and plugin versions. The two versions must match. `editor_state` gives the open scene,
  readiness and whether the game is live.
- If the bridge refuses with `NEW_CLIENT_SESSION_REQUIRED`, a server started with
  different arguments (an older version, or a domain exclusion) is still running on port
  8000. It belongs to the Claude session that launched it and stops when that session
  closes.
- The server is never exposed beyond this machine. No Tailscale tunnel, `GODOT_AI_AUTH_TOKEN`
  unset, `godot_ai/allow_remote_hosts` empty (#222).

### Which tool

| Task | Tool |
|---|---|
| Scene tree | `scene_get_hierarchy` |
| Open a scene | `scene_open(path, force_reload=true)` after any disk edit |
| Create, save as | `scene_manage(op="create" / "save_as")` |
| Nodes | `node_create`, `node_find`, `node_get_properties`, `node_set_property`, `node_manage` (rename, move, reparent, groups, call_method) |
| Scripts | `script_create`, `script_patch` (both return parse diagnostics), `script_attach`, `script_manage(op="read" / "validate" / "find_symbols")` |
| Files | `filesystem_manage(op="read" / "write" / "list" / "search" / "scan" / "reimport")` |
| GDScript in the editor | `editor_manage(op="eval", code=...)` |
| Logs | `logs_read(source="editor" or "game", include_details=true)` |
| Editor screenshot | `editor_screenshot`; `source="cinematic"` renders the edited scene through its own camera without running it |
| Many edits at once | `batch_execute` (internal command names such as `create_node`, `set_property`; rolls back if a step fails) |
| Run and stop the game | `project_run(autosave=false)`, `project_manage(op="stop")` |
| Screenshot of the running game | `editor_screenshot(source="game")` |
| GDScript in the running game | `editor_manage(op="game_eval", code=...)`; may `await`, returns a value |
| Game tree, input, pausing | `game_manage` (`get_scene_tree`, `get_node_info`, `input_key`, `input_action`, `suspend`, `resume`, `next_frame`) |
| Headless, no editor | `headless_manage(op="run_script" / "run_headless_scene")`; for the whole suite use `python tools/run_tests.py` |

### Rules that matter on this project

1. **Run with `project_run(autosave=false)`.** The default saves every open scene that has
   unsaved editor changes, over whatever is on disk. Godot's own "save before running"
   does the same, so this is not new, but `autosave=false` is the reliable way out.
2. **After editing an open `.tscn` on disk, `scene_open(path, force_reload=true)`.** A
   plain `scene_open` of the scene already open is a no-op and keeps the stale copy, which
   the next save then writes back over your edit.
3. **Never save a scene with `;` comments through the editor**, by `scene_save` or any
   other route. Godot 4.7's serializer strips the comments, fills in uids and
   `layout_mode`, and mints a fresh `unique_id` on every load, so two saves of the same
   content differ. Edit such scenes on disk. A save can also rewrite `assets/theme.tres`
   (line endings only); restore it with git.
4. **No editor-side scripts while the game runs.** `editor_manage(op="eval")` and
   `execute_script` are refused with `EDITOR_PLAYING`. Reads such as `scene_get_hierarchy`
   still work. Stop the game first.
5. **Keep each `game_eval` short** (about 8 s). To watch a whole fight, poll with short
   reads every couple of seconds. A long loop inside one eval can hang the game
   (`EVAL_HUNG`) until it is restarted.
6. **A new `class_name` needs a scan.** `script_create` answers
   `class_registration: "scan_required"`; call `filesystem_manage(op="scan")`, which also
   refreshes the class cache headless test runs read. Its
   `global_classes_registered_delta` field under-reports; `.godot/global_script_class_cache.cfg`
   is the truth.
7. **Destructive editor actions are blocked** by `.claude/hooks/godot_ai_guard.py`: node
   deletion, scene-file deletion, animation deletion, autoload removal, exports and
   TileMap clears, including inside `batch_execute`. Ask the user instead.
8. **The game runs embedded** in a floating Game window by default. Runtime tools work
   whichever editor tab is showing.
9. **The web export excludes `addons/godot_ai/*`.** The plugin's export hook strips its
   `_mcp_game_helper` autoload from exported packs, so nothing of it ships.
10. **Script diagnostics lie about `class_name` scripts.** `script_manage(op="validate")`,
    and the diagnostics `script_patch`, `script_create` and `filesystem_manage` writes
    attach, compile a pathless copy of the source
    (`addons/godot_ai/handlers/script_handler.gd`, `_validate_gdscript_source`). Godot
    rejects that copy with "hides a global script class" whenever the `class_name` is
    already registered, so a good script such as `battle_director.gd` reports "GDScript
    reload failed with error code 43" at its last line. The write itself lands, but the
    editor's loaded copy is not refreshed (`reload_reason: parse_error`). Genuine errors
    come back the same way, without the real message or line. For a `class_name` script,
    ignore that result and check with `python tools/run_tests.py`, or with
    `filesystem_manage(op="scan")` and then `logs_read(source="editor")`. Scripts without
    a `class_name` validate correctly. Unfixed upstream as of 5.0.45.

## Best Practices

1. **Prefer inspector properties over code** — When changing visual properties (colors, sizes, theme overrides, transforms, etc.), set them on the node rather than in a script, so the values stay visible in the Godot inspector and easy to tweak. Write them into the `.tscn` on disk and reload, or use `node_set_property` on a scene with no `;` comments (rule 3 above). Only use GDScript when the property isn't available in the inspector or needs to be dynamic at runtime.

2. **Flag when Meshy would beat procedural drawing** — Before hand-coding a new visual asset as a procedural `_draw()` shape (polygons, arcs, lines), pause and tell the user if it's the kind of thing Meshy would do better, rather than silently defaulting to code. Non-trivial shapes — anything that isn't a handful of vertices, and that a player would recognize as "a sword" or "a shield" rather than "a triangle" — are hard to get right as hand-written coordinate geometry (verified directly on this project: a procedurally-drawn axe icon took two failed geometry rewrites before it read correctly, while the equivalent Meshy-generated icon set was right on the first prompt for 5 of 7 icons). Raise the option; let the user decide, since it costs Meshy credits.
   - **Suggest Meshy** for icon/sprite/texture-style art with real shape detail: weapon icons, class/status icons, creature or prop art, anything with a recognizable silhouette.
   - **Keep it procedural** for simple geometric primitives (circles, bars, simple polygons) and anything that must stay dynamically parametric at runtime — recolored per rarity/state, resized, animated by code — since a generated image is baked pixels and loses that flexibility (see `scripts/modals/item_glyph.gd`'s rarity ring/glow, which stays procedural around a Meshy-generated icon for exactly this reason).

3. **For a Meshy 3D model, default to `model_type: "smart-topology"` (`meshy-t2`)** — not the standard `meshy-6`/`meshy-7` path. It is half the price *and* a better fit for this project's art direction. Directly A/B'd on the sporecap, same concept image, same settings otherwise:

   | | meshy-6 | meshy-t2 smart-topology |
   |---|---|---|
   | Credits (image-to-3d + texture) | 30 | **15** |
   | Triangles | 9,316 | **4,001** |
   | Connected parts | 1 welded blob | **5 separated** |
   | Cap dome + gills | lumpier, irregular fins | **cleaner, evenly spaced** |
   | Hands | slightly better | blockier |

   The part separation is the real win: t2 returns body / cap / gill-underside / left eye / right eye as discrete connected components, so assigning the flat palette materials is one material per part. The standard path returns a single welded mesh, which forces a hand-written geometric classifier (brim-line z threshold, normal-facing test for gills, hand-placed radius spheres for the eyes) that has to be re-tuned for every new model. t2's chunkier faceting is also closer to §23's "chunky silhouettes, no bevel-heavy detail" than meshy-6's softer forms.

   Note the parts are **not** separate glTF nodes — one node, one mesh, one material, one baked texture. Find them as connected components (Blender: separate by loose parts).

4. **Mobile legibility: no text below `Tuning.MIN_FONT_SIZE` (36 px).** The game is played
   on phones, where the 1080 px canvas shows about 390 pt wide, so 36 px lands at about
   13 pt. That is the Rune Floor hero plate's HP number, the smallest text that read
   comfortably in the 2026-09-27 phone playtest; the old dock's 26 px and 20 px labels
   (9 and 7 pt) did not. It applies to every new or changed text: theme sizes, node font
   overrides, exported `font_size` properties, and text a script draws. Shrink-to-fit
   floors too. If something doesn't fit at 36, change the layout or cut the words, not
   the size.
   - `tests/test_font_floor.gd` enforces it for scenes and resources as a ratchet. The
     sizes that predate the rule are grandfathered there. Lower a file's count when you
     raise its text; the test fails until you do. Issue #205 tracks raising the rest.
   - Script-drawn text is not covered by the test, so check it by hand.

## Common Pitfalls

1. **Never edit project.godot while the editor is open** — Use `project_manage(op="settings_set")` instead. The Godot editor overwrites the file. With the editor closed, a direct edit is safe.
2. **GDScript type inference** — Use explicit type annotations in for-loops: `for item: String in array` instead of `for item in array`.
3. **A new `class_name` needs a scan** — see rule 6 above. For a headless run without the editor, `godot --headless --import` refreshes the class cache too.
4. **Blender MCP: `transform_apply` silently drops rotation** — `bpy.ops.object.transform_apply(rotation=True)` reports success and zeroes `obj.rotation_euler`, but does **not** bake the rotation into the mesh. `location=True` and `scale=True` apply fine. Rotate the mesh data directly instead: `mesh.transform(mathutils.Matrix.Rotation(angle, 4, 'Z'))`, which is context-free and always works. This cost a full rebuild of the sporecap — the model was correctly scaled and grounded, so the lost 90° rotation was only caught by noticing the arm axis hadn't swapped.
5. **Blender MCP: `bound_box` and `matrix_world` are stale right after an operator** — measure from `obj.data.vertices` (times `matrix_world`), or call `bpy.context.view_layer.update()` first. Verify every transform by re-measuring vertex bounds rather than trusting the operator's return value.
6. **Blender MCP: mutating a live selection while iterating it** — `for o in bpy.context.selected_objects: o.select_set(False)` skips entries, which can leave unintended objects selected when a destructive operator (`transform_apply`) runs next. Use `bpy.ops.object.select_all(action='DESELECT')`.
7. **Workbench `WIREFRAME` shading renders empty**, and `show_wire` is a viewport overlay that never reaches a render. For a renderable wireframe, duplicate the mesh and add a `WIREFRAME` modifier with `use_replace = True`.

## Project Notes

### Task tracking: the GitHub board is the source of truth

Task state lives on the **Sir Fish** GitHub Project (https://github.com/users/DarkCascade/projects/3),
backed by the issues in `DarkCascade/Sir-Fish`. `design documents/Sir Fish - Backlog.md` is design
rationale and history: it explains why something was decided, not whether it is done.

- Before starting work, check the board (`gh issue list`, `gh project item-list 3 --owner DarkCascade`)
  rather than reading the backlog doc for status. New work gets an issue, not a new doc bullet.
- Columns: Backlog (blocked), Needs decision, Ready, In progress, In review, Done. Move the card as work
  moves; a PR that says `Closes #N` closes the issue.
- Epics P3-P7 are parent issues, and blocked-by links are real dependencies. Decisions carry the
  `decision` label; anything that spends Meshy credits carries `needs-meshy` and still needs an explicit
  credit confirmation.
- When a decision is made or a task ships, record the *why* in the backlog doc and link the issue, so the
  doc stays a rationale record and the board stays the status record.

### Combat: real-time vs turn-based

`BattleDirector` (`scripts/battle/battle_director.gd`) supports two combat modes via the `turn_based_combat` export (default `true`), a dev-only toggle not exposed to the player in any UI:

- **Turn-based**: a combatant requests a turn when its cooldown expires (`Combatant.request_turn()` → `BattleDirector.request_turn()`), requests queue in `_turn_queue` in arrival order, and `_advance_turn_queue()` dispatches one combatant at a time — the next one only acts once the current actor's animation finishes.
- **Real-time**: `request_turn()` calls `_take_action()` immediately instead of queueing, so multiple combatants can act simultaneously (this was the only mode before turn-based combat was added).

Damage calculation, targeting, abilities, and VFX are identical in both modes — only the scheduling of *when* a combatant acts changes.

### Adding a new enemy: the Meshy -> Blender -> Godot pipeline

Established building the sporecap (`assets/meshes/sporecap.glb`). Meshy generates the
mesh; **the rig is hand-built in Blender**, not by Meshy.

1. **Concept image first.** `meshy_text_to_image` (nano-banana-pro, 9 credits) then
   `meshy_image_to_3d`. The mesh follows the concept image closely, so the image is
   where silhouette problems get fixed cheaply. Prompt the palette hexes and
   "chunky faceted, no bevels, flat solid colours, thick dark outline" explicitly.
2. **Generate in A-pose, never T-pose — on this in-house rig.** `pose_mode: "a-pose"`. A
   T-pose model has to be re-posed to get its arms down, which skins the mesh twice and
   flattens the arms into fins — this happened on the first sporecap attempt and was only
   fixed by regenerating. An A-pose model is rigged in its modelled pose, so the rest pose
   needs no baking at all. **The rule flips for KayKit `Rig_Medium`**, whose rest pose is a
   true T-pose: there, generate in T-pose (see "Adding a humanoid character on KayKit
   `Rig_Medium`" below).
3. **Do not bother with `meshy_rig`.** It returns HTTP 422 "Pose estimation failed" for any
   non-humanoid silhouette (the sporecap's wide cap and absent neck defeat it). Only worth
   attempting for roughly human proportions.
4. **Build the armature on the in-house 17-bone names** — `Root`, `Hips`, `Spine`, `Chest`,
   `Head`, `Shoulder/Arm/Hand.L/.R`, `Thigh/Shin/Foot.L/.R`. This is the whole trick:
   `CombatantSkeletonAnimations` then drives the new enemy with the shared
   `_humanoid_idle/run/hurt/die` builders for free, and only the attack clip needs
   authoring. Proportions may differ freely from the orc's — the builders compose deltas
   onto each bone's own rest transform, so only the NAMES have to match.
   - Blender's automatic ("bone heat") weighting fails on these meshes. Weight by hand:
     region-gated distance-to-bone-segment, then a few Laplacian smoothing passes, then a
     hard clamp so the cap belongs entirely to `Head` (arm weights bleeding into the cap
     brim drag it down during the attack).
   - Author facing **+X**, **+Z** up, feet at z=0, ~1.7 units tall to match the orc.
5. **Flat palette materials, no textures.** Delete Meshy's baked texture and assign one
   flat material per part. glTF `baseColorFactor` takes the hex digits over 255
   **unconverted** — see §6.1; the failure mode is applying a transfer function once too
   often. Verify by parsing the exported `.glb` and checking the factors round-trip to the
   intended hex exactly.
6. **Export** with `export_animations=False` (clips are GDScript-authored) and
   `export_apply=False` (never apply the armature modifier).
7. **Wire up in Godot**: `resources/stats/<id>.tres`, `scenes/battle/enemies/<id>.tscn`
   (instance `combatant.tscn`, add the `.glb` under `Visual/Rig` as `Model`), a
   `RigProfile` resource under `resources/rig_profiles/` (`source = AUTHORED_SKELETON`,
   `skeleton_path = "Rig/Model/<Name>Rig/Skeleton3D"`, `clips` naming the shared
   `humanoid_idle/run/hurt/die` builders plus your own attack builder in
   `CombatantSkeletonAnimations`), referenced from the stats resource's `rig_profile`
   field, and the id added to the `explicit_ids` of an `EnemyPool` under `resources/pools/`
   (`endless_early`, `endless_mid` or `boss_pool`). Those three pools are hand-pinned
   rosters, so authoring `tags` on the stats resource does not put the enemy into rotation
   by itself — `explicit_ids` bypasses the tag filter. There is no `IMPACT_DELAYS` table
   to update any more (content-phase-0 §1.1/§3 Step 3 deleted it) — the attack clip's own
   `_anim_impact` call track, authored inside your attack builder, is the only impact
   timing that has ever actually fired.

**Verifying the new enemy.** Prefer `game_eval` for animation checks: instance the
enemy, call `setup()` with its stats, return `anim.get_animation_list()`, and drive a clip
directly in the running game. Check the pose with `editor_screenshot(source="game")`.

The throwaway-scene route is the fallback when the editor is not connected, or when a
check needs a real scene tree rather than a one-off script: make
`res://scratch/<name>.tscn` (the `scratch/` folder is gitignored), run it, read
`logs_read(source="game")`, then screenshot it to confirm the mesh actually deforms. The
permission rules deny `rm -rf`, so leave scratch files where they are instead of trying
to delete them. Run a single headless suite through
`headless_manage(op="run_headless_scene")`, which needs no editor connection at all.

**For the whole suite, use `python tools/run_tests.py`.** It discovers every
`tests/test_*.tscn` rather than naming them, so a new suite is picked up the moment it
exists, and it prints one table of verdicts and check counts, exiting non-zero if
anything failed. Pass substrings to narrow it (`run_tests.py quest forge`), `--list` to
see the selection, `-v` to stream full output. Godot comes from `GODOT_PATH`, then the
known install paths, then `PATH`; on Windows it wants `Godot_console.exe`, since plain
`Godot.exe` writes nothing to a redirected stdout. A suite that hangs (a missing
`t.finish()` does this) is cut off by `--timeout` and reported as TIMEOUT rather than
blocking the run, and one that dies on load is reported as ERROR with the parse error
that killed it. A suite that prints `RESULT PASS` with any `SCRIPT ERROR:` line in its
output is reported as SCRIPT_ERROR, with each error and its `at:` location listed under
the table. A runtime error aborts only its own function, so without this the rest of the
suite would still pass, just with those checks missing.

Node, property and script-attach edits through godot-ai go through the editor's undo
stack (`undoable: true` in the reply); file writes do not, and say so. Commit before a
large batch of either.

### Adding a humanoid character on KayKit `Rig_Medium`

**This is the main route for new characters. Use the `new-character` skill.**
- **Tooling:** `tools/character_pipeline/`, driven by one JSON spec per character:
  `pipeline.py doctor | template | build | verify | register`. Its README covers the
  spec fields and how to read the report.
- **Worked example:** the bandit officer, `specs/bandit_officer.json`.
- **Findings and costs:** backlog doc §4.
- **Non-humanoids** stay on the in-house route above.

Facts the tooling depends on, worth knowing before changing it:
- **The shipped KayKit characters already use this rig.** `knight`, `rogue`, `mage` and
  `skeleton_*`.glb (armature `Rig`) are the 1.x export of `Rig_Medium`: the same 21
  deform bones and rest pose, plus handslots and 18 IK bones. Pack clips play on them,
  but `Idle` → `Idle_A` and `Running_A` are revised motions, not renames.
- **The rest pose is a true T-pose**, so Meshy generates in T-pose here. The A-pose
  rule above does not apply.
- **Restyling the concept onto `templates/mannequin_tpose_front.png`** is what makes a
  Meshy mesh land on the bones.
- **A clothed humanoid gets a palette-snapped texture**, not per-part flat materials.
  Skin, clothes and boots weld into one part, and the eyes exist only in the texture.
- **Clips are baked into each glb,** because `CombatantBakedAnimations.build()` reads
  clips only from the character's own glb. Backlog decision 4.3 (issue #79) moves to a
  shared library, built with #78 or #81; until then new characters keep baking.
- **Blender 5.2 runs headless** through `BLENDER_PATH`.
  - Assigning an action also needs `action_slot` set.
  - Clearing an armature's animation data orphans its clips, and Blender drops orphans
    on save.
- **Locations.**
  - The zip is at `third_party/kaykit/`.
  - The extracted packs, including the Adventurers 2.0 weapon props, are in
    `C:\Projects\Third Party Assets\KayKit\`.
- **In-game checks autosave the dev profile.** Back up both `profile.save` and
  `profile.dev.save` in `%APPDATA%/Godot/app_userdata/Sir Fish/` before a debug fight
  (`Debug.command = "quest easy"`, then `"spawn <id>"`); the debug fights write
  `profile.dev.save`. Guard `director.enemies` entries with `is_instance_valid()`.
  The solo level-1 warrior cannot survive the easy quest unaided, so a check that
  needs the shop or the boss raises the heroes' HP from `game_eval` at each fight.
