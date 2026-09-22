"""Finishes the Blender portrait renders for the slot's special-charge coin:
mirrors each so the hero faces right (toward the enemies, as on the field) and
masks it to a circle so it sits inside the coin's rim.

    blender -b -P tools/slot_art/render_portraits.py -- <project_root> <render_dir>
    python tools/slot_art/finish_portraits.py <render_dir>

Writes assets/ui/slot/portrait_<hero>.png.
"""
import sys
from PIL import Image, ImageDraw, ImageOps

render_dir = sys.argv[1]
for hero in ("warrior", "ranger", "mage"):
    im = ImageOps.mirror(Image.open(f"{render_dir}/portrait_{hero}.png").convert("RGBA"))
    n = im.size[0]
    mask = Image.new("L", (n * 4, n * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, n * 4 - 1, n * 4 - 1), fill=255)
    mask = mask.resize((n, n), Image.LANCZOS)
    im.putalpha(Image.composite(im.getchannel("A"), Image.new("L", (n, n), 0), mask))
    im.save(f"assets/ui/slot/portrait_{hero}.png")
    print("wrote", hero)
