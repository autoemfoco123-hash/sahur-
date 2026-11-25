"""Tiny DSP toolkit for ROT's sound design. Everything is synthesized: no samples."""
import os
import struct

import numpy as np
from scipy import signal

SR = 44100
rng = np.random.default_rng(1337)


# ----------------------------------------------------------------- sources
def secs(d):
    return int(round(d * SR))


def tt(d):
    return np.arange(secs(d)) / SR


def white(d):
    return rng.standard_normal(secs(d))


def pink(d):
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    return signal.lfilter(b, a, white(d)) * 6.0


def brown(d):
    return signal.lfilter([1.0], [1.0, -0.997], white(d)) * 0.06


def saw_ph(ph):
    return 2.0 * (ph - np.floor(ph + 0.5))


def phase(freq):
    """Integrate an instantaneous frequency array into phase (cycles)."""
    return np.cumsum(np.asarray(freq, dtype=np.float64)) / SR


def osc(freq, d=None, kind="sin", ph0=0.0):
    if np.isscalar(freq):
        freq = np.full(secs(d), float(freq))
    p = phase(freq) + ph0
    if kind == "sin":
        return np.sin(2 * np.pi * p)
    if kind == "saw":
        return saw_ph(p)
    if kind == "sq":
        return np.sign(np.sin(2 * np.pi * p))
    if kind == "tri":
        return 2 * np.abs(saw_ph(p)) - 1
    raise ValueError(kind)


def glottal(freq, d=None, jitter=0.01, breath=0.08):
    """Voice source: bright pulse with jitter and breath noise."""
    if np.isscalar(freq):
        freq = np.full(secs(d), float(freq))
    n = len(freq)
    j = 1.0 + jitter * lp(rng.standard_normal(n), 30) * 4
    p = phase(freq * j)
    src = saw_ph(p) - 0.6 * saw_ph(p * 2 + 0.3) * 0.3
    src = hp(src, 80)
    return src + breath * rng.standard_normal(n)


# ----------------------------------------------------------------- filters
def _sos(kind, f, order=2):
    nyq = SR * 0.49
    if kind == "bp":
        lo, hi = max(20.0, f[0]), min(nyq, f[1])
        return signal.butter(order, [lo, hi], "bandpass", fs=SR, output="sos")
    return signal.butter(order, min(max(f, 10.0), nyq), {"lp": "low", "hp": "high"}[kind], fs=SR, output="sos")


def lp(x, f, order=2):
    return signal.sosfilt(_sos("lp", f, order), x, axis=-1)


def hp(x, f, order=2):
    return signal.sosfilt(_sos("hp", f, order), x, axis=-1)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bp", (lo, hi), order), x, axis=-1)


def reson(x, f, q):
    b, a = signal.iirpeak(min(f, SR * 0.45), q, fs=SR)
    return signal.lfilter(b, a, x)


def tvf(x, freq, kind="lp", q=4.0, block=256):
    """Time-varying filter: per-block coefficients, state carried across blocks."""
    x = np.asarray(x, dtype=np.float64)
    freq = np.broadcast_to(np.asarray(freq, dtype=np.float64), x.shape)
    out = np.zeros_like(x)
    zi = None
    for i in range(0, len(x), block):
        f = float(np.mean(freq[i:i + block]))
        f = min(max(f, 20.0), SR * 0.45)
        if kind == "bp":
            b, a = signal.iirpeak(f, q, fs=SR)
        elif kind == "lp":
            b, a = signal.butter(2, f, "low", fs=SR)
        else:
            b, a = signal.butter(2, f, "high", fs=SR)
        if zi is None:
            zi = np.zeros(max(len(a), len(b)) - 1)
        out[i:i + block], zi = signal.lfilter(b, a, x[i:i + block], zi=zi)
    return out


def formants(src, tracks, block=256):
    """Parallel formant filter bank. tracks = [(freq_array_or_scalar, q, gain), ...]."""
    y = np.zeros_like(src)
    for f, q, g in tracks:
        y += tvf(src, f, "bp", q, block) * g
    return y


VOWELS = {
    "a": [(800, 8, 1.0), (1150, 10, 0.6), (2900, 14, 0.25)],
    "e": [(400, 8, 1.0), (2000, 12, 0.5), (2600, 14, 0.3)],
    "i": [(300, 8, 1.0), (2300, 14, 0.4), (3000, 16, 0.3)],
    "o": [(450, 8, 1.0), (800, 10, 0.6), (2830, 14, 0.15)],
    "u": [(350, 8, 1.0), (650, 10, 0.5), (2400, 14, 0.12)],
}


