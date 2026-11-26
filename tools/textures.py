"""Offline texture generator for sahur (tileable, photo-style).

Every texture is periodic by construction (FFT-filtered noise + integer-period patterns),
so it tiles without seams in world-space box mapping.

  wallpaper.png  512 px = 1.0 m   mono-yellow wallpaper, faint stripes + chevron print, paper grain
  carpet.png     512 px = 1.0 m   loop-pile office carpet, multicolour yarn, mottling
  ceiling.png    512 px = 1.2 m   2x2 fissured acoustic tiles in a T-bar grid
  panel.png      128 px = 0.6 m   prismatic troffer lens with two tubes behind it

usage: python3 tools/textures.py <out_dir>
"""
import sys
import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "textures"
N = 512


def noise(n, sx, sy=None, seed=0):
    """Periodic gaussian noise with feature size ~sx by sy pixels (unit variance)."""
    sy = sx if sy is None else sy
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((n, n))
    fy = np.fft.fftfreq(n)[:, None]
    fx = np.fft.fftfreq(n)[None, :]
    filt = np.exp(-((fx * sx) ** 2 + (fy * sy) ** 2) * 2.0)
    r = np.real(np.fft.ifft2(np.fft.fft2(w) * filt))
    return (r - r.mean()) / (r.std() + 1e-9)


def save(name, rgb):
    a = np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(a, "RGB").save(f"{OUT}/{name}")
    print(name, a.shape, a.reshape(-1, 3).mean(0).round(1))


