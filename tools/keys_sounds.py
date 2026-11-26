"""Sector 1 sounds (the key rooms). All synthesized.

  key_hop_0..2.wav  one hop of a giant golden key: a bright clink and a jingle
  chase_keys.wav    loop: frantic shaken keys, metal hits, a pulsing low drone (when they come)
  amb_keys.wav      loop: an old hotel at night: ventilation hum, creaks, a muffled elevator
                    ding, and every so often a ring of keys shaken somewhere far away

  scare_keys.wav    the keys jumpscare: your scream in a dissonant cluster (forward, reversed, an
                    octave and a half down), metal screech, smashed keys, stutters; blown out

usage: python3 tools/keys_sounds.py [SCREAM_SOURCE.mp3]
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
from dsp import SR, bp, env_exp, hp, lp, osc, place, secs, tt, verb, white  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")
rng = np.random.default_rng(444)


def clink(f0=2400.0, d=0.45, bright=1.0):
    """One piece of metal against another: inharmonic partials, fast decay, a tick."""
    t = tt(d)
    x = np.zeros(len(t))
    for k, (ratio, amp, dec) in enumerate([(1.0, 1.0, 9), (1.47, 0.7, 12), (2.09, 0.55, 15), (2.76, 0.4, 19), (3.52, 0.28, 24), (4.61, 0.2, 30)]):
        f = f0 * ratio * rng.uniform(0.985, 1.015)
        x += amp * np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * np.exp(-t * dec * rng.uniform(0.8, 1.2))
    tick = hp(white(0.01), 3000) * env_exp(secs(0.01), 500) * 0.6 * bright
    x[:len(tick)] += tick
    return x


def jingle(n=7, span=0.18, f_lo=1800, f_hi=4200, d=0.6):
    x = np.zeros(secs(d + span))
    for _ in range(n):
        c = clink(rng.uniform(f_lo, f_hi), d * rng.uniform(0.5, 1.0), 0.6) * rng.uniform(0.25, 0.7)
        i = secs(rng.uniform(0, span))
        x[i:i + len(c)] += c[:len(x) - i]
    return x


def key_hops():
    for v in range(3):
        d = 0.7
        x = np.zeros(secs(d))
        thud = lp(white(0.08), 400) * env_exp(secs(0.08), 60) * 0.9          # the tip hits the carpet
        x[:len(thud)] += thud
        c = clink(rng.uniform(1700, 2300), 0.6) * 0.9
        x[secs(0.004):secs(0.004) + len(c)] += c[:len(x) - secs(0.004)]
        j = jingle(6, 0.12, 2200, 5000, 0.45) * 0.55
        x[secs(0.02):secs(0.02) + len(j)] += j[:len(x) - secs(0.02)]
        sc = screech(0.3, rng.uniform(2700, 3400)) * np.linspace(1, 0, secs(0.3)) ** 2 * 0.28
        x[secs(0.06):secs(0.06) + len(sc)] += sc[:len(x) - secs(0.06)]
        wh = whisper(0.45, v) * 0.5
        x[secs(0.1):secs(0.1) + len(wh)] += wh[:len(x) - secs(0.1)]
        y = verb(x, "small", wet=0.25, dry=1.0)[:, :len(x)]
        dsp.write(os.path.join(OUT, "key_hop_%d.wav" % v), y, peak=0.85)
    print("key_hop_0..2.wav")


def circ(fn, x, n):
    two = np.concatenate([x, x], axis=-1)
    return fn(two)[..., n:2 * n]


def chase():
    L = 8.0                     # 2 bars at 120 bpm
    n = secs(L)
    b = np.zeros((2, n))
    beat = 0.5
    for i in range(int(L / beat * 4)):
        tm = i * beat / 4
        accent = 1.0 if i % 4 == 0 else (0.55 if i % 2 == 0 else 0.35)
        j = jingle(4, 0.03, 2500, 6500, 0.18) * 0.35 * accent
        p = rng.uniform(-0.6, 0.6)
        place(b, np.vstack([j * (1 - p), j * (1 + p)]), tm)
    for i in range(int(L / beat)):
        tm = i * beat
        hit = clink(rng.choice([420, 470, 560]), 1.2, 1.0) * (0.9 if i % 2 == 0 else 0.5)
        if i % 4 == 0:
            k = dsp.kick(f_hi=110, f_lo=38, dur=0.5, click=0.3)
            hit[:len(k)] += k
        place(b, np.vstack([hit, hit]), tm, 0.6)
    t = np.arange(n) / SR
    drone = osc(np.full(n, round(46.25 * L) / L), kind="saw") * 0.5 + osc(np.full(n, round(69.3 * L) / L), kind="saw") * 0.3
    drone = circ(lambda v: lp(v, 220, 2), drone, n) * (0.55 + 0.45 * np.abs(np.sin(np.pi * t / beat)))
    b += np.vstack([drone, drone]) * 0.5
    knots = [880, 831, 932, 784, 880]
    f = np.interp(t, np.linspace(0, L, len(knots)), knots) * (1 + 0.012 * np.sin(2 * np.pi * 5.5 * t))
    wail = np.sin(2 * np.pi * np.cumsum(f) / SR) * (0.5 + 0.5 * np.sin(2 * np.pi * t / L * 2)) * 0.16
    b += np.vstack([wail, wail * 0.8])
    for i in range(10):
        w = whisper(rng.uniform(0.4, 0.9), 100 + i) * 0.35
        p = np.sin(i * 2.4)
        place(b, np.vstack([w * (1 - p), w * (1 + p)]), rng.uniform(0, L))
    b = circ(lambda v: verb(v, "concrete", wet=0.3, dry=1.0)[:, :v.shape[1]], b, n)
    dsp.write(os.path.join(OUT, "chase_keys.wav"), b, loop=True, peak=0.9)
    print("chase_keys.wav")


def ambience():
    L = 32.0
    n = secs(L)
    b = np.zeros((2, n))
    t = np.arange(n) / SR
    hum = osc(np.full(n, 60.0), kind="sin") * 0.25 + osc(np.full(n, 120.0), kind="sin") * 0.12
    air = circ(lambda v: lp(v, 500, 2), rng.standard_normal(n), n) * 0.35
    vent = (hum + air) * (0.85 + 0.15 * np.sin(2 * np.pi * t * (2 / L)))
    b += np.vstack([vent, vent * 0.95])
    # creaks of an old building
    for tm in [3.1, 11.7, 19.4, 27.0]:
        d = rng.uniform(0.5, 1.1)
        f = np.linspace(rng.uniform(180, 260), rng.uniform(120, 200), secs(d))
        c = bp(osc(f, kind="saw") * (rng.random(secs(d)) < 0.4), 150, 900) * np.sin(np.linspace(0, np.pi, secs(d))) * 0.25
        place(b, verb(c, "wood_hall", wet=0.6, dry=0.4)[:, :secs(d) + secs(1.5)], tm, 0.7)
    # a muffled elevator ding, floors away
    ding = np.zeros(secs(2.5))
    for f, a in [(880, 1.0), (1108, 0.6)]:
        ding += a * osc(np.full(len(ding), f), kind="sin") * env_exp(len(ding), 2.0)
    place(b, verb(lp(ding, 900, 2), "concrete", wet=0.9, dry=0.2), 15.0, 0.12)
    # keys, somewhere far away
    for tm in [7.5, 23.8]:
        j = jingle(12, 0.6, 1800, 4500, 0.8)
        place(b, verb(lp(j, 1800, 2), "far", wet=0.95, dry=0.15), tm, 0.35)
    b = np.array([circ(lambda v: hp(v, 30), b[c], n) for c in range(2)])
    dsp.write(os.path.join(OUT, "amb_keys.wav"), b, loop=True, peak=0.7)
    print("amb_keys.wav")


def screech(d, f0=2950.0):
    """Fork on a plate: close inharmonic partials, wobbling, roughened at ~47 Hz."""
    t = tt(d)
    wob = 1 + 0.03 * np.sin(2 * np.pi * 9.0 * t) + 0.01 * lp(rng.standard_normal(len(t)), 20) * 10
    x = np.zeros(len(t))
    for ratio, a in [(1.0, 1.0), (1.074, 0.8), (1.49, 0.55), (2.21, 0.35)]:
        x += a * np.sin(2 * np.pi * np.cumsum(f0 * ratio * wob) / SR)
    x *= 0.6 + 0.4 * np.sin(2 * np.pi * 47.0 * t)
    x += bp(white(d), 2500, 6000) * 0.25
    return x


def whisper(d, seed=0):
    """Breathy formant noise: a voice with no throat."""
    r = np.random.default_rng(seed)
    src = white(d) * (0.6 + 0.4 * lp(r.standard_normal(secs(d)), 4) * 6)
    tr = [(r.uniform(500, 900), 6, 1.0), (r.uniform(1100, 1900), 8, 0.7), (r.uniform(2400, 3200), 10, 0.4)]
    return dsp.formants(src, tr) * np.sin(np.linspace(0, np.pi, secs(d))) ** 2


def _load(path):
    import subprocess, tempfile, wave
    with tempfile.TemporaryDirectory() as d:
        w = os.path.join(d, "s.wav")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-ac", "1", "-ar", str(SR), w], check=True)
        f = wave.open(w)
        return np.frombuffer(f.readframes(f.getnframes()), dtype="<i2") / 32768.0


def _shift(x, semis):
    from scipy import signal as sg
    f = 2 ** (semis / 12.0)
    return sg.resample_poly(x, 1000, int(round(1000 * f)))


def scare_keys(src_path):
    D = 2.0
    n = secs(D)
    base = _load(src_path)
    env = np.abs(base) > 0.05
    on = np.where(env)[0]
    base = base[on[0]:on[-1]]
    out = np.zeros(n)
    # the scream as a dissonant cluster; one voice runs backwards
    for semis, gain, rev, delay in [(-4, 1.0, False, 0.0), (-7, 0.8, True, 0.02), (3, 0.55, False, 0.045), (-16, 0.9, False, 0.0), (-11, 0.5, True, 0.07)]:
        v = _shift(base[::-1] if rev else base, semis)
        i = secs(delay)
        m = min(n - i, len(v))
        out[i:i + m] += v[:m] * gain
    out += dsp.pad(np.pad(screech(1.8), (secs(0.05), 0)), n) * 0.45
    out += dsp.pad(np.pad(screech(1.5, 3730.0), (secs(0.3), 0)), n) * 0.3
    crash = jingle(26, 0.25, 1500, 6500, 0.9) * 1.4
    out += dsp.pad(crash, n)
    t = np.arange(n) / SR
    out += np.sin(2 * np.pi * 33.0 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 6.0 * t)) * 0.6   # throb you feel
    k = dsp.kick(f_hi=140, f_lo=32, dur=0.8, click=1.0) * 1.8
    out[:len(k)] += k
    # digital stutters: slices that repeat where they should not
    sl = secs(0.035)
    for at in [0.55, 0.9, 1.3, 1.62]:
        i = secs(at)
        piece = out[i:i + sl].copy()
        for r in range(1, rng.integers(3, 6)):
            j = i + r * sl
            if j + sl < n:
                out[j:j + sl] = piece * (1.0 - 0.1 * r)
    out[:secs(0.003)] *= np.linspace(0, 1, secs(0.003))
    out = out / (np.max(np.abs(out)) + 1e-9)
    out = np.tanh(out * 7.0) / np.tanh(7.0)
    out = np.clip(out * 1.3, -1, 1)
    st = np.vstack([out, np.roll(out, secs(0.004))])
    dsp.write(os.path.join(OUT, "scare_keys.wav"), st, peak=0.999)
    print("scare_keys.wav  rms %.1f dBFS" % (20 * np.log10(np.sqrt(np.mean(st ** 2)))))


if __name__ == "__main__":
    key_hops()
    chase()
    ambience()
    if len(sys.argv) > 1:
        scare_keys(sys.argv[1])
