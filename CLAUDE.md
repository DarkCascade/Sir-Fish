# Godot MCP Pro - AI Assistant Instructions

You have access to the Godot MCP Pro toolset for building and testing Godot games through the editor. Follow these rules carefully.

## Critical: Editor vs Runtime Tools

Tools are split into two categories. **Using a runtime tool without starting the game will always fail.**

### Editor Tools (always available)
These work on the currently open scene in the Godot editor:
- **Scene**: `get_scene_tree`, `create_scene`, `open_scene`, `save_scene`, `delete_scene`, `add_scene_instance`, `get_scene_file_content`, `get_scene_exports`
- **Nodes**: `add_node`, `delete_node`, `duplicate_node`, `move_node`, `rename_node`, `update_property`, `get_node_properties`, `add_resource`, `set_anchor_preset`, `connect_signal`, `disconnect_signal`, `get_node_groups`, `set_node_groups`, `find_nodes_in_group`
- **Scripts**: `create_script`, `read_script`, `edit_script`, `validate_script`, `attach_script`, `get_open_scripts`, `list_scripts`
- **Project**: `get_project_info`, `get_project_settings`, `set_project_setting`, `get_project_statistics`, `get_filesystem_tree`, `get_input_actions`, `set_input_action`
- **Editor**: `execute_editor_script`, `get_editor_errors`, `get_output_log`, `get_editor_screenshot`, `clear_output`, `reload_plugin`, `reload_project`
- **Resources**: `create_resource`, `read_resource`, `edit_resource`, `get_resource_preview`
- **Batch**: `batch_add_nodes`, `batch_set_property`, `find_nodes_by_type`, `find_signal_connections`, `find_node_references`, `get_scene_dependencies`, `cross_scene_set_property`
- **3D**: `add_mesh_instance`, `setup_environment`, `setup_lighting`, `setup_camera_3d`, `setup_collision`, `setup_physics_body`, `set_material_3d`, `add_raycast`, `add_gridmap`
- **Animation**: `create_animation`, `add_animation_track`, `set_animation_keyframe`, `list_animations`, `get_animation_info`, `remove_animation`
- **Animation Tree**: `create_animation_tree`, `get_animation_tree_structure`, `add_state_machine_state`, `add_state_machine_transition`, `remove_state_machine_state`, `remove_state_machine_transition`, `set_blend_tree_node`, `set_tree_parameter`
- **Audio**: `add_audio_player`, `add_audio_bus`, `add_audio_bus_effect`, `set_audio_bus`, `get_audio_bus_layout`, `get_audio_info`
- **Navigation**: `setup_navigation_region`, `setup_navigation_agent`, `bake_navigation_mesh`, `set_navigation_layers`, `get_navigation_info`
- **Particles**: `create_particles`, `set_particle_material`, `set_particle_color_gradient`, `apply_particle_preset`, `get_particle_info`
- **Physics**: `get_physics_layers`, `set_physics_layers`, `get_collision_info`
- **Shader**: `create_shader`, `read_shader`, `edit_shader`, `assign_shader_material`, `get_shader_params`, `set_shader_param`
- **Theme**: `create_theme`, `get_theme_info`, `set_theme_color`, `set_theme_font_size`, `set_theme_constant`, `set_theme_stylebox`
- **Tilemap**: `tilemap_get_info`, `tilemap_set_cell`, `tilemap_get_cell`, `tilemap_fill_rect`, `tilemap_clear`, `tilemap_get_used_cells`
- **Export**: `list_export_presets`, `get_export_info`, `export_project`
- **Analysis**: `analyze_scene_complexity`, `analyze_signal_flow`, `detect_circular_dependencies`, `find_unused_resources`, `get_performance_monitors`, `search_files`, `search_in_files`, `find_script_references`
- **Profiling**: `get_editor_performance`

### Runtime Tools (require `play_scene` first)
You MUST call `play_scene` before using any of these. They interact with the running game:
- **Game State**: `get_game_scene_tree`, `get_game_node_properties`, `set_game_node_property`, `execute_game_script`, `get_game_screenshot`, `get_autoload`, `find_nodes_by_script`
- **Input Simulation**: `simulate_key`, `simulate_mouse_click`, `simulate_mouse_move`, `simulate_action`, `simulate_sequence`
- **Capture/Recording**: `capture_frames`, `record_frames`, `monitor_properties`, `start_recording`, `stop_recording`, `replay_recording`, `batch_get_properties`
- **UI Interaction**: `find_ui_elements`, `click_button_by_text`, `wait_for_node`, `find_nearby_nodes`, `navigate_to`, `move_to`
- **Testing**: `run_test_scenario`, `assert_node_state`, `assert_screen_text`, `run_stress_test`, `get_test_report`
- **Screenshots**: `get_game_screenshot`, `compare_screenshots`
- **Control**: `play_scene`, `stop_scene`

## Workflow Patterns

### Building a scene from scratch
1. `create_scene` or `open_scene`
2. Use `add_node` or `batch_add_nodes` to add nodes
3. `create_script` + `attach_script` for behavior
4. `save_scene`

### Testing gameplay
1. Build scene with editor tools (above)
2. `play_scene` to start the game
3. Use `simulate_key`/`simulate_mouse_click` for input
4. `get_game_screenshot` or `capture_frames` to observe results
5. `stop_scene` when done

### Inspecting a project
1. `get_project_info` for overview
2. `get_scene_tree` for current scene structure
3. `read_script` to read code
4. `get_node_properties` for specific node details

### Migrating code properties to inspector
When a script hardcodes visual properties (colors, sizes, positions, theme overrides) that should be in the inspector:
1. `read_script` to find hardcoded property assignments (e.g. `modulate = Color(...)`, `add_theme_color_override(...)`)
2. `get_node_properties` to see current inspector values
3. `update_property` to set the same values as node properties in the inspector
4. `edit_script` to remove the hardcoded lines from the script
5. `save_scene` to persist the inspector changes
6. `validate_script` to verify the script still works

