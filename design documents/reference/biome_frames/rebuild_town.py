# Rebuilds raw_town_v2 as one plank per side between the corner stones,
# dropping Meshy's extra stone blocks so the nine-patch middle tiles cleanly.
# Planks are cut from the nail-free stretch; one nail goes back at each plank's
# centre, so a tile-fit panel gets evenly spaced single nails.
import sys
from PIL import Image, ImageDraw
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGBA")
px = []
for r, g, b, a in im.getdata():
    d = g - max(r, b)
    if d > 90: px.append((0, 0, 0, 0))
    elif d > 25: px.append((r, max(r, b), b, int(255 * (1 - (d - 25) / 65))))
    else: px.append((r, max(r, b) if d > 0 else g, b, 255))
im.putdata(px)

new = Image.new("RGBA", im.size, (0, 0, 0, 0))
LO, HI = 200, 824
MID = (LO + HI) // 2
new.alpha_composite(im.crop((360, 30, 665, 215)).resize((HI - LO, 185), Image.LANCZOS), (LO, 30))
new.alpha_composite(im.crop((360, 810, 665, 995)).resize((HI - LO, 185), Image.LANCZOS), (LO, 810))
new.alpha_composite(im.crop((30, 360, 215, 665)).resize((185, HI - LO), Image.LANCZOS), (30, LO))
new.alpha_composite(im.crop((810, 360, 995, 665)).resize((185, HI - LO), Image.LANCZOS), (810, LO))

R = 17
mask = Image.new("L", (2 * R, 2 * R), 0)
ImageDraw.Draw(mask).ellipse((0, 0, 2 * R - 1, 2 * R - 1), fill=255)
def nail(sx, sy, dx, dy):
    n = im.crop((sx - R, sy - R, sx + R, sy + R))
    n.putalpha(Image.composite(n.getchannel("A"), Image.new("L", n.size, 0), mask))
    new.alpha_composite(n, (dx - R, dy - R))
nail(330, 118, MID, 118)
nail(322, 905, MID, 905)
nail(118, 330, 118, MID)
nail(905, 330, 905, MID)

K = 0.95  # shrink corners toward the outer corner so they sit inside the 75px patch
for (x0, y0, ax, ay) in [(20, 20, 0, 0), (805, 20, 1, 0), (20, 805, 0, 1), (805, 805, 1, 1)]:
    c = im.crop((x0, y0, x0 + 199, y0 + 199))
    s = round(199 * K)
    c = c.resize((s, s), Image.LANCZOS)
    new.alpha_composite(c, (x0 + (199 - s) * ax, y0 + (199 - s) * ay))

flat = Image.new("RGBA", im.size, (0, 255, 0, 255))
flat.alpha_composite(new)
flat.convert("RGB").save(out)
print("rebuilt")
