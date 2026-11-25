"""ROT sounds, part A: player foley, UI, jumpscares, brainrot voices & SFX."""
import numpy as np

from dsp import *  # noqa: F401,F403
from dsp import rng

SOUNDS = {}


def sound(name, loop=False, peak=0.89, rms=None):
    def deco(fn):
        SOUNDS[name] = (fn, loop, peak, rms)
        return fn
    return deco


# ================================================================= FOOTSTEPS
def _heel_toe(d, thump_f, thump_amt, click_f, click_amt, toe_delay):
    n = secs(d)
    t = tt(d)
    y = np.zeros(n)
    for k, (delay, g) in enumerate([(0.0, 1.0), (toe_delay, 0.45)]):
        i = secs(delay)
        m = n - i
        tk = t[:m]
        hit = osc(thump_f * (1 + 0.6 * np.exp(-tk * 60)), kind="sin") * np.exp(-tk * 45) * thump_amt
        hit += lp(white(m / SR), 900) * np.exp(-tk * 70) * thump_amt * 0.8
        hit += bp(white(m / SR), click_f * 0.6, min(click_f * 2.2, 20000)) * np.exp(-tk * 160) * click_amt
        y[i:] += hit * g
    return y


def step_variant(surface, v):
    r = np.random.default_rng(hash((surface, v)) % 10000)
    j = lambda a, b: r.uniform(a, b)
    d = 0.45
    if surface == "wood":
        y = _heel_toe(d, j(80, 110), 1.0, j(1800, 2600), 0.5, j(0.05, 0.08))
        y += reson(white(d), j(220, 320), 6) * env_exp(secs(d), 18) * 0.5  # hollow floor
        if v % 2 == 0:  # creak
            t = tt(0.3)
            pulses = (np.sin(2 * np.pi * phase(j(30, 60) + 20 * np.sin(2 * np.pi * 2 * t))) > 0.97).astype(float)
            cr = reson(pulses, j(500, 900), 12) * np.sin(np.pi * t / 0.3) * 0.25
            y = mix(y, np.concatenate([np.zeros(secs(0.08)), cr]))
        return verb(y, "small", 0.12, out_stereo=False)
    if surface == "tile":
        y = _heel_toe(d, j(100, 140), 0.6, j(3000, 4500), 1.3, j(0.04, 0.07))
        y += reson(white(d), j(3200, 4200), 30) * env_exp(secs(d), 40) * 0.6
        return verb(y, "tile", 0.15, out_stereo=False)
    if surface == "concrete":
        y = _heel_toe(d, j(90, 120), 0.8, j(2200, 3200), 0.9, j(0.05, 0.08))
        grit = bp(white(0.2), 2000, 9000) * (r.random(secs(0.2)) < 0.03) * env_exp(secs(0.2), 20)
        y = mix(y, grit * 2.0)
        return verb(y, "concrete", 0.1, out_stereo=False)
    if surface == "metal":
        t = tt(d)
        f0 = j(320, 480)
        y = sum(a * np.sin(2 * np.pi * f0 * k * t + r.uniform(0, 6)) * np.exp(-t * dd)
                for k, a, dd in [(1, 1, 12), (2.76, 0.6, 16), (5.4, 0.4, 22), (8.93, 0.25, 30)])
        y = y * 0.5 + _heel_toe(d, 120, 0.6, 3500, 0.8, 0.05)
        return verb(y, "concrete", 0.15, out_stereo=False)
    if surface == "water":
        dd = 0.5
        t = tt(dd)
        sp = tvf(white(dd), 2500 * np.exp(-t * 6) + 400, "bp", 2.0) * (1 - np.exp(-t * 80)) * np.exp(-t * 7)
        drops = np.zeros(secs(dd))
        for _ in range(r.integers(4, 9)):
            s = r.uniform(0.05, 0.35)
            dl = 0.04
            tk = tt(dl)
            blip = np.sin(2 * np.pi * phase(r.uniform(900, 2200) * (1 + tk * 25))) * np.exp(-tk * 90) * 0.3
            place(drops, blip, s)
        y = sp * 1.4 + drops + lp(white(dd), 300) * np.exp(-t * 12) * 0.6
        return verb(y, "concrete", 0.12, out_stereo=False)
    if surface == "sand":
        dd = 0.35
        y = np.zeros(secs(dd))
        for _ in range(140):
            s = r.uniform(0.0, 0.22)
            g = bp(white(0.006), 2000, 9000) * r.uniform(0.1, 0.6)
            place(y, g, s)
        y *= np.concatenate([np.linspace(0.3, 1, secs(0.05)), np.exp(-tt(dd - 0.05) * 10)])[: len(y)]
        y += lp(white(dd), 200) * env_exp(secs(dd), 25) * 1.2
        return y
    if surface == "grass":
        dd = 0.4
        y = np.zeros(secs(dd))
        for _ in range(90):
            place(y, bp(white(0.012), 1200, 6000) * r.uniform(0.1, 0.5), r.uniform(0, 0.25))
        y *= env_exp(len(y), 6)
        y += lp(white(dd), 180) * env_exp(secs(dd), 30)
        return y
    if surface == "mud":
        dd = 0.5
        t = tt(dd)
        sq = tvf(white(dd), 300 + 900 * (1 - np.exp(-t * 15)), "bp", 6.0) * np.exp(-t * 9) * 2.0
        pop = osc(120 * (1 + 2 * t), dd) * np.exp(-((t - 0.18) ** 2) / 0.0004) * 0.5
        return sq + pop + lp(white(dd), 250) * np.exp(-t * 20)
    raise ValueError(surface)