def vowel(src, v):
    return formants(src, VOWELS[v])


# ----------------------------------------------------------------- envelopes / shaping
def env_exp(n, rate):
    return np.exp(-np.arange(n) / SR * rate)


def adsr(n, a=0.01, d=0.1, s=0.7, r=0.2):
    e = np.full(n, s)
    na, nd, nr = secs(a), secs(d), secs(r)
    na = min(na, n)
    e[:na] = np.linspace(0, 1, na, endpoint=False)
    if na + nd < n:
        e[na:na + nd] = np.linspace(1, s, nd, endpoint=False)
    if nr > 0 and nr < n:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def fades(x, fi=0.003, fo=0.02):
    x = np.array(x, dtype=np.float64)
    n = x.shape[-1]
    a, b = min(secs(fi), n), min(secs(fo), n)
    if a > 0:
        x[..., :a] *= np.linspace(0, 1, a)
    if b > 0:
        x[..., -b:] *= np.linspace(1, 0, b)
    return x


def sat(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def crush(x, bits=8, down=4):
    y = np.repeat(x[::down], down)[: len(x)]
    q = 2 ** (bits - 1)
    return np.round(y * q) / q


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) + 1e-12
    return x * (peak / m)


def rms_norm(x, rms=0.1):
    r = np.sqrt(np.mean(x ** 2)) + 1e-12
    return x * (rms / r)


def pad(x, n):
    if x.shape[-1] >= n:
        return x[..., :n]
    w = [(0, 0)] * (x.ndim - 1) + [(0, n - x.shape[-1])]
    return np.pad(x, w)


def mix(*parts):
    n = max(p.shape[-1] for p in parts)
    return sum(pad(p, n) for p in parts)


def place(buf, x, t, gain=1.0):
    """Add x into buf at time t (wraps around: perfect loops)."""
    i = secs(t) % buf.shape[-1]
    n = x.shape[-1]
    L = buf.shape[-1]
    end = i + n
    if end <= L:
        buf[..., i:end] += x * gain
    else:
        k = L - i
        buf[..., i:] += x[..., :k] * gain
        rest = x[..., k:]
        while rest.shape[-1] > 0:
            m = min(L, rest.shape[-1])
            buf[..., :m] += rest[..., :m] * gain
            rest = rest[..., m:]
    return buf


def resample(x, ratio):
    """ratio > 1 = higher pitch / shorter."""
    n = int(len(x) / ratio)
    idx = np.arange(n) * ratio
    return np.interp(idx, np.arange(len(x)), x)


def varispeed(x, speed):
    """Time-varying playback speed (array same length as output wanted)."""
    pos = np.cumsum(speed)
    pos = pos[pos < len(x) - 1]
    return np.interp(pos, np.arange(len(x)), x)


def loopify(x, xf=0.8):
    """Equal-power crossfade of the tail into the head."""
    n = secs(xf)
    body = x[..., :-n].copy()
    tail = x[..., -n:]
    w = np.linspace(0, np.pi / 2, n)
    body[..., :n] = body[..., :n] * np.sin(w) + tail * np.cos(w)
    return body


def stereo(x, width=0.0, delay_ms=0.0):
    l = x.copy()
    r = x.copy()
    if delay_ms > 0:
        d = secs(delay_ms / 1000)
        r = np.concatenate([np.zeros(d), r[:-d]])
    return np.vstack([l * (1 - width * 0.3), r * (1 + width * 0.3)])


def pan(x, p):
    """p in [-1, 1]."""
    a = (p + 1) * np.pi / 4
    return np.vstack([x * np.cos(a), x * np.sin(a)])


# ----------------------------------------------------------------- reverb
_IR_CACHE = {}


