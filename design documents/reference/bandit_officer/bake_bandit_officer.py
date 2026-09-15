import bpy, os, sys, json
import numpy as np
from mathutils import Vector

BW = os.environ['BW']
sys.path.insert(0, BW)
import render_lib

OUT_GLB = "C:/Projects/Godot/Sir Fish/assets/meshes/bandit_officer.glb"
RAW_TEX = "C:/Projects/Godot/Sir Fish/design documents/reference/bandit_officer/meshy_raw_base_color.png"
KNIGHT = "C:/Projects/Godot/Sir Fish/assets/meshes/knight.glb"
ANIM = "C:/Projects/Third Party Assets/KayKit/KayKit_Character_Animations_1.1_FREE/Animations/gltf/Rig_Medium/"
WANTED = ["Idle_A", "Running_A", "Melee_1H_Attack_Chop", "Hit_A", "Death_A"]
TEX_SIZE = 1024
R = {}

bpy.ops.wm.open_mainfile(filepath=BW + "/work_rigged.blend")
arm = bpy.data.objects["Rig_Medium"]
body = bpy.data.objects["BanditOfficer"]
scn = bpy.context.scene

# ---------- 1. texture: resample the raw Meshy texture to 1024, then palette-snap ----------
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
img = bpy.data.images.load(RAW_TEX)
img.scale(TEX_SIZE, TEX_SIZE)
px = np.empty(TEX_SIZE * TEX_SIZE * 4, dtype=np.float32)
img.pixels.foreach_get(px)
px = px.reshape(-1, 4)
L = lab(px[:, :3].astype(np.float64))
labels = ((L[:, None, :] - pal_lab[None, :, :]) ** 2).sum(-1).argmin(1)
px[:, :3] = pal_rgb[labels]
px[:, 3] = 1.0
img.pixels.foreach_set(px.ravel())
img.name = "bandit_officer_palette"
img.filepath_raw = BW + "/bandit_palette_1024.png"
img.file_format = 'PNG'
img.save()
img.pack()
mat = body.data.materials[0]
old_img = None
for n in mat.node_tree.nodes:
    if n.type == 'TEX_IMAGE':
        old_img = n.image
        n.image = img
if old_img is not None and old_img.users == 0:
    bpy.data.images.remove(old_img)
R["texture"] = [img.name, list(img.size)]

# ---------- 2. sword: the shipped knight's 1H_Sword, at the knight's own attachment ----------
before_obj = set(bpy.data.objects.keys())
before_act = set(bpy.data.actions.keys())
bpy.ops.import_scene.gltf(filepath=KNIGHT)
new_obj = [bpy.data.objects[n] for n in set(bpy.data.objects.keys()) - before_obj]
knight_rig = next(o for o in new_obj if o.type == 'ARMATURE')
knight_rig.data.pose_position = 'REST'
if knight_rig.animation_data:
    knight_rig.animation_data.action = None
bpy.context.view_layer.update()
sword = next(o for o in new_obj if o.name.startswith("1H_Sword") and "Offhand" not in o.name)
sword_world = sword.matrix_world.copy()
sword.parent = None
sword.matrix_world = sword_world
knight_chop = None
for n in set(bpy.data.actions.keys()) - before_act:
    a = bpy.data.actions[n]
    if n == "1H_Melee_Attack_Chop":
        a.name = "KNIGHT_CHOP_REFERENCE"
        knight_chop = a
    else:
        bpy.data.actions.remove(a)
for o in new_obj:
    if o is not sword:
        bpy.data.objects.remove(o, do_unlink=True)
sword.name = "Sabre"
arm.data.pose_position = 'REST'
bpy.context.view_layer.update()
sword.parent = arm
sword.parent_type = 'BONE'
sword.parent_bone = "handslot.r"
bpy.context.view_layer.update()
sword.matrix_world = sword_world
bpy.context.view_layer.update()
hs = arm.matrix_world @ arm.data.bones["handslot.r"].head_local
R["sword"] = {"origin_to_handslot_r": round((sword.matrix_world.translation - hs).length, 4),
              "world_matches_knight": round(max(abs(a - b) for ra, rb in zip(sword.matrix_world, sword_world) for a, b in zip(ra, rb)), 6),
              "materials": [m.name for m in sword.data.materials]}

