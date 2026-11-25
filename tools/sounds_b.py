"""ROT sounds, part B: ambiences, distant events, nextbot-style chase music."""
import numpy as np

from dsp import *  # noqa: F401,F403
from dsp import rng
from sounds_a import SOUNDS, sound, wood_hit, demon_voice, squeak, step_variant, croak, whisper

AL = 24.0  # ambience loop length


def _st(fn):
    """Two decorrelated renders -> stereo."""
    return np.vstack([fn(0), fn(1)])


def _room_tone(lo=120, amt=1.0):
    return _st(lambda c: lp(brown(AL + 2), lo) * 6 * amt + hp(pink(AL + 2), 3000) * 0.004 * amt)


def _events(buf, gen, count, gain=1.0, room="far"):
    for _ in range(count):
        s = rng.uniform(0, AL)
        x = gen()
        w = verb(x, room, wet=0.8, dry=0.3)
        p = rng.uniform(-0.8, 0.8)
        w = np.vstack([w[0] * (1 - p) * 0.7, w[1] * (1 + p) * 0.7])
        place(buf, w * gain, s)
    return buf


def _hum(freqs, beat=0.07):
    t = tt(AL + 2)
    l = sum(np.sin(2 * np.pi * f * t) / (i + 1) for i, f in enumerate(freqs))
    r = sum(np.sin(2 * np.pi * (f + beat) * t) / (i + 1) for i, f in enumerate(freqs))
    return np.vstack([l, r])


@sound("amb_hall", loop=True, rms=0.06)
def amb_hall():
    y = _room_tone(150) + _hum([60, 120, 180, 240]) * 0.025
    creak = lambda: reson(((np.sin(2 * np.pi * phase(40 + 30 * np.sin(2 * np.pi * 1.2 * tt(1.2)))) > 0.96).astype(float)), rng.uniform(400, 800), 14) * np.sin(np.pi * tt(1.2) / 1.2)
    _events(y, creak, 5, 0.25, "wood_hall")
    _events(y, lambda: wood_hit(rng.uniform(140, 170), 0.8) * 0.4, 2, 0.12, "far")
    return loopify(y, 2.0)


@sound("amb_water", loop=True, rms=0.07)
def amb_water():
    t = tt(AL + 2)
    lap = _st(lambda c: lp(white(AL + 2), 500) * (0.5 + 0.5 * np.sin(2 * np.pi * (0.21 + c * 0.03) * t + c)) * 1.2)
    y = lap + _room_tone(90) + _hum([50, 100], 0.05) * 0.02
    drip = lambda: np.sin(2 * np.pi * phase(rng.uniform(900, 1700) * (1 + tt(0.06) * 20))) * env_exp(secs(0.06), 90)
    _events(y, drip, 40, 0.35, "concrete")
    return loopify(y, 2.0)


@sound("amb_hangar", loop=True, rms=0.08)
def amb_hangar():
    t = tt(AL + 2)
    wind = _st(lambda c: tvf(white(AL + 2), 450 + 300 * np.sin(2 * np.pi * (0.06 + 0.02 * c) * t) + 150 * np.sin(2 * np.pi * 0.23 * t), "bp", 2.5) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.11 * t + c)))
    y = wind * 1.2 + _room_tone(60, 1.5)
    groan = lambda: reson(white(3.0), rng.uniform(150, 300), 40) * np.sin(np.pi * tt(3.0) / 3.0) * 3
    _events(y, groan, 3, 0.4, "concrete")
    return loopify(y, 2.0)


@sound("amb_cafe", loop=True, rms=0.06)
def amb_cafe():
    t = tt(AL + 2)
    babble = np.zeros((2, secs(AL + 2)))
    for v in range(14):
        tc = rng.uniform(0, 2)
        while tc < AL:
            dl = rng.uniform(0.1, 0.3)
            f0 = rng.uniform(100, 240)
            g = vowel(glottal(f0 * (1 + 0.1 * np.sin(2 * np.pi * 3 * tt(dl))), dl, breath=0.1), rng.choice(list("aeiou"))) * np.sin(np.pi * tt(dl) / dl)
            place(babble, pan(g, rng.uniform(-0.9, 0.9)), tc, 0.4)
            tc += dl + (rng.uniform(0.02, 0.1) if rng.random() < 0.85 else rng.uniform(0.6, 2.0))
    babble = lp(babble, 1100)
    rev = babble[:, ::-1] * 0.4  # reversed crowd underneath: wrong in a way you can't name
    y = pad(verb(babble + rev, "tile", 0.5), secs(AL + 2)) + _room_tone(100)
    clink = lambda: sum(np.sin(2 * np.pi * f * tt(0.5)) * env_exp(secs(0.5), 15) for f in [rng.uniform(2500, 3500), rng.uniform(4200, 5200)])
    _events(y, clink, 8, 0.15, "tile")
    return loopify(pad(y, secs(AL + 2)), 2.0)


