"""The doors between sectors, and what waits behind them. All synthesized.

  door_open.wav      latch, a long hinge groan, air rushing through the gap
  door_slam.wav      a heavy fire door slammed shut behind you: thud, latch clatter, the room booms
  door_rattle.wav    a locked handle jerked twice
  threshold.wav      the dark between two sectors (~1.4 s): close whispers on both sides, a wet
                     breath in your ear, keys right next to you, a sub drone and a reversed
                     swell that rises to the moment the lights come back
  threshold_hit.wav  the lights snap on and it is in your face: a dissonant metal stab, a sub
                     punch and a ring that won't stop

usage: python3 tools/door_sounds.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
from dsp import SR, bp, env_exp, hp, lp, secs, tt, white  # noqa: E402
from keys_sounds import clink, jingle, screech, whisper  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")
rng = np.random.default_rng(909)


def latch(gain=1.0):
    """A steel latch bolt: two clicks and a short metallic ring."""
    x = np.zeros(secs(0.25))
    for t0, f in [(0.0, 3100), (0.035, 2300)]:
        c = clink(f, 0.18, 1.2) * 0.5
        i = secs(t0)
        x[i:i + len(c)] += c[:len(x) - i]
    k = lp(white(0.03), 900) * env_exp(secs(0.03), 140)
    x[:len(k)] += k * 0.9
    return x * gain


def creak(d=0.75, f_from=38.0, f_to=95.0, body=(520, 1240, 2350)):
    """Stick-slip friction: a pulse train that speeds up and stutters, through wood resonances."""
    t = tt(d)
    rate = f_from + (f_to - f_from) * (t / d) ** 0.7
    rate *= 1 + 0.18 * lp(rng.standard_normal(len(t)), 6) * 8
    ph = np.cumsum(rate) / SR
    pulses = np.zeros(len(t))
    idx = np.nonzero(np.diff(np.floor(ph)) > 0)[0]
    pulses[idx] = rng.uniform(0.5, 1.0, len(idx))
    x = np.zeros(len(t))
    for f, q, a in zip(body, (9, 12, 16), (1.0, 0.7, 0.45)):
        x += dsp.reson(pulses, f * rng.uniform(0.97, 1.03), q) * a
    x += bp(white(d), 1500, 5000) * 0.05
    return x * np.sin(np.linspace(0, np.pi, len(t))) ** 0.5


def door_open():
    D = 1.2
    x = np.zeros(secs(D))
    dsp.place(x, latch(), 0.0)
    dsp.place(x, creak(0.8) * 0.9, 0.06)
    # air rushing through the opening gap
    air = lp(white(0.9), 900) * np.sin(np.linspace(0, np.pi, secs(0.9))) ** 2 * 0.25
    dsp.place(x, air, 0.12)
    y = dsp.verb(x, "small", wet=0.25, dry=1.0)[:, :len(x)]
    dsp.write(os.path.join(OUT, "door_open.wav"), y, peak=0.85)
    print("door_open.wav")


def door_slam():
    D = 2.6
    x = np.zeros(secs(D))
    # the slab hits the frame: a big low thud with a hard edge
    t = tt(0.5)
    thud = np.sin(2 * np.pi * (55 + 90 * np.exp(-t * 30)) * t) * np.exp(-t * 9) * 1.2
    thud += lp(white(0.5), 260) * np.exp(-t * 14) * 1.4
    thud += bp(white(0.5), 900, 3200) * np.exp(-t * 60) * 0.7
    dsp.place(x, thud, 0.0)
    # the frame and the latch clatter
    dsp.place(x, latch(0.8), 0.012)
    for k in range(5):
        c = clink(rng.uniform(1200, 2600), 0.25, 0.8) * rng.uniform(0.1, 0.3)
        dsp.place(x, c, 0.02 + k * rng.uniform(0.015, 0.04))
    # a dull boom down the corridor
    boom = lp(white(2.0), 120) * env_exp(secs(2.0), 2.2) * 0.6
    dsp.place(x, boom, 0.03)
    x = np.tanh(x * 1.6)
    y = dsp.verb(x, "concrete", wet=0.5, dry=1.0)[:, :len(x)]
    dsp.write(os.path.join(OUT, "door_slam.wav"), y, peak=0.95)
    print("door_slam.wav")


def door_rattle():
    D = 0.8
    x = np.zeros(secs(D))
    for t0 in [0.0, 0.07, 0.24, 0.3]:
        dsp.place(x, latch(rng.uniform(0.6, 1.0)), t0)
        k = lp(white(0.06), 400) * env_exp(secs(0.06), 80) * 0.6
        dsp.place(x, k, t0 + 0.01)
    y = dsp.verb(x, "small", wet=0.3, dry=1.0)[:, :len(x)]
    dsp.write(os.path.join(OUT, "door_rattle.wav"), y, peak=0.8)
    print("door_rattle.wav")


def threshold():
    D = 1.6
    n = secs(D)
    L = np.zeros(n)
    R = np.zeros(n)
    t = tt(D)
    # sub drone swelling under everything
    sub = np.sin(2 * np.pi * (31 + 6 * t / D) * t) * (t / D) ** 1.5 * 0.55
    L += sub
    R += sub
    # whispers, close, left and right, overlapping, getting faster
    for k in range(9):
        t0 = rng.uniform(0.05, 1.15)
        w = whisper(rng.uniform(0.25, 0.5), 50 + k) * rng.uniform(0.5, 0.9)
        p = rng.uniform(-1, 1)
        st = dsp.pan(w, p)
        dsp.place(L, st[0], t0)
        dsp.place(R, st[1], t0)
    # a wet breath right in your left ear
    br = bp(white(0.55), 300, 2400) * np.sin(np.linspace(0, np.pi, secs(0.55))) ** 3
    br *= 1 + 0.6 * np.sin(2 * np.pi * 11 * tt(0.55))
    dsp.place(L, br * 0.9, 0.25)
    dsp.place(R, br * 0.15, 0.25)
    # keys, right next to you, very close and very quiet
    j = jingle(7, 0.25, 2500, 6000, 0.5) * 0.35
    dsp.place(R, j, 0.7)
    dsp.place(L, j * 0.3, 0.705)
    # a reversed swell rising to the moment the lights snap on (1.35 s)
    sw_d = 1.0
    sw = (screech(sw_d, 1900) * 0.4 + lp(white(sw_d), 700) * 0.6) * np.linspace(0, 1, secs(sw_d)) ** 3
    dsp.place(L, sw * 0.8, 1.35 - sw_d)
    dsp.place(R, sw * 0.8, 1.35 - sw_d)
    st = np.vstack([L, R])
    st = np.array([np.tanh(c * 1.3) for c in st])
    y = dsp.verb(st[0] * 0.5 + st[1] * 0.5, "small", wet=0.2, dry=0.0)[:, :n] * 0.6 + st
    dsp.write(os.path.join(OUT, "threshold.wav"), y, peak=0.92)
    print("threshold.wav")


def threshold_hit():
    D = 2.4
    x = np.zeros(secs(D))
    t = tt(D)
    # dissonant metal cluster: three screeches a tritone and a minor second apart
    for f0, a in [(1480, 0.5), (2093, 0.45), (2217, 0.4), (740, 0.35)]:
        s = screech(D, f0) * np.exp(-t * 1.6) * a
        x += s
    # low saw cluster, like a brass section hit through a broken speaker
    cl = np.zeros(len(t))
    for f in [55.0, 58.3, 77.8, 82.4]:
        cl += dsp.osc(f, D, "saw") * 0.25
    x += lp(cl, 900) * np.exp(-t * 2.2)
    # the punch
    pt = tt(0.4)
    punch = np.sin(2 * np.pi * (45 + 120 * np.exp(-pt * 40)) * pt) * np.exp(-pt * 7) * 1.4
    dsp.place(x, punch, 0.0)
    dsp.place(x, hp(white(0.12), 1500) * env_exp(secs(0.12), 40) * 0.8, 0.0)
    x[:secs(0.002)] *= np.linspace(0, 1, secs(0.002))
    x = np.tanh(x * 2.2)
    y = dsp.verb(x, "concrete", wet=0.3, dry=1.0)[:, :len(x)]
    dsp.write(os.path.join(OUT, "threshold_hit.wav"), y, peak=0.97)
    print("threshold_hit.wav")


if __name__ == "__main__":
    door_open()
    door_slam()
    door_rattle()
    threshold()
    threshold_hit()
