"""Character pipeline - verify stage (headless Blender).

Opens the build's work file and produces the two things a person reviews:

- `pose_sheet.png`: the rest pose from front, three-quarter and side, then three frames
  of every clip the spec plays, one row per state. Every tile is framed on the posed
  body and its props, so a death that ends lying down stays in shot.
- `report.md` / `report.json`: the build numbers plus a deformation check. Edge lengths
  in nine frames of every clip are compared with the rest pose, and each clip is flagged
  when its stretch or squash goes well past what the bandit officer shows.
"""

import json
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402

# Calibrated on the bandit officer, the one character checked by eye in Blender and in
# Godot: its worst clips reach 1.54 stretch (Running_A) and 0.60 squash (Death_A).
# Edges shorter than MIN_EDGE_FRACTION of the height are skipped - near joints they swing
# wildly with nothing visibly wrong. Revise these as more characters come through.
MIN_EDGE_FRACTION = 0.02
STRETCH_FLAG = 1.9
SQUASH_FLAG = 0.45
TILE = 384
MIN_FRAME = 3.0
SAMPLE_FRACTIONS = {"idle": [0.0, 0.33, 0.66], "run": [0.0, 0.25, 0.5], "hurt": [0.15, 0.4, 0.8],
                    "die": [0.3, 0.7, 1.0]}

job = C.load_job()
spec = job["spec"]
char_id = spec["id"]
work = job["work"]
project = job["project"]
with open(job["build_report"], encoding="utf-8") as f:
    build = json.load(f)

bpy.ops.wm.open_mainfile(filepath=job["built_blend"])
scene = bpy.context.scene
armature = bpy.data.objects["Rig_Medium"]
body = bpy.data.objects[job["node_name"]]
props = [o for o in bpy.data.objects if o.parent == armature and o.type == 'MESH'
         and o is not body and not o.name.startswith("Mannequin")]
for obj in bpy.data.objects:
    if obj.name.startswith("Mannequin") or obj.name.startswith("Icosphere"):
        obj.hide_render = True
for track in armature.animation_data.nla_tracks:
    track.mute = True

mesh = body.data
rest = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
mesh.vertices.foreach_get("co", rest)
rest = rest.reshape(-1, 3)
height = float(rest[:, 2].max() - rest[:, 2].min())
edge_index = np.empty(len(mesh.edges) * 2, dtype=np.int32)
mesh.edges.foreach_get("vertices", edge_index)
edge_index = edge_index.reshape(-1, 2)
rest_length = np.linalg.norm(rest[edge_index[:, 0]] - rest[edge_index[:, 1]], axis=1)
measured = rest_length > max(1e-5, MIN_EDGE_FRACTION * height)


def deformed_positions():
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = body.evaluated_get(depsgraph)
    temp = evaluated.to_mesh()
    positions = np.empty(len(temp.vertices) * 3, dtype=np.float32)
    temp.vertices.foreach_get("co", positions)
    evaluated.to_mesh_clear()
    return positions.reshape(-1, 3)


def set_clip(action, fraction):
    C.assign_action(armature, action)
    armature.data.pose_position = 'POSE' if action is not None else 'REST'
    if action is not None:
        first, last = action.frame_range
        scene.frame_set(int(round(first + (last - first) * fraction)))
    bpy.context.view_layer.update()


def framed_tile(azimuth):
    """Renders the current pose, framed on the posed body and its props."""
    points = [deformed_positions()]
    for prop in props:
        points.append(np.array([(prop.matrix_world @ Vector(corner))[:] for corner in prop.bound_box]))
    points = np.concatenate(points)
    low, high = points.min(0), points.max(0)
    center = (low + high) / 2
    frame = max(MIN_FRAME, float((high - low).max()) * 1.15)
    return C.render_png(os.path.join(work, "_tile.png"), res=TILE, ortho_scale=frame,
                        center_z=float(center[2]), azimuth_deg=azimuth,
                        center_xy=(float(center[0]), float(center[1])))


tiles = []
set_clip(None, 0.0)
for azimuth in (0, -35, 90):
    tiles.append(framed_tile(azimuth))

