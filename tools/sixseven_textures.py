"""Sector 3 textures (the 67 maze: monochrome, "6 7" written over everything).

  textures/67_face.png      the entity's head, flat, cut out, pure black and white (alpha)
  textures/67_hand_l.png    its two white hands, cut out (alpha)
  textures/67_hand_r.png
  textures/wall_67.png      tileable: off-white paper covered in hand-written 6s and 7s
  textures/floor_67.png     tileable: grey concrete, 6 7 scrawled in black and in chalk
  textures/ceiling_67.png   tileable: pale ceiling tiles, faint 6 7 everywhere
  textures/gate_67.png      tileable: the gates, black from the other side, written over in white
  textures/67_glyphs.png    a 6 and a 7 side by side (the digits drifting in the air)

The handwriting is the walls' font (fonts/NothingYouCouldDo.ttf, OFL).
usage: python3 tools/sixseven_textures.py REFERENCE_IMAGE.jpg
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "textures")
FONT = os.path.join(ROOT, "fonts", "NothingYouCouldDo.ttf")
rng = np.random.default_rng(67)

FACE_BOX = (195, 55, 445, 400)      # 250 x 345 px of the 640 x 480 reference: head and neck
HANDS = {"l": (0, 195, 235, 345), "r": (405, 195, 640, 345)}


def face(src):
    """The head, flat, cut out along its silhouette, pushed to pure black and white."""
    S = 4
    im = src.crop(FACE_BOX).convert("L")
    a = np.asarray(im).astype(np.float32) / 255.0
    h, w = a.shape
    yy, xx = np.mgrid[0:h, 0:w]
    sx, sy = xx + FACE_BOX[0], yy + FACE_BOX[1]
    strokes = a > 0.3
    # the hands' fingers reach into the crop at the sides: separate blobs, not the head
    lab, n = ndimage.label(strokes, structure=np.ones((3, 3)))
    keep = np.zeros_like(strokes)
    for i, sl in enumerate(ndimage.find_objects(lab)):
        x0, x1 = sl[1].start + FACE_BOX[0], sl[1].stop + FACE_BOX[0]
        part = lab[sl] == i + 1
        if part.sum() < 15 or x1 <= 236 or x0 >= 408 or ((sl[1].start == 0 or sl[1].stop == w) and sl[0].start + FACE_BOX[1] > 160):
            continue
        keep[sl] |= part
    # the silhouette, row by row: from the leftmost to the rightmost stroke near that row
    # (so the open mouth and the dark face stay solid), the outline smoothed
    left = np.full(h, np.nan)
    right = np.full(h, np.nan)
    for y in range(h):
        cols = np.nonzero(keep[max(0, y - 8):y + 9].any(axis=0))[0]
        if cols.size:
            left[y], right[y] = cols.min(), cols.max()
            if y + FACE_BOX[1] > 160:
                # below the hairline the head is no wider than its cheeks (strands, fingers)
                left[y] = max(left[y], 233 - FACE_BOX[0])
                right[y] = min(right[y], 408 - FACE_BOX[0])
    rows = np.nonzero(~np.isnan(left))[0]
    y0, y1 = rows.min(), rows.max()
    left[y0:y1 + 1] = ndimage.gaussian_filter1d(np.interp(np.arange(y0, y1 + 1), rows, left[rows]), 6)
    right[y0:y1 + 1] = ndimage.gaussian_filter1d(np.interp(np.arange(y0, y1 + 1), rows, right[rows]), 6)
    m = np.zeros((h, w), bool)
    for y in range(y0, y1 + 1):
        m[y, int(left[y]):int(np.ceil(right[y])) + 1] = True
    m = ndimage.binary_dilation(m, iterations=1)
    # upscale, then an extremely hard curve: nothing between black and white
    big = np.asarray(im.resize((w * S, h * S), Image.LANCZOS)).astype(np.float32) / 255.0
    big = ndimage.gaussian_filter(big, 1.2)
    lo, hi = 0.36, 0.44
    k = np.clip((big - lo) / (hi - lo), 0, 1)
    k = k * k * (3 - 2 * k)
    alpha = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize((w * S, h * S), Image.BILINEAR)).astype(np.float32) / 255.0
    alpha = ndimage.gaussian_filter(alpha, 2.0)
    rgba = np.dstack([k, k, k, alpha])
    Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "67_face.png"))
    print("67_face.png  %dx%d" % (w * S, h * S))


def hand(src, side):
    im = src.crop(HANDS[side])
    w, h = im.size
    im = im.resize((w * 4, h * 4), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255.0
    lum = a.mean(-1)
    red = a[..., 0] - a[..., 1]
    mask = (lum > 0.55) & (red < 0.25)
    # the head's hair reaches into the crops near the face: not part of the hands
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]] / 4.0
    if side == "l":
        mask &= ~((xx > 182) & (yy < 58))
    else:
        mask &= ~((xx < 58) & (yy < 60))
    mask = ndimage.binary_opening(mask, iterations=1)
    alpha = ndimage.gaussian_filter(mask.astype(np.float32), 1.0)
    rgba = np.dstack([np.full(a.shape[:2] + (3,), 0.96, np.float32), alpha])
    Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "67_hand_%s.png" % side))
    print("67_hand_%s.png  %dx%d" % (side, w * 4, h * 4))


def scrawl(size, base, inks, count, sizes, seed, words=("6 7", "6 7", "6 7", "67", "6", "7", "6  7", "6 7", "67", "six seven")):
    """Hand-written words scattered over a tileable square (drawn 3x3 and folded back)."""
    r = np.random.default_rng(seed)
    S = size
    canvas = Image.new("L", (S * 3, S * 3), 0)
    for k in range(count):
        word = words[r.integers(len(words))]
        fs = int(r.uniform(*sizes))
        font = ImageFont.truetype(FONT, fs)
        layer = Image.new("L", (fs * 6, fs * 2), 0)
        d = ImageDraw.Draw(layer)
        d.text((fs * 0.3, fs * 0.2), word, font=font, fill=int(r.uniform(150, 255)))
        layer = layer.rotate(r.uniform(-28, 28), resample=Image.BICUBIC, expand=True)
        x = int(r.uniform(0, S)) + S
        y = int(r.uniform(0, S)) + S
        canvas.paste(Image.eval(layer, lambda v: v), (x - layer.width // 2, y - layer.height // 2), layer)
    a = np.asarray(canvas).astype(np.float32) / 255.0
    fold = np.zeros((S, S), np.float32)
    for i in range(3):
        for j in range(3):
            fold = np.maximum(fold, a[i * S:(i + 1) * S, j * S:(j + 1) * S])
    ink_mask = fold
    out = base.copy()
    for ink, share in inks:
        sel = (r.random((S, S)) < share).astype(np.float32)
        sel = ndimage.gaussian_filter(sel, 40) > np.median(ndimage.gaussian_filter(sel, 40))
        m = ink_mask * (sel if share < 1.0 else 1.0)
        out = out * (1 - m[..., None]) + np.array(ink)[None, None] * m[..., None]
    return out


def paper(S, level, grain, seed):
    r = np.random.default_rng(seed)
    g = r.random((S // 8, S // 8)).astype(np.float32)
    g = np.asarray(Image.fromarray((g * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)).astype(np.float32) / 255.0
    n = level + (g - 0.5) * grain + (r.random((S, S)).astype(np.float32) - 0.5) * grain * 0.4
    return np.repeat(n[..., None], 3, axis=2)


def walls():
    S = 1024
    wall = scrawl(S, paper(S, 0.9, 0.08, 1), [((0.05, 0.05, 0.05), 1.0)], 260, (34, 150), 11)
    Image.fromarray((np.clip(wall, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "wall_67.png"))
    print("wall_67.png")
    floor = scrawl(S, paper(S, 0.55, 0.2, 2), [((0.08, 0.08, 0.08), 1.0), ((0.9, 0.9, 0.9), 0.35)], 170, (50, 190), 12)
    Image.fromarray((np.clip(floor, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "floor_67.png"))
    print("floor_67.png")
    ceil = paper(S, 0.82, 0.05, 3)
    # ceiling tiles: thin grid lines every quarter
    for k in range(0, S, S // 4):
        ceil[k:k + 3, :] *= 0.75
        ceil[:, k:k + 3] *= 0.75
    ceil = scrawl(S, ceil, [((0.35, 0.35, 0.35), 1.0)], 120, (40, 120), 13)
    Image.fromarray((np.clip(ceil, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "ceiling_67.png"))
    print("ceiling_67.png")
    gate = scrawl(S, paper(S, 0.05, 0.04, 4), [((0.92, 0.92, 0.92), 1.0)], 200, (40, 160), 14)
    Image.fromarray((np.clip(gate, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "gate_67.png"))
    print("gate_67.png")


def glyphs():
    S = 128
    im = Image.new("RGBA", (S * 2, S), (255, 255, 255, 0))
    font = ImageFont.truetype(FONT, 104)
    for i, ch in enumerate("67"):
        layer = Image.new("L", (S, S), 0)
        d = ImageDraw.Draw(layer)
        w, h = d.textbbox((0, 0), ch, font=font)[2:]
        d.text(((S - w) / 2, (S - h) / 2 - 8), ch, font=font, fill=255)
        layer = layer.filter(ImageFilter.MaxFilter(3))
        im.paste(Image.new("RGBA", (S, S), (255, 255, 255, 255)), (i * S, 0), layer)
    im.save(os.path.join(OUT, "67_glyphs.png"))
    print("67_glyphs.png")


if __name__ == "__main__":
    src = Image.open(sys.argv[1]).convert("RGB")
    face(src)
    hand(src, "l")
    hand(src, "r")
    walls()
    glyphs()