def coords(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    return x, y


# ------------------------------------------------------------------ wallpaper
def wallpaper():
    x, y = coords(N)
    base = np.array([0.80, 0.735, 0.445])
    lum = np.ones((N, N))
    # stripe bands every 64 px (12.5 cm): lighter band, thin darker borders
    sx = np.mod(x, 64.0)
    band = (np.abs(sx - 32.0) < 11.0).astype(float)
    band = noise(N, 1.2, seed=1) * 0.0 + band
    border = np.exp(-((np.abs(sx - 32.0) - 11.0) ** 2) / 0.8)
    lum += band * 0.022 - border * 0.035
    # chevron print inside each band: a small '^' every 32 px
    cx = np.abs(sx - 32.0)
    cy = np.mod(y, 32.0) - 16.0
    d = np.abs((cy + cx * 0.55) - 0.0)
    chev = np.exp(-(d ** 2) / 1.1) * (cx < 6.5)
    ink = np.clip(0.75 + 0.35 * noise(N, 30, seed=2), 0.3, 1.2)   # uneven print
    lum -= chev * 0.055 * ink
    # small dots between the bands
    dx = np.mod(x + 32.0, 64.0) - 32.0
    dy = np.mod(y + 16.0, 32.0) - 16.0
    lum -= np.exp(-(dx * dx + dy * dy) / 2.2) * 0.04 * ink
    # paper: vertical fibres, fine grain, mottling, very slow tone drift
    lum += noise(N, 1.0, 5.0, seed=3) * 0.012
    lum += noise(N, 0.7, seed=4) * 0.008
    lum += noise(N, 55, seed=5) * 0.009
    lum += noise(N, 170, seed=6) * 0.008
    rgb = base[None, None, :] * lum[..., None]
    # slight yellowing in blotches
    yel = noise(N, 90, seed=7) * 0.015
    rgb[..., 2] -= yel
    save("wallpaper.png", rgb)


# ------------------------------------------------------------------ carpet
def carpet():
    x, y = coords(N)
    base = np.array([0.56, 0.475, 0.29])
    lum = np.ones((N, N))
    # loop pile: tufted rows every 4 px, loops ~1.5 px
    rows = 0.5 + 0.5 * np.cos(2 * np.pi * y / 4.0)
    loops = noise(N, 1.1, seed=11)
    lum += loops * 0.10 + (rows - 0.5) * 0.05
    lum += noise(N, 3.0, seed=12) * 0.05
    # mottling + traffic/damp shading
    lum += noise(N, 35, seed=13) * 0.03 + noise(N, 140, seed=14) * 0.022
    rgb = base[None, None, :] * lum[..., None]
    # multicolour yarn: per-tuft hue jitter
    for c, s in zip(range(3), (21, 22, 23)):
        rgb[..., c] *= 1.0 + noise(N, 1.6, seed=s) * 0.045
    # flecks of darker yarn
    fleck = (noise(N, 1.2, seed=24) > 2.3).astype(float)
    rgb *= (1.0 - fleck * 0.35)[..., None]
    save("carpet.png", rgb)


# ------------------------------------------------------------------ ceiling tiles
def ceiling():
    x, y = coords(N)
    T = N // 2                       # one 60 cm tile = 256 px
    tile = np.array([0.86, 0.845, 0.78])
    lum = np.ones((N, N))
    # fissured acoustic surface: worm-like contour lines + pits + speckle
    for k, s in enumerate((2.2, 3.4)):
        nn = noise(N, s, seed=31 + k)
        worm = np.exp(-(nn ** 2) / 0.0025)
        mask = noise(N, 9, seed=41 + k) > -0.3
        lum -= worm * mask * 0.2
    pits = noise(N, 0.9, seed=51)
    lum -= np.clip(pits - 1.9, 0, None) * 0.3
    lum += noise(N, 0.8, seed=52) * 0.02 + noise(N, 18, seed=53) * 0.008
    # per-tile tone (some tiles older)
    tx = (x // T).astype(int)
    ty = (y // T).astype(int)
    tones = np.array([[1.0, 0.965], [0.975, 1.012]])
    lum *= tones[ty, tx]
    # edges: bevel shading + dark reveal + T-bar
    ex = np.minimum(np.mod(x, T), T - np.mod(x, T))
    ey = np.minimum(np.mod(y, T), T - np.mod(y, T))
    e = np.minimum(ex, ey)
    lum *= 1.0 - 0.16 * np.exp(-np.maximum(e - 5.0, 0) / 4.0) * (e > 5.0)
    rgb = tile[None, None, :] * lum[..., None]
    bar = (e <= 4.5)
    reveal = (e > 4.5) & (e <= 6.0)
    metal = np.array([0.80, 0.80, 0.77])
    rgb[bar] = metal * (1.0 + noise(N, 6, seed=54)[bar][:, None] * 0.015)
    rgb[reveal] *= 0.55
    save("ceiling.png", rgb)


# ------------------------------------------------------------------ light panel lens
def panel():
    n = 128
    x, y = coords(n)
    lum = np.full((n, n), 0.86)
    # two tubes behind the lens
    for cx in (n * 0.33, n * 0.67):
        lum += 0.16 * np.exp(-((x - cx) ** 2) / (2 * 9.0 ** 2))
    # prismatic lens: tiny pyramids
    lum *= 1.0 + 0.035 * np.sin(x * np.pi / 2.0) * np.sin(y * np.pi / 2.0)
    # end caps a bit darker, frame
    lum *= 1.0 - 0.10 * np.exp(-np.minimum(y, n - 1 - y) / 10.0)
    e = np.minimum(np.minimum(x, n - 1 - x), np.minimum(y, n - 1 - y))
    rgb = np.stack([lum, lum * 0.985, lum * 0.94], -1)
    frame = e < 5
    rgb[frame] = np.array([0.62, 0.62, 0.6])
    rgb[(e >= 5) & (e < 6)] *= 0.7
    a = np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(a, "RGB").save(f"{OUT}/panel.png")
    print("panel.png", a.shape)


# ------------------------------------------------------------------ sector 1: the key rooms
def polar(n, cell):
    x, y = coords(n)
    cx = np.mod(x, cell) - cell / 2
    cy = np.mod(y, cell) - cell / 2
    return np.sqrt(cx * cx + cy * cy) / (cell / 2), np.arctan2(cy, cx), cx, cy


def wallpaper_green():
    """Old hotel damask: dark green with a faded olive-gold medallion every 25 cm."""
    base = np.array([0.15, 0.22, 0.16])
    ink = np.array([0.36, 0.38, 0.22])
    r, th, cx, cy = polar(N, 128)
    petals = np.clip(np.cos(4 * th) * 0.5 + 0.5, 0, 1) ** 2
    medal = np.exp(-((r - 0.55) ** 2) / 0.012) * (0.4 + 0.6 * petals)
    medal += np.exp(-(r ** 2) / 0.02) * 0.8
    medal += np.exp(-((r - 0.85) ** 2) / 0.002) * 0.5 * (np.cos(16 * th) > 0.3)
    # offset second grid (classic half-drop)
    r2, th2, _, _ = polar(N, 128)
    r2 = np.roll(np.roll(r2, 64, 0), 64, 1)
    th2 = np.roll(np.roll(th2, 64, 0), 64, 1)
    medal += np.exp(-((r2 - 0.32) ** 2) / 0.006) * (np.cos(6 * th2) * 0.5 + 0.5) * 0.6
    wear = np.clip(0.75 + 0.35 * noise(N, 40, seed=61), 0.2, 1.1)
    m = np.clip(medal, 0, 1) * wear * 0.75
    rgb = base[None, None, :] * (1 - m[..., None]) + ink[None, None, :] * m[..., None]
    rgb *= (1.0 + noise(N, 1.0, 4.0, seed=62) * 0.02 + noise(N, 60, seed=63) * 0.05)[..., None]
    save("wallpaper_green.png", rgb)


def carpet_red():
    """Hotel carpet: burgundy with a gold-and-navy geometric repeat every 25 cm."""
    x, y = coords(N)
    base = np.array([0.34, 0.06, 0.07])
    gold = np.array([0.62, 0.45, 0.16])
    navy = np.array([0.08, 0.08, 0.16])
    cell = 128
    u = np.mod(x, cell) / cell - 0.5
    v = np.mod(y, cell) / cell - 0.5
    dia = np.abs(u) + np.abs(v)
    ring = np.exp(-((dia - 0.36) ** 2) / 0.0012)
    core = (dia < 0.12).astype(float)
    cross = (np.minimum(np.abs(u), np.abs(v)) < 0.02).astype(float) * (dia > 0.42)
    rgb = base[None, None, :] * np.ones((N, N, 1))
    rgb = rgb * (1 - ring[..., None] * 0.85) + gold * ring[..., None] * 0.85
    rgb = rgb * (1 - core[..., None]) + navy * core[..., None]
    rgb = rgb * (1 - cross[..., None] * 0.7) + gold * cross[..., None] * 0.7
    pile = 1.0 + noise(N, 1.1, seed=71) * 0.12 + noise(N, 3.0, seed=72) * 0.05 + noise(N, 50, seed=73) * 0.06
    rgb *= pile[..., None]
    save("carpet_red.png", rgb)


def plaster():
    """Ceiling plaster: warm off-white, soft trowel marks, hairline cracks."""
    lum = 1.0 + noise(N, 30, seed=81) * 0.03 + noise(N, 2.0, seed=82) * 0.015
    crack = np.exp(-(noise(N, 14, seed=83) ** 2) / 0.0015) * (noise(N, 60, seed=84) > 0.6)
    lum -= crack * 0.18
    rgb = np.array([0.8, 0.76, 0.68])[None, None, :] * lum[..., None]
    save("plaster.png", rgb)


def wood():
    """Dark stained door wood, vertical grain."""
    x, y = coords(N)
    g = noise(N, 3.0, 60.0, seed=91)
    lines = np.sin((x + g * 6.0) * 2 * np.pi / 9.0) * 0.5 + 0.5
    lum = 0.85 + 0.18 * noise(N, 12, 90, seed=92) + 0.08 * lines ** 6
    rgb = np.array([0.27, 0.13, 0.065])[None, None, :] * lum[..., None]
    save("wood.png", rgb)


def brass():
    n = 64
    lum = 1.0 + noise(n, 4, seed=95) * 0.06
    rgb = np.array([0.78, 0.6, 0.26])[None, None, :] * lum[..., None]
    a = np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(a, "RGB").save(f"{OUT}/brass.png")
    print("brass.png")


def lamp_round():
    """Round frosted ceiling lamp on a dark plate (fills one 60 cm lens quad)."""
    n = 128
    x, y = coords(n)
    r = np.sqrt((x - 63.5) ** 2 + (y - 63.5) ** 2) / 64.0
    glass = np.clip(1.0 - (r / 0.7) ** 4, 0, 1)
    lum = 0.2 + 0.8 * glass * (0.92 + 0.08 * np.cos(r * 30))
    ring = np.exp(-((r - 0.72) ** 2) / 0.0008) * 0.35
    rgb = np.stack([lum + ring, lum * 0.9 + ring * 0.9, lum * 0.7 + ring * 0.6], -1)
    rgb[r > 0.76] = np.array([0.16, 0.15, 0.14])
    a = np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(a, "RGB").save(f"{OUT}/lamp_round.png")
    print("lamp_round.png")


if __name__ == "__main__":
    import os
    os.makedirs(OUT, exist_ok=True)
    wallpaper()
    carpet()
    ceiling()
    panel()
    wallpaper_green()
    carpet_red()
    plaster()
    wood()
    brass()
    lamp_round()
