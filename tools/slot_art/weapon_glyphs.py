"""[slot vocabulary] Placeholder board glyphs for each weapon type, keyed out of the item-card
weapon icons (white silhouette on teal) and restyled to the board's look:
gold fill with a top-light gradient, a bevel highlight, and a thick ink outline.
Output: assets/ui/slot/glyph_weapon_<type>.png, 512x512 RGBA."""
from PIL import Image, ImageFilter, ImageChops, ImageDraw
import numpy as np

SRC = 'assets/icons/weapon_%s.png'
DST = 'assets/ui/slot/glyph_weapon_%s.png'
SIZE = 512
FILL = 0.78          # silhouette's longest side as a fraction of the canvas
THICKEN = 9          # px (at 512) the silhouette is grown by - thin bows/staves
OUTLINE = 20         # px ink outline
INK = (36, 30, 20)
GOLD_TOP = np.array([246, 214, 120], dtype=float)
GOLD_BOT = np.array([196, 142, 48], dtype=float)
HILITE = np.array([255, 240, 190], dtype=float)


def mask_of(path):
    im = np.asarray(Image.open(path).convert('RGB')).astype(float)
    lum = im.mean(axis=2)
    sat = im.max(axis=2) - im.min(axis=2)
    m = ((lum > 150) & (sat < 60)).astype(np.uint8) * 255
    return Image.fromarray(m, 'L')


def fit(mask):
    box = mask.getbbox()
    mask = mask.crop(box)
    w, h = mask.size
    scale = (SIZE * FILL) / max(w, h)
    mask = mask.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
    canvas = Image.new('L', (SIZE, SIZE), 0)
    canvas.paste(mask, ((SIZE - mask.size[0]) // 2, (SIZE - mask.size[1]) // 2))
    return canvas


def grow(mask, px):
    return mask.filter(ImageFilter.MaxFilter(px * 2 + 1)) if px > 0 else mask


def build(kind):
    body = grow(fit(mask_of(SRC % kind)), THICKEN // 2).point(lambda v: 255 if v > 110 else 0)
    body = body.filter(ImageFilter.GaussianBlur(1.2)).point(lambda v: 255 if v > 127 else 0)
    outline = grow(body, OUTLINE // 2).filter(ImageFilter.GaussianBlur(1.5))

    ys = np.linspace(0.0, 1.0, SIZE)[:, None, None]
    gold = GOLD_TOP * (1 - ys) + GOLD_BOT * ys
    gold = np.repeat(gold, SIZE, axis=1)
    # Bevel: the body's top-left edge catches light, bottom-right falls off.
    b = np.asarray(body).astype(float) / 255.0
    shifted = np.roll(np.roll(b, 6, axis=0), 6, axis=1)
    edge_light = np.clip(b - shifted, 0, 1)[..., None]
    shade = np.clip(b - np.roll(np.roll(b, -6, axis=0), -6, axis=1), 0, 1)[..., None]
    rgb = gold * (1 - edge_light) + HILITE * edge_light
    rgb = rgb * (1 - 0.35 * shade)

    out = np.zeros((SIZE, SIZE, 4), dtype=float)
    o = np.asarray(outline).astype(float)[..., None] / 255.0
    out[..., :3] = np.array(INK, dtype=float)
    out[..., 3:] = o * 255
    out[..., :3] = out[..., :3] * (1 - b[..., None]) + rgb * b[..., None]
    out[..., 3:] = np.maximum(out[..., 3:], b[..., None] * 255)
    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA').save(DST % kind)


for kind in ('axe', 'bow', 'dagger', 'staff'):
    build(kind)
    print('wrote', DST % kind)
