"""Character pipeline - build stage (headless Blender).

Imports KayKit Rig_Medium and its mannequin, fits the Meshy mesh to the armature (never
the armature to the mesh), transfers the mannequin's weights, palette-snaps the texture,
attaches props, bakes the spec's clips as NLA tracks and exports the glb. Writes
`build_report.json` and `<id>_built.blend` beside the glb for the verify stage.

Every threshold below is in Rig_Medium's own space (or, for the `arm_select_x` /
`torso_box` / `facing_region` samples, Meshy's unit-box output), which is why the values
that fitted the bandit officer are the defaults. A spec's `fit` / `weights` blocks
override them per character.
"""

import json
import math
import os
import struct
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402

FIT_DEFAULTS = {
    "weld_distance": 1e-4,
    "arm_select_x": 0.40,
    "torso_box_x": 0.15,
    "torso_box_z": [-0.25, 0.0],
    "arm_band_x": 0.42,
    "arm_band_z": [0.80, 1.45],
    "facing_region_z": [0.08, 0.26],
    "facing_region_x": 0.12,
}
WEIGHT_DEFAULTS = {
    "smoothing_passes": 3,
    "head_blend_below": 0.07,
    "head_blend_above": 0.03,
    "head_blend_half_width": 0.30,
    "head_full_above": 0.08,
    "head_full_half_width": 0.75,
    "rigid_head_above": 0.06,
    "max_influences": 4,
    "prune_below": 0.01,
}
IMPACT_DEFAULT_BONE = "handslot.r"

job = C.load_job()
spec = job["spec"]
char_id = spec["id"]
fit_cfg = dict(FIT_DEFAULTS, **spec.get("fit", {}))
weight_cfg = dict(WEIGHT_DEFAULTS, **spec.get("weights", {}))
report = {"id": char_id, "blender": bpy.app.version_string, "warnings": []}
scene = bpy.context.scene

C.reset_scene()
scene = bpy.context.scene

# ---------- the rig and its mannequin ----------
names, actions = C.import_glb(job["rig_source"])
C.remove_actions(actions)
C.remove_objects([n for n in names if n.startswith("Icosphere")])
armature = bpy.data.objects.get("Rig_Medium")
if armature is None or armature.type != 'ARMATURE':
    raise RuntimeError("the rig source has no 'Rig_Medium' armature")
armature.animation_data_clear()
armature.data.pose_position = 'REST'
bpy.context.view_layer.update()
mannequin = [bpy.data.objects[n] for n in names if n.startswith("Mannequin") and n in bpy.data.objects]
bone_names = [b.name for b in armature.data.bones]
bones = {name: C.bone_head_world(armature, name) for name in bone_names}

# ---------- the Meshy mesh, baked to identity ----------
names, actions = C.import_glb(job["raw_mesh"])
C.remove_actions(actions)
meshes = [bpy.data.objects[n] for n in names if bpy.data.objects[n].type == 'MESH']
if len(meshes) != 1:
    raise RuntimeError(f"expected one mesh in {job['raw_mesh']}, found {len(meshes)}")
body = meshes[0]
world = body.matrix_world.copy()
body.parent = None
body.matrix_world = world
bpy.context.view_layer.update()
body.data.transform(body.matrix_world)
body.matrix_world = Matrix.Identity(4)
C.remove_objects([n for n in names if n != body.name])
body.name = job["node_name"]
body.data.name = job["node_name"]
mesh = body.data

# ---------- weld: the glTF import splits vertices at every UV seam ----------
bm = bmesh.new()
bm.from_mesh(mesh)
verts_before = len(bm.verts)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=fit_cfg["weld_distance"])
bm.to_mesh(mesh)
bm.free()
mesh.update()
report["weld"] = {"verts_before": verts_before, "verts_after": len(mesh.vertices)}

# ---------- facing: KayKit characters face -Y; turn the mesh if its face points +Y ----------
centers = np.array([p.center[:] for p in mesh.polygons])
normals = np.array([p.normal[:] for p in mesh.polygons])
z0, z1 = fit_cfg["facing_region_z"]
region = (centers[:, 2] > z0) & (centers[:, 2] < z1) & (np.abs(centers[:, 0]) < fit_cfg["facing_region_x"])
facing_y = float(normals[region, 1].mean()) if region.any() else 0.0
rotated = facing_y > 0.05
if rotated:
    mesh.transform(Matrix.Rotation(math.pi, 4, 'Z'))
    mesh.update()
    report["warnings"].append("the mesh faced +Y and was turned 180 degrees - check the pose sheet")
