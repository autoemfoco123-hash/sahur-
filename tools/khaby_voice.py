"""The Khaby Lame Mechanism's voice (sector 2): terrified, alone, talking fast.

Speech from the Kokoro-82M neural text-to-speech model (Apache-2.0, run locally with
kokoro-onnx), then made frightened: a little higher and quicker, the voice trembling (an
unsteady tremor in loudness and pitch), short shaky breaths between phrases, the open air of the
field around it. The scream is built from the voice itself plus a synthesized throat, torn.

  sounds/khaby_line_NN.wav   the monologue, one file per line
  sounds/khaby_watchout.wav  "watch out!" as the ground opens
  sounds/khaby_scream.wav    the scream as it falls into the crack
  sounds/khaby_fall.wav      the scream far below you, falling away into the dark, fading
  scripts/khaby_lines.gd     the lines, their sounds and when they start (generated)

usage: python3 tools/khaby_voice.py KOKORO_PYTHON MODEL_DIR
  KOKORO_PYTHON: a python with kokoro-onnx + soundfile installed
  MODEL_DIR: kokoro-v1.0.onnx and voices-v1.0.bin
"""
import json
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np
from scipy import signal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
from dsp import SR, bp, hp, lp, secs, tt, white  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "sounds")
VOICE = "am_michael"
rng = np.random.default_rng(2020)

# [spoken text, subtitle, where it looks: you / sky / beacon / down / around, hands 0..1]
LINES = [
	["No. No, no, no... you shouldn't be here. Nobody comes through that door. Nobody.",
		"no. no, no, no... you shouldn't be here. nobody comes through that door. nobody.", "you", 0.0],
	["Listen to me. Please, just listen. This isn't a field. It's a lid.",
		"listen to me. please, just listen. this isn't a field. it's a lid.", "around", 0.3],
	["Look at the sky. Not one cloud has moved since I got here. Not one.",
		"look at the sky. not one cloud has moved since i got here. not one.", "sky", 0.0],
	["Those beacons you switched off... they were holding it shut.",
		"those beacons you switched off... they were holding it shut.", "beacon", 0.0],
	["Every night I hear it under the grass. Breathing. Scratching. Waiting.",
		"every night i hear it under the grass. breathing. scratching. waiting.", "down", 0.0],
	["I explain things. That's all I ever did. Hands up... it's that simple. But I can't explain this.",
		"i explain things. that's all i ever did. hands up... it's that simple. but i can't explain this.", "you", 1.0],
	["Do you feel that? The ground... it's humming.",
		"do you feel that? the ground... it's humming.", "down", 0.0],
	["Oh no. Oh no, no, no. It's opening. It's opening!",
		"oh no. oh no, no, no. it's opening. it's opening!", "around", 0.0],
]
GAP = 0.75          # seconds between lines (a shaky breath goes in there)
LEAD = 0.6          # before the first line


TTS = r'''
import sys, json, soundfile as sf
from kokoro_onnx import Kokoro
model, voices, jobs = sys.argv[1], sys.argv[2], json.load(open(sys.argv[3]))
k = Kokoro(model, voices)
for j in jobs:
	audio, sr = k.create(j["text"], voice=j["voice"], speed=j["speed"], lang="en-us")
	sf.write(j["out"], audio, sr)
'''


def speak_all(py, model_dir, jobs):
	with tempfile.TemporaryDirectory() as d:
		script = os.path.join(d, "tts.py")
		open(script, "w").write(TTS)
		jf = os.path.join(d, "jobs.json")
		json.dump(jobs, open(jf, "w"))
		subprocess.run([py, script, os.path.join(model_dir, "kokoro-v1.0.onnx"), os.path.join(model_dir, "voices-v1.0.bin"), jf], check=True)


def load(path):
	import soundfile  # noqa: F401  (only if available; fall back to wave)


def read_wav(path):
	w = wave.open(path)
	n, ch, sw, rate = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
	raw = w.readframes(n)
	if sw == 2:
		a = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
	else:
		a = np.frombuffer(raw, dtype="<i4").astype(np.float64) / 2147483648.0
	a = a.reshape(-1, ch).mean(axis=1)
	if rate != SR:
		a = signal.resample_poly(a, SR, rate)
	return a


