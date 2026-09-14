import bpy, bmesh, os, json, math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

BW = os.environ['BW']
OUT_GLB = "C:/Projects/Godot/Sir Fish/assets/meshes/bandit_officer.glb"
bpy.ops.wm.open_mainfile(filepath=BW + "/work_welded.blend")
arm = bpy.data.objects["Rig_Medium"]
body = bpy.data.objects["Bandit_Raw"]
mann = [o for o in bpy.data.objects if o.name.startswith("Mannequin_")]
arm.data.pose_position = 'REST'
arm.animation_data_clear()
bpy.context.view_layer.update()
R = {}
bones = {b.name: arm.matrix_world @ b.head_local for b in arm.data.bones}
BONES = [b.name for b in arm.data.bones]
me = body.data
co = np.array([v.co[:] for v in me.vertices])

# ---------- fit the mesh to the rig (the armature is never touched) ----------
min_z = float(co[:, 2].min())
arm_z = float(co[np.abs(co[:, 0]) > 0.40][:, 2].mean())
s = bones["hand.l"].z / (arm_z - min_z)
torso = co[(np.abs(co[:, 0]) < 0.15) & (co[:, 2] > -0.25) & (co[:, 2] < 0.0)]
y_off = float((torso[:, 1].min() + torso[:, 1].max()) / 2)
new = co.copy()
new[:, 0] *= s
new[:, 1] = (new[:, 1] - y_off) * s
new[:, 2] = (new[:, 2] - min_z) * s
mann_tip = max(abs((o.matrix_world @ v.co).x) for o in mann if "Arm" in o.name for v in o.data.vertices)
x0 = 0.42
band = (new[:, 2] > 0.80) & (new[:, 2] < 1.45) & (np.abs(new[:, 0]) > x0)
tip = float(np.abs(new[band][:, 0]).max())
k = (mann_tip - x0) / (tip - x0)
new[band, 0] = np.sign(new[band, 0]) * (x0 + (np.abs(new[band, 0]) - x0) * k)
for i, v in enumerate(me.vertices):
    v.co = Vector(new[i])
me.update()
R["fit"] = {
    "scale": round(s, 4), "y_off": round(y_off, 4), "arm_squash": round(k, 4),
    "height": round(float(new[:, 2].max()), 4), "arm_tip": round(float(np.abs(new[:, 0]).max()), 4),
    "mannequin_tip": round(mann_tip, 4),
    "boot_x": [round(float(new[(new[:, 2] < 0.2) & (new[:, 0] < 0)][:, 0].mean()), 3),
               round(float(new[(new[:, 2] < 0.2) & (new[:, 0] > 0)][:, 0].mean()), 3)],
    "upperleg_x": round(bones["upperleg.l"].x, 3),
}

# ---------- connected parts ----------
bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
isl_of = np.full(len(bm.verts), -1)
isl = []
for v in bm.verts:
    if isl_of[v.index] != -1:
        continue
    kk = len(isl)
    st = [v]
    isl_of[v.index] = kk
    members = []
    while st:
        u = st.pop()
        members.append(u.index)
        for e in u.link_edges:
            w = e.other_vert(u)
            if isl_of[w.index] == -1:
                isl_of[w.index] = kk
                st.append(w)
    isl.append(members)
edges = np.array([(e.verts[0].index, e.verts[1].index) for e in bm.edges])
bm.free()
sizes = [len(m) for m in isl]
order = np.argsort(sizes)[::-1]
main_i = int(order[0])
hat_i = int(order[1])

# ---------- weights: nearest-surface transfer from the mannequin body parts ----------
sv, sw, stri = [], [], []
for o in mann:
    if o.name.endswith("Head"):
        continue
    names = {g.index: g.name for g in o.vertex_groups}
    o.data.calc_loop_triangles()
    base = len(sv)
    sv += [o.matrix_world @ v.co for v in o.data.vertices]
    for v in o.data.vertices:
        sw.append({names[g.group]: g.weight for g in v.groups if g.weight > 1e-5})
    stri += [tuple(i + base for i in t.vertices) for t in o.data.loop_triangles]
bvh = BVHTree.FromPolygons(sv, stri)
bi = {n: i for i, n in enumerate(BONES)}
W = np.zeros((len(me.vertices), len(BONES)), dtype=np.float64)
e1, e2, e3 = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
for vi, v in enumerate(me.vertices):
    loc, nor, ti, dist = bvh.find_nearest(v.co)
    a, b, c = stri[ti]
    bc = barycentric_transform(loc, sv[a], sv[b], sv[c], e1, e2, e3)
    for wgt, src in zip(bc, (a, b, c)):
        for name, gw in sw[src].items():
            W[vi, bi[name]] += max(0.0, wgt) * gw


def normalize(M):
    t = M.sum(1, keepdims=True)
    t[t == 0] = 1
    return M / t


W = normalize(W)

main_mask = isl_of == main_i
for _ in range(3):
    acc = np.zeros_like(W)
    cnt = np.zeros((len(W), 1))
    np.add.at(acc, edges[:, 0], W[edges[:, 1]])
    np.add.at(acc, edges[:, 1], W[edges[:, 0]])
    np.add.at(cnt, edges[:, 0], 1)
    np.add.at(cnt, edges[:, 1], 1)
    cnt[cnt == 0] = 1
    Ws = 0.5 * W + 0.5 * (acc / cnt)
    W[main_mask] = Ws[main_mask]