for _s in ["wood", "tile", "concrete", "metal", "water", "sand", "grass", "mud"]:
    for _v in range(4):
        SOUNDS[f"step_{_s}_{_v}"] = ((lambda s=_s, v=_v: fades(pad(step_variant(s, v), secs(0.7)), 0.0005, 0.25)), False, 0.7, None)


# ================================================================= PLAYER BODY
@sound("breath", loop=True, rms=0.09)
def breath():
    """Fast scared breathing, close to the ear. Stereo, loops."""
    L = 12.8
    buf = np.zeros((2, secs(L)))
    period = 1.6
    for k in range(int(L / period)):
        t0 = k * period + rng.uniform(-0.05, 0.05)
        ind = rng.uniform(0.4, 0.55)
        t = tt(ind)
        inh = bp(white(ind), 900, 3500) * np.sin(np.pi * t / ind) ** 1.5
        inh = formants(inh + 0.3 * white(ind), [(1300, 4, 1.0), (2600, 6, 0.5)])
        exd = rng.uniform(0.55, 0.7)
        t2 = tt(exd)
        src = white(exd) + 0.15 * glottal(rng.uniform(180, 230), exd, breath=0.0)
        exh = formants(src, [(700, 4, 1.0), (1500, 6, 0.6), (2500, 8, 0.2)]) * np.sin(np.pi * t2 / exd) ** 1.2
        place(buf, pan(inh, rng.uniform(-0.15, 0.15)), t0)
        place(buf, pan(exh, rng.uniform(-0.15, 0.15)), t0 + ind + 0.05, 1.3)
    return buf


@sound("tinnitus", peak=0.35)
def tinnitus():
    d = 6.0
    t = tt(d)
    e = np.minimum(t / 0.05, 1) * np.exp(-t * 0.7)
    l = np.sin(2 * np.pi * 6900 * t) * e
    r = np.sin(2 * np.pi * 6907 * t) * e
    return np.vstack([l, r])


@sound("heartbeat", peak=0.95)
def heartbeat():
    d = 0.9
    y = np.zeros(secs(d))
    for t0, g in [(0.0, 1.0), (0.26, 0.7)]:
        t = tt(0.35)
        f = 40 + 60 * np.exp(-t * 35)
        h = osc(f, kind="sin") * np.exp(-t * 14) + lp(white(0.35), 200) * np.exp(-t * 40) * 0.4
        place(y, h * g, t0)
    return sat(y, 1.6)


