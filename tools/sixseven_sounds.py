"""Sector 3 sounds (the 67 maze). All synthesized (formant speech, no samples).

  chant_6.wav    67 calls SIX: its hands rise (a rushing swell), then the word, a choir of
                 three throats an octave apart, huge and far, the world turning over under it
  chant_7.wav    the same, SEVEN
  gate_move.wav  a slab of the maze sliding up out of the floor / down into it: stone grinding,
                 a deep thump when it seats
  amb_67.wav     loop: two drones a 6:7 apart beating slowly, paper rustling, now and then a
                 whisper somewhere counting six... seven...
  chase_67.wav   loop: 6 against 7 polyrhythm (low thumps in sixes, ticks in sevens) over a
                 rising 6:7 chord, it is close
  scare_67.wav   the jumpscare: a scream in fifths and sevenths, SIX SEVEN shouted into your face
  land_thud.wav  you land on the maze floor after the void lets go

usage: python3 tools/sixseven_sounds.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
from dsp import SR, bp, env_exp, hp, lp, secs, tt, white  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")
rng = np.random.default_rng(6767)

# phone plans: (seconds, voicing 0..1, formants F1 F2 F3 or None, noise band (lo, hi, gain) or None)
SIX = [
    (0.17, 0.0, None, (4200, 9500, 0.55)),          # s
    (0.05, 0.6, (330, 2100, 2700), (3500, 8000, 0.1)),
    (0.17, 1.0, (400, 1950, 2600), None),            # ɪ
    (0.05, 0.0, None, None),                         # closure
    (0.03, 0.0, None, (1400, 3600, 0.9)),            # k
    (0.03, 0.0, None, None),
    (0.24, 0.0, None, (4200, 9500, 0.55)),           # s
]
SEVEN = [
    (0.15, 0.0, None, (4200, 9500, 0.55)),           # s
    (0.05, 0.6, (480, 1850, 2550), (3500, 8000, 0.1)),
    (0.15, 1.0, (560, 1770, 2500), None),            # ɛ
    (0.07, 0.55, (330, 1300, 2400), (1200, 4500, 0.14)),   # v
    (0.07, 1.0, (500, 1500, 2500), None),            # ə
    (0.24, 0.8, (260, 1100, 2300), None),            # n
]


def speak(plan, f0a, f0b, fs=1.0, whisper=False, seed=0):
    """A word from a phone plan: voicing through moving formants, plus the noise of its consonants."""
    r = np.random.default_rng(seed)
    n = sum(secs(p[0]) for p in plan)
    voice = np.zeros(n)
    noise = np.zeros(n)
    keys = []
    i = 0
    for d, v, F, nz in plan:
        m = secs(d)
        voice[i:i + m] = v
        if nz:
            lo, hi, g = nz
            w = np.sin(np.linspace(0, np.pi, m)) ** 0.6
            noise[i:i + m] += bp(r.standard_normal(m), lo, hi) * g * w
        if F:
            keys.append((i + m * 0.5, F))
        i += m
    idx = np.arange(n)
    tracks = []
    for k, (q, g) in enumerate([(8, 1.0), (12, 0.5), (14, 0.3)]):
        f = np.interp(idx, [c for c, _ in keys], [F[k] * fs for _, F in keys])
        tracks.append((f, q, g))
    # smooth the voicing so the phones run into each other
    win = np.hanning(secs(0.025))
    voice = np.convolve(voice, win / win.sum(), "same")
    if whisper:
        src = r.standard_normal(n) * 0.6
    else:
        f0 = np.linspace(f0a, f0b, n) * (1.0 + 0.012 * np.sin(2 * np.pi * 5.5 * idx / SR))
        src = dsp.glottal(f0, jitter=0.02, breath=0.06)
    vo = dsp.formants(src, tracks) * voice
    return vo + noise * (0.5 if whisper else 1.0)


def choir(plan, base=1.0, seed=0):
    """Three throats an octave apart, a little out of step."""
    parts = []
    for k, (f0a, f0b, fs, g, off) in enumerate([
            (98 * base, 78 * base, 1.0, 1.0, 0.0),
            (49 * base, 40 * base, 0.86, 0.85, 0.014),
            (196 * base, 160 * base, 1.17, 0.32, 0.028)]):
        w = speak(plan, f0a, f0b, fs, seed=seed + k)
        parts.append(np.concatenate([np.zeros(secs(off)), w]) * g)
    n = max(len(p) for p in parts)
    return sum(dsp.pad(p, n) for p in parts)


def chant(plan, name, seed):
    D = 2.6
    x = np.zeros(secs(D))
    # the hands rise: a swell of rushing air and a rising tone (6:7)
    sw = tt(0.55)
    rise = (sw / 0.55) ** 2
    swell = bp(white(0.55), 300, 3000) * rise * 0.35
    f = 70 + 50 * rise
    swell += (np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.6 * np.sin(2 * np.pi * np.cumsum(f * 7 / 6) / SR)) * rise * 0.25
    dsp.place(x, swell, 0.0)
    w = choir(plan, seed=seed)
    w = np.tanh(w / (np.max(np.abs(w)) + 1e-9) * 2.2)
    dsp.place(x, w, 0.5)
    # the world turns over: a sub drop under the vowel
    tb = tt(1.4)
    boom = np.sin(2 * np.pi * (30 + 32 * np.exp(-tb * 5)) * tb) * np.exp(-tb * 2.0)
    dsp.place(x, boom * 0.9, 0.6)
    y = dsp.verb(x, "far", wet=0.55, dry=1.0)[:, :len(x)]
    dsp.write(os.path.join(OUT, name), y, peak=0.95)
    print(name)


def gate_move():
    D = 1.6
    t = tt(D)
    env = np.minimum(1.0, t / 0.08) * np.clip((1.15 - t) / 0.1, 0, 1)
    rough = 0.6 + 0.4 * lp(rng.standard_normal(len(t)), 30) * 8
    grind = lp(dsp.brown(D), 500) * rough * env * 2.5 + bp(white(D), 700, 2600) * rough * env * 0.12
    rumble = np.sin(2 * np.pi * 38 * t) * env * 0.25
    x = grind + rumble
    tb = tt(0.45)
    thump = np.sin(2 * np.pi * (50 + 60 * np.exp(-tb * 30)) * tb) * np.exp(-tb * 9) + lp(white(0.45), 900) * np.exp(-tb * 25) * 0.5
    dsp.place(x, thump, 1.08)
    y = dsp.verb(x, "concrete", wet=0.35, dry=1.0)[:, :len(x)]
    dsp.write(os.path.join(OUT, "gate_move.wav"), y, peak=0.85)
    print("gate_move.wav")


def ambience():
    D = 24.0
    t = tt(D)
    # 6:7, slowly breathing (the loop is whole periods long, so it joins)
    slow = 0.6 + 0.4 * np.sin(2 * np.pi * t / D * 3)
    drone = (np.sin(2 * np.pi * 42 * t) + np.sin(2 * np.pi * 49 * t) * 0.9 + 0.35 * np.sin(2 * np.pi * 84 * t) + 0.3 * np.sin(2 * np.pi * 98 * t)) * slow * 0.16
    hiss = bp(white(D), 1800, 6000) * 0.012
    L = drone + hiss
    R = drone * 0.95 + np.roll(hiss, secs(0.02))
    st = np.vstack([L, R])
    # paper: someone leafing through pages somewhere
    for k in range(18):
        rd = rng.uniform(0.08, 0.35)
        p = hp(white(rd), 1500) * np.sin(np.linspace(0, np.pi, secs(rd))) ** 2 * rng.uniform(0.05, 0.14)
        dsp.place(st, dsp.pan(p, rng.uniform(-1, 1)), rng.uniform(0, D))
    # whispers counting
    tt0 = 2.0
    while tt0 < D:
        for k, plan in enumerate([SIX, SEVEN]):
            w = speak(plan, 0, 0, rng.uniform(0.95, 1.15), whisper=True, seed=int(tt0 * 10) + k)
            dsp.place(st, dsp.pan(w * rng.uniform(0.06, 0.12), rng.uniform(-1, 1)), tt0 + k * 0.75)
        tt0 += rng.uniform(5.0, 9.0)
    st = np.array([lp(c, 7000) for c in st])
    dsp.write(os.path.join(OUT, "amb_67.wav"), st, loop=True, peak=0.6)
    print("amb_67.wav")


def chase():
    bar = 2.1
    D = bar * 4
    n = secs(D)
    x = np.zeros(n)
    tk = tt(0.25)
    thump = np.sin(2 * np.pi * (48 + 50 * np.exp(-tk * 30)) * tk) * np.exp(-tk * 14)
    tick = bp(white(0.05), 2500, 7000) * env_exp(secs(0.05), 90)
    for b in range(4):
        for k in range(6):
            dsp.place(x, thump * (1.0 if k == 0 else 0.6), b * bar + k * bar / 6)
        for k in range(7):
            dsp.place(x, tick * (0.5 if k == 0 else 0.3), b * bar + k * bar / 7)
    t = tt(D)
    # the chord: a 6:7 pair of saws, low-passed, swelling every bar
    sw = 0.5 + 0.5 * np.sin(2 * np.pi * t / bar - np.pi / 2)
    ph = np.cumsum(np.full(n, 84.0)) / SR
    ph2 = np.cumsum(np.full(n, 98.0)) / SR
    pad = (dsp.saw_ph(ph) + dsp.saw_ph(ph2)) * 0.5
    pad = dsp.tvf(pad, 300 + 900 * sw, "lp", 2.0)
    x = x + pad * (0.2 + 0.25 * sw)
    st = np.vstack([x, np.roll(x, secs(0.011))])
    dsp.write(os.path.join(OUT, "chase_67.wav"), st, loop=True, peak=0.75)
    print("chase_67.wav")


def scare():
    D = 2.0
    t = tt(D)
    x = np.zeros(secs(D))
    # the scream: four throats, a fifth and a 7:6 apart, rising, torn
    for f, g in [(180, 1.0), (210, 0.8), (270, 0.6), (360, 0.45)]:
        f0 = f * (1.0 + 0.25 * np.minimum(1.0, t / 0.4)) * (1.0 + 0.03 * np.sin(2 * np.pi * 9 * t))
        v = dsp.vowel(dsp.glottal(f0, jitter=0.05, breath=0.3), "a")
        x += v * g
    x = x * np.minimum(1.0, t / 0.02) * np.exp(-np.maximum(0, t - 1.4) * 4)
    # six seven, shouted right in your face
    w6 = choir(SIX, base=1.6, seed=91)
    w7 = choir(SEVEN, base=1.6, seed=93)
    x = x / (np.max(np.abs(x)) + 1e-9)
    dsp.place(x, w6 / (np.max(np.abs(w6)) + 1e-9) * 0.9, 0.12)
    dsp.place(x, w7 / (np.max(np.abs(w7)) + 1e-9) * 0.9, 0.82)
    burst = white(0.3) * np.exp(-tt(0.3) * 10) * 0.8
    dsp.place(x, burst, 0.0)
    tb = tt(1.2)
    dsp.place(x, np.sin(2 * np.pi * (34 + 60 * np.exp(-tb * 8)) * tb) * np.exp(-tb * 2.5) * 0.9, 0.0)
    x = np.tanh(x * 3.0)
    y = dsp.verb(x, "small", wet=0.25, dry=1.0)[:, :len(x)]
    dsp.write(os.path.join(OUT, "scare_67.wav"), y, peak=0.99)
    print("scare_67.wav")


def land():
    tb = tt(0.9)
    x = np.sin(2 * np.pi * (45 + 70 * np.exp(-tb * 25)) * tb) * np.exp(-tb * 7) + lp(white(0.9), 1200) * np.exp(-tb * 18) * 0.6
    x += hp(white(0.9), 3000) * np.exp(-tb * 30) * 0.15        # paper scattering
    y = dsp.verb(x, "concrete", wet=0.3, dry=1.0)[:, :len(x)]
    dsp.write(os.path.join(OUT, "land_thud.wav"), y, peak=0.9)
    print("land_thud.wav")


if __name__ == "__main__":
    chant(SIX, "chant_6.wav", 61)
    chant(SEVEN, "chant_7.wav", 71)
    gate_move()
    ambience()
    chase()
    scare()
    land()