## Formatting Rules

### execute_editor_script
The `code` parameter must be valid GDScript. Use `_mcp_print(value)` to return output.

```
# Correct
_mcp_print("hello")

# Correct - multi-line
var nodes = []
for child in EditorInterface.get_edited_scene_root().get_children():
    nodes.append(child.name)
_mcp_print(str(nodes))
```

### execute_game_script
Same as above but runs inside the running game. Additional rules:
- No nested functions (`func` inside `func` is invalid GDScript)
- Use `.get("property")` instead of `.property` for safe access
- Runs in a temporary node — use `get_tree()` to access the scene tree

### batch_add_nodes
Pass an array of node definitions. Nodes are processed in order, so earlier nodes can be parents for later ones:
```json
{
  "nodes": [
    {"type": "Node2D", "name": "Container", "parent_path": "."},
    {"type": "Sprite2D", "name": "Icon", "parent_path": "Container"},
    {"type": "Label", "name": "Title", "parent_path": "Container", "properties": {"text": "Hello"}}
  ]
}
```

## Best Practices

1. **Prefer inspector properties over code** — When changing visual properties (colors, sizes, theme overrides, transforms, etc.), use `update_property` to set them directly on the node. This keeps values visible in the Godot inspector and easy to tweak. Only use GDScript when the property isn't available in the inspector or needs to be dynamic at runtime.

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

## Common Pitfalls

1. **Never edit project.godot directly** — Use `set_project_setting` instead. The Godot editor overwrites the file.
2. **GDScript type inference** — Use explicit type annotations in for-loops: `for item: String in array` instead of `for item in array`.
3. **Reload after script changes** — After `create_script`, call `reload_project` if the script doesn't take effect.
4. **Property values as strings** — Properties like position accept string format: `"Vector2(100, 200)"`, `"Color(1, 0, 0, 1)"`.
5. **simulate_key duration** — Use short durations (0.3-0.5s) for precise movement. Integer seconds (1, 2, 3) cause overshooting.
6. **compare_screenshots** — Pass file paths (`user://screenshot.png`), not base64 data.
7. **Blender MCP: `transform_apply` silently drops rotation** — `bpy.ops.object.transform_apply(rotation=True)` reports success and zeroes `obj.rotation_euler`, but does **not** bake the rotation into the mesh. `location=True` and `scale=True` apply fine. Rotate the mesh data directly instead: `mesh.transform(mathutils.Matrix.Rotation(angle, 4, 'Z'))`, which is context-free and always works. This cost a full rebuild of the sporecap — the model was correctly scaled and grounded, so the lost 90° rotation was only caught by noticing the arm axis hadn't swapped.
8. **Blender MCP: `bound_box` and `matrix_world` are stale right after an operator** — measure from `obj.data.vertices` (times `matrix_world`), or call `bpy.context.view_layer.update()` first. Verify every transform by re-measuring vertex bounds rather than trusting the operator's return value.
9. **Blender MCP: mutating a live selection while iterating it** — `for o in bpy.context.selected_objects: o.select_set(False)` skips entries, which can leave unintended objects selected when a destructive operator (`transform_apply`) runs next. Use `bpy.ops.object.select_all(action='DESELECT')`.
10. **Workbench `WIREFRAME` shading renders empty**, and `show_wire` is a viewport overlay that never reaches a render. For a renderable wireframe, duplicate the mesh and add a `WIREFRAME` modifier with `use_replace = True`.

## CLI Mode (Alternative to MCP Tools)

If MCP tools are unavailable or you have a terminal/bash tool, you can control Godot via the CLI.
The CLI requires the server to be built first (`node build/setup.js install` in the server directory).

```bash
# Discover available command groups
node /path/to/server/build/cli.js --help

# Discover commands in a group
node /path/to/server/build/cli.js scene --help

# Discover options for a specific command
node /path/to/server/build/cli.js node add --help

# Execute commands
node /path/to/server/build/cli.js project info
node /path/to/server/build/cli.js scene tree
node /path/to/server/build/cli.js node add --type CharacterBody3D --name Player --parent /root/Main
node /path/to/server/build/cli.js script read --path res://player.gd
node /path/to/server/build/cli.js scene play
node /path/to/server/build/cli.js input key --key W --duration 0.5
node /path/to/server/build/cli.js runtime tree
```

**Command groups**: project, scene, node, script, editor, input, runtime

Always start by running `--help` to discover available commands. Use the CLI when MCP tools are not loaded or when you need to reduce context usage.

## Project Notes

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
2. **Generate in A-pose, never T-pose.** `pose_mode: "a-pose"`. A T-pose model has to be
   re-posed to get its arms down, which skins the mesh twice and flattens the arms into
   fins — this happened on the first sporecap attempt and was only fixed by regenerating.
   An A-pose model is rigged in its modelled pose, so the rest pose needs no baking at all.
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
   `SKELETON_PATH` entry `Rig/Model/<Name>Rig/Skeleton3D` plus a `match` branch in
   `CombatantSkeletonAnimations`, an `IMPACT_DELAYS` entry in `CombatantAnimations`, and
   the id added to a pool in `game_state.gd`.

**Verifying without `execute_game_script`** (this MCP build has neither it nor
`execute_editor_script`): make a throwaway scene at `res://scratch_<name>.tscn` that
instances the enemy, calls `setup()` with its stats, prints
`anim.get_animation_list()`, and loops a clip. `play_scene` it, read `get_output_log`,
`capture_frames` to confirm the mesh actually deforms, then delete the scratch files.
