"""Sector 3.5 textures (the 6-7 Ultra fight).

  textures/skin_ultra.png    tileable (1024): the monster's hide: near-black, wet, a network of
                             swollen dark-red veins, pale scar streaks, pores
  textures/skin_ultra_n.png  its normal map (veins and scars raised, pores sunk)
  textures/bone_ultra.png    tileable (512): ribs, spines, teeth: yellowed bone, grime, cracks
  textures/tile_6.png        the arena floor tiles (512): worn grey stone slab, chipped bevel,
  textures/tile_7.png        a huge hand-written 6 / 7 in black marker, smaller ones scrawled round
  textures/tile_safe.png     a slab with no number (it never falls)

usage: python3 tools/ultra_textures.py
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "textures")
FONT = os.path.join(ROOT, "fonts", "NothingYouCouldDo.ttf")


class Noise:
    def __init__(self, seed, n=256):
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

    def tile_fbm(self, S, f, octaves=5, seed_off=0.0):
        """Tileable fbm on an S x S image: the lattice period divides the image."""
        u = np.arange(S) / S
        X, Y = np.meshgrid(u, u)
        s = np.zeros((S, S), np.float32)
        amp, tot, ff = 1.0, 0.0, f
        for o in range(octaves):
            per = int(ff)
            xs = X * per
            ys = Y * per
            # wrap the lattice at `per` cells so the result tiles
            xi = np.floor(xs).astype(np.int64)
            yi = np.floor(ys).astype(np.int64)
            fx = xs - xi
            fy = ys - yi
            fx = fx * fx * (3 - 2 * fx)
            fy = fy * fy * (3 - 2 * fy)
            off = int(seed_off * 13 + o * 37)
            x0 = (xi % per + off) % self.n
            y0 = (yi % per + off) % self.n
            x1 = ((xi + 1) % per + off) % self.n
            y1 = ((yi + 1) % per + off) % self.n
            r = self.r
            a = r[y0, x0] + (r[y0, x1] - r[y0, x0]) * fx
            b = r[y1, x0] + (r[y1, x1] - r[y1, x0]) * fx
            s += (a + (b - a) * fy) * amp
            tot += amp
            amp *= 0.5
            ff *= 2
        return s / tot


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def save(name, arr):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, name))
    print(name)


def normal_from(h, strength):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.dstack([-gx, gy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def skin():
    S = 1024
    n = Noise(3)
    base = n.tile_fbm(S, 4, 5, 1)
    # veins: the ridges of two noise fields, swollen
    v1 = 1 - np.abs(2 * n.tile_fbm(S, 6, 4, 2) - 1)
    v2 = 1 - np.abs(2 * n.tile_fbm(S, 14, 3, 3) - 1)
    veins = smoothstep(0.9, 0.985, v1) * 0.9 + smoothstep(0.93, 0.99, v2) * 0.6
    scars = smoothstep(0.82, 0.95, n.tile_fbm(S, 3, 3, 4)) * smoothstep(0.55, 0.75, n.tile_fbm(S, 24, 2, 5))
    pores = n.tile_fbm(S, 128, 2, 6)
    col = np.dstack([0.075 + 0.05 * base, 0.066 + 0.04 * base, 0.064 + 0.035 * base])
    col = col * (0.85 + 0.3 * pores[..., None])
    col = col * (1 - veins[..., None] * 0.35) + veins[..., None] * np.array([0.2, 0.035, 0.035])
    col = col + scars[..., None] * np.array([0.16, 0.14, 0.13])
    save("skin_ultra.png", col)
    h = base * 0.4 + veins * 1.2 + scars * 0.5 - pores * 0.35
    save("skin_ultra_n.png", normal_from(h, 6.0))


def bone():
    S = 512
    n = Noise(9)
    b = n.tile_fbm(S, 4, 5, 1)
    grime = smoothstep(0.5, 0.8, n.tile_fbm(S, 8, 4, 2))
    cracks = smoothstep(0.96, 0.995, 1 - np.abs(2 * n.tile_fbm(S, 10, 3, 3) - 1))
    col = np.dstack([0.78 + 0.1 * b, 0.72 + 0.09 * b, 0.6 + 0.08 * b])
    col = col * (1 - grime[..., None] * 0.45) - cracks[..., None] * 0.45
    save("bone_ultra.png", col)


def tiles():
    S = 512
    n = Noise(21)
    r = np.random.default_rng(67)
    for name, ch in [("tile_6.png", "6"), ("tile_7.png", "7"), ("tile_safe.png", "")]:
        g = n.tile_fbm(S, 6, 5, 1 + len(name))
        stone = 0.5 + 0.16 * (g - 0.5) + 0.05 * (n.tile_fbm(S, 40, 2, 4) - 0.5)
        U, V = np.meshgrid(np.arange(S) / S, np.arange(S) / S)
        edge = np.minimum(np.minimum(U, 1 - U), np.minimum(V, 1 - V))
        bevel = smoothstep(0.0, 0.03, edge)
        chips = smoothstep(0.7, 0.8, n.tile_fbm(S, 20, 2, 7)) * (1 - smoothstep(0.0, 0.06, edge))
        val = stone * (0.55 + 0.45 * bevel) - chips * 0.15
        img = Image.fromarray((np.clip(np.dstack([val, val, val * 0.98]), 0, 1) * 255).astype(np.uint8))
        d = ImageDraw.Draw(img)
        if ch:
            # small ones scrawled everywhere, then the big one
            for k in range(26):
                f = ImageFont.truetype(FONT, int(r.uniform(28, 60)))
                layer = Image.new("L", (120, 100), 0)
                ImageDraw.Draw(layer).text((10, 5), ch, font=f, fill=int(r.uniform(90, 170)))
                layer = layer.rotate(r.uniform(-35, 35), expand=True)
                img.paste((30, 30, 30), (int(r.uniform(-20, S - 80)), int(r.uniform(-20, S - 80))), layer)
            f = ImageFont.truetype(FONT, 360)
            layer = Image.new("L", (S, S), 0)
            ImageDraw.Draw(layer).text((S * 0.28, S * 0.02), ch, font=f, fill=235)
            layer = layer.filter(ImageFilter.MaxFilter(5)).rotate(r.uniform(-8, 8))
            img.paste((12, 12, 12), (0, 0), layer)
        else:
            # a plain slab: cross-hatched hush paint, "safe"
            for k in range(6):
                y = int(S * (0.3 + 0.08 * k))
                d.line([(S * 0.2, y), (S * 0.8, y + 6)], fill=(205, 205, 200), width=5)
        img = img.filter(ImageFilter.SMOOTH)
        img.save(os.path.join(OUT, name))
        print(name)


if __name__ == "__main__":
    skin()
    bone()
    tiles()