@sound("shout")
def shout():
    """The player shouting SAHUR! — formant voice, tense and cracking."""
    d = 0.95
    t = tt(d)
    f0 = 165 * (1 + 0.18 * np.clip((t - 0.35) / 0.2, 0, 1) - 0.25 * np.clip((t - 0.62) / 0.3, 0, 1))
    f0 *= 1 + 0.02 * np.sin(2 * np.pi * 6 * t)
    src = glottal(f0, jitter=0.02, breath=0.15)
    # formant tracks: s | a | h | u-r
    def seg(a, b, va, vb):
        k = np.clip((t - a) / max(b - a, 1e-3), 0, 1)
        return va + (vb - va) * k
    F1 = np.where(t < 0.4, 800, seg(0.4, 0.7, 450, 380))
    F2 = np.where(t < 0.4, 1200, seg(0.4, 0.7, 900, 1250))
    F3 = np.where(t < 0.4, 2800, seg(0.4, 0.7, 2400, 1700))
    voiced = formants(src, [(F1, 7, 1.0), (F2, 9, 0.7), (F3, 12, 0.3)])
    vmask = ((t > 0.14) & (t < 0.36)) | (t > 0.44)
    vmask = lp(vmask.astype(float), 40)
    s_noise = hp(white(d), 4500) * ((t < 0.15).astype(float)) * 0.5
    h_noise = bp(white(d), 600, 3000) * (((t > 0.35) & (t < 0.45)).astype(float)) * 0.6
    y = voiced * vmask + lp(s_noise, 12000) + h_noise
    y *= np.minimum(1, (d - t) / 0.15)
    return verb(sat(y * 1.5, 2.0), "concrete", 0.25)


# ================================================================= UI
@sound("ui_hover", peak=0.3)
def ui_hover():
    t = tt(0.05)
    return bp(white(0.05), 2000, 6000) * np.exp(-t * 120)


@sound("ui_click", peak=0.6)
def ui_click():
    y = _heel_toe(0.4, 90, 1.0, 2400, 0.4, 0.0)
    return verb(y, "wood_hall", 0.3)


@sound("flash_on", peak=0.5)
def flash_on():
    t = tt(0.08)
    a = bp(white(0.08), 2500, 9000) * np.exp(-t * 200)
    b = osc(1800, 0.08) * np.exp(-t * 150) * 0.3
    return a + b


@sound("flash_off", peak=0.45)
def flash_off():
    return resample(flash_on(), 0.8)


@sound("pickup", peak=0.6)
def pickup():
    t = tt(0.9)
    click = flash_on()
    ring = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * dd) * a for f, dd, a in [(1320, 6, 0.3), (1980, 8, 0.2), (2640, 10, 0.1)])
    return verb(mix(click, ring), "small", 0.3)


@sound("page", peak=0.55)
def page():
    d = 0.7
    y = np.zeros(secs(d))
    for _ in range(60):
        place(y, bp(white(0.02), 2500, 9000) * rng.uniform(0.1, 0.6), rng.uniform(0.0, 0.45))
    y += bp(white(d), 3000, 8000) * np.sin(np.pi * tt(d) / d) * 0.3
    return verb(y, "small", 0.2)


# ================================================================= HORROR HITS
@sound("jumpscare", peak=0.98)
def jumpscare():
    d = 2.8
    t = tt(d)
    impact = osc(35 + 140 * np.exp(-t * 18), kind="sin") * np.exp(-t * 2.5) * 1.6
    impact += lp(white(d), 4000) * np.exp(-t * 9) * 1.2
    cluster = np.zeros(secs(d))
    for f in [311.1, 329.6, 349.2, 466.2, 493.9, 739.9, 783.9, 1244.5]:
        vib = 1 + 0.012 * np.sin(2 * np.pi * rng.uniform(5, 8) * t + rng.uniform(0, 6))
        cluster += saw_ph(phase(f * vib * (1 - 0.06 * t)))
    cluster = bp(cluster, 700, 7000) * np.minimum(t / 0.01, 1) * np.exp(-t * 1.4)
    cluster *= 0.8 + 0.2 * np.sin(2 * np.pi * 14 * t)
    scrape = tvf(white(d), 2500 + 3000 * np.minimum(t, 1), "bp", 12) * (0.6 + 0.4 * np.sin(2 * np.pi * 45 * t)) * np.exp(-t * 1.5) * 2
    y = sat(impact + cluster * 0.35 + scrape * 0.6, 2.2)
    return verb(y, "concrete", 0.35)


