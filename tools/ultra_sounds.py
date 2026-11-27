"""Sector 3.5 sounds (the 6-7 Ultra fight). All synthesized.

  ultra_roar.wav     its roar: a huge throat (glottal pulses at 40-70 Hz through wide formants),
                     a torn upper scream, distortion, the room answering
  ultra_inhale.wav   the breath it draws before it screams
  ultra_slam.wav     a hand the size of a car hitting stone: sub boom, crack, debris
  ultra_sweep.wav    an arm dragged across the floor: rising rush, scraping
  ultra_hit.wav      hurt (a photo through its open shield): a shriek, a flinch
  ultra_death.wav    dying: a long falling roar, the body collapsing into the pit
  tile_drop.wav      floor slabs dropping away: stone grinding, crumbling
  anchor_on.wav      a hush anchor powering up: electric rise, a lock clunk, a tone
  shield_break.wav   its shield coming down: a glassy burst, a sucking whoosh
  shield_up.wav      the shield closing again: a reversed swell, a hum
  amb_ultra.wav      loop: the fight's music: drums six against seven, a pulsing 6:7 drone,
                     a distorted bass figure, metal hits

usage: python3 tools/ultra_sounds.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
from dsp import SR, bp, env_exp, hp, lp, secs, tt, white  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")
rng = np.random.default_rng(6767)


def throat(d, f0a, f0b, vowel, jitter=0.05, breath=0.25):
    t = tt(d)
    f = np.linspace(f0a, f0b, len(t)) * (1 + 0.03 * np.sin(2 * np.pi * 5.5 * t))
    src = dsp.glottal(f, jitter=jitter, breath=breath)
    return dsp.vowel(src, vowel)


def norm(x):
    return x / (np.max(np.abs(x)) + 1e-9)


def write(name, x, peak=0.95, verb="far", wet=0.4, loop=False):
    if verb:
        x = dsp.verb(x, verb, wet=wet, dry=1.0)[:, :x.shape[-1]]
    dsp.write(os.path.join(OUT, name), x, peak=peak, loop=loop)
    print(name)


def roar():
    D = 3.2
    t = tt(D)
    env = np.minimum(1, t / 0.15) * np.exp(-np.maximum(0, t - 2.2) * 2.5)
    low = norm(throat(D, 62, 44, "o", 0.08, 0.4)) * 1.0
    mid = norm(throat(D, 130, 95, "a", 0.06, 0.3)) * 0.6
    top = norm(throat(D, 420, 300, "a", 0.04, 0.5)) * 0.25
    sub = np.sin(2 * np.pi * (38 + 6 * np.sin(2 * np.pi * 3 * t)) * t) * 0.6
    x = (low + mid + top + sub) * env
    x = np.tanh(x * 2.5) + lp(white(D), 300) * env * 0.3
    write("ultra_roar.wav", x, wet=0.45)


def inhale():
    D = 1.5
    t = tt(D)
    e = (t / D) ** 1.6
    x = bp(white(D), 500, 2500) * e * 0.6 + lp(white(D), 200) * e * 0.4
    x = dsp.formants(x, [(np.linspace(700, 400, len(t)), 6, 1.0), (np.linspace(1200, 900, len(t)), 8, 0.6)]) * 0.8 + x * 0.3
    write("ultra_inhale.wav", x, peak=0.8, wet=0.4)


def slam():
    D = 2.2
    x = np.zeros(secs(D))
    tb = tt(1.6)
    boom = np.sin(2 * np.pi * (30 + 70 * np.exp(-tb * 14)) * tb) * np.exp(-tb * 2.4) * 1.4
    dsp.place(x, boom, 0.0)
    crack = hp(white(0.4), 600) * np.exp(-tt(0.4) * 16) + bp(white(0.4), 150, 1500) * np.exp(-tt(0.4) * 8)
    dsp.place(x, crack, 0.0)
    for k in range(50):
        g = lp(white(0.08), rng.uniform(500, 3000)) * env_exp(secs(0.08), 50) * rng.uniform(0.05, 0.3)
        dsp.place(x, g, rng.uniform(0.05, 1.6))
    write("ultra_slam.wav", np.tanh(x * 1.6), peak=0.98, wet=0.5)


def sweep():
    D = 2.2
    t = tt(D)
    e = np.sin(np.pi * np.clip(t / D, 0, 1)) ** 1.5
    rush = bp(white(D), 200, 2200) * e
    scrape = bp(white(D), 1500, 5000) * e * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 23 * t))) * 0.3
    low = np.sin(2 * np.pi * 45 * t) * e * 0.5
    write("ultra_sweep.wav", rush + scrape + low, peak=0.9, wet=0.35)


def hit():
    D = 1.3
    t = tt(D)
    env = np.minimum(1, t / 0.02) * np.exp(-t * 2.2)
    s = norm(throat(D, 520, 380, "i", 0.08, 0.5)) + norm(throat(D, 260, 190, "a", 0.08, 0.4)) * 0.7
    write("ultra_hit.wav", np.tanh(s * env * 2.6), peak=0.95, wet=0.4)


def death():
    D = 7.0
    t = tt(D)
    env = np.minimum(1, t / 0.2) * np.exp(-np.maximum(0, t - 4.0) * 0.9)
    r = norm(throat(D, 120, 35, "o", 0.1, 0.5)) + norm(throat(D, 380, 90, "a", 0.08, 0.5)) * 0.5
    x = np.tanh(r * env * 2.2)
    rumble = lp(white(D), 90) * 2.0 * np.minimum(1, np.maximum(0, t - 2.5) / 1.0) * np.exp(-np.maximum(0, t - 5.5) * 1.2)
    x = x + rumble
    for k in range(30):
        g = lp(white(0.1), rng.uniform(300, 2000)) * env_exp(secs(0.1), 40) * rng.uniform(0.1, 0.35)
        dsp.place(x, g, rng.uniform(2.5, 6.0))
    write("ultra_death.wav", x, peak=0.97, wet=0.55)


def tile_drop():
    D = 1.6
    t = tt(D)
    e = np.minimum(1, t / 0.05) * np.exp(-t * 1.8)
    grind = lp(dsp.brown(D), 600) * 3 * e + bp(white(D), 300, 2000) * e * 0.3
    x = grind.copy()
    for k in range(24):
        g = lp(white(0.06), rng.uniform(600, 2500)) * env_exp(secs(0.06), 60) * rng.uniform(0.1, 0.3)
        dsp.place(x, g, rng.uniform(0.0, 1.2))
    write("tile_drop.wav", x, peak=0.85, verb="concrete", wet=0.35)


def anchor_on():
    D = 1.6
    t = tt(D)
    f = 80 + 500 * np.minimum(1, t / 0.9) ** 2
    hum = (dsp.saw_ph(np.cumsum(f) / SR) * 0.3 + np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.5) * np.minimum(1, t / 0.9)
    hum = lp(hum, 3000) * np.exp(-np.maximum(0, t - 1.0) * 6)
    x = hum.copy()
    dsp.place(x, lp(white(0.1), 900) * env_exp(secs(0.1), 40) * 0.8, 0.9)
    tone = np.sin(2 * np.pi * 880 * tt(0.6)) * env_exp(secs(0.6), 5) * 0.3
    dsp.place(x, tone, 0.95)
    write("anchor_on.wav", x, peak=0.8, verb="concrete", wet=0.3)


def shield_break():
    D = 2.2
    t = tt(D)
    x = np.zeros(secs(D))
    for k in range(40):
        f = rng.uniform(1500, 6000)
        d = rng.uniform(0.1, 0.5)
        tk = tt(d)
        dsp.place(x, np.sin(2 * np.pi * f * tk) * np.exp(-tk * rng.uniform(8, 20)) * rng.uniform(0.05, 0.2), rng.uniform(0, 0.3))
    dsp.place(x, hp(white(0.5), 2000) * np.exp(-tt(0.5) * 8), 0.0)
    whoosh = bp(white(D), 200, 1500) * np.exp(-((t - 0.6) / 0.5) ** 2)
    write("shield_break.wav", x + whoosh, peak=0.9, wet=0.45)


def shield_up():
    D = 1.3
    t = tt(D)
    e = (t / D) ** 2
    x = bp(white(D), 300, 2500) * e + np.sin(2 * np.pi * 110 * t) * e * 0.4
    x[-secs(0.05):] *= np.linspace(1, 0, secs(0.05))
    write("shield_up.wav", x, peak=0.8, wet=0.3)


def music():
    bar = 2.1
    bars = 8
    D = bar * bars
    n = secs(D)
    x = np.zeros(n)
    tk = tt(0.35)
    kick = np.sin(2 * np.pi * (45 + 90 * np.exp(-tk * 30)) * tk) * np.exp(-tk * 9)
    snare = bp(white(0.25), 200, 5000) * np.exp(-tt(0.25) * 14)
    tick = bp(white(0.05), 3000, 8000) * env_exp(secs(0.05), 80)
    metal = np.zeros(secs(0.8))
    tm = tt(0.8)
    for f in [233, 377, 512, 701]:
        metal += np.sin(2 * np.pi * f * tm) * np.exp(-tm * 5)
    for b in range(bars):
        for k in range(6):
            dsp.place(x, kick * (1.0 if k % 3 == 0 else 0.55), b * bar + k * bar / 6)
        for k in range(7):
            dsp.place(x, tick * 0.4, b * bar + k * bar / 7)
        dsp.place(x, snare * 0.6, b * bar + bar / 2)
        if b % 2 == 1:
            dsp.place(x, metal * 0.15, b * bar + bar * 5 / 6)
    t = tt(D)
    drone = (np.sin(2 * np.pi * 42 * t) + 0.9 * np.sin(2 * np.pi * 49 * t)) * 0.25
    # a distorted bass figure: six notes against the seven ticks
    notes = [42, 42, 49, 42, 56, 49]
    bass = np.zeros(n)
    for b in range(bars):
        for k, f in enumerate(notes):
            d = bar / 6
            seg = tt(d)
            s = np.tanh(dsp.saw_ph(np.cumsum(np.full(len(seg), f * (2 if b % 4 == 3 else 1))) / SR) * 3) * np.exp(-seg * 4)
            dsp.place(bass, s * 0.35, b * bar + k * d)
    x = x + drone + lp(bass, 900)
    st = np.vstack([x, np.roll(x, secs(0.013))])
    dsp.write(os.path.join(OUT, "amb_ultra.wav"), st, loop=True, peak=0.8)
    print("amb_ultra.wav")


if __name__ == "__main__":
    roar()
    inhale()
    slam()
    sweep()
    hit()
    death()
    tile_drop()
    anchor_on()
    shield_break()
    shield_up()
    music()