def trim(x, thr=0.01):
	idx = np.nonzero(np.abs(x) > thr)[0]
	if idx.size == 0:
		return x
	return x[max(0, idx[0] - secs(0.02)):min(len(x), idx[-1] + secs(0.08))]


def frightened(x, semis=1.3, tremor=0.16, rate=7.5, wobble=0.007):
	"""Higher and a little quicker, the voice shaking (loudness and pitch tremor)."""
	n = len(x)
	t = np.arange(n) / SR
	# an unsteady tremor: two rates beating, wandering
	drift = dsp.lp(rng.standard_normal(n), 2.0)
	drift = drift / (np.max(np.abs(drift)) + 1e-9)
	trem = np.sin(2 * np.pi * rate * t + 2.0 * np.sin(2 * np.pi * 0.7 * t)) * 0.65 + np.sin(2 * np.pi * rate * 1.37 * t) * 0.35
	amp = 1.0 - tremor * (0.5 + 0.5 * trem) * (0.6 + 0.4 * drift)
	# pitch: resample along a wobbling time base (raise + quaver)
	ratio = 2 ** (semis / 12.0)
	speed = ratio * (1.0 + wobble * trem)
	pos = np.cumsum(speed)
	pos = pos[pos < n - 1]
	y = np.interp(pos, np.arange(n), x)
	a2 = np.interp(pos, np.arange(n), amp)
	y = y * a2
	# a tight, dry throat: less body, a bit more breath
	y = hp(y, 140) + bp(white(len(y) / SR), 1500, 6000) * 0.004 * np.abs(signal.hilbert(y))
	return y


def breath(d=0.45, gain=0.05, shaky=True):
	"""A short, shaky intake of air."""
	n = secs(d)
	e = np.sin(np.linspace(0, np.pi, n)) ** 1.5
	if shaky:
		e = e * (0.75 + 0.25 * np.sign(np.sin(np.linspace(0, np.pi * 2 * 5, n))))
		e = dsp.lp(e, 40)
	b = bp(white(d), 600, 3200) * e * gain + bp(white(d), 3000, 7000) * e * gain * 0.4
	return b


def outdoors(x, wet=0.12):
	y = dsp.verb(x, "far", wet=wet, dry=1.0)
	return y[:, :len(x)] if y.ndim == 2 else y[:len(x)]


def write(name, x, peak=0.9):
	dsp.write(os.path.join(OUT, name), x, peak=peak)


def scream_core(d, f0, f1, seed):
	r = np.random.default_rng(seed)
	t = tt(d)
	f = f0 + (f1 - f0) * np.minimum(1.0, t / (d * 0.35))
	f = f * (1.0 + 0.035 * np.sin(2 * np.pi * 6.5 * t) + 0.02 * dsp.lp(r.standard_normal(len(t)), 8) * 6)
	src = dsp.glottal(f, jitter=0.04, breath=0.35)
	tracks = [(np.full(len(t), 850.0), 6, 1.0), (np.full(len(t), 1300.0), 8, 0.7), (np.full(len(t), 2800.0), 10, 0.35)]
	v = dsp.formants(src, tracks)
	v = np.tanh(v / (np.max(np.abs(v)) + 1e-9) * 3.0)
	return v


