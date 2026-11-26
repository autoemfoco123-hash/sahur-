"""Cut the big golden key out of a photo (the source image is not part of the repo).

  textures/key_front.png   the key exactly as in the photo, transparent background (RGBA)
  textures/key_back.png    the same silhouette as plain polished gold (back side / thickness)
  prints the key's bounding box and the face landmarks in texture UV (for the jumpscare mouth)

usage: python3 tools/key_cutout.py PHOTO OUT_DIR
"""
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
a = np.asarray(im).astype(np.float64) / 255.0
r, g, b = a[..., 0], a[..., 1], a[..., 2]
mx = a.max(-1)
mn = a.min(-1)
s = (mx - mn) / (mx + 1e-6)
h = np.zeros_like(mx)
d = mx - mn + 1e-6
h = np.where(mx == r, (g - b) / d % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
gold = (h > 20) & (h < 50) & (s > 0.46) & (mx > 0.22)
gold[:, 205:] = False                                   # only the big key on the left
gold = ndimage.binary_opening(gold, iterations=2)
lab, n = ndimage.label(gold)
sizes = ndimage.sum(gold, lab, range(1, n + 1))
key = lab == (1 + int(np.argmax(sizes)))
key = ndimage.binary_closing(key, iterations=4)
key = ndimage.binary_opening(key, structure=np.ones((5, 5)))
key = ndimage.binary_fill_holes(key)
# the ring hole at the top of the bow: dark pixels inside the filled silhouette, upper part
ys, xs = np.where(key)
top = ys.min()
bowh = int((ys.max() - top) * 0.3)
dark = (mx < 0.5) & key
dark[top + bowh // 2 + 30:, :] = False
dl, dn = ndimage.label(dark)
if dn:
    # the dark blob closest to the top centre of the bow
    cx = xs[ys < top + 40].mean()
    best, bd = 0, 1e9
    for i in range(1, dn + 1):
        yy, xx = np.where(dl == i)
        if len(yy) < 25:
            continue
        dd = (yy.mean() - (top + 25)) ** 2 + (xx.mean() - cx) ** 2
        if dd < bd:
            best, bd = i, dd
    if best:
        hole = ndimage.binary_dilation(dl == best, iterations=1)
        key &= ~hole
ys, xs = np.where(key)
y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
pad = 4
y0, x0 = max(0, y0 - pad), max(0, x0 - pad)
y1, x1 = min(a.shape[0], y1 + pad), min(a.shape[1], x1 + pad)
crop = (np.asarray(im)[y0:y1, x0:x1]).astype(np.uint8)
alpha = (key[y0:y1, x0:x1] * 255).astype(np.uint8)
# soften the edge a touch and upscale 2x (the source is small)
A = Image.fromarray(alpha).filter(ImageFilter.GaussianBlur(0.6))
rgba = Image.fromarray(np.dstack([crop, np.asarray(A)]), "RGBA")
W, H = rgba.size
rgba = rgba.resize((W * 2, H * 2), Image.LANCZOS)
# bleed colour into the transparent border so filtering never shows a halo
arr = np.asarray(rgba).astype(np.float64)
m = arr[..., 3] > 128
idx = ndimage.distance_transform_edt(~m, return_distances=False, return_indices=True)
arr[..., :3] = arr[..., :3][idx[0], idx[1]]
front = Image.fromarray(arr.astype(np.uint8), "RGBA")
front.save(out + "/key_front.png")
# the back: same silhouette, polished gold with soft vertical shading
gw, gh = front.size
base = np.array([0.86, 0.63, 0.22])
shade = 0.78 + 0.3 * np.sin(np.linspace(0, np.pi, gw))[None, :] - 0.12 * (np.mgrid[0:gh, 0:gw][0] / gh)
back = np.dstack([np.clip(base[c] * shade, 0, 1) * 255 for c in range(3)] + [np.asarray(front)[..., 3]]).astype(np.uint8)
Image.fromarray(back, "RGBA").save(out + "/key_back.png")
print("cutout %dx%d from photo box x[%d:%d] y[%d:%d]" % (gw, gh, x0, x1, y0, y1))
