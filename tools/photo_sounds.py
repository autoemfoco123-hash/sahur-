"""The hush field camera: shutter, flash pop, capacitor recharge whine.

  sounds/shutter.wav

usage: python3 tools/photo_sounds.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
from dsp import bp, env_exp, hp, lp, secs, tt, white  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds", "shutter.wav")


def click(d=0.03, lo=1500, hi=9000, rate=180):
    return bp(white(d), lo, hi) * env_exp(secs(d), rate)


def main():
    D = 1.3
    x = np.zeros(secs(D))
    # mirror slap, then the curtain 45 ms later
    a = click(0.04, 600, 7000, 120) * 1.0 + lp(white(0.04), 300) * env_exp(secs(0.04), 90) * 0.8
    b = click(0.03, 1800, 11000, 220) * 0.9
    x[:len(a)] += a
    x[secs(0.045):secs(0.045) + len(b)] += b
    # the flash: a soft electric pop
    pop = hp(white(0.08), 2500) * env_exp(secs(0.08), 60) * 0.35
    x[secs(0.02):secs(0.02) + len(pop)] += pop
    # capacitor recharging: a thin whine climbing in pitch
    t = tt(1.0)
    f = 2400 + 3600 * (t / 1.0) ** 0.6
    whine = np.sin(2 * np.pi * np.cumsum(f) / dsp.SR) * 0.05 * np.minimum(1.0, t / 0.1) * (1 - t / 1.0)
    x[secs(0.25):secs(0.25) + len(whine)] += whine
    y = dsp.verb(x, "small", wet=0.2, dry=1.0)[:, :len(x)]
    dsp.write(OUT, y, peak=0.8)
    print("shutter.wav")


if __name__ == "__main__":
    main()