report["facing"] = {"head_region_normal_y": round(facing_y, 3), "rotated_180": rotated}

# ---------- fit the mesh to the rig ----------
co = np.array([v.co[:] for v in mesh.vertices])
min_z = float(co[:, 2].min())
arm_z = float(co[np.abs(co[:, 0]) > fit_cfg["arm_select_x"]][:, 2].mean())
scale = bones["hand.l"].z / (arm_z - min_z)
tz0, tz1 = fit_cfg["torso_box_z"]
torso = co[(np.abs(co[:, 0]) < fit_cfg["torso_box_x"]) & (co[:, 2] > tz0) & (co[:, 2] < tz1)]
y_offset = float((torso[:, 1].min() + torso[:, 1].max()) / 2)
new = co.copy()
new[:, 0] *= scale
new[:, 1] = (new[:, 1] - y_offset) * scale
new[:, 2] = (new[:, 2] - min_z) * scale
mannequin_verts = np.array([(o.matrix_world @ v.co)[:] for o in mannequin for v in o.data.vertices])
mannequin_tip = max(abs((o.matrix_world @ v.co).x) for o in mannequin if "Arm" in o.name for v in o.data.vertices)
x0 = fit_cfg["arm_band_x"]
bz0, bz1 = fit_cfg["arm_band_z"]
band = (new[:, 2] > bz0) & (new[:, 2] < bz1) & (np.abs(new[:, 0]) > x0)
tip = float(np.abs(new[band][:, 0]).max()) if band.any() else x0
squash = (mannequin_tip - x0) / (tip - x0) if tip > x0 else 1.0
new[band, 0] = np.sign(new[band, 0]) * (x0 + (np.abs(new[band, 0]) - x0) * squash)
mesh.vertices.foreach_set("co", new.astype(np.float32).ravel())
mesh.update()
left_feet = new[(new[:, 2] < 0.2) & (new[:, 0] < 0)]
right_feet = new[(new[:, 2] < 0.2) & (new[:, 0] > 0)]
boot_x = [round(float(left_feet[:, 0].mean()), 3) if len(left_feet) else None,
          round(float(right_feet[:, 0].mean()), 3) if len(right_feet) else None]
report["fit"] = {
    "scale": round(scale, 4), "y_offset": round(y_offset, 4), "arm_squash": round(squash, 4),
    "height": round(float(new[:, 2].max()), 3), "mannequin_height": round(float(mannequin_verts[:, 2].max()), 3),
    "arm_tip": round(float(np.abs(new[:, 0]).max()), 3), "mannequin_tip": round(mannequin_tip, 3),
    "boot_x": boot_x, "upperleg_x": round(bones["upperleg.l"].x, 3),
}
fit = report["fit"]
if None in boot_x or max(abs(abs(b) - fit["upperleg_x"]) for b in boot_x) > 0.05:
    report["warnings"].append(f"boots at {boot_x} sit off the upperleg bones (±{fit['upperleg_x']})")
if not 0.7 <= squash <= 1.15:
    report["warnings"].append(f"arms needed a {round((1 - squash) * 100)}% pull-in - the concept's arm span is off")
if not 0.85 <= fit["height"] / fit["mannequin_height"] <= 1.12:
    report["warnings"].append(f"height {fit['height']} is far from the mannequin's {fit['mannequin_height']}")

# ---------- connected parts ----------
bm = bmesh.new()
bm.from_mesh(mesh)
bm.verts.ensure_lookup_table()
island_of = np.full(len(bm.verts), -1)
islands = []
for vert in bm.verts:
    if island_of[vert.index] != -1:
        continue
    index = len(islands)
    stack = [vert]
    island_of[vert.index] = index
    members = []
    while stack:
        current = stack.pop()
        members.append(current.index)
        for edge in current.link_edges:
            other = edge.other_vert(current)
            if island_of[other.index] == -1:
                island_of[other.index] = index
                stack.append(other)
    islands.append(members)
