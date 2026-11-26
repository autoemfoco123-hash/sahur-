"""Rebuild a recording's soundtrack from tools/gameplay_rec.gd's audio log.

Every frame the recorder logs every playing sound (stream, volume, pitch, bus, 3D position)
plus the listener, bus mutes and master effects. Here each sound is mixed from its WAV at the
moment it started, in game time:
  - 2D: volume_db as logged
  - 3D: Godot's inverse-distance model (unit_size, max_distance, max_db 3), stereo pan from
    the listener's right vector, muffled (low-pass) while occluded
  - SFX bus -> reverb, Amb bus, Master bus (the jumpscare scream bypasses everything)
  - bus mutes (the silence before the scream), madness low-pass on the master

usage: python3 tools/mix_log.py REC_DIR/audio.jsonl OUT.wav [fps=30]
"""
import json
import os
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LOOP_PREFIXES = ("amb_", "chase_")
LOOPS = {"breath", "engine", "jet", "musicbox", "roll", "static", "fridge_hum", "death_drone", "nv_hum"}


def is_loop(path):
    name = os.path.splitext(os.path.basename(path))[0]
    return name in LOOPS or name.startswith(LOOP_PREFIXES)


_cache = {}


def load(path):
    if path in _cache:
        return _cache[path]
    f = os.path.join(ROOT, path.replace("res://", ""))
    w = wave.open(f)
    ch, rate = w.getnchannels(), w.getframerate()
    a = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").reshape(-1, ch).T / 32768.0
    if ch == 1:
        a = np.vstack([a, a])
    if rate != SR:
        a = np.array([np.interp(np.arange(int(a.shape[1] * SR / rate)) * rate / SR, np.arange(a.shape[1]), c) for c in a])
    _cache[path] = a
    return a


def repitch(a, p):
    if abs(p - 1.0) < 1e-3:
        return a
    n = int(a.shape[1] / p)
    idx = np.arange(n) * p
    return np.array([np.interp(idx, np.arange(a.shape[1]), c) for c in a])


def per_sample(vals, spf, n):
    """Frame values -> per-sample (linear interpolation between frame centres)."""
    x = np.arange(len(vals)) * spf + spf / 2
    return np.interp(np.arange(n), x, vals)


def main():
    log_path, out = sys.argv[1], sys.argv[2]
    fps = float(sys.argv[3]) if len(sys.argv) > 3 else 30.0
    frames = [json.loads(l) for l in open(log_path) if l.strip()]
    F = len(frames)
    spf = int(round(SR / fps))
    N = F * spf
    lst = []
    last = [0, 0, 0, 1, 0, 0]
    for fr in frames:
        if fr["L"]:
            last = fr["L"]
        lst.append(last)
    lst = np.array(lst, dtype=np.float64)
    tracks = {}
    for fi, fr in enumerate(frames):
        for r in fr["P"]:
            t = tracks.setdefault(r["id"], {"s": r["s"], "k": r["k"], "b": r["b"], "p": r["p"], "f0": fi, "off": r.get("off", 0.0), "rows": {}})
            t["rows"][fi] = r
    buses = {"SFX": np.zeros((2, N)), "Amb": np.zeros((2, N)), "Master": np.zeros((2, N))}
    for tid, t in tracks.items():
        src = repitch(load(t["s"]), t["p"])
        loop = is_loop(t["s"])
        f0 = t["f0"]
        if loop:
            f1 = max(t["rows"]) + 1
            n = (f1 - f0) * spf
            start = int(t["off"] * SR / t["p"]) % src.shape[1]
            idx = (start + np.arange(n)) % src.shape[1]
            seg = src[:, idx]
        else:
            seg = src
            n = seg.shape[1]
            f1 = min(F, f0 + int(np.ceil(n / spf)) + 1)
        n = min(n, N - f0 * spf)
        if n <= 0:
            continue
        seg = seg[:, :n]
        # per-frame gain (and pan / occlusion for 3D); missing frames keep the last known row
        gl, gr, occ = [], [], []
        row = t["rows"][f0]
        for fi in range(f0, f0 + int(np.ceil(n / spf))):
            fi_c = min(fi, F - 1)
            row = t["rows"].get(fi, row)
            if t["k"] == "2d":
                g = 10 ** (row["v"] / 20)
                gl.append(g)
                gr.append(g)
                occ.append(0.0)
            else:
                L = lst[fi_c]
                pos = np.array(row["x"])
                d = pos - L[:3]
                dist = np.linalg.norm(d) + 1e-6
                if dist > row["md"]:
                    gl.append(0.0)
                    gr.append(0.0)
                else:
                    att = 20 * np.log10(1.0 / (dist / row["us"] + 1e-6)) + row["v"]
                    g = 10 ** (min(att, 3.0) / 20)
                    pan = float(np.clip(np.dot(d, L[3:6]) / dist, -1, 1))
                    th = (pan + 1) * np.pi / 4
                    gl.append(g * min(1.0, np.sqrt(2) * np.cos(th)))
                    gr.append(g * min(1.0, np.sqrt(2) * np.sin(th)))
                occ.append(1.0 if row.get("c", 9000) < 2000 else 0.0)
        GL = per_sample(gl, spf, n)
        GR = per_sample(gr, spf, n)
        if t["k"] == "3d" and max(occ) > 0:
            O = per_sample(occ, spf, n)
            muff = np.array([dsp.lp(c, 700, 2) for c in seg])
            seg = seg * (1 - O) + muff * O
        y = np.vstack([seg[0] * GL, seg[1] * GR])
        bus = t["b"] if t["b"] in buses else "Master"
        a = f0 * spf
        buses[bus][:, a:a + n] += y
    # SFX reverb (the level's room)
    wet = np.mean([fr["fx"][2] for fr in frames])
    sfx = buses["SFX"]
    rv = dsp.verb(sfx, "concrete", wet=wet * 1.4, dry=1.0)[:, :N]
    # bus mutes, frame by frame (5 ms ramps)
    ramp = int(SR * 0.005)

    def mask(col):
        m = np.array([0.0 if fr["B"][col] else 1.0 for fr in frames])
        s = np.repeat(m, spf)[:N]
        k = np.ones(ramp) / ramp
        return np.convolve(s, k, mode="same")

    mix = rv * mask(1) + buses["Amb"] * mask(2) + buses["Master"]
    mix *= mask(0)
    # master: volume, madness low-pass + drive
    vol = 10 ** (np.mean([fr["B"][3] for fr in frames]) / 20)
    mix *= vol
    cut = per_sample([min(19000.0, fr["fx"][1]) for fr in frames], spf, N)
    if cut.min() < 18000:
        mix = np.array([dsp.tvf(c, cut, "lp", 0.7) for c in mix])
    drive = per_sample([fr["fx"][0] for fr in frames], spf, N)
    if drive.max() > 0.01:
        k = 1 + drive * 6
        mix = np.tanh(mix * k) / np.tanh(k)
    mix = np.clip(mix, -1, 1)
    data = (mix * 32767).astype("<i2").T.copy()
    w = wave.open(out, "wb")
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(data.tobytes())
    w.close()
    print("%s  %.1f s  %d sounds  peak %.2f" % (out, N / SR, len(tracks), np.abs(mix).max()))


if __name__ == "__main__":
    main()