@sound("amb_desert", loop=True, rms=0.06)
def amb_desert():
    t = tt(AL + 2)
    wind = _st(lambda c: hp(white(AL + 2), 2500) * (0.3 + 0.7 * np.maximum(0, np.sin(2 * np.pi * (0.08 + c * 0.01) * t)) ** 2) * 0.4)
    drone = _hum([41.2, 61.7], 0.1) * 0.06
    y = wind + drone + _room_tone(80, 0.6)
    _events(y, lambda: np.sin(2 * np.pi * 2800 * tt(0.08)) * env_exp(secs(0.08), 60), 20, 0.08, "far")
    return loopify(y, 2.0)


@sound("amb_jungle", loop=True, rms=0.07)
def amb_jungle():
    t = tt(AL + 2)
    y = _room_tone(120)
    for k in range(3):
        f = rng.uniform(4000, 7000)
        am = 0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(40, 80) * t)
        sw = np.maximum(0, np.sin(2 * np.pi * rng.uniform(0.05, 0.12) * t + k)) ** 3
        y += pan(bp(white(AL + 2), f * 0.9, f * 1.1) * am * sw * 0.3, rng.uniform(-0.8, 0.8))

    def bird():
        d = rng.uniform(0.3, 0.7)
        tb = tt(d)
        f = rng.uniform(1200, 2600) * (1 + 0.4 * np.sin(2 * np.pi * rng.uniform(6, 14) * tb))
        return sat(vowel(glottal(f, breath=0.05), "i") * np.sin(np.pi * tb / d) * 2, 2)
    _events(y, bird, 10, 0.25, "outdoor")
    return loopify(y, 2.0)


@sound("amb_swamp", loop=True, rms=0.07)
def amb_swamp():
    y = _room_tone(100) + _hum([36.7, 55], 0.05) * 0.03
    _events(y, lambda: croak()[: secs(0.8)] * 0.5, 14, 0.3, "far")
    bub = lambda: np.sin(2 * np.pi * phase(rng.uniform(150, 400) * (1 + tt(0.08) * 15))) * env_exp(secs(0.08), 40)
    _events(y, bub, 30, 0.2, "outdoor")
    t = tt(AL + 2)
    y += _st(lambda c: bp(white(AL + 2), 5000, 6500) * (0.5 + 0.5 * np.sin(2 * np.pi * 55 * t)) * 0.03)
    return loopify(y, 2.0)


@sound("amb_cold", loop=True, rms=0.07)
def amb_cold():
    t = tt(AL + 2)
    hum = _hum([50, 100, 150, 200, 250], 0.04) * 0.05
    fans = _st(lambda c: bp(white(AL + 2), 250, 1400) * (0.8 + 0.2 * np.sin(2 * np.pi * 23 * t)) * 0.3)
    y = hum + fans + _room_tone(90)
    ice = lambda: reson(white(0.5), rng.uniform(1500, 3000), 30) * env_exp(secs(0.5), 20) * 2
    _events(y, ice, 6, 0.25, "concrete")
    return loopify(y, 2.0)


@sound("amb_space", loop=True, rms=0.07)
def amb_space():
    t = tt(AL + 2)
    drone = _hum([32.7, 49.0, 65.4, 98.0], 0.13) * 0.1
    shimmer = _st(lambda c: bp(white(AL + 2), 3000, 6000) * (0.5 + 0.5 * np.sin(2 * np.pi * (0.07 + 0.03 * c) * t)) * 0.05)
    tones = _st(lambda c: sum(np.sin(2 * np.pi * f * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.05 * (i + 1) * t + c)) for i, f in enumerate([523.3, 659.3, 987.8])) * 0.015)
    y = verb(drone + shimmer + tones, "space", 0.5)
    return loopify(pad(y, secs(AL + 2)), 2.0)


