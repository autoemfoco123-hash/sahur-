"""Sector 2 sounds (bliss). All synthesized.

  amb_field.wav     loop: a soft breeze over grass, a far skylark, now and then small birds
  khaby_servo.wav   the mechanism turning its arms: a servo whine, chain ticking over sprockets,
                    a clunk when it stops in the pose
  talk_blip.wav     one syllable of an operative talking through the respirator (dialogue)
  radio_blip.wav    one syllable of the hush radio (band-limited, crackly)
  crack_break.wav   the world tearing: a huge splitting crack, earth giving way, debris
  crack_rumble.wav  the ground groaning open underneath (long, deep)
  void_fall.wav     falling through the void: rushing wind rising, a low red drone, whispers

usage: python3 tools/field_sounds.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
from dsp import SR, bp, env_exp, hp, lp, secs, tt, white  # noqa: E402
from keys_sounds import whisper  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")
rng = np.random.default_rng(3003)


def circ(fn, x, n):
    y = fn(np.concatenate([x[-n:], x, x[:n]]))
    return y[n:n + len(x)]


def chirp(f0, f1, d, amp=1.0):
    t = tt(d)
    f = np.linspace(f0, f1, len(t))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.linspace(0, np.pi, len(t))) ** 2
    return x * amp


def bird_phrase():
    x = np.zeros(secs(1.2))
    t0 = 0.0
    for k in range(rng.integers(3, 7)):
        f = rng.uniform(3200, 5200)
        d = rng.uniform(0.04, 0.12)
        c = chirp(f, f * rng.uniform(0.75, 1.35), d, rng.uniform(0.4, 1.0))
        i = secs(t0)
        x[i:i + len(c)] += c[:len(x) - i]
        t0 += d + rng.uniform(0.02, 0.09)
    return x


def ambience():
    D = 24.0
    n = secs(D)
    # breeze: slow gusts of filtered noise
    gust = lp(rng.standard_normal(n), 0.35)
    gust = (gust - gust.min()) / (gust.max() - gust.min())
    wind = bp(white(D), 200, 1600) * (0.15 + 0.6 * gust) * 0.5
    grass = hp(white(D), 3000) * (0.05 + 0.25 * gust ** 2) * 0.35
    L = wind + grass * 0.8
    R = np.roll(wind, secs(0.013)) + np.roll(grass, secs(0.021))
    st = np.vstack([L, R])
    # a skylark far away, and small birds now and then
    t = 1.0
    while t < D - 2.0:
        ph = bird_phrase() * rng.uniform(0.04, 0.12)
        p = rng.uniform(-0.8, 0.8)
        pan = dsp.pan(ph, p)
        dsp.place(st, pan, t)
        t += rng.uniform(1.5, 4.5)
    st = np.array([circ(lambda v: hp(v, 40), st[c], secs(0.5)) for c in range(2)])
    dsp.write(os.path.join(OUT, "amb_field.wav"), st, loop=True, peak=0.6)
    print("amb_field.wav")


def servo():
    D = 1.9
    t = tt(D)
    shape = np.sin(np.linspace(0, np.pi, secs(1.6))) ** 0.5
    sh = np.zeros(len(t))
    sh[:len(shape)] = shape
    f = 420 + 260 * sh
    ph = 2 * np.pi * np.cumsum(f) / SR
    whine = (np.sin(ph) * 0.4 + np.sin(2 * ph) * 0.25 + np.sin(3 * ph) * 0.1) * sh
    # the chain ticking over the sprockets
    ticks = np.zeros(len(t))
    rate = 14 + 30 * sh
    tp = np.cumsum(rate) / SR
    idx = np.nonzero(np.diff(np.floor(tp)) > 0)[0]
    ticks[idx] = 1.0
    ticks = bp(ticks, 2500, 7000) * 6.0 * sh
    x = whine * 0.5 + ticks * 0.3 + bp(white(D), 600, 2400) * 0.04 * sh
    stop = lp(white(0.12), 600) * env_exp(secs(0.12), 60) * 0.8
    dsp.place(x, stop, 1.6)
    y = dsp.verb(x, "small", wet=0.15, dry=1.0)[:, :len(x)]
    dsp.write(os.path.join(OUT, "khaby_servo.wav"), y, peak=0.7)
    print("khaby_servo.wav")


def talk():
    # a voiced syllable through a respirator: buzzy glottal source, a vowel, muffled
    d = 0.11
    src = dsp.glottal(rng.uniform(115, 135), d)
    v = dsp.vowel(src, "a")
    v = lp(v, 2200) * np.sin(np.linspace(0, np.pi, len(v))) ** 0.7
    dsp.write(os.path.join(OUT, "talk_blip.wav"), v, peak=0.5)
    print("talk_blip.wav")
    src = dsp.glottal(150, d)
    r = bp(dsp.vowel(src, "o"), 400, 2600) * np.sin(np.linspace(0, np.pi, len(src))) ** 0.7
    r = np.tanh(r * 3.0) * 0.5 + hp(white(d), 2000) * 0.05
    dsp.write(os.path.join(OUT, "radio_blip.wav"), r, peak=0.45)
    print("radio_blip.wav")


def crack_break():
    D = 3.6
    x = np.zeros(secs(D))
    t = tt(0.35)
    # the split: a sharp tearing crack, then a second
    for t0, g in [(0.0, 1.0), (0.18, 0.7), (0.42, 0.5)]:
        c = hp(white(0.35), 700) * np.exp(-t * 18) * g + bp(white(0.35), 200, 1800) * np.exp(-t * 9) * g * 0.8
        dsp.place(x, c, t0)
    # earth giving way: a huge low thump and rubble
    tb = tt(1.6)
    boom = np.sin(2 * np.pi * (34 + 40 * np.exp(-tb * 6)) * tb) * np.exp(-tb * 2.2) * 1.3
    dsp.place(x, boom, 0.05)
    for k in range(40):
        g = lp(white(0.06), rng.uniform(400, 2500)) * env_exp(secs(0.06), 60) * rng.uniform(0.05, 0.25)
        dsp.place(x, g, rng.uniform(0.2, 2.8))
    x = np.tanh(x * 1.8)
    y = dsp.verb(x, "far", wet=0.45, dry=1.0)[:, :len(x)]
    dsp.write(os.path.join(OUT, "crack_break.wav"), y, peak=0.97)
    print("crack_break.wav")


def crack_rumble():
    D = 7.0
    t = tt(D)
    env = np.minimum(1.0, t / 0.6) * np.exp(-np.maximum(0, t - 4.5) * 0.8)
    r = lp(white(D), 90) * 2.2 + np.sin(2 * np.pi * 28 * t) * 0.3 + lp(white(D), 400) * 0.25
    grind = bp(white(D), 300, 1200) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.7 * t)) * 0.25
    x = (r + grind) * env
    y = dsp.verb(x, "far", wet=0.3, dry=1.0)[:, :len(x)]
    dsp.write(os.path.join(OUT, "crack_rumble.wav"), y, peak=0.9)
    print("crack_rumble.wav")


def void_fall():
    D = 7.0
    t = tt(D)
    rise = np.minimum(1.0, t / 2.5)
    rush = bp(white(D), 300, 3500) * (0.3 + 0.7 * rise) + lp(white(D), 200) * 0.5 * rise
    drone = (np.sin(2 * np.pi * 41 * t) + 0.5 * np.sin(2 * np.pi * 61.5 * t)) * 0.18 * rise
    x = rush * 0.6 + drone
    L = x.copy()
    R = np.roll(x, secs(0.017))
    st = np.vstack([L, R])
    for k in range(8):
        w = whisper(rng.uniform(0.3, 0.6), 200 + k) * rng.uniform(0.15, 0.35)
        dsp.place(st, dsp.pan(w, rng.uniform(-1, 1)), rng.uniform(1.0, 6.0))
    fade = np.minimum(1.0, (D - t) / 1.0)
    st = st * fade
    dsp.write(os.path.join(OUT, "void_fall.wav"), st, peak=0.9)
    print("void_fall.wav")


if __name__ == "__main__":
    ambience()
    servo()
    talk()
    crack_break()
    crack_rumble()
    void_fall()