# ---------- 3. clips: import the pack actions, keep only the five this enemy plays ----------
for f in ["Rig_Medium_General.glb", "Rig_Medium_CombatMelee.glb", "Rig_Medium_MovementBasic.glb"]:
    b_obj = set(bpy.data.objects.keys())
    b_act = set(bpy.data.actions.keys())
    bpy.ops.import_scene.gltf(filepath=ANIM + f)
    for n in set(bpy.data.objects.keys()) - b_obj:
        bpy.data.objects.remove(bpy.data.objects[n], do_unlink=True)
    for n in set(bpy.data.actions.keys()) - b_act:
        if n not in WANTED:
            bpy.data.actions.remove(bpy.data.actions[n])
for n in list(bpy.data.actions.keys()):
    if n not in WANTED and n != "KNIGHT_CHOP_REFERENCE":
        bpy.data.actions.remove(bpy.data.actions[n])
missing = [n for n in WANTED if n not in bpy.data.actions]
R["missing_actions"] = missing
fps = scn.render.fps / scn.render.fps_base
R["fps"] = fps


def assign(action):
    ad = arm.animation_data_create()
    ad.action = action
    if hasattr(ad, "action_slot") and len(action.slots):
        ad.action_slot = action.slots[0]


def hand_track(action):
    assign(action)
    arm.data.pose_position = 'POSE'
    f0, f1 = [int(round(x)) for x in action.frame_range]
    zs = []
    for fr in range(f0, f1 + 1):
        scn.frame_set(fr)
        bpy.context.view_layer.update()
        zs.append((arm.matrix_world @ arm.pose.bones["handslot.r"].matrix).translation.z)
    zs = np.array(zs)
    peak = int(zs.argmax())
    low = peak + int(zs[peak:].argmin())
    vel = np.diff(zs)
    fastest = peak + int(vel[peak:].argmin()) + 1 if peak < len(vel) else peak
    n = f1 - f0
    return {"frames": [f0, f1], "seconds": round(n / fps, 4), "peak_frac": round(peak / n, 4),
            "lowest_after_peak_frac": round(low / n, 4), "fastest_down_frac": round(fastest / n, 4),
            "z_peak": round(float(zs.max()), 3), "z_low": round(float(zs[low]), 3)}


R["impact_new_chop"] = hand_track(bpy.data.actions["Melee_1H_Attack_Chop"])
if knight_chop is not None:
    R["impact_knight_chop"] = hand_track(knight_chop)
    R["knight_authored_impact_frac"] = round(0.3 / 0.7, 4)

# ---------- 4. verification renders: rest with sabre, and the chop at its strike ----------
for o in bpy.data.objects:
    if o.name.startswith("Mannequin_") or o.name.startswith("Icosphere"):
        o.hide_render = True
tiles = []
chop = bpy.data.actions["Melee_1H_Attack_Chop"]
f0, f1 = chop.frame_range
for label, action, frac, az in [("rest", None, 0, -30), ("windup", chop, R["impact_new_chop"]["peak_frac"], -30),
                                ("strike", chop, R["impact_new_chop"]["fastest_down_frac"], -30)]:
    if action is None:
        arm.data.pose_position = 'REST'
        arm.animation_data.action = None
    else:
        arm.data.pose_position = 'POSE'
        assign(action)
        scn.frame_set(int(round(f0 + (f1 - f0) * frac)))
    p = BW + "/enemy_%s.png" % label
    render_lib.render_front(p, res=512, ortho_scale=3.2, center_z=1.1, azimuth_deg=az)
    im = bpy.data.images.load(p)
    arr = np.empty(512 * 512 * 4, dtype=np.float32)
    im.pixels.foreach_get(arr)
    tiles.append(arr.reshape(512, 512, 4))
sheet = bpy.data.images.new("enemy_sheet", 1536, 512)
sheet.pixels.foreach_set(np.concatenate(tiles, 1).ravel())
sheet.filepath_raw = BW + "/enemy_sheet.png"
sheet.file_format = 'PNG'
sheet.save()

# ---------- 5. bake the five clips as NLA tracks and export ----------
if knight_chop is not None:
    bpy.data.actions.remove(knight_chop)
ad = arm.animation_data_create()
ad.action = None
for t in list(ad.nla_tracks):
    ad.nla_tracks.remove(t)
for name in WANTED:
    a = bpy.data.actions[name]
    track = ad.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, int(a.frame_range[0]), a)
    if hasattr(strip, "action_slot") and len(a.slots):
        strip.action_slot = a.slots[0]
    a.use_fake_user = True
arm.data.pose_position = 'POSE'
scn.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=BW + "/work_enemy.blend")
for o in bpy.context.view_layer.objects:
    o.select_set(False)
for o in (arm, body, sword):
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='NLA_TRACKS',
                          export_apply=False, export_skins=True, export_yup=True)
R["exported"] = OUT_GLB
json.dump(R, open(BW + "/07_bake.json", "w"), indent=1)