def make_ir(name, rt_lo, rt_hi, length=None, predelay=0.012, er=18, er_span=0.06, er_gain=2.5, seed=0):
    """Synthetic stereo impulse response with frequency-dependent decay + early reflections."""
    key = (name, rt_lo, rt_hi)
    if key in _IR_CACHE:
        return _IR_CACHE[key]
    g = np.random.default_rng(seed + hash(name) % 1000)
    length = length or max(rt_lo, rt_hi) * 1.1
    n = secs(length)
    t = np.arange(n) / SR
    chans = []
    for c in range(2):
        w = g.standard_normal(n)
        lo, mid, hi = lp(w, 400), bp(w, 400, 3500), hp(w, 3500)
        rt_mid = (rt_lo + rt_hi) / 2
        y = lo * np.exp(-t * 6.9 / rt_lo) + mid * np.exp(-t * 6.9 / rt_mid) + hi * np.exp(-t * 6.9 / rt_hi)
        y *= 1 - np.exp(-t * 300)
        for _ in range(er):
            d = g.uniform(0.003, er_span)
            i = secs(d)
            if i < n:
                y[i] += g.uniform(-1, 1) * er_gain * (1 - d / er_span * 0.7)
        y = np.concatenate([np.zeros(secs(predelay)), y])[:n]
        chans.append(y)
    ir = np.array(chans)
    ir /= np.sqrt(np.sum(ir ** 2) / 2)
    _IR_CACHE[key] = ir
    return ir


ROOMS = {
    "wood_hall": (1.4, 0.7),
    "concrete": (2.8, 1.4),
    "tile": (1.6, 1.2),
    "cathedral": (6.0, 3.2),
    "outdoor": (0.9, 0.3),
    "space": (8.0, 5.0),
    "small": (0.5, 0.3),
    "far": (3.5, 1.2),
}


def verb(x, room="concrete", wet=0.3, dry=1.0, out_stereo=True):
    rt_lo, rt_hi = ROOMS[room]
    ir = make_ir(room, rt_lo, rt_hi)
    if x.ndim == 1:
        chans = [signal.fftconvolve(x, ir[c]) for c in range(2)]
        w = np.array(chans)
        d = np.vstack([x, x])
    else:
        w = np.array([signal.fftconvolve(x[c], ir[c]) for c in range(2)])
        d = x
    y = mix(d * dry, w * wet)
    if not out_stereo:
        return y.mean(axis=0)
    return y


def distant(x, room="far", cutoff=1800, wet=0.9):
    """Something far away: dull, mostly reverb."""
    return verb(lp(x, cutoff, 2), room, wet=wet, dry=0.25, out_stereo=False)


# ----------------------------------------------------------------- drums / tonal helpers
def kick(f_hi=150, f_lo=45, dur=0.5, click=0.6):
    t = tt(dur)
    f = f_lo + (f_hi - f_lo) * np.exp(-t * 30)
    y = osc(f, kind="sin") * env_exp(len(t), 7)
    y += hp(white(dur), 1500) * env_exp(len(t), 300) * click
    return sat(y, 1.5)


def snare(dur=0.3, body=190):
    t = tt(dur)
    n = bp(white(dur), 1200, 9000) * env_exp(len(t), 18)
    b = osc(body, dur) * env_exp(len(t), 25) * 0.7
    return sat(n + b, 1.8)


def hat(dur=0.06, open_=False):
    t = tt(dur)
    return hp(white(dur), 7000) * env_exp(len(t), 25 if open_ else 90)


def tom(f=110, dur=0.5):
    t = tt(dur)
    fr = f * (1 + 0.5 * np.exp(-t * 20))
    return sat(osc(fr, kind="sin") * env_exp(len(t), 8) + lp(white(dur), 1500) * env_exp(len(t), 60) * 0.3, 1.4)


def bass808(f, dur=0.6, glide=0.0):
    t = tt(dur)
    fr = f * (1 + glide * np.exp(-t * 12))
    return sat(osc(fr, kind="sin") * adsr(len(t), 0.004, 0.2, 0.6, 0.1), 2.5)


def note_hz(semi_from_a4):
    return 440.0 * 2 ** (semi_from_a4 / 12)


# ----------------------------------------------------------------- output
def write(path, x, loop=False, peak=0.89, rms=None):
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        x = x[None, :]
    x = x - x.mean(axis=1, keepdims=True) * 0
    if rms is not None:
        x = rms_norm(x, rms)
        x = np.tanh(x / peak) * peak if np.max(np.abs(x)) > peak else x
    else:
        x = norm(x, peak)
    if not loop:
        x = fades(x, 0.0005, 0.01)
    ch, n = x.shape
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").T.copy()
    fmt = struct.pack("<HHIIHH", 1, ch, SR, SR * ch * 2, ch * 2, 16)
    body = b"WAVE" + b"fmt " + struct.pack("<I", 16) + fmt
    body += b"data" + struct.pack("<I", data.nbytes) + data.tobytes()
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, n - 1, 0, 0)
        body += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body)) + body)