def smoothstep(a0, a1, x):
    t = np.clip((x - a0) / (a1 - a0), 0, 1)
    return t * t * (3 - 2 * t)


hz = bones["head"].z
H = bi["head"]
z = new[:, 2]
ax = np.abs(new[:, 0])
h = np.where(z > hz + 0.08, np.where(ax < 0.75, 1.0, 0.0),
             np.where(ax < 0.30, smoothstep(hz - 0.07, hz + 0.03, z), 0.0))
h = np.where(main_mask, h, 0.0)
W[main_mask] *= (1 - h[main_mask])[:, None]
W[main_mask, H] += h[main_mask]

rigid = {}
for ii, members in enumerate(isl):
    if ii == main_i:
        continue
    m = np.array(members)
    cz = float(new[m, 2].mean())
    if ii == hat_i or cz > hz + 0.06:
        row = np.zeros(len(BONES))
        row[H] = 1.0
    else:
        row = normalize(W[m].mean(0, keepdims=True))[0]
    W[m] = row
    rigid[str(ii)] = [len(members), round(cz, 3), BONES[int(row.argmax())]]

idx = np.argsort(W, axis=1)[:, :-4]
np.put_along_axis(W, idx, 0.0, axis=1)
W[W < 0.01] = 0.0
W = normalize(W)
body.vertex_groups.clear()
vgs = {n: body.vertex_groups.new(name=n) for n in BONES}
for vi in range(len(W)):
    for j in np.nonzero(W[vi])[0]:
        vgs[BONES[j]].add([vi], float(W[vi, j]), 'REPLACE')
R["islands"] = {"count": len(isl), "main_verts": sizes[main_i], "hat_verts": sizes[hat_i], "rigid": rigid}
dom = W.argmax(1)
R["dominant_bone_vertex_counts"] = {BONES[j]: int((dom == j).sum()) for j in range(len(BONES)) if (dom == j).sum()}

# ---------- palette-snap the Meshy texture ----------
PAL = [("tunic", "A8262D"), ("tunic_shadow", "761C28"), ("gold", "D8AF52"), ("gold_dark", "7A5A18"),
       ("trousers", "496071"), ("trousers_shadow", "344552"), ("leather", "5A3419"), ("leather_light", "7A4E28"),
       ("hat", "2F2C38"), ("hat_trim", "77766F"), ("beard", "A39E90"), ("beard_dark", "6F6B62"),
       ("skin", "F0B28C"), ("skin_shadow", "C98A6B"), ("ink", "241E14"), ("steel", "8C94A3")]


def lab(rgb):
    c = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ M.T / np.array([0.9505, 1.0, 1.089])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


pal_rgb = np.array([[int(hx[i:i + 2], 16) / 255 for i in (0, 2, 4)] for _, hx in PAL])
pal_lab = lab(pal_rgb)
img = None
mat = None
for m in me.materials:
    for n in m.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image:
            img = n.image
            mat = m
w_, h_ = img.size
px = np.empty(w_ * h_ * 4, dtype=np.float32)
img.pixels.foreach_get(px)
px = px.reshape(-1, 4)
labels = np.empty(len(px), dtype=np.int32)
CH = 400000
for s0 in range(0, len(px), CH):
    L = lab(px[s0:s0 + CH, :3].astype(np.float64))
    labels[s0:s0 + CH] = ((L[:, None, :] - pal_lab[None, :, :]) ** 2).sum(-1).argmin(1)
px[:, :3] = pal_rgb[labels]
img.pixels.foreach_set(px.ravel())
img.name = "BanditOfficer_Palette"
img.filepath_raw = BW + "/bandit_palette.png"
img.file_format = 'PNG'
img.save()
img.pack()
counts = np.bincount(labels, minlength=len(PAL))
R["palette_pixel_share"] = {PAL[i][0]: round(float(counts[i]) / len(labels), 4) for i in range(len(PAL))}
for n in mat.node_tree.nodes:
    if n.type == 'BSDF_PRINCIPLED':
        n.inputs["Roughness"].default_value = 1.0
        n.inputs["Metallic"].default_value = 0.0
mat.name = "BanditOfficer"

# ---------- bind and export ----------
body.name = "BanditOfficer"
me.name = "BanditOfficer"
body.parent = arm
body.matrix_parent_inverse.identity()
for mod in list(body.modifiers):
    body.modifiers.remove(mod)
am = body.modifiers.new("Armature", 'ARMATURE')
am.object = arm
arm.data.pose_position = 'POSE'
bpy.ops.wm.save_as_mainfile(filepath=BW + "/work_rigged.blend")
for o in bpy.context.view_layer.objects:
    o.select_set(False)
arm.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB', use_selection=True,
                          export_animations=False, export_apply=False, export_skins=True, export_yup=True)
R["exported"] = OUT_GLB
json.dump(R, open(BW + "/05_rig.json", "w"), indent=1)
