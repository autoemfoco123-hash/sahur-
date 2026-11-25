"""Jumpscare scream from a recorded scream (the source file is not part of the repo).

  - trims the silence before the scream and cuts the last quarter of the scream itself
    (it ends mid-scream, hard)
  - pitches it down (varispeed: slower and heavier) and layers a copy an octave lower
  - blows it out: heavy saturation + brick-wall clip, normalized to full scale

  sounds/scare_scream.wav      the victim
  sounds/scare_scream_far.wav  what the other operatives hear, far down the hallway

usage: python3 tools/scream_from_file.py SOURCE.(mp3|wav) [semitones=-6] [cut=0.25]
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np
from scipy import signal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402

SR = dsp.SR
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")


def load(path):
    with tempfile.TemporaryDirectory() as d:
        wav = os.path.join(d, "in.wav")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-ac", "2", "-ar", str(SR), wav], check=True)
        w = wave.open(wav)
        a = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").reshape(-1, 2).T / 32768.0
    return a.astype(np.float64)


def scream_span(a, floor_db=-30.0, max_gap=0.12):
    """The longest continuous loud stretch (gaps under max_gap s are bridged)."""
    m = np.abs(a).max(0)
    blk = int(SR * 0.01)
    e = np.array([np.sqrt(np.mean(m[i:i + blk] ** 2)) for i in range(0, len(m), blk)])
    loud = 20 * np.log10(e + 1e-9) > 20 * np.log10(e.max() + 1e-9) + floor_db
    spans, start, gap = [], None, 0
    for i, on in enumerate(loud):
        if on:
            if start is None:
                start = i
            gap = 0
            end = i
        elif start is not None:
            gap += 1
            if gap * 0.01 > max_gap:
                spans.append((start, end))
                start = None
    if start is not None:
        spans.append((start, end))
    s, e2 = max(spans, key=lambda p: p[1] - p[0])
    return s * blk, (e2 + 1) * blk


def varispeed(a, semitones):
    """Pitch down by playing slower (tape style): length grows by the same factor."""
    f = 2 ** (semitones / 12.0)
    up, down = 1000, int(round(1000 * f))
    return signal.resample_poly(a, up, down, axis=1)


def blow_out(x, drive=7.0):
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = np.tanh(x * drive) / np.tanh(drive)
    x = np.clip(x * 1.3, -1.0, 1.0)
    return x / (np.max(np.abs(x)) + 1e-9) * 0.999


def main():
    src = sys.argv[1]
    semis = float(sys.argv[2]) if len(sys.argv) > 2 else -6.0
    cut = float(sys.argv[3]) if len(sys.argv) > 3 else 0.25
    a = load(src)
    s, e = scream_span(a)
    print("scream in source: %.2f s -> %.2f s, keeping %.2f s" % (s / SR, e / SR, (e - s) * (1.0 - cut) / SR))
    s = max(0, s - int(SR * 0.005))
    a = a[:, s:s + int((e - s) * (1.0 - cut))]
    main_v = varispeed(a, semis)
    low = varispeed(a, semis - 7.0)[:, :main_v.shape[1]]            # a fifth lower again, underneath
    sub = varispeed(a, semis - 12.0)[:, :main_v.shape[1]]           # and an octave down: the monster
    x = dsp.mix(main_v, low * 0.45, sub * 0.55)
    x = dsp.hp(x, 35)                                               # no useless rumble below hearing
    x = blow_out(x)
    x[:, :int(SR * 0.002)] *= np.linspace(0, 1, int(SR * 0.002))    # no click at the start
    x[:, -int(SR * 0.004):] *= np.linspace(1, 0, int(SR * 0.004))   # hard cut, just no click
    dsp.write(os.path.join(OUT, "scare_scream.wav"), x, peak=0.999)
    rms = 20 * np.log10(np.sqrt(np.mean(x ** 2)))
    print("scare_scream.wav  %.2f s  rms %.1f dBFS  clipped %.0f%%" % (x.shape[1] / SR, rms, 100 * np.mean(np.abs(x) > 0.98)))
    far = dsp.distant(x.mean(0) * 0.8, room="far", cutoff=1500, wet=0.85)
    dsp.write(os.path.join(OUT, "scare_scream_far.wav"), far, peak=0.85)
    print("scare_scream_far.wav  %.2f s" % (len(far) / SR))


if __name__ == "__main__":
    main()