@sound("stinger", peak=0.9)
def stinger():
    """Played the moment a brainrot spots you."""
    d = 2.4
    t = tt(d)
    boom = osc(45 + 60 * np.exp(-t * 10), kind="sin") * np.exp(-t * 3) * 1.4
    strings = np.zeros(secs(d))
    for f in [220, 233.1, 246.9, 311.1, 329.6]:
        strings += saw_ph(phase(f * (1 + 0.008 * np.sin(2 * np.pi * 6 * t + f))))
    strings = lp(strings, 2500) * np.minimum(t / 0.04, 1) * np.exp(-t * 1.2) * 0.25
    gliss = saw_ph(phase(1400 + 900 * t)) * np.minimum(t / 0.2, 1) * np.exp(-t * 1.6) * 0.15
    return verb(sat(boom + strings + bp(gliss, 1000, 6000), 1.8), "cathedral", 0.4)


@sound("transition", peak=0.85)
def transition():
    """Reverse-reverb swell into silence."""
    hit = mix(kick(120, 40, 0.6) * 0.8, lp(white(0.4), 5000) * env_exp(secs(0.4), 10))
    w = verb(hit, "cathedral", 1.0, 0.0)
    w = w[:, ::-1][:, -secs(3.0):]
    return w


@sound("ding", peak=0.8)
def ding():
    d = 6.0
    t = tt(d)
    f0 = 196
    partials = [(0.5, 1.0, 0.6), (1.0, 0.8, 1.0), (1.19, 0.9, 0.5), (1.56, 1.2, 0.35), (2.0, 1.5, 0.4), (2.51, 2.0, 0.2), (2.66, 2.2, 0.15), (3.0, 2.6, 0.12), (4.07, 3.5, 0.08)]
    y = sum(a * np.sin(2 * np.pi * f0 * r * t + rng.uniform(0, 6)) * np.exp(-t * dd) for r, dd, a in partials)
    y += hp(white(d), 3000) * np.exp(-t * 200) * 0.4
    return verb(y, "cathedral", 0.5)


@sound("death_drone", loop=True, rms=0.08)
def death_drone():
    d = 9.0
    t = tt(d + 1)
    y = sum(np.sin(2 * np.pi * f * t) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.1 * (i + 1) * t)) for i, f in enumerate([41.2, 43.65, 61.7, 87.3]))
    y += lp(brown(d + 1), 200) * 6
    return loopify(verb(y, "cathedral", 0.4), 1.0)


# ================================================================= BRAINROT SFX
def wood_hit(f0, dur=0.9, hollow=1.0, bright=1.0):
    t = tt(dur)
    modes = [(1.0, 7, 1.0), (2.32, 14, 0.55), (4.25, 22, 0.35), (6.63, 34, 0.2), (9.38, 48, 0.1)]
    y = sum(a * np.sin(2 * np.pi * f0 * r * t + rng.uniform(0, 6)) * np.exp(-t * d) for r, d, a in modes)
    y += hollow * 0.8 * np.sin(2 * np.pi * f0 * 0.5 * t) * np.exp(-t * 5)
    y += hp(white(dur), 2000) * np.exp(-t * 300) * 0.8 * bright
    y += lp(white(dur), 500) * np.exp(-t * 35) * 0.5
    return sat(y * 1.1, 1.4)


for _i, _f in enumerate([150, 162, 141]):
    SOUNDS[f"tung_{_i}"] = ((lambda f=_f: verb(wood_hit(f), "wood_hall", 0.18, out_stereo=False)), False, 0.9, None)


@sound("knock", peak=0.8)
def knock():
    y = np.zeros(secs(0.7))
    for t0 in [0.0, 0.16, 0.3]:
        place(y, wood_hit(300, 0.4, 0.3, 1.3) * rng.uniform(0.7, 1.0), t0)
    return verb(y, "wood_hall", 0.25, out_stereo=False)


def demon_voice(text_vowels, f0=60, dur=1.6, stretch=1.0):
    t = tt(dur)
    f = f0 * (1 + 0.03 * np.sin(2 * np.pi * 4 * t)) * (1 + 0.15 * np.clip((t - dur * 0.45) / (dur * 0.2), 0, 1) - 0.3 * np.clip((t - dur * 0.65) / (dur * 0.35), 0, 1))
    src = glottal(f, jitter=0.04, breath=0.3)
    src += 0.6 * glottal(f * 0.5, jitter=0.05, breath=0.0)
    y = np.zeros(len(t))
    nseg = len(text_vowels)
    for k, v in enumerate(text_vowels):
        a = k / nseg * dur
        b = (k + 1) / nseg * dur
        m = ((t >= a - 0.05) & (t < b + 0.05)).astype(float)
        m = lp(m, 20)
        if v == "s":
            y += hp(white(dur), 3500) * m * 0.6
        elif v == "h":
            y += bp(white(dur), 500, 2500) * m * 0.8
        else:
            y += vowel(src, v) * m
    return sat(y * 2.0, 3.0)


