"""sahur menu theme: containment-facility dark ambient (original composition).

A 64 s seamless loop (every event is placed into a circular buffer, so reverb tails wrap):
  - sub drone on A1 with a buried tritone, slowly breathing filter
  - dissonant pad clusters that drift every 16 s (detuned saws, dark low-pass)
  - an old, out-of-tune piano playing a slow motif far away in a huge hall
  - a containment door slamming somewhere deep in the facility
  - a two-tone alarm heard through concrete walls
  - radio crackle and air

  sounds/amb_menu.wav   (stereo, loops: 'amb_' prefix = looping ambience in Audio)

usage: python3 tools/menu_music.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
from dsp import SR, bp, env_exp, hp, kick, lp, note_hz, osc, place, secs, tt, verb, white  # noqa: E402

L = 64.0
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds", "amb_menu.wav")
N = secs(L)
rng = np.random.default_rng(301)


def hz(name):
    """'A4', 'C#3', 'Bb2' -> Hz."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    n = names[name[0]]
    i = 1
    if name[1] == "#":
        n += 1
        i = 2
    elif name[1] == "b":
        n -= 1
        i = 2
    octave = int(name[i:])
    return note_hz(n + (octave - 4) * 12)


def loop_f(f):
    """Nearest frequency with a whole number of cycles in the loop (no click at the seam)."""
    return round(f * L) / L


def buf():
    return np.zeros((2, N))


def circ(fn, x):
    """Apply a filter / reverb as if the loop played forever: run it over two copies and keep
    the second one, so filter state and reverb tails wrap across the seam."""
    two = np.concatenate([x, x], axis=-1)
    y = fn(two)
    return y[..., N:2 * N]


# ------------------------------------------------------------------ layers
def drone():
    t = np.arange(N) / SR
    b = buf()
    for ch, det in enumerate([0.0, 0.4]):
        f1 = loop_f(55.0 + det)
        x = osc(np.full(N, f1), kind="sin") * 0.9
        x += osc(np.full(N, loop_f(55.0 * 1.003 + det)), kind="saw") * 0.35
        x += osc(np.full(N, loop_f(110.0 - det)), kind="saw") * 0.12
        x += osc(np.full(N, loop_f(77.78 + det * 0.5)), kind="sin") * 0.16    # the tritone, buried
        cut = 140 + 90 * (0.5 + 0.5 * np.sin(2 * np.pi * t * (3 / L) + ch))  # breathing filter
        x = circ(lambda v: dsp.tvf(v, np.concatenate([cut, cut]), "lp", 0.7), x)
        x *= 0.75 + 0.25 * np.sin(2 * np.pi * t * (5 / L) + ch * 1.7)
        b[ch] = x
    return b * 0.55


def saw_voice(f, d, detune_cents):
    k = 2 ** (detune_cents / 1200)
    return osc(np.full(secs(d), f * k), kind="saw")


def pad():
    chords = [
        ["A2", "C3", "E3", "Bb3"],       # minor with a flat second leaning on it
        ["F2", "Ab2", "C3", "E3"],       # minor-major seventh: wrong, beautiful
        ["D2", "F2", "Ab2", "B2"],       # diminished: something is loose
        ["E2", "G#2", "D3", "F3"],       # dominant with a flat ninth: it never resolves
    ]
    b = buf()
    seg = L / len(chords)
    d = seg + 8.0
    for i, ch in enumerate(chords):
        voice = np.zeros((2, secs(d)))
        for note in ch:
            f = hz(note)
            for c, cents in enumerate([-9, 7]):
                v = saw_voice(f, d, cents + rng.uniform(-2, 2)) + saw_voice(f * 2, d, -cents) * 0.25
                voice[c] += v
        e = dsp.adsr(voice.shape[1], a=4.5, d=1.0, s=1.0, r=6.0)
        voice = np.array([lp(voice[c], 700, 2) for c in range(2)]) * e
        place(b, voice, i * seg - 2.0, 0.07)
    return circ(lambda v: verb(v, "cathedral", wet=0.45, dry=0.8)[:, :v.shape[1]], b)


def piano_note(f, d=7.0):
    t = tt(d)
    x = np.zeros(len(t))
    for k in range(1, 9):
        fk = f * k * np.sqrt(1 + 0.0004 * k * k)          # stiff strings: inharmonic
        x += np.sin(2 * np.pi * fk * t + rng.uniform(0, 6)) * (1.0 / k ** 1.3) * np.exp(-t * (0.6 + 0.55 * k))
    x += np.sin(2 * np.pi * f * 1.004 * t) * 0.3 * np.exp(-t * 0.7)   # a second string, out of tune
    hammer = bp(white(0.05), 1500, 6000) * env_exp(secs(0.05), 90) * 0.3
    x[:len(hammer)] += hammer
    return lp(x, 3200, 2)