edges = np.array([(e.verts[0].index, e.verts[1].index) for e in bm.edges])
bm.free()
sizes = [len(m) for m in islands]
order = np.argsort(sizes)[::-1]
main_island = int(order[0])

# ---------- weights: nearest-surface transfer from the mannequin's body parts ----------
# The mannequin's head is left out: its oversized block reaches down over the shoulders
# and would pull epaulettes and collars onto `head`.
source_verts, source_weights, source_tris = [], [], []
for part in mannequin:
    if part.name.endswith("Head"):
        continue
    group_names = {g.index: g.name for g in part.vertex_groups}
    part.data.calc_loop_triangles()
    base = len(source_verts)
    source_verts += [part.matrix_world @ v.co for v in part.data.vertices]
    for v in part.data.vertices:
        source_weights.append({group_names[g.group]: g.weight for g in v.groups if g.weight > 1e-5})
    source_tris += [tuple(i + base for i in t.vertices) for t in part.data.loop_triangles]
bvh = BVHTree.FromPolygons(source_verts, source_tris)
bone_index = {name: i for i, name in enumerate(bone_names)}
W = np.zeros((len(mesh.vertices), len(bone_names)), dtype=np.float64)
e1, e2, e3 = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
for vi, v in enumerate(mesh.vertices):
    location, _normal, tri, _distance = bvh.find_nearest(v.co)
    a, b, c = source_tris[tri]
    barycentric = barycentric_transform(location, source_verts[a], source_verts[b], source_verts[c], e1, e2, e3)
    for weight, source in zip(barycentric, (a, b, c)):
        for name, bone_weight in source_weights[source].items():
            W[vi, bone_index[name]] += max(0.0, weight) * bone_weight


def normalize(matrix):
    totals = matrix.sum(1, keepdims=True)
    totals[totals == 0] = 1
    return matrix / totals


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


W = normalize(W)
main_mask = island_of == main_island
for _ in range(int(weight_cfg["smoothing_passes"])):
    accumulated = np.zeros_like(W)
    counts = np.zeros((len(W), 1))
    np.add.at(accumulated, edges[:, 0], W[edges[:, 1]])
    np.add.at(accumulated, edges[:, 1], W[edges[:, 0]])
    np.add.at(counts, edges[:, 0], 1)
    np.add.at(counts, edges[:, 1], 1)
    counts[counts == 0] = 1
    W[main_mask] = (0.5 * W + 0.5 * (accumulated / counts))[main_mask]

head_z = bones["head"].z
head = bone_index["head"]
z = new[:, 2]
ax = np.abs(new[:, 0])
head_share = np.where(
    z > head_z + weight_cfg["head_full_above"],
    np.where(ax < weight_cfg["head_full_half_width"], 1.0, 0.0),
    np.where(ax < weight_cfg["head_blend_half_width"],
             smoothstep(head_z - weight_cfg["head_blend_below"], head_z + weight_cfg["head_blend_above"], z), 0.0))
head_share = np.where(main_mask, head_share, 0.0)
W[main_mask] *= (1 - head_share[main_mask])[:, None]
W[main_mask, head] += head_share[main_mask]

rigid = []
for index, members in enumerate(islands):
    if index == main_island:
        continue
    member_array = np.array(members)
    center_z = float(new[member_array, 2].mean())
    if center_z > head_z + weight_cfg["rigid_head_above"]:
        row = np.zeros(len(bone_names))
        row[head] = 1.0
    else:
        row = normalize(W[member_array].mean(0, keepdims=True))[0]
    W[member_array] = row
    rigid.append({"verts": len(members), "center_z": round(center_z, 3), "bone": bone_names[int(row.argmax())]})

keep = int(weight_cfg["max_influences"])
np.put_along_axis(W, np.argsort(W, axis=1)[:, :-keep], 0.0, axis=1)
W[W < weight_cfg["prune_below"]] = 0.0
W = normalize(W)
body.vertex_groups.clear()
groups = {name: body.vertex_groups.new(name=name) for name in bone_names}
for vi in range(len(W)):
    for j in np.nonzero(W[vi])[0]:
        groups[bone_names[j]].add([vi], float(W[vi, j]), 'REPLACE')