@sound("sahur_low", peak=0.95)
def sahur_low():
    y = demon_voice(["s", "a", "a", "h", "u", "o"], 58, 1.8)
    y = mix(y, resample(y, 0.5)[: len(y)] * 0.6)
    return verb(y, "wood_hall", 0.35, out_stereo=False)


@sound("squeak", peak=0.6)
def squeak():
    d = 0.22
    t = tt(d)
    f = 1900 + 900 * t / d + 150 * np.sin(2 * np.pi * 47 * t)
    y = (osc(f, kind="sin") + 0.35 * osc(f * 2, kind="sin")) * np.sin(np.pi * t / d) ** 0.7
    return verb(y, "concrete", 0.2, out_stereo=False)


@sound("shriek", peak=0.95)
def shriek():
    d = 1.4
    t = tt(d)
    sq = np.zeros(secs(d))
    for k in range(4):
        place(sq, squeak() * 0.8, k * 0.11)
    growl = lp(white(d), 400) * (0.5 + 0.5 * np.sin(2 * np.pi * 38 * t)) * np.exp(-t * 1.5) * 3
    scream = vowel(glottal(420 * (1 + 0.3 * t) * (1 + 0.03 * np.sin(2 * np.pi * 9 * t)), d, breath=0.3), "a") * np.exp(-t * 2)
    return verb(sat(sq + growl + scream * 1.5, 2.5), "concrete", 0.3, out_stereo=False)


@sound("engine", loop=True, rms=0.2)
def engine():
    L = 6.0
    t = tt(L + 1)
    fire = (np.sin(2 * np.pi * 27 * t) > 0.6).astype(float)
    fire = lp(fire, 600) * 2
    blade = sum(np.sin(2 * np.pi * 96 * k * t) / k for k in range(1, 7)) * (0.6 + 0.4 * np.sin(2 * np.pi * 96 * t))
    roar = lp(white(L + 1), 900) * 1.5
    y = sat(fire + blade * 0.5 + roar, 1.6)
    return loopify(y, 1.0)


@sound("jet", loop=True, rms=0.2)
def jet():
    L = 6.0
    t = tt(L + 1)
    whine = np.sin(2 * np.pi * phase(3150 + 40 * np.sin(2 * np.pi * 0.3 * t))) * 0.15 + np.sin(2 * np.pi * 6300 * t) * 0.05
    roar = bp(white(L + 1), 200, 4000) * 1.0 + lp(white(L + 1), 150) * 2
    return loopify(whine + roar, 1.0)


@sound("whistle", peak=0.7)
def whistle():
    d = 2.4
    t = tt(d)
    f = 1800 * (300 / 1800) ** (t / d) * (1 + 0.01 * np.sin(2 * np.pi * 7 * t))
    y = osc(f, kind="sin") * (0.15 + 0.85 * t / d) + bp(white(d), 800, 3000) * 0.1 * t / d
    return y


@sound("explosion", peak=0.98)
def explosion():
    d = 4.5
    t = tt(d)
    sub = osc(30 + 90 * np.exp(-t * 8), kind="sin") * np.exp(-t * 1.8) * 2.0
    body = tvf(white(d), 6000 * np.exp(-t * 2.5) + 150, "lp") * np.exp(-t * 1.2) * 2.0
    crackle = np.zeros(secs(d))
    for _ in range(260):
        s = rng.exponential(0.5)
        if s < d - 0.1:
            place(crackle, hp(white(0.01), 1500) * rng.uniform(0.1, 1.0) * np.exp(-s), s)
    debris = np.zeros(secs(d))
    for _ in range(25):
        s = rng.uniform(0.6, 3.0)
        place(debris, wood_hit(rng.uniform(300, 900), 0.2, 0.0) * rng.uniform(0.05, 0.2), s)
    y = sat(sub + body + crackle * 0.7 + debris, 1.8)
    return verb(y, "outdoor", 0.5, out_stereo=False)