def main():
	py, model_dir = sys.argv[1], sys.argv[2]
	tmp = tempfile.mkdtemp()
	jobs = []
	for i, ln in enumerate(LINES):
		jobs.append({"text": ln[0], "voice": VOICE, "speed": 1.12, "out": os.path.join(tmp, "l%02d.wav" % i)})
	jobs.append({"text": "Watch out!!", "voice": VOICE, "speed": 1.0, "out": os.path.join(tmp, "watch.wav")})
	jobs.append({"text": "Aaaaaaaaaaaah!", "voice": VOICE, "speed": 0.62, "out": os.path.join(tmp, "aah.wav")})
	jobs.append({"text": "No! Nooooooooo!", "voice": VOICE, "speed": 0.7, "out": os.path.join(tmp, "noo.wav")})
	print("speaking %d lines (%s)..." % (len(jobs), VOICE))
	speak_all(py, model_dir, jobs)
	# --- the monologue
	at = LEAD
	rows = []
	for i, ln in enumerate(LINES):
		x = trim(read_wav(os.path.join(tmp, "l%02d.wav" % i)))
		y = frightened(x, semis=1.3 + 0.15 * i, tremor=0.14 + 0.012 * i)
		pre = breath(0.42 + rng.uniform(0, 0.15), 0.045 + 0.004 * i)
		full = np.concatenate([pre, np.zeros(secs(0.05)), y])
		out = outdoors(full)
		write("khaby_line_%02d.wav" % i, out, peak=0.85)
		d = len(full) / SR
		rows.append([round(at, 2), ln[1], "khaby_line_%02d" % i, ln[2], ln[3], round(d, 2)])
		print("khaby_line_%02d.wav  %.2f s  %s" % (i, d, ln[1][:50]))
		at += d + GAP
	talk_end = at
	# --- "watch out!": shouted, cracking
	w = trim(read_wav(os.path.join(tmp, "watch.wav")))
	w = frightened(w, semis=3.5, tremor=0.08, rate=9.0, wobble=0.012)
	w = np.tanh(w / (np.max(np.abs(w)) + 1e-9) * 2.4)
	w = np.concatenate([breath(0.22, 0.09, shaky=False), w])
	write("khaby_watchout.wav", outdoors(w, 0.2), peak=0.97)
	print("khaby_watchout.wav  %.2f s" % (len(w) / SR))
	# --- the scream: his own voice dragged into it, a torn throat underneath
	a = trim(read_wav(os.path.join(tmp, "aah.wav")))
	a = frightened(a, semis=7.0, tremor=0.2, rate=8.0, wobble=0.03)
	core = scream_core(len(a) / SR + 0.4, 420, 640, 7)
	n = max(len(a), len(core))
	s = dsp.pad(a / (np.max(np.abs(a)) + 1e-9), n) * 0.8 + dsp.pad(core, n) * 0.55
	s = np.tanh(s * 1.8) * np.minimum(1.0, np.arange(n) / secs(0.03)) * np.minimum(1.0, (n - np.arange(n)) / secs(0.4))
	write("khaby_scream.wav", outdoors(s, 0.25), peak=0.98)
	print("khaby_scream.wav  %.2f s" % (n / SR))
	# --- falling away from you into the dark: "no! nooo!", the scream dropping and fading
	nn = trim(read_wav(os.path.join(tmp, "noo.wav")))
	nn = frightened(nn, semis=5.0, tremor=0.22, rate=8.5, wobble=0.03)
	core2 = scream_core(5.5, 520, 380, 9)
	D = 7.0
	f = np.zeros(secs(D))
	dsp.place(f, nn / (np.max(np.abs(nn)) + 1e-9) * 0.8, 0.0)
	dsp.place(f, core2 * 0.6, len(nn) / SR - 0.3)
	t = tt(D)
	# receding: quieter, duller and lower as it goes
	gone = np.clip(t / D, 0, 1)
	f = f * (1.0 - gone) ** 1.6
	pos = np.cumsum(1.0 - 0.12 * gone)
	pos = pos[pos < len(f) - 1]
	f = np.interp(pos, np.arange(len(f)), f)
	f = signal.lfilter(*signal.butter(2, 2500, "low", fs=SR), f) * 0.6 + f * 0.4 * (1.0 - gone[:len(f)])
	y = dsp.verb(f, "far", wet=0.6, dry=0.8)[:, :len(f)]
	write("khaby_fall.wav", y, peak=0.9)
	print("khaby_fall.wav  %.2f s" % (len(f) / SR))
	# --- the timing, for the level
	gd = ["## Generated by tools/khaby_voice.py: the mechanism's lines and when they start.",
		"## [start s, subtitle, sound, looks at (you/sky/beacon/down/around), hands 0..1, length s]",
		"", "const LINES = ["]
	for r in rows:
		gd.append("\t[%.2f, \"%s\", \"%s\", \"%s\", %.1f, %.2f]," % (r[0], r[1].replace('"', '\\"'), r[2], r[3], r[4], r[5]))
	gd += ["]", "const TALK_END = %.2f" % talk_end, ""]
	open(os.path.join(ROOT, "scripts", "khaby_lines.gd"), "w").write("\n".join(gd))
	print("scripts/khaby_lines.gd  talk %.1f s" % talk_end)


if __name__ == "__main__":
	main()