dominant = W.argmax(1)
report["islands"] = {"count": len(islands), "main_verts": sizes[main_island],
                     "rigid": sorted(rigid, key=lambda r: -r["verts"])}
report["dominant_bone_verts"] = {bone_names[j]: int((dominant == j).sum())
                                 for j in range(len(bone_names)) if (dominant == j).sum()}

# ---------- bind: parent to the armature and deform through it ----------
# Without this the weights exist but nothing uses them: the glb exports an unskinned mesh.
body.parent = armature
body.matrix_parent_inverse.identity()
for modifier in list(body.modifiers):
    body.modifiers.remove(modifier)
armature_modifier = body.modifiers.new("Armature", 'ARMATURE')
armature_modifier.object = armature

# ---------- texture: resample, then palette-snap, under a stable image name ----------
material = mesh.materials[0] if mesh.materials else None
texture_node = None
if material is not None and material.use_nodes:
    texture_node = next((n for n in material.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image), None)
if texture_node is None:
    raise RuntimeError("the raw mesh has no base colour texture - the palette snap needs one")
image = bpy.data.images.load(job["raw_texture"]) if job["raw_texture"] else texture_node.image
size = int(spec.get("texture_size", 1024))
if tuple(image.size) != (size, size):
    image.scale(size, size)
report["palette"] = C.palette_snap_image(image, spec["palette"])
# The exported image is named after this file, and Godot extracts embedded textures as
# <glb>_<image>.png - a stable name means a rebuild overwrites that file instead of
# orphaning it.
image.filepath_raw = os.path.join(job["work"], "albedo.png")
image.file_format = 'PNG'
image.save()
image.name = "albedo"
image.pack()
previous = texture_node.image
texture_node.image = image
if previous is not image and previous.users == 0:
    bpy.data.images.remove(previous)
for node in material.node_tree.nodes:
    if node.type == 'BSDF_PRINCIPLED':
        node.inputs["Roughness"].default_value = 1.0
        node.inputs["Metallic"].default_value = 0.0
material.name = char_id
for name, entry in report["palette"].items():
    if entry["share"] > 0.02 and entry["mean_delta_e"] is not None and entry["mean_delta_e"] > 12:
        report["warnings"].append(f"palette '{name}' is a loose fit (mean ΔE {entry['mean_delta_e']})")

# ---------- props: another glb's mesh, at that glb's own attachment ----------
prop_objects = []
report["props"] = []
for prop in job["props"]:
    names, actions = C.import_glb(prop["source"])
    C.remove_actions(actions)
    for n in names:
        obj = bpy.data.objects[n]
        if obj.type == 'ARMATURE':
            obj.animation_data_clear()
            obj.data.pose_position = 'REST'
    bpy.context.view_layer.update()
    source = next((bpy.data.objects[n] for n in names if n.split(".")[0] == prop["node"]), None)
    if source is None:
        raise RuntimeError(f"no node '{prop['node']}' in {prop['source']}")
    prop_world = source.matrix_world.copy()
    source.parent = None
    source.matrix_world = prop_world
    C.remove_objects([n for n in names if n != source.name])
    source.name = prop.get("name", prop["node"])
    source.parent = armature
    source.parent_type = 'BONE'
    source.parent_bone = prop["bone"]
    bpy.context.view_layer.update()
    source.matrix_world = prop_world
    bpy.context.view_layer.update()
    drift = max(abs(a - b) for ra, rb in zip(source.matrix_world, prop_world) for a, b in zip(ra, rb))
    report["props"].append({"name": source.name, "bone": prop["bone"], "source": os.path.basename(prop["source"]),
                            "attachment_drift": round(drift, 6),
                            "materials": [m.name for m in source.data.materials]})
    if drift > 1e-4:
        report["warnings"].append(f"prop {source.name} moved {drift:.4f} when bone-parented")
    prop_objects.append(source)

# ---------- clips: import the pack actions, keep only the ones the spec plays ----------
states = [s for s in C.STATE_ORDER if s in spec["clips"]]
wanted = []
for state in states:
    clip = spec["clips"][state]["clip"]
    if clip not in wanted:
        wanted.append(clip)
