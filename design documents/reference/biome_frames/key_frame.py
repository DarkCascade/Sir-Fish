import sys
from PIL import Image
raw, out, preview = sys.argv[1], sys.argv[2], sys.argv[3]
M = 75  # patch margin used by item_card_v2 / slot_machine

im = Image.open(raw).convert("RGBA")
px = []
for r, g, b, a in im.getdata():
    d = g - max(r, b)
    if d > 90:
        px.append((0, 0, 0, 0)); continue
    if d > 25:
        alpha = int(255 * (1 - (d - 25) / 65))
        px.append((r, max(r, b), b, alpha)); continue
    if d > 0:
        g = max(r, b)  # despill faint green fringe
    px.append((r, g, b, 255))
im.putdata(px)
im = im.crop(im.getbbox()).resize((384, 384), Image.LANCZOS)
im.save(out)

def tile_fit(src, W, H, m=M):
    S = src.size[0]; s = S - 2 * m
    dst = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    def run(seg, length, horizontal):
        n = max(1, round(length / s))
        piece = length / n
        for i in range(n):
            a, b = round(i * piece), round((i + 1) * piece)
            size = (b - a, seg.size[1]) if horizontal else (seg.size[0], b - a)
            yield a, seg.resize(size, Image.LANCZOS)
    for (sx, sy, dx, dy) in [(0, 0, 0, 0), (S - m, 0, W - m, 0), (0, S - m, 0, H - m), (S - m, S - m, W - m, H - m)]:
        dst.alpha_composite(src.crop((sx, sy, sx + m, sy + m)), (dx, dy))
    for sy, dy in [(0, 0), (S - m, H - m)]:
        for a, p in run(src.crop((m, sy, S - m, sy + m)), W - 2 * m, True):
            dst.alpha_composite(p, (m + a, dy))
    for sx, dx in [(0, 0), (S - m, W - m)]:
        for a, p in run(src.crop((sx, m, sx + m, S - m)), H - 2 * m, False):
            dst.alpha_composite(p, (dx, m + a))
    return dst

GROUND, PANEL = (19, 13, 25, 255), (42, 30, 44, 255)
glyph = Image.open("assets/ui/slot/glyph_dmg_flat.png").convert("RGBA").resize((230, 230), Image.LANCZOS)
orig = Image.open("assets/ui/reliquary/card_frame.png").convert("RGBA")
canvas = Image.new("RGBA", (1000, 880), GROUND)

def card(frame, x, y):
    panel = Image.new("RGBA", (384 - 76, 384 - 76), PANEL)
    canvas.alpha_composite(panel, (x + 38, y + 38))
    canvas.alpha_composite(glyph, (x + 77, y + 77))
    canvas.alpha_composite(frame, (x, y))

card(orig, 72, 40)
card(im, 544, 40)
wide = tile_fit(im, 856, 360)
canvas.alpha_composite(Image.new("RGBA", (856 - 76, 360 - 76), PANEL), (72 + 38, 480 + 38))
canvas.alpha_composite(wide, (72, 480))
canvas.convert("RGB").save(preview)
print("ok", im.size)