@sound("amb_fry", loop=True, rms=0.16)
def amb_fry():
    t = tt(AL + 2)
    bass = saw_ph(phase(41 + 3 * np.sin(2 * np.pi * 0.25 * t))) * 1.5
    y = sat(bass + bp(white(AL + 2), 1000, 8000) * 0.4, 4)
    for _ in range(40):
        s = rng.uniform(0, AL)
        f = rng.choice([220, 330, 440, 660, 880, 1320])
        dl = rng.uniform(0.05, 0.3)
        place(y, saw_ph(phase(np.full(secs(dl), f))) * 0.6, s)
    y = crush(y, 6, 6)
    return loopify(np.vstack([y, np.roll(y, 300)]), 1.0)


@sound("amb_meet", loop=True, rms=0.08)
def amb_meet():
    t = tt(AL + 2)
    choir = np.zeros(secs(AL + 2))
    for f in [55.0, 65.4, 82.4, 87.3, 110.0, 130.8]:
        for v in range(3):
            fr = f * (1 + rng.uniform(-0.004, 0.004)) * (1 + 0.006 * np.sin(2 * np.pi * rng.uniform(4, 6) * t))
            choir += vowel(glottal(fr, breath=0.15), rng.choice(["o", "u"])) * 0.2
    choir *= 0.6 + 0.4 * np.sin(2 * np.pi * 0.05 * t)
    y = verb(lp(choir, 2500), "cathedral", 0.6)
    return loopify(pad(y, secs(AL + 2)), 2.0)


@sound("amb_silence", loop=True, rms=0.004)
def amb_silence():
    t = tt(10)
    return loopify(_st(lambda c: lp(white(10), 60) * 0.1), 1.0)


# ================================================================= DISTANT EVENTS (3D, mono)
@sound("ev_slam", peak=0.8)
def ev_slam():
    t = tt(0.5)
    x = osc(60 + 60 * np.exp(-t * 30), kind="sin") * np.exp(-t * 10) + lp(white(0.5), 2000) * np.exp(-t * 25)
    return distant(x, "far", 2500)


@sound("ev_groan", peak=0.8)
def ev_groan():
    d = 3.5
    t = tt(d)
    x = sum(tvf(white(d), f * (1 + 0.05 * t), "bp", 60) for f in [140, 233, 377]) * np.sin(np.pi * t / d)
    return distant(x * 3, "far", 1500)


@sound("ev_run", peak=0.8)
def ev_run():
    y = np.zeros(secs(3.0))
    for k in range(9):
        place(y, step_variant("concrete", k % 4) * (0.4 + 0.6 * k / 9), k * 0.28)
    return distant(y, "far", 1600)


@sound("ev_whisper", peak=0.7)
def ev_whisper():
    return distant(whisper(), "concrete", 3500, 0.6)


@sound("ev_tung", peak=0.8)
def ev_tung():
    y = np.zeros(secs(1.2))
    for k in range(3):
        place(y, wood_hit(150, 0.6), k * 0.3)
    return distant(y, "far", 1200)


@sound("ev_laugh", peak=0.7)
def ev_laugh():
    y = np.zeros(secs(1.4))
    for k in range(5):
        dl = 0.12
        place(y, vowel(glottal(400 + k * 10, dl, breath=0.3), "e") * np.sin(np.pi * tt(dl) / dl), k * 0.17)
    return distant(y, "far", 2500)


@sound("ev_scream", peak=0.7)
def ev_scream():
    d = 1.8
    t = tt(d)
    x = vowel(glottal(520 * (1 + 0.1 * np.sin(np.pi * t / d)) * (1 + 0.03 * np.sin(2 * np.pi * 7 * t)), d, breath=0.3), "a") * np.sin(np.pi * t / d) ** 0.5
    return distant(sat(x * 2, 2), "far", 2000)


@sound("ev_radio", peak=0.7)
def ev_radio():
    d = 3.0
    y = bp(white(d), 1000, 4000) * 0.3
    tc = 0.3
    while tc < d - 0.3:
        dl = rng.uniform(0.08, 0.2)
        place(y, vowel(glottal(rng.uniform(110, 170), dl, breath=0.1), rng.choice(list("aeiou"))) * np.sin(np.pi * tt(dl) / dl), tc)
        tc += dl + rng.uniform(0.0, 0.15)
    y = sat(bp(y, 350, 3000) * 2, 3)
    return distant(crush(y, 8, 2), "concrete", 4000, 0.5)


@sound("ev_drip", peak=0.6)
def ev_drip():
    x = np.sin(2 * np.pi * phase(1300 * (1 + tt(0.06) * 22))) * env_exp(secs(0.06), 90)
    return verb(x, "concrete", 0.7, out_stereo=False)