states = [s for s in C.STATE_ORDER if s in spec["clips"]]
deformation = {}
for state in states:
    clip = spec["clips"][state]
    action = bpy.data.actions[clip["clip"]]
    ratios = []
    for fraction in np.linspace(0.0, 1.0, 9):
        set_clip(action, float(fraction))
        positions = deformed_positions()
        length = np.linalg.norm(positions[edge_index[:, 0]] - positions[edge_index[:, 1]], axis=1)
        ratios.append(length[measured] / rest_length[measured])
    ratios = np.concatenate(ratios)
    entry = {"clip": clip["clip"],
             "stretch_p99_5": round(float(np.percentile(ratios, 99.5)), 2),
             "stretch_max": round(float(ratios.max()), 2),
             "squash_p0_5": round(float(np.percentile(ratios, 0.5)), 2),
             "squash_min": round(float(ratios.min()), 2)}
    entry["flag"] = entry["stretch_p99_5"] > STRETCH_FLAG or entry["squash_p0_5"] < SQUASH_FLAG
    deformation[state] = entry

    track = build.get("impact_tracks", {}).get(state)
    if track:
        fractions = [track["peak_frac"], track["impact_frac"], min(1.0, track["impact_frac"] + 0.25)]
    else:
        fractions = SAMPLE_FRACTIONS.get(state, [0.2, 0.5, 0.8])
    for fraction in fractions:
        set_clip(action, fraction)
        tiles.append(framed_tile(-60 if state == "die" else -35))
os.remove(os.path.join(work, "_tile.png"))
sheet_path = os.path.join(work, "pose_sheet.png")
C.save_sheet(sheet_path, tiles, cols=3)


def rel(path):
    try:
        return os.path.relpath(path, project).replace("\\", "/")
    except ValueError:
        return path


fit = build["fit"]
glb = build["glb"]
warnings = list(build.get("warnings", []))
warnings += [f"{state} ({entry['clip']}) deforms well past the bandit officer's range - check its row"
             for state, entry in deformation.items() if entry["flag"]]
palette = sorted(build["palette"].items(), key=lambda kv: -kv[1]["share"])
lines = [
    f"# {char_id} - pipeline report",
    "",
    f"- **glb:** `{rel(glb['path'])}`, {glb['bytes'] / 1024:.0f} KB; {build['mesh']['verts']} verts, "
    f"{build['mesh']['tris']} tris, {build['mesh']['texture_size']}² texture, {glb['joints']} joints",
    f"- **images:** {', '.join(glb['images'])}; **materials:** {', '.join(glb['materials'])}",
    f"- **fit:** height {fit['height']} (mannequin {fit['mannequin_height']}); arm tip {fit['arm_tip']} "
    f"(mannequin {fit['mannequin_tip']}); boots {fit['boot_x']} on upperleg ±{fit['upperleg_x']}; "
    f"arms pulled in {round((1 - fit['arm_squash']) * 100)}%",
    f"- **facing:** head normal y {build['facing']['head_region_normal_y']}, rotated: {build['facing']['rotated_180']}",
    f"- **parts:** {build['islands']['count']} (main {build['islands']['main_verts']} verts); rigid: "
    + ", ".join(f"{r['verts']}v@{r['bone']}" for r in build["islands"]["rigid"][:8]),
    "- **props:** " + (", ".join(f"{p['name']} on {p['bone']} from {p['source']} (drift {p['attachment_drift']})"
                                for p in build["props"]) or "none"),
    "- **palette share:** " + ", ".join(f"{name} {entry['share'] * 100:.0f}% (ΔE {entry['mean_delta_e']})"
                                        for name, entry in palette if entry["share"] >= 0.01),
    "",
    f"Deformation skips edges under {MIN_EDGE_FRACTION:.0%} of the height; CHECK above {STRETCH_FLAG} stretch "
    f"or below {SQUASH_FLAG} squash (both percentiles).",
    "",
    "| state | clip | source s | game length | impact | stretch p99.5 | max | squash p0.5 | min | flag |",
    "|---|---|---|---|---|---|---|---|---|---|",
]
for state in states:
    clip = build["clips"][state]
    entry = deformation[state]
    impact = build.get("impacts", {}).get(state, spec["clips"][state].get("impact", ""))
    lines.append(f"| {state} | {clip['clip']} | {clip['source_seconds']} | {clip['game_length']} | {impact} | "
                 f"{entry['stretch_p99_5']} | {entry['stretch_max']} | {entry['squash_p0_5']} | "
                 f"{entry['squash_min']} | {'CHECK' if entry['flag'] else 'ok'} |")
lines += ["", f"**Review:** `{rel(sheet_path)}` - row 1 is the rest pose (front, three-quarter, side), then one "
          f"row per state in the table's order.", ""]
lines += (["**Warnings:**"] + [f"- {w}" for w in warnings]) if warnings else ["**Warnings:** none"]
with open(os.path.join(work, "report.md"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
with open(os.path.join(work, "report.json"), "w", encoding="utf-8") as f:
    json.dump({"build": build, "deformation": deformation, "warnings": warnings, "pose_sheet": sheet_path},
              f, indent=1, ensure_ascii=False)