@sound("musicbox", loop=True, rms=0.12)
def musicbox():
    beat = 0.42
    notes = [0, 3, 7, 12, 10, 7, 8, 7, 3, 5, 3, 2, 0, 3, 7, 15, 14, 12, 11, 7, 8, 7, 3, -1]
    L = len(notes) * beat
    buf = np.zeros(secs(L))
    for i, n in enumerate(notes):
        f = note_hz(n + 3) * (1 + 0.004 * np.sin(i * 1.7))
        t = tt(2.5)
        tine = np.sin(2 * np.pi * f * t) * np.exp(-t * 2.2) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 9) + 0.1 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * 20)
        tine += hp(white(2.5), 4000) * np.exp(-t * 400) * 0.2
        place(buf, tine, i * beat + rng.uniform(-0.01, 0.01))
        if i % 3 == 0:
            place(buf, osc(note_hz(n - 9), 2.5) * np.exp(-t * 2.5) * 0.5, i * beat)
    # Mechanism clicks
    for k in range(int(L / 0.105)):
        place(buf, hp(white(0.004), 3000) * 0.04, k * 0.105)
    # Wow & flutter (old, warped)
    tw = np.arange(len(buf)) / SR
    speed = 1 + 0.006 * np.sin(2 * np.pi * tw / L * 3) + 0.002 * np.sin(2 * np.pi * 7 * tw)
    speed *= len(buf) / np.sum(speed)
    y = varispeed(np.concatenate([buf, buf[:4000]]), speed)
    y = pad(y, len(buf))
    return verb(y, "small", 0.25, out_stereo=False)[: len(buf)]


@sound("musicbox_stop", peak=0.6)
def musicbox_stop():
    src = musicbox()
    seg = src[: secs(4.0)]
    sp = np.linspace(1.0, 0.05, secs(4.0)) ** 1.5
    y = varispeed(seg, sp)
    return fades(y, 0.001, 0.4)


@sound("slice", peak=0.9)
def slice_():
    d = 0.6
    t = tt(d)
    sw = tvf(white(d), 1000 + 9000 * np.minimum(t / 0.15, 1), "bp", 3) * np.sin(np.pi * np.minimum(t / 0.2, 1)) * np.exp(-t * 6)
    ring = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * dd) * a for f, dd, a in [(4200, 6, 0.3), (6100, 9, 0.2), (8800, 12, 0.1)])
    return verb(sw * 2 + ring, "small", 0.2, out_stereo=False)


@sound("whisper", peak=0.8)
def whisper():
    d = 1.8
    y = np.zeros(secs(d))
    seq = ["s", "i", "e", "h", "o", "s", "e", "a", "i"]
    tcur = 0.0
    for v in seq:
        dl = rng.uniform(0.12, 0.25)
        t = tt(dl)
        src = white(dl)
        if v in ("s", "h"):
            g = hp(src, 3500 if v == "s" else 1200) * 0.6
        else:
            g = vowel(src, v) * 1.2
        place(y, g * np.sin(np.pi * t / dl), tcur)
        tcur += dl * 0.85
    return verb(y, "small", 0.25, out_stereo=False)


@sound("tick", peak=0.6)
def tick():
    t = tt(0.12)
    return bp(white(0.12), 2500, 6000) * np.exp(-t * 200) + np.sin(2 * np.pi * 3400 * t) * np.exp(-t * 80) * 0.3


@sound("tock", peak=0.6)
def tock():
    t = tt(0.12)
    return bp(white(0.12), 1200, 3500) * np.exp(-t * 180) + np.sin(2 * np.pi * 1900 * t) * np.exp(-t * 60) * 0.3


@sound("rewind", peak=0.9)
def rewind():
    d = 1.8
    t = tt(d)
    swell = hp(white(d), 2000) * (t / d) ** 3
    dive = vowel(glottal(300 * 2 ** (-3 * t / d), d, breath=0.2), "o") * (t / d) ** 2
    bell = ding()[0][: secs(d)][::-1] * 0.4
    return verb(sat(swell + dive + pad(bell, secs(d)), 1.5), "cathedral", 0.3)