for clip_file in job["clip_files"]:
    names, actions = C.import_glb(clip_file)
    C.remove_objects(names)
    C.remove_actions([n for n in actions if n not in wanted])
missing = [c for c in wanted if c not in bpy.data.actions]
if missing:
    raise RuntimeError(f"clips missing after import: {missing}")
fps = scene.render.fps / scene.render.fps_base


def measure_strike(action, bone):
    """Frame fractions of the bone's highest point and its fastest drop after it.

    The impact lands between the two. Tuned on overhead and downward strikes - for a
    thrust, kick or cast, set a number in the spec instead of "auto".
    """
    C.assign_action(armature, action)
    armature.data.pose_position = 'POSE'
    first, last = int(round(action.frame_range[0])), int(round(action.frame_range[1]))
    heights = []
    for frame in range(first, last + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        heights.append(C.pose_bone_world(armature, bone).z)
    heights = np.array(heights)
    span = max(1, last - first)
    peak = int(heights.argmax())
    drops = np.diff(heights)
    fastest = peak + int(drops[peak:].argmin()) + 1 if peak < len(drops) else peak
    return {"bone": bone, "frames": [first, last], "peak_frac": round(peak / span, 4),
            "fastest_drop_frac": round(fastest / span, 4), "impact_frac": round((peak + fastest) / 2 / span, 4)}


report["impacts"] = {}
report["impact_tracks"] = {}
for state in states:
    clip = spec["clips"][state]
    for key in ("impact", "cast", "charge"):
        if clip.get(key) == "auto":
            track = measure_strike(bpy.data.actions[clip["clip"]], clip.get("impact_bone", IMPACT_DEFAULT_BONE))
            report["impact_tracks"][state] = track
            report["impacts"][state] = round(float(clip["length"]) * track["impact_frac"], 2)
C.assign_action(armature, None)
armature.data.pose_position = 'REST'

report["clips"] = {}
for state in states:
    action = bpy.data.actions[spec["clips"][state]["clip"]]
    report["clips"][state] = {"clip": action.name,
                              "source_seconds": round((action.frame_range[1] - action.frame_range[0]) / fps, 3),
                              "game_length": spec["clips"][state]["length"]}

animation = armature.animation_data_create()
animation.action = None
for track in list(animation.nla_tracks):
    animation.nla_tracks.remove(track)
for clip in wanted:
    action = bpy.data.actions[clip]
    action.use_fake_user = True
    track = animation.nla_tracks.new()
    track.name = clip
    strip = track.strips.new(clip, int(action.frame_range[0]), action)
    if hasattr(strip, "action_slot") and len(action.slots):
        strip.action_slot = action.slots[0]
armature.data.pose_position = 'POSE'
scene.frame_set(0)

# ---------- save the work file, export the glb ----------
bpy.ops.wm.save_as_mainfile(filepath=job["out_blend"])
for obj in bpy.context.view_layer.objects:
    obj.select_set(False)
for obj in [armature, body] + prop_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = armature
bpy.ops.export_scene.gltf(filepath=job["out_glb"], export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='NLA_TRACKS',
                          export_apply=False, export_skins=True, export_yup=True)

with open(job["out_glb"], "rb") as f:
    data = f.read()
gltf = json.loads(data[20:20 + struct.unpack("<I", data[12:16])[0]])
report["glb"] = {
    "path": job["out_glb"],
    "bytes": len(data),
    "animations": [a["name"] for a in gltf.get("animations", [])],
    "joints": len(gltf["skins"][0]["joints"]) if gltf.get("skins") else 0,
    "images": [i.get("name") for i in gltf.get("images", [])],
    "materials": [m.get("name") for m in gltf.get("materials", [])],
}
report["mesh"] = {"verts": len(mesh.vertices), "tris": sum(len(p.vertices) - 2 for p in mesh.polygons),
                  "texture_size": size}
if len(report["glb"]["animations"]) > 12:
    report["warnings"].append("more than 12 clips - over tests/test_animation_clips.gd's ceiling")
with open(os.path.join(job["work"], "build_report.json"), "w", encoding="utf-8") as f:
    json.dump(report, f, indent=1, ensure_ascii=False)