@sound("ev_thud", peak=0.8)
def ev_thud():
    t = tt(0.8)
    return distant(osc(40 + 50 * np.exp(-t * 20), kind="sin") * np.exp(-t * 6) * 2, "far", 800)


@sound("ev_knock", peak=0.8)
def ev_knock():
    return distant(SOUNDS["knock"][0](), "concrete", 3000, 0.7)


# ================================================================= CHASE MUSIC (nextbot style)
def _bar_loop(bpm, bars):
    beat = 60.0 / bpm
    return beat, np.zeros(secs(beat * 4 * bars))


def _finish_chase(buf, bits=12, down=1, drive=2.0):
    y = sat(buf, drive)
    if bits < 16:
        y = crush(y, bits, down)
    return y


@sound("chase_tung", loop=True, rms=0.22)
def chase_tung():
    beat, buf = _bar_loop(150, 4)
    roots = [-21, -21, -18, -16]
    for bar in range(4):
        b0 = bar * 4 * beat
        for k in [0, 0.5, 1.0]:
            place(buf, wood_hit(152, 0.5) * 0.9, b0 + k * beat)
        for k in [2.0, 2.5, 3.0]:
            place(buf, wood_hit(141, 0.5) * 0.7, b0 + k * beat)
        place(buf, kick(), b0)
        place(buf, kick(), b0 + 2.5 * beat)
        place(buf, snare() * 0.6, b0 + beat)
        place(buf, snare() * 0.6, b0 + 3 * beat)
        for h in range(8):
            place(buf, hat() * 0.25, b0 + h * beat * 0.5 + beat * 0.25)
        place(buf, bass808(note_hz(roots[bar]), beat * 3.5, 0.3) * 0.9, b0)
    voice = demon_voice(["s", "a", "h", "u"], 90, beat * 2)
    place(buf, voice * 0.6, 3 * 4 * beat + 2 * beat)
    return _finish_chase(buf, 11, 2, 2.2)


@sound("chase_tralalero", loop=True, rms=0.22)
def chase_tralalero():
    beat, buf = _bar_loop(172, 4)
    motif = [7, 5, 3, 2, 0, 0, 0, -2]
    for bar in range(4):
        b0 = bar * 4 * beat
        for k in range(4):
            place(buf, tom(95 if k % 2 == 0 else 130) * 0.8, b0 + k * beat)
            place(buf, squeak() * 0.6, b0 + k * beat + beat * 0.5)
        place(buf, kick(), b0)
        place(buf, kick(), b0 + 2 * beat)
        place(buf, bass808(note_hz(-24 + (bar % 2) * 3), beat * 3.5, 0.5), b0)
        for i, n in enumerate(motif):
            dl = beat * 0.5
            t = tt(dl)
            f = note_hz(n + 7) * (1 + 0.01 * np.sin(2 * np.pi * 7 * t))
            place(buf, osc(f, kind="sq") * adsr(len(t), 0.005, 0.05, 0.5, 0.03) * 0.25, b0 + i * dl)
    return _finish_chase(buf, 12, 1, 2.0)


@sound("chase_patapim", loop=True, rms=0.24)
def chase_patapim():
    beat, buf = _bar_loop(92, 2)
    for bar in range(2):
        b0 = bar * 4 * beat
        place(buf, kick(90, 30, 0.9) * 1.3, b0)
        place(buf, kick(90, 30, 0.9) * 1.3, b0 + 2 * beat)
        place(buf, SOUNDS["brr"][0]()[: secs(beat * 1.2)] * 0.7, b0 + beat)
        place(buf, SOUNDS["brr"][0]()[: secs(beat * 1.2)] * 0.7, b0 + 3 * beat)
        for i, f in enumerate([98, 110, 82.4]):
            place(buf, tom(f, 0.4), b0 + 3 * beat + i * beat / 3)
        t = tt(beat * 4)
        brass = sum(saw_ph(phase(np.full(len(t), f * (1 + 0.003 * k)))) for k, f in enumerate([41.2, 61.7, 49.0]))
        place(buf, lp(brass, 500) * adsr(len(t), 0.3, 0.5, 0.7, 0.5) * 0.25, b0)
    return _finish_chase(buf, 12, 1, 2.4)


