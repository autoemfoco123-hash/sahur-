"""The electronic sliding doors between sectors. All synthesized.

  door_slide.wav   the lock releases (a relay clack and a hiss), the motor whines, the slab
                   rumbles along its track and stops with a soft rubber thump
  door_close.wav   the same the other way, ending in a heavier clunk as the lock catches
  door_deny.wav    the keypad refuses: two low buzzes and a relay click

usage: python3 tools/door_sounds.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
from dsp import SR, bp, env_exp, hp, lp, secs, tt, white  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")
rng = np.random.default_rng(1212)


def clack(gain=1.0, f=2600):
    """A relay / lock bolt: a sharp click with a short metallic ring."""
    d = 0.12
    t = tt(d)
    x = bp(white(d), 1500, 7000) * env_exp(secs(d), 220)
    for ratio, a in [(1.0, 0.5), (1.53, 0.3), (2.31, 0.2)]:
        x += a * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t * 60)
    x += lp(white(d), 500) * env_exp(secs(d), 90) * 0.8
    return x * gain


def hiss(d, gain=1.0):
    """Air let out of a pneumatic cylinder."""
    x = bp(white(d), 2500, 9000) * np.exp(-tt(d) * 5.0)
    return x * np.minimum(1.0, tt(d) / 0.01) * gain


def motor(d, f0=110.0, f1=150.0):
    """An electric drive: a whine with its harmonics, a little gear grit, rising then settling."""
    t = tt(d)
    shape = np.sin(np.linspace(0, np.pi, len(t))) ** 0.6
    f = f0 + (f1 - f0) * shape
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.zeros(len(t))
    for k, a in [(1, 0.5), (2, 0.35), (3, 0.22), (5, 0.12), (8, 0.06)]:
        x += a * np.sin(k * ph)
    grit = bp(white(d), 300, 1400) * (0.5 + 0.5 * np.sin(ph * 0.5)) * 0.25
    return (x * 0.6 + grit) * shape


def rumble(d):
    """The slab rolling on its track."""
    t = tt(d)
    x = lp(white(d), 220) * 1.2 + bp(white(d), 600, 1800) * 0.12
    x *= 0.7 + 0.3 * np.sin(2 * np.pi * 23 * t)
    return x * np.sin(np.linspace(0, np.pi, len(t))) ** 0.8


def thump(gain=1.0, f=70):
    d = 0.35
    t = tt(d)
    x = np.sin(2 * np.pi * (f + 60 * np.exp(-t * 40)) * t) * np.exp(-t * 14)
    x += lp(white(d), 300) * np.exp(-t * 25) * 0.6
    return x * gain


def door_slide():
    D = 1.4
    x = np.zeros(secs(D))
    dsp.place(x, clack(0.9), 0.0)
    dsp.place(x, hiss(0.45, 0.35), 0.02)
    dsp.place(x, motor(0.62) * 0.55, 0.06)
    dsp.place(x, rumble(0.6) * 0.5, 0.08)
    dsp.place(x, thump(0.55), 0.62)
    y = dsp.verb(x, "small", wet=0.25, dry=1.0)[:, :len(x)]
    dsp.write(os.path.join(OUT, "door_slide.wav"), y, peak=0.85)
    print("door_slide.wav")


def door_close():
    D = 1.4
    x = np.zeros(secs(D))
    dsp.place(x, motor(0.6, 140.0, 105.0) * 0.5, 0.0)
    dsp.place(x, rumble(0.58) * 0.5, 0.02)
    dsp.place(x, thump(0.9, 60), 0.58)
    dsp.place(x, clack(0.8, 2100), 0.62)
    dsp.place(x, hiss(0.3, 0.2), 0.64)
    y = dsp.verb(x, "small", wet=0.25, dry=1.0)[:, :len(x)]
    dsp.write(os.path.join(OUT, "door_close.wav"), y, peak=0.85)
    print("door_close.wav")


def door_deny():
    D = 0.75
    x = np.zeros(secs(D))
    for t0 in (0.0, 0.26):
        d = 0.18
        t = tt(d)
        b = np.sign(np.sin(2 * np.pi * 220 * t)) * 0.35 + np.sin(2 * np.pi * 440 * t) * 0.2
        b = lp(b, 2500) * np.minimum(1.0, t / 0.005) * np.minimum(1.0, (d - t) / 0.01)
        dsp.place(x, b, t0)
    dsp.place(x, clack(0.4, 3200), 0.0)
    y = dsp.verb(x, "small", wet=0.15, dry=1.0)[:, :len(x)]
    dsp.write(os.path.join(OUT, "door_deny.wav"), y, peak=0.7)
    print("door_deny.wav")


if __name__ == "__main__":
    door_slide()
    door_close()
    door_deny()
