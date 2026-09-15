# Crops the top-left ornament (stone block + crystal) out of the rebuilt
# Hearthwood frame, keyed to true alpha transparency (no baked background) so
# it overlays cleanly regardless of what texture/gradient the modal panel
# actually uses underneath - unlike frame_corner.png's own flat-matte
# convention, which only works because that art's background happens to match
# a flat panel fill exactly.
import sys
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGBA")
px = []
for r, g, b, a in im.getdata():
    d = g - max(r, b)
    if d > 90: px.append((0, 0, 0, 0))
    elif d > 25: px.append((r, max(r, b), b, int(255 * (1 - (d - 25) / 65))))
    else: px.append((r, max(r, b) if d > 0 else g, b, 255))
im.putdata(px)

corner = im.crop((0, 0, 300, 300))
bbox = corner.getbbox()
corner = corner.crop(bbox)
SCALE = 0.62
w, h = corner.size
corner = corner.resize((round(w * SCALE), round(h * SCALE)), Image.LANCZOS)

canvas = Image.new("RGBA", (240, 240), (0, 0, 0, 0))
canvas.alpha_composite(corner, (0, 0))
canvas.save(out)
print("corner", corner.size)
