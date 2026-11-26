"""Sector 2 textures.

  textures/khaby_face.png    the mechanism's head, neck and chest from the reference photo,
                             upscaled; everything that is not the bust (the black curtain, the
                             white pedestal) is filled with the nearest bust colour, so the
                             planar projection in khaby_bust.shader never smears black or white
                             onto the sides
  textures/khaby_hand_l.png  the two hands, cut out of the table (alpha), colour bled under the
  textures/khaby_hand_r.png  edges so filtering never shows a white halo
  textures/grass_bliss.png   tileable bright meadow grass
  textures/sky_bliss.png     equirectangular sky: deep blue at the top, pale at the horizon,
                             soft cumulus (made here, in the spirit of the famous wallpaper)

usage: python3 tools/khaby_textures.py REFERENCE_PHOTO.jpg
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures")
rng = np.random.default_rng(2002)

# where the bust is in the reference photo (637 x 358): see khaby_model.gd
FACE_BOX = (220, 0, 420, 250)          # x0, y0, x1, y1 -> 200 x 250 px, u/v 0..1
HANDS = {"l": (160, 252, 252, 358), "r": (392, 252, 490, 358)}


def bleed(rgb, mask):
    """Every pixel outside mask takes the colour of the nearest pixel inside it."""
    idx = ndimage.distance_transform_edt(~mask, return_distances=False, return_indices=True)
    out = rgb[idx[0], idx[1]]
    # soften what was filled in, keep the subject sharp
    soft = np.stack([ndimage.gaussian_filter(out[..., c], 3) for c in range(3)], -1)
    return np.where(mask[..., None], rgb, soft)


def face(src):
    im = src.crop(FACE_BOX).resize((800, 1000), Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    a = np.asarray(im).astype(np.float32) / 255.0
    lum = a.mean(-1)
    red = a[..., 0] - a[..., 2]
    # the bust: darker than the pedestal, brighter or redder than the black curtain
    mask = ((lum > 0.12) | (red > 0.05)) & (lum < 0.62)
    mask = ndimage.binary_opening(mask, iterations=2)
    lab, n = ndimage.label(mask)
    if n > 0:
        sizes = ndimage.sum(mask, lab, range(1, n + 1))
        mask = lab == (np.argmax(sizes) + 1)
    mask = ndimage.binary_fill_holes(mask)
    # only inside the bust's outline (head, neck, the chest cup): never the table or the rods
    yy, xx = np.mgrid[0:1000, 0:800] / 4.0          # back to crop pixels (200 x 250)
    head = ((xx - 98) / 60.0) ** 2 + ((yy - 80) / 79.0) ** 2 < 1.0
    neck = (abs(xx - 98) < 32) & (yy > 130) & (yy < 172)
    cup = (((xx - 100) / 90.0) ** 2 + ((yy - 196) / 44.0) ** 2 < 1.0) & (yy > 158)
    mask &= head | neck | cup
    out = bleed(a, mask)
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "khaby_face.png"))
    print("khaby_face.png  bust %.0f%% of the crop" % (mask.mean() * 100))


def hand(src, side):
    box = HANDS[side]
    im = src.crop(box)
    w, h = im.size
    im = im.resize((w * 5, h * 5), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255.0
    lum = a.mean(-1)
    mask = lum < 0.52
    mask = ndimage.binary_opening(mask, iterations=2)
    lab, n = ndimage.label(mask)
    if n > 0:
        sizes = ndimage.sum(mask, lab, range(1, n + 1))
        mask = lab == (np.argmax(sizes) + 1)
    mask = ndimage.binary_fill_holes(mask)
    rgb = bleed(a, mask)
    alpha = ndimage.gaussian_filter(mask.astype(np.float32), 1.2)
    rgba = np.dstack([rgb, alpha])
    Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "khaby_hand_%s.png" % side))
    ys, xs = np.nonzero(mask)
    print("khaby_hand_%s.png  %dx%d, hand %d..%d x %d..%d" % (side, w * 5, h * 5, xs.min(), xs.max(), ys.min(), ys.max()))


def fbm(shape, octaves=5, base=8, seed=0):
    r = np.random.default_rng(seed)
    out = np.zeros(shape, np.float32)
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        n = base * 2 ** o
        g = r.random((n, n)).astype(np.float32)
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((shape[1], shape[0]), Image.BICUBIC)
        out += np.asarray(img).astype(np.float32) / 255.0 * amp
        tot += amp
        amp *= 0.5
    return out / tot


def tileable_noise(size, cells, seed):
    """Periodic value noise (wraps at the edges)."""
    r = np.random.default_rng(seed)
    g = r.random((cells, cells)).astype(np.float32)
    g = np.tile(g, (3, 3))
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((size * 3, size * 3), Image.BICUBIC)
    a = np.asarray(img).astype(np.float32) / 255.0
    return a[size:2 * size, size:2 * size]


def grass():
    S = 512
    n = sum(tileable_noise(S, c, 30 + c) * w for c, w in [(4, 0.5), (16, 0.3), (64, 0.15), (128, 0.05)])
    n = (n - n.min()) / (n.max() - n.min())
    # blades: short vertical streaks of light and dark
    streak = tileable_noise(S, 256, 7)
    streak = ndimage.uniform_filter1d(streak, 9, axis=0, mode="wrap")
    base = np.array([0.22, 0.56, 0.12])
    light = np.array([0.45, 0.78, 0.2])
    dark = np.array([0.1, 0.33, 0.07])
    t = np.clip(n * 0.7 + streak * 0.5 - 0.1, 0, 1)[..., None]
    col = dark * (1 - t) + light * t
    col = col * 0.55 + base * 0.45
    col *= (0.9 + 0.2 * tileable_noise(S, 200, 9))[..., None]
    Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "grass_bliss.png"))
    print("grass_bliss.png")


def sky():
    W, H = 2048, 1024
    y = (np.arange(H)[:, None] + 0.5) / H          # 0 top .. 1 bottom
    elev = (0.5 - y) * np.pi                         # +pi/2 zenith .. -pi/2 nadir
    s = np.clip(np.sin(elev), -1, 1)
    zen = np.array([0.07, 0.25, 0.78])
    hor = np.array([0.6, 0.77, 0.95])
    t = np.clip(s, 0, 1) ** 0.5
    col = hor * (1 - t[..., None]) + zen * t[..., None]
    col = np.broadcast_to(col, (H, W, 3)).copy()
    # puffy cumulus: smooth noise, wide rather than tall, in two bands, wrapping around
    def wrap_noise(cells_x, cells_y, seed):
        r = np.random.default_rng(seed)
        g = r.random((cells_y, cells_x)).astype(np.float32)
        g = np.concatenate([g, g, g], 1)
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((W * 3, H), Image.BICUBIC)
        a = np.asarray(img).astype(np.float32)[:, W:2 * W] / 255.0
        return ndimage.gaussian_filter(a, (2, 4), mode="wrap")
    n = wrap_noise(10, 6, 4) * 0.5 + wrap_noise(24, 14, 5) * 0.3 + wrap_noise(60, 30, 6) * 0.2
    band = np.exp(-((elev - 0.3) / 0.22) ** 2) + 0.6 * np.exp(-((elev - 0.72) / 0.22) ** 2)
    d = n + 0.42 * np.broadcast_to(band, (H, W)) - 0.78
    c = np.clip(d * 5.0, 0, 1) * (elev > 0.03)
    c = ndimage.gaussian_filter(c, 1.5, mode="wrap")
    # sunlit tops, softly shaded bottoms
    below = np.roll(c, -18, axis=0)
    shade = np.clip(1.0 - np.clip(below - c, 0, 1) * 0.0 - np.clip(c - np.roll(c, 22, axis=0), 0, 1) * 0.28, 0.7, 1.0)
    white = np.array([1.0, 1.0, 1.0])[None, None] * shade[..., None]
    col = col * (1 - c[..., None] * 0.97) + white * (c[..., None] * 0.97)
    # below the horizon: the far hills' haze
    under = np.clip(-s * 6, 0, 1)[..., None]
    col = col * (1 - under) + np.array([0.45, 0.62, 0.38]) * under
    Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "sky_bliss.png"))
    print("sky_bliss.png")


if __name__ == "__main__":
    src = Image.open(sys.argv[1]).convert("RGB")
    face(src)
    hand(src, "l")
    hand(src, "r")
    grass()
    sky()
