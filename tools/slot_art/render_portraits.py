"""Side-on head-and-shoulders portraits of the three heroes, for the slot's
special-charge coin. Run headless:

    blender -b -P tools/slot_art/render_portraits.py -- <project_root> <out_dir>

then tools/slot_art/finish_portraits.py mirrors and circle-masks the renders.

Renders each hero glb in Workbench (flat texture colour, ink outline) from the
side with an orthographic camera, transparent background, cropped to the head
and shoulders. Hand props (weapons, shields, books) are hidden so the profile
is the character alone - the same props CombatantRig hides or swaps per gear.
"""
import sys
import bpy
import mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
ROOT, OUT = argv[0], argv[1]
HEROES = {"warrior": "knight", "ranger": "rogue", "mage": "mage"}
PROP_WORDS = ("sword", "shield", "crossbow", "staff", "wand", "book", "knife",
              "throwable", "offhand", "dagger", "bow", "axe")
RES = 512
CROP_TOP = 0.5       # fraction of the character's height kept, from the top


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def is_prop(obj):
    name = obj.name.lower()
    return any(w in name for w in PROP_WORDS)


def render(hero, glb):
    reset()
    bpy.ops.import_scene.gltf(filepath=glb)
    meshes = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        if is_prop(obj) or (obj.parent is not None and is_prop(obj.parent)):
            obj.hide_render = True
            continue
        meshes.append(obj)
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    lo = mathutils.Vector((1e9, 1e9, 1e9))
    hi = mathutils.Vector((-1e9, -1e9, -1e9))
    for obj in meshes:
        ev = obj.evaluated_get(deps)
        mesh = ev.to_mesh()
        for v in mesh.vertices:
            w = ev.matrix_world @ v.co
            lo = mathutils.Vector(map(min, lo, w))
            hi = mathutils.Vector(map(max, hi, w))
        ev.to_mesh_clear()
    height = hi.z - lo.z
    top = hi.z
    bottom = top - height * CROP_TOP
    mid_z = (top + bottom) * 0.5
    span = (top - bottom) * 1.22

    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = span
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    # Looking along -X from +X: the character's side. glTF +Z forward imports
    # as Blender -Y, so the face points to the image's right from here.
    centre_y = (lo.y + hi.y) * 0.5
    cam.location = (hi.x + 10.0, centre_y, mid_z)
    cam.rotation_euler = (1.5707963, 0.0, 1.5707963)
    scene.camera = cam

    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_object_outline = True
    scene.display.shading.object_outline_color = (0.14, 0.12, 0.08)
    scene.render.film_transparent = True
    scene.render.resolution_x = RES
    scene.render.resolution_y = RES
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.render.filepath = f"{OUT}/portrait_{hero}.png"
    bpy.ops.render.render(write_still=True)
    print("rendered", hero)


for hero, model in HEROES.items():
    render(hero, f"{ROOT}/assets/meshes/{model}.glb")