@sound("chase_lirili", loop=True, rms=0.2)
def chase_lirili():
    beat, buf = _bar_loop(120, 4)
    for bar in range(4):
        b0 = bar * 4 * beat
        for h in range(16):
            place(buf, (SOUNDS["tick"][0]() if h % 2 == 0 else SOUNDS["tock"][0]()) * 0.35, b0 + h * beat / 4)
        place(buf, kick(), b0)
        place(buf, kick(), b0 + 2 * beat)
        dl = beat * 1.5
        t = tt(dl)
        f = note_hz(-14 + [0, 3, -2, 5][bar]) * (1 + 0.15 * np.minimum(t / 0.15, 1))
        trumpet = formants(saw_ph(phase(f)), [(700, 4, 1), (1200, 5, 0.6), (2600, 8, 0.3)]) * adsr(len(t), 0.05, 0.2, 0.7, 0.2)
        place(buf, sat(trumpet * 2, 2) * 0.5, b0 + beat)
        place(buf, bass808(note_hz(-26 + [0, 3, -2, 5][bar]), beat * 2), b0)
    return _finish_chase(buf, 12, 1, 1.8)


@sound("chase_assassino", loop=True, rms=0.2)
def chase_assassino():
    beat, buf = _bar_loop(144, 4)
    seq = [0, 0, 3, 0, 7, 0, 6, 3]
    for bar in range(4):
        b0 = bar * 4 * beat
        for i in range(16):
            n = seq[i % 8] + [0, 0, -4, -2][bar]
            dl = beat / 4
            t = tt(dl)
            s = saw_ph(phase(note_hz(n - 9) * (1 + 0.004 * np.sin(2 * np.pi * 6 * t))))
            place(buf, lp(s, 3000) * adsr(len(t), 0.003, 0.05, 0.4, 0.02) * 0.35, b0 + i * dl)
        place(buf, tom(70, 0.8) * 1.2, b0)
        place(buf, tom(70, 0.8), b0 + 2.5 * beat)
        place(buf, SOUNDS["slice"][0]() * 0.5, b0 + 3.5 * beat)
    return _finish_chase(buf, 14, 1, 1.8)


@sound("chase_fry", loop=True, rms=0.26)
def chase_fry():
    parts = [chase_tung(), chase_tralalero(), chase_patapim()]
    L = secs(6.0)
    buf = np.zeros(L)
    pos = 0
    while pos < L:
        src = parts[rng.integers(0, len(parts))]
        dl = secs(rng.choice([0.1, 0.2, 0.4]))
        st = rng.integers(0, len(src) - dl)
        chunk = src[st:st + dl]
        if rng.random() < 0.3:
            chunk = resample(chunk, rng.choice([0.5, 1.5, 2.0]))[:dl]
        chunk = pad(chunk, dl)[: L - pos]
        buf[pos:pos + len(chunk)] += chunk
        pos += dl
    return _finish_chase(buf, 5, 6, 4.0)


@sound("glitch", peak=0.8)
def glitch():
    d = 0.45
    t = tt(d)
    y = bp(white(d), 500, 9000) * np.exp(-t * 5)
    y += saw_ph(phase(np.full(secs(d), 140.0))) * 0.5 * np.exp(-t * 8)
    y = crush(y, 4, 12)
    return verb(y, "small", 0.3, out_stereo=False)


@sound("amb_heavy", loop=True, rms=0.07)
def amb_heavy():
    """Dense, heavy air: sub drone, far machinery, buzzing tubes, the building settling."""
    t = tt(AL + 2)
    sub = _st(lambda c: np.sin(2 * np.pi * (31.0 + c * 0.07) * t) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.06 * t + c)) * 0.5)
    mach = _st(lambda c: lp(white(AL + 2), 90) * 6 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.43 * t + c * 0.5)))
    buzz = sum(np.sin(2 * np.pi * 120 * k * t + k) / k ** 0.8 for k in range(1, 12))
    buzz = bp(buzz, 100, 4000) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.17 * t))
    crack = (rng.random(secs(AL + 2)) < 0.0004) * rng.uniform(-1, 1, secs(AL + 2))
    buzz = buzz * 0.05 + hp(crack, 2000) * 0.6
    y = sub + mach + np.vstack([buzz, np.roll(buzz, 220)])
    settle = lambda: reson(white(1.5), rng.uniform(80, 220), 25) * np.sin(np.pi * tt(1.5) / 1.5) * 3
    _events(y, settle, 4, 0.35, "concrete")
    return loopify(y, 2.0)
