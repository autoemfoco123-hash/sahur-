"""Sector 2 (bliss), made real: the sky, the ground, the earth under it.

  textures/sky_bliss.png      equirectangular sky (4096 x 2048): a deep blue zenith paling to a
                              hazy horizon, the sun where the field's sun is, fair-weather cumulus
                              on a cloud layer seen in perspective (flattening toward the horizon,
                              lit from the sun side, grey-blue bellies, bright rims near the sun),
                              distant hazy hills all round the horizon
  textures/grass_ground.png   tileable (1024): the ground between the blades, seen from standing
                              height: thousands of short blade strokes in a dozen greens, clover-dark
                              patches, sun-bleached ones
  textures/earth_layers.png   the walls of the tear (512 x 1024, top to bottom): turf and roots,
                              dark topsoil, stony subsoil, clay bands, rock, then darkness

Mapping (Godot 3 panorama): u = atan2(x, z) / 2pi (wrapped to 0..1), v = acos(y) / pi.
usage: python3 tools/bliss_textures.py
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "textures")
# toward the sun: the field's DirectionalLight is rotated (-46, -125, 0) degrees
SUN = np.array([-0.569, 0.719, -0.399])
SUN = SUN / np.linalg.norm(SUN)


class Noise:
    """Smooth value noise on a tiling lattice, any number of octaves."""

    def __init__(self, seed, n=512):
        self.r = np.random.default_rng(seed).random((n, n)).astype(np.float32)
        self.n = n

    def at(self, x, y):
        n = self.n
        xi = np.floor(x).astype(np.int64)
        yi = np.floor(y).astype(np.int64)
        fx = (x - xi).astype(np.float32)
        fy = (y - yi).astype(np.float32)
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        x0, y0 = xi % n, yi % n
        x1, y1 = (x0 + 1) % n, (y0 + 1) % n
        r = self.r
        a = r[y0, x0] + (r[y0, x1] - r[y0, x0]) * fx
        b = r[y1, x0] + (r[y1, x1] - r[y1, x0]) * fx
        return a + (b - a) * fy

    def fbm(self, x, y, octaves=6, lac=2.03, gain=0.5):
        s = np.zeros_like(x, dtype=np.float32)
        amp, f, tot = 1.0, 1.0, 0.0
        for o in range(octaves):
            s += self.at(x * f + o * 17.3, y * f - o * 9.1) * amp
            tot += amp
            amp *= gain
            f *= lac
        return s / tot


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def sky():
    W, H = 4096, 2048
    v = (np.arange(H) + 0.5) / H
    u = (np.arange(W) + 0.5) / W
    U, V = np.meshgrid(u, v)
    phi = U * 2 * np.pi
    th = V * np.pi
    y = np.cos(th)
    x = np.sin(th) * np.sin(phi)
    z = np.sin(th) * np.cos(phi)
    cos_sun = np.clip(x * SUN[0] + y * SUN[1] + z * SUN[2], -1, 1)
    ang = np.arccos(cos_sun)
    yy = np.clip(y, 0.0, 1.0)
    # --- the sky: rayleigh-ish gradient, brighter and whiter toward the horizon and the sun
    zen = np.array([0.19, 0.44, 0.86])
    hor = np.array([0.7, 0.84, 0.97])
    k = (1.0 - yy) ** 3.2
    col = zen[None, None] * (1 - k[..., None]) + hor[None, None] * k[..., None]
    mie = np.exp(-ang * 5.5)[..., None] * np.array([0.42, 0.38, 0.3]) + np.exp(-ang * 22.0)[..., None] * np.array([0.6, 0.55, 0.45])
    col = col + mie * (0.4 + 0.6 * (1 - yy[..., None]) ** 0.5)
    # --- clouds on a layer 1.6 km up, seen in perspective
    noise = Noise(11)
    warp = Noise(23)
    up = np.maximum(y, 0.012)
    px = x / up * 1.6
    pz = z / up * 1.6
    sx, sz = SUN[0] / math.hypot(SUN[0], SUN[2]), SUN[2] / math.hypot(SUN[0], SUN[2])

    def density(ax, az):
        wx = warp.fbm(ax * 0.18, az * 0.18, 3) - 0.5
        wz = warp.fbm(az * 0.18 + 40, ax * 0.18 + 40, 3) - 0.5
        base = noise.fbm(ax * 0.62 + wx * 1.1, az * 0.62 + wz * 1.1, 6)
        # fair-weather cumulus: separate heaps, ~30% of the sky, cauliflower edges
        d = smoothstep(0.53, 0.66, base)
        b = noise.fbm(ax * 2.2 + 5, az * 2.2 - 3, 4)
        billow = 1.0 - np.abs(2.0 * b - 1.0)
        edge = smoothstep(0.0, 0.5, d)
        return np.clip(d * (0.7 + 0.5 * billow) * (0.75 + 0.25 * edge), 0, 1)

    dens = density(px, pz)
    toward = density(px + sx * 0.55, pz + sz * 0.55)
    light = 0.46 + 0.54 * np.exp(-1.8 * toward) * (0.7 + 0.3 * (1 - dens))
    near_sun = np.exp(-ang * 3.0)
    lit = np.array([1.0, 0.985, 0.95]) * 1.08
    shade = np.array([0.66, 0.72, 0.82])
    ccol = shade[None, None] * (1 - light[..., None]) + lit[None, None] * light[..., None]
    ccol = ccol * (1.0 - 0.09 * dens)[..., None]          # thick middles: a grey-blue belly
    ccol = ccol + (near_sun * (1 - dens) * 0.45)[..., None] * np.array([1.0, 0.95, 0.85])
    # far away the clouds sink into the haze
    far = smoothstep(0.012, 0.16, y)
    alpha = np.clip(dens * 1.35, 0, 1) * far
    hz = (1 - far)[..., None]
    ccol = ccol * (1 - hz * 0.7) + hor[None, None] * hz * 0.7
    col = col * (1 - alpha[..., None]) + ccol * alpha[..., None]
    # --- the sun
    disk = smoothstep(0.0068, 0.0052, ang)
    col = col + disk[..., None] * np.array([1.6, 1.55, 1.4])
    # --- distant hills all round the horizon, hazy
    hill_n = Noise(31, 256)
    hx = np.cos(phi[0]) * 40.0
    hzz = np.sin(phi[0]) * 40.0
    ridge = 0.012 + 0.05 * hill_n.fbm(hx * 0.12 + 7, hzz * 0.12 + 3, 5) ** 1.5
    ridge2 = 0.004 + 0.026 * hill_n.fbm(hx * 0.3 + 70, hzz * 0.3 + 30, 4) ** 1.3
    h1 = ridge[None, :]
    h2 = ridge2[None, :]
    far_hill = np.array([0.5, 0.62, 0.62])
    near_hill = np.array([0.33, 0.48, 0.34])
    tex = noise.fbm(U * 900, V * 300, 3)[..., None]
    in1 = (y < h1) & (y > -0.2)
    in2 = (y < h2) & (y > -0.2)
    hill1 = far_hill[None, None] * (0.94 + 0.12 * tex) * 0.8 + hor[None, None] * 0.2
    hill2 = near_hill[None, None] * (0.9 + 0.2 * tex) * 0.75 + hor[None, None] * 0.25
    col = np.where(in1[..., None], hill1, col)
    col = np.where(in2[..., None], hill2, col)
    # below: dark hazy ground (never really seen: the field covers it)
    below = y < -0.02
    col = np.where(below[..., None], np.array([0.24, 0.34, 0.22])[None, None] * 0.9, col)
    img = np.clip(col, 0, 1) ** (1 / 1.0)
    Image.fromarray((img * 255).astype(np.uint8)).save(os.path.join(OUT, "sky_bliss.png"))
    print("sky_bliss.png")


def fold3(canvas, S):
    a = np.asarray(canvas).astype(np.float32)
    out = np.zeros((S, S) + a.shape[2:], np.float32)
    w = np.zeros((S, S), np.float32)
    for i in range(3):
        for j in range(3):
            out += a[i * S:(i + 1) * S, j * S:(j + 1) * S]
    return out


def grass_ground():
    S = 1024
    r = np.random.default_rng(5)
    n = Noise(41, 256)
    U, V = np.meshgrid(np.arange(S) / S, np.arange(S) / S)
    # tileable base: noise sampled on a torus
    def tn(f, o):
        a = U * 2 * np.pi
        b = V * 2 * np.pi
        return n.fbm(np.cos(a) * f + o, np.sin(a) * f + np.cos(b) * f * 0.5 + o * 2, 4) * 0.5 + n.fbm(np.sin(b) * f + o * 3, np.cos(b) * f + o, 4) * 0.5
    big = tn(2.0, 3)
    mid = tn(7.0, 11)
    base = np.stack([0.17 + 0.07 * big, 0.36 + 0.12 * big, 0.08 + 0.04 * mid], -1)
    base *= (0.85 + 0.3 * mid)[..., None]
    img = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8)).resize((S * 3, S * 3), Image.BILINEAR)
    img = Image.fromarray(np.tile(np.asarray(img.resize((S, S))), (3, 3, 1)))
    d = ImageDraw.Draw(img)
    greens = [(46, 102, 24), (64, 128, 30), (88, 150, 40), (110, 168, 52), (38, 84, 20), (130, 172, 70), (72, 120, 36), (150, 176, 84)]
    for k in range(42000):
        x0 = r.uniform(S, 2 * S)
        y0 = r.uniform(S, 2 * S)
        L = r.uniform(5, 16)
        a = r.uniform(-np.pi * 0.85, -np.pi * 0.15)
        x1 = x0 + math.cos(a) * L * 0.6
        y1 = y0 + math.sin(a) * L
        c = greens[r.integers(len(greens))]
        c = tuple(int(v * r.uniform(0.8, 1.1)) for v in c)
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                d.line([(x0 + ox, y0 + oy), (x1 + ox, y1 + oy)], fill=c, width=int(r.integers(1, 3)))
    out = np.asarray(img.crop((S, S, 2 * S, 2 * S))).astype(np.float32) / 255.0
    # dark clover patches and sun-bleached spots (tileable masks)
    clover = smoothstep(0.58, 0.72, tn(5.0, 77))[..., None]
    bleach = smoothstep(0.62, 0.78, tn(4.0, 99))[..., None]
    out = out * (1 - 0.25 * clover) + bleach * np.array([0.06, 0.05, 0.0])
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.SMOOTH).save(os.path.join(OUT, "grass_ground.png"))
    print("grass_ground.png")


def earth_layers():
    W, H = 512, 1024
    r = np.random.default_rng(9)
    n = Noise(61, 256)
    X, Y = np.meshgrid(np.arange(W) / W, np.arange(H) / H)
    t = Y
    a = X * 2 * np.pi
    def tn(f, o, fy=1.0):
        return n.fbm(np.cos(a) * f + o, np.sin(a) * f + Y * f * fy * 4 + o, 5)
    wav = (tn(1.5, 3) - 0.5) * 0.04
    tt = t + wav
    turf = np.array([0.22, 0.3, 0.1])
    top = np.array([0.2, 0.13, 0.07])
    sub = np.array([0.36, 0.25, 0.15])
    clay = np.array([0.52, 0.34, 0.2])
    rock = np.array([0.34, 0.31, 0.28])
    deep = np.array([0.08, 0.05, 0.04])
    col = np.zeros((H, W, 3))
    def band(c, a0, a1):
        return smoothstep(a0 - 0.01, a0 + 0.01, tt) * (1 - smoothstep(a1 - 0.01, a1 + 0.01, tt))
    for c, a0, a1 in [(turf, -0.1, 0.025), (top, 0.025, 0.12), (sub, 0.12, 0.26), (clay, 0.26, 0.31), (sub * 0.9, 0.31, 0.42),
                      (clay * 0.85, 0.42, 0.45), (rock, 0.45, 0.66), (rock * 0.7, 0.66, 0.8), (deep, 0.8, 1.2)]:
        col += band(c, a0, a1)[..., None] * c[None, None]
    grain = tn(14.0, 21, 0.6)[..., None]
    col *= 0.72 + 0.5 * grain
    # stones in the subsoil and rock, roots in the topsoil
    img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    for k in range(260):
        yv = r.uniform(0.14, 0.78) * H
        x0 = r.uniform(0, W)
        s = r.uniform(2, 8) * (1.0 + (yv / H) * 1.2)
        g = int(r.uniform(55, 105))
        for ox in (-W, 0, W):
            d.ellipse([x0 + ox - s, yv - s * 0.65, x0 + ox + s, yv + s * 0.65], fill=(g, int(g * 0.9), int(g * 0.8)))
            d.ellipse([x0 + ox - s * 0.7, yv - s * 0.6, x0 + ox + s * 0.5, yv - s * 0.1], fill=(int(g * 1.25), int(g * 1.15), int(g * 1.02)))
    for k in range(260):
        x0 = r.uniform(0, W)
        y0 = r.uniform(0.01, 0.06) * H
        pts = [(x0, y0)]
        for j in range(int(r.integers(4, 12))):
            x0 += r.uniform(-6, 6)
            y0 += r.uniform(4, 14)
            pts.append((x0, y0))
        for ox in (-W, 0, W):
            d.line([(p[0] + ox, p[1]) for p in pts], fill=(int(r.uniform(150, 200)), int(r.uniform(120, 160)), 90), width=1)
    out = np.asarray(img).astype(np.float32) / 255.0
    out *= (1 - smoothstep(0.78, 1.0, t))[..., None] * 0.9 + 0.1
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.SMOOTH).save(os.path.join(OUT, "earth_layers.png"))
    print("earth_layers.png")


if __name__ == "__main__":
    sky()
    grass_ground()
    earth_layers()
