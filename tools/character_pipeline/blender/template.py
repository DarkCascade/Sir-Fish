"""Character pipeline - template stage (headless Blender).

Renders the KayKit Rig_Medium mannequin in its rest T-pose, flat grey on white, from the
front, side and back. Image 1 of the concept restyle pass (meshy_image_to_image) is the
front render: it is what gives a Meshy concept KayKit proportions and level arms.
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C  # noqa: E402

job = C.load_job()
C.reset_scene()
objects, actions = C.import_glb(job["rig_source"])
C.remove_actions(actions)
C.remove_objects([n for n in objects if n.startswith("Icosphere")])
armature = bpy.data.objects["Rig_Medium"]
armature.animation_data_clear()
armature.data.pose_position = 'REST'
bpy.context.view_layer.update()

for view, azimuth in (("front", 0), ("side", 90), ("back", 180)):
    C.render_png(os.path.join(job["out_dir"], f"mannequin_tpose_{view}.png"), res=1024,
                 ortho_scale=2.35, center_z=1.1, azimuth_deg=azimuth, single_color=(0.82, 0.82, 0.80))
