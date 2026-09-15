"""Shared helpers for the character pipeline's headless Blender stages.

Every stage is launched by pipeline.py as
`blender --background --factory-startup --python <stage>.py -- <job.json>`.
"""

import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

STATE_ORDER = ["idle", "run", "attack", "special", "hurt", "die"]


def load_job() -> dict:
    argv = sys.argv[sys.argv.index("--") + 1:]
    with open(argv[0], encoding="utf-8") as f:
        return json.load(f)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path: str):
    """Imports a glb. Returns the NAMES of the objects and actions it added.

    Names rather than datablocks, because callers delete most of what they import and
    touching a removed datablock raises ReferenceError.
    """
    objects_before = set(bpy.data.objects.keys())
    actions_before = set(bpy.data.actions.keys())
    bpy.ops.import_scene.gltf(filepath=path)
    objects = [n for n in bpy.data.objects.keys() if n not in objects_before]
    actions = [n for n in bpy.data.actions.keys() if n not in actions_before]
    return objects, actions


def remove_objects(names) -> None:
    for name in names:
        obj = bpy.data.objects.get(name)
        if obj is not None:
            bpy.data.objects.remove(obj, do_unlink=True)


def remove_actions(names) -> None:
    for name in names:
        action = bpy.data.actions.get(name)
        if action is not None:
            bpy.data.actions.remove(action)


def assign_action(armature, action) -> None:
    """Blender 4.4+ slotted actions: an action only drives an object through a slot."""
    data = armature.animation_data_create()
    data.action = action
    if action is not None and hasattr(data, "action_slot") and len(action.slots):
        data.action_slot = action.slots[0]


def bone_head_world(armature, bone_name: str) -> Vector:
    return armature.matrix_world @ armature.data.bones[bone_name].head_local


def pose_bone_world(armature, bone_name: str) -> Vector:
    return (armature.matrix_world @ armature.pose.bones[bone_name].matrix).translation


# --- palette ---------------------------------------------------------------------

def hex_to_rgb(hex_code: str) -> list:
    h = hex_code.lstrip("#")
    return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]


def srgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    linear = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    matrix = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = linear @ matrix.T / np.array([0.9505, 1.0, 1.089])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def palette_snap_image(image, palette, chunk: int = 400000) -> dict:
    """Snaps every pixel to its nearest palette colour in Lab space, in place.

    Returns {name: {"share": fraction of pixels, "mean_delta_e": how far those pixels
    were from the colour}} - a large mean ΔE means the palette entry is a poor fit.
    """
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(-1, 4)
    pal_rgb = np.array([hex_to_rgb(hex_code) for _, hex_code in palette])
    pal_lab = srgb_to_lab(pal_rgb)
    labels = np.empty(len(pixels), dtype=np.int32)
    distance = np.empty(len(pixels), dtype=np.float64)
    for start in range(0, len(pixels), chunk):
        lab = srgb_to_lab(pixels[start:start + chunk, :3].astype(np.float64))
        d2 = ((lab[:, None, :] - pal_lab[None, :, :]) ** 2).sum(-1)
        labels[start:start + chunk] = d2.argmin(1)
        distance[start:start + chunk] = np.sqrt(d2.min(1))
    pixels[:, :3] = pal_rgb[labels]
    pixels[:, 3] = 1.0
    image.pixels.foreach_set(pixels.ravel())
    counts = np.bincount(labels, minlength=len(palette))
    sums = np.bincount(labels, weights=distance, minlength=len(palette))
    return {palette[i][0]: {"share": round(float(counts[i]) / len(labels), 4),
                            "mean_delta_e": round(float(sums[i] / counts[i]), 1) if counts[i] else None}
            for i in range(len(palette))}


# --- rendering -------------------------------------------------------------------

def render_png(path: str, res: int = 768, ortho_scale: float = 2.6, center_z: float = 1.1,
               azimuth_deg: float = 0.0, single_color=None, distance: float = 10.0,
               center_xy=(0.0, 0.0)) -> np.ndarray:
    """Workbench render on white. Azimuth 0 looks from -Y, the side KayKit characters face.

    The camera aims at (center_xy, center_z) - off the origin for poses that travel, such
    as a death that ends lying on the ground. Returns a bottom-up HxWx4 float array.
    """
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    shading = scene.display.shading
    shading.light = 'STUDIO'
    if single_color is not None:
        shading.color_type = 'SINGLE'
        shading.single_color = single_color
    else:
        shading.color_type = 'TEXTURE'
    shading.show_object_outline = True
    shading.object_outline_color = (0.14, 0.12, 0.08)
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = 'RGBA'
    cam_data = bpy.data.cameras.get("PipelineCam") or bpy.data.cameras.new("PipelineCam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = ortho_scale
    cam = bpy.data.objects.get("PipelineCam") or bpy.data.objects.new("PipelineCam", cam_data)
    if cam.name not in scene.collection.objects:
        scene.collection.objects.link(cam)
    angle = math.radians(azimuth_deg)
    cx, cy = center_xy
    cam.location = (cx + distance * math.sin(angle), cy - distance * math.cos(angle), center_z)
    cam.rotation_euler = (Vector((cx, cy, center_z)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    raw_path = path + ".rgba.png"
    scene.render.filepath = raw_path
    bpy.ops.render.render(write_still=True)
    image = bpy.data.images.load(raw_path)
    pixels = np.empty(res * res * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(res, res, 4)
    alpha = pixels[..., 3:4]
    pixels[..., :3] = pixels[..., :3] * alpha + (1.0 - alpha)
    pixels[..., 3] = 1.0
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = path
    image.file_format = 'PNG'
    image.save()
    bpy.data.images.remove(image)
    os.remove(raw_path)
    return pixels


def save_sheet(path: str, tiles, cols: int) -> None:
    """Tiles are bottom-up HxWx4 arrays in reading order: row by row, top row first."""
    height, width = tiles[0].shape[:2]
    rows = (len(tiles) + cols - 1) // cols
    blank = np.ones((height, width, 4), dtype=np.float32)
    grid = []
    for r in range(rows):
        row = list(tiles[r * cols:(r + 1) * cols])
        row += [blank] * (cols - len(row))
        grid.append(np.concatenate(row, axis=1))
    sheet = np.concatenate(grid[::-1], axis=0)  # Blender stores the bottom row first
    image = bpy.data.images.new("pipeline_sheet", width * cols, height * rows)
    image.pixels.foreach_set(sheet.ravel())
    image.filepath_raw = path
    image.file_format = 'PNG'
    image.save()
    bpy.data.images.remove(image)