@sound("stomp", peak=0.98)
def stomp():
    d = 2.6
    t = tt(d)
    sub = osc(26 + 70 * np.exp(-t * 14), kind="sin") * np.exp(-t * 3) * 2.2
    body = lp(white(d), 700) * np.exp(-t * 9) * 2.0
    rattle = np.zeros(secs(d))
    for _ in range(40):
        place(rattle, wood_hit(rng.uniform(200, 700), 0.15, 0.0) * rng.uniform(0.03, 0.12), rng.uniform(0.05, 1.2))
    leaves = np.zeros(secs(d))
    for _ in range(150):
        place(leaves, bp(white(0.015), 1500, 7000) * rng.uniform(0.02, 0.15), rng.uniform(0.1, 1.5))
    return verb(sat(sub + body + rattle + leaves, 1.7), "outdoor", 0.5, out_stereo=False)


@sound("brr", peak=0.95)
def brr():
    """Brr brr — a rolled growl."""
    d = 1.5
    t = tt(d)
    src = glottal(70 * (1 + 0.05 * np.sin(2 * np.pi * 3 * t)), d, breath=0.4)
    trill = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 26 * t))
    y = formants(src, [(500, 5, 1.0), (1200, 7, 0.5)]) * lp(trill, 200) * np.sin(np.pi * t / d) ** 0.5
    return verb(sat(y * 2, 2.5), "outdoor", 0.3, out_stereo=False)


@sound("chitter", peak=0.8)
def chitter():
    d = 1.3
    y = np.zeros(secs(d))
    tc = 0.0
    for k in range(9):
        dl = rng.uniform(0.07, 0.12)
        t = tt(dl)
        f = rng.uniform(500, 900) * (1 + 0.6 * t / dl)
        g = vowel(glottal(f, breath=0.1), rng.choice(["o", "a", "u"])) * np.sin(np.pi * t / dl)
        place(y, g, tc)
        tc += dl + rng.uniform(0.01, 0.05)
    return verb(y, "outdoor", 0.25, out_stereo=False)


@sound("roll", loop=True, rms=0.18)
def roll():
    L = 3.0
    t = tt(L + 0.6)
    y = lp(white(L + 0.6), 300) * (0.6 + 0.4 * np.sin(2 * np.pi * 3 * t)) * 3
    y += tvf(white(L + 0.6), 400 + 200 * np.sin(2 * np.pi * 1.5 * t), "bp", 5) * 0.8
    y += np.sin(2 * np.pi * 34 * t) * 0.2
    return loopify(y, 0.6)


@sound("croak", peak=0.95)
def croak():
    d = 1.0
    t = tt(d)
    pulses = (np.sin(2 * np.pi * phase(28 + 8 * t)) > 0.9).astype(float)
    y = formants(lp(pulses, 2000), [(280, 6, 1.0), (850, 8, 0.6), (2200, 10, 0.2)]) * np.sin(np.pi * t / d) ** 0.6
    return verb(sat(y * 4, 2.5), "outdoor", 0.25, out_stereo=False)


@sound("reveal", peak=0.98)
def reveal():
    d = 1.5
    t = tt(d)
    sq = osc(900 + 1800 * t, kind="saw") * np.exp(-t * 3) * 0.3
    hit = osc(50 + 100 * np.exp(-t * 20), kind="sin") * np.exp(-t * 4)
    return verb(sat(mix(croak() * 1.2, bp(sq, 800, 5000), hit), 2.2), "outdoor", 0.3, out_stereo=False)


@sound("fridge_hum", loop=True, rms=0.12)
def fridge_hum():
    L = 6.0
    t = tt(L + 1)
    hum = sum(np.sin(2 * np.pi * 50 * k * t + k) / k ** 1.2 for k in range(1, 9))
    rattle = bp(white(L + 1), 150, 600) * (0.5 + 0.5 * np.sin(2 * np.pi * 100 * t)) * 0.3
    fan = bp(white(L + 1), 300, 1500) * 0.2
    return loopify(hum * 0.5 + rattle + fan, 1.0)


