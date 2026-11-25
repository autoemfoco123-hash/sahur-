"""The jumpscare scream: a deep wooden TUNG, an impact, and a scream blown past the speakers.

Layers: wooden knock + sub boom + metal crash at t=0, then three voices (a human scream
gliding up with vibrato, a growling octave below, an inhuman shriek on top) and breath hiss.
Everything is driven through hard saturation, a light bitcrush and a brick-wall clip, then
normalized to full scale: as loud as digital audio goes. The end is cut, not faded.

  sounds/scare_scream.wav      the victim (stereo, ~2.2 s)
  sounds/scare_scream_far.wav  what the other operatives hear, far down the hallway

usage: python3 tools/scream.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
from dsp import SR, bp, crush, distant, env_exp, formants, glottal, hp, kick, lp, osc, sat, secs, stereo, tt, white  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")
D = 2.25


def smooth(a, b, t):
    x = np.clip((t - a) / (b - a), 0.0, 1.0)
    return x * x * (3 - 2 * x)


def scream_voice(seed):
    dsp.rng = np.random.default_rng(seed)
    t = tt(D)
    # pitch: snaps up, holds with a wide vibrato, breaks upward at the end
    f0 = 430 + 240 * (1 - np.exp(-t * 14)) + 110 * smooth(1.55, 2.1, t)
    wob = lp(dsp.rng.standard_normal(len(t)), 6) * 9.0
    f0 = f0 * (1 + 0.055 * np.sin(2 * np.pi * 7.3 * t) + 0.03 * wob)
    # "AAAAH" opening into "EEEH": formant tracks
    m = smooth(0.15, 1.2, t)
    f1 = 880 - 220 * m
    f2 = 1250 + 700 * m
    f3 = 2900 + 300 * m
    v1 = formants(glottal(f0, jitter=0.05, breath=0.06), [(f1, 6, 1.0), (f2, 8, 0.75), (f3, 10, 0.45), (4200, 6, 0.2)])
    # growl an octave down, amplitude-roughened
    g = glottal(f0 * 0.5 * 1.008, jitter=0.08, breath=0.08)
    v2 = formants(g, [(f1 * 0.9, 5, 1.0), (f2 * 0.85, 7, 0.6), (2600, 8, 0.3)])
    v2 *= 1.0 + 0.85 * np.sin(2 * np.pi * 37 * t + 3 * np.sin(2 * np.pi * 3.1 * t))
    # inhuman shriek on top
    sh = osc(f0 * 3.97 + 260 * np.sin(2 * np.pi * 13 * t), kind="saw")
    sh = bp(sh, 1800, 7000) * (0.6 + 0.4 * np.sin(2 * np.pi * 21 * t))
    hiss = bp(white(D), 1500, 8000)
    x = v1 * 1.0 + v2 * 0.6 + sh * 0.22 + hiss * 0.05
    # instant attack, no fade at the end: it is cut
    x *= np.minimum(1.0, t / 0.004)
    return x


def impact():
    t = tt(D)
    k = kick(f_hi=190, f_lo=36, dur=1.2, click=1.2) * 1.9
    # deep wooden TUNG (the log itself)
    wood = osc(125 * (1 + 0.5 * np.exp(-tt(0.9) * 40)), kind="sin") * env_exp(secs(0.9), 9)
    wood += bp(white(0.9), 250, 1400) * env_exp(secs(0.9), 28) * 0.8
    wood = sat(wood * 2.0, 2.0)
    # metal crash: inharmonic partials
    metal = np.zeros(secs(1.6))
    for f, a in [(523, 1.0), (1187, 0.8), (1795, 0.7), (2533, 0.6), (3301, 0.5), (4410, 0.35), (5873, 0.25)]:
        metal += a * osc(f * (1 + 0.002 * np.sin(2 * np.pi * 5 * tt(1.6))), kind="sin")
    metal *= env_exp(len(metal), 4.5) * 0.35
    burst = hp(white(0.4), 600) * env_exp(secs(0.4), 22) * 1.2
    out = np.zeros(len(t))
    for part, g in [(k, 1.0), (wood, 1.2), (metal, 1.0), (burst, 1.0)]:
        out[:len(part)] += part[:len(out)] * g
    return out


def blow_out(x):
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = sat(x * 2.7, 4.0)                       # speaker-shredding saturation
    x = 0.85 * x + 0.15 * crush(x, bits=8, down=2)
    x = np.clip(x * 1.35, -1.0, 1.0)            # brick wall
    return x


def main():
    os.makedirs(OUT, exist_ok=True)
    hit = impact()
    l = scream_voice(11) + hit * 0.9
    r = scream_voice(23) + hit * 0.9
    l, r = blow_out(l), blow_out(r)
    st = np.vstack([l, r])
    st = st / (np.max(np.abs(st)) + 1e-9) * 0.999
    dsp.write(os.path.join(OUT, "scare_scream.wav"), st, peak=0.999)
    rms = 20 * np.log10(np.sqrt(np.mean(st ** 2)))
    print("scare_scream.wav  %.2f s  rms %.1f dBFS  peak 0 dBFS" % (st.shape[1] / SR, rms))
    # far away: someone else screaming somewhere in the office
    far = distant(blow_out(scream_voice(5) + hit * 0.5) * 0.8, room="far", cutoff=1600, wet=0.85)
    dsp.write(os.path.join(OUT, "scare_scream_far.wav"), far, peak=0.85)
    print("scare_scream_far.wav")


if __name__ == "__main__":
    main()