def piano():
    # (time, note): slow, sparse, never quite going where you expect
    motif = [
        (1.0, "A4"), (3.6, "C5"), (6.0, "B4"), (8.9, "G#4"),
        (14.0, "E5"), (16.4, "F5"), (18.6, "E5"), (21.5, "C5"),
        (26.0, "A4"), (28.4, "Bb4"), (30.6, "A4"), (33.8, "E4"),
        (38.0, "D5"), (40.2, "F5"), (42.8, "G#4"),
        (47.5, "A4"), (49.9, "C5"), (52.1, "B4"), (54.6, "F4"), (58.4, "E4"),
    ]
    b = buf()
    for tm, n in motif:
        x = piano_note(hz(n) * 0.5 if n.endswith("5") and rng.random() < 0.3 else hz(n))
        pan = rng.uniform(-0.35, 0.35)
        st = np.vstack([x * (1 - pan), x * (1 + pan)]) * 0.5
        place(b, st, tm + rng.uniform(-0.05, 0.05), 0.55)
    # far away in a huge hall: mostly reverb, top end gone
    def far(v):
        w = verb(v, "space", wet=0.9, dry=0.35)[:, :v.shape[1]]
        return np.array([lp(w[c], 2400, 2) for c in range(2)])
    return circ(far, b)


def door_slam():
    d = 7.0
    x = np.zeros(secs(d))
    k = kick(f_hi=95, f_lo=28, dur=2.5, click=0.4) * 1.4
    x[:len(k)] += k
    clang = np.zeros(secs(3.0))
    for f, a in [(87, 1.0), (191, 0.7), (293, 0.6), (467, 0.45), (733, 0.3), (1109, 0.2)]:
        clang += a * osc(np.full(len(clang), f), kind="sin")
    clang *= env_exp(len(clang), 2.2) * 0.4
    x[:len(clang)] += clang
    rattle = bp(white(1.2), 300, 2500) * env_exp(secs(1.2), 6) * 0.35
    x[secs(0.04):secs(0.04) + len(rattle)] += rattle
    x = lp(x, 900, 2)
    return verb(x, "space", wet=1.0, dry=0.4)


def alarm():
    d = 9.0
    t = tt(d)
    f = np.where((t * 1.25) % 1.0 < 0.5, 620.0, 465.0)
    x = osc(f, kind="sq") * 0.5 + osc(f * 1.5, kind="saw") * 0.2
    x *= np.clip(np.minimum(t / 1.5, (d - t) / 2.5), 0, 1)
    x = lp(hp(x, 200), 650, 2)                      # heard through concrete
    return verb(x, "concrete", wet=0.9, dry=0.3)


def crackle():
    b = buf()
    for _ in range(26):
        tm = rng.uniform(0, L)
        d = rng.uniform(0.15, 0.9)
        x = bp(white(d), 900, 5000) * (rng.random(secs(d)) < 0.08) * 1.5
        x += bp(white(d), 1500, 3000) * 0.12
        x *= np.sin(np.linspace(0, np.pi, secs(d)))
        p = rng.uniform(-0.8, 0.8)
        place(b, np.vstack([x * (1 - p), x * (1 + p)]), tm, 0.05)
    air = np.vstack([circ(lambda v: lp(v, 600), rng.standard_normal(N)) for _ in range(2)]) * 0.12
    return b + air


def main():
    music = buf()
    music += drone()
    music += pad()
    music += piano()
    for tm, g in [(6.5, 0.55), (33.0, 0.4), (55.5, 0.5)]:
        place(music, door_slam(), tm, g)
    place(music, alarm(), 40.0, 0.12)
    music += crackle()
    music = np.array([circ(lambda v: hp(v, 25), music[c]) for c in range(2)])
    rms = np.sqrt(np.mean(music ** 2))
    music *= 10 ** (-17 / 20) / rms
    music = np.tanh(music / 0.9) * 0.9
    dsp.write(OUT, music, loop=True, peak=0.9, rms=None)
    seam = np.abs(music[:, 0] - music[:, -1]).max()
    print("loop seam jump %.4f (typical step %.4f)" % (seam, np.percentile(np.abs(np.diff(music[0])), 99)))
    print("amb_menu.wav  %.1f s  rms %.1f dBFS" % (music.shape[1] / SR, 20 * np.log10(np.sqrt(np.mean(music ** 2)))))


if __name__ == "__main__":
    main()