@sound("fridge_open", peak=0.8)
def fridge_open():
    d = 1.6
    t = tt(d)
    pop = lp(white(d), 1200) * np.exp(-t * 40) * 1.5
    suction = tvf(white(d), 300 + 1500 * np.minimum(t * 3, 1), "bp", 3) * np.exp(-t * 4) * 0.6
    clinks = np.zeros(secs(d))
    for s in [0.25, 0.32, 0.5]:
        place(clinks, np.sin(2 * np.pi * rng.uniform(2400, 3600) * tt(0.4)) * env_exp(secs(0.4), 18) * 0.3, s)
    return verb(pop + suction + clinks, "small", 0.3, out_stereo=False)


@sound("camel", peak=0.9)
def camel():
    d = 1.6
    t = tt(d)
    src = glottal(95 * (1 - 0.3 * t / d) * (1 + 0.04 * np.sin(2 * np.pi * 5 * t)), d, jitter=0.05, breath=0.4)
    y = formants(src, [(450, 5, 1), (900, 6, 0.6), (2200, 8, 0.2)]) * np.sin(np.pi * t / d)
    return verb(sat(y * 2, 2.0), "concrete", 0.25, out_stereo=False)


@sound("moo", peak=0.95)
def moo():
    d = 4.5
    t = tt(d)
    f = (110 - 45 * t / d) * (1 + 0.025 * np.sin(2 * np.pi * 4.5 * t))
    src = glottal(f, jitter=0.03, breath=0.2) + 0.5 * glottal(f * 0.5, jitter=0.03, breath=0.0)
    F1 = 300 + 400 * np.sin(np.pi * t / d)
    y = formants(src, [(F1, 6, 1.0), (F1 * 2.4, 8, 0.4), (2400, 10, 0.1)]) * np.sin(np.pi * t / d) ** 0.5
    y = resample(sat(y * 2, 2.0), 0.7)
    return verb(y, "space", 0.6)


@sound("static", loop=True, rms=0.12)
def static():
    L = 3.0
    y = bp(white(L + 0.5), 800, 9000)
    cr = (rng.random(secs(L + 0.5)) < 0.002) * rng.uniform(-3, 3, secs(L + 0.5))
    return loopify(y + cr, 0.5)


@sound("elevator", peak=0.8)
def elevator():
    d = 3.0
    t = tt(d)
    chime = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * 2.5) for f in [659.3, 830.6]) * 0.4
    chime = mix(chime, pad(np.sin(2 * np.pi * 523.3 * tt(2.5)) * env_exp(secs(2.5), 2.5) * 0.4, secs(d))[::1])
    return verb(crush(chime, 10, 2), "small", 0.3)


@sound("grass_touch", peak=0.6)
def grass_touch():
    d = 2.0
    y = np.zeros(secs(d))
    for _ in range(200):
        place(y, bp(white(0.015), 1500, 8000) * rng.uniform(0.02, 0.15), rng.uniform(0, 1.2))
    y *= env_exp(len(y), 1.5)
    return verb(y, "outdoor", 0.2)


@sound("end_tone", peak=0.7)
def end_tone():
    d = 10.0
    t = tt(d)
    y = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(261.6, 0.5), (329.6, 0.35), (392.0, 0.3), (523.3, 0.15)])
    y *= np.minimum(t / 3, 1) * np.minimum((d - t) / 4, 1)
    return verb(y, "cathedral", 0.5)


@sound("nv_on", peak=0.5)
def nv_on():
    """NVG power-up: click + rising capacitor whine."""
    d = 1.4
    t = tt(d)
    f = 2200 + 9000 * (1 - np.exp(-t * 2.5))
    whine = np.sin(2 * np.pi * phase(f)) * np.minimum(t / 0.05, 1) * np.exp(-t * 1.6) * 0.25
    click = mix(flash_on(), np.zeros(secs(d)))
    hiss = hp(white(d), 6000) * np.exp(-t * 3) * 0.05
    return mix(click, whine, hiss)


@sound("nv_off", peak=0.45)
def nv_off():
    d = 0.9
    t = tt(d)
    f = 11000 * np.exp(-t * 3) + 800
    whine = np.sin(2 * np.pi * phase(f)) * np.exp(-t * 4) * 0.2
    return mix(flash_off(), whine)


@sound("nv_hum", loop=True, rms=0.03)
def nv_hum():
    L = 4.0
    t = tt(L + 0.5)
    y = np.sin(2 * np.pi * 15750 * t) * 0.05 + hp(white(L + 0.5), 8000) * 0.02
    return loopify(np.vstack([y, np.roll(y, 37)]), 0.5)
