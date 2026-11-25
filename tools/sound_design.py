#!/usr/bin/env python3
"""ROT sound design. Synthesizes every sound in the game (no recordings, no samples).

    pip install numpy scipy
    python3 tools/sound_design.py            # all sounds
    python3 tools/sound_design.py chase_tung # just one

Writes 44.1 kHz WAVs into sounds/. Looping sounds carry a 'smpl' loop chunk that
Godot's importer picks up automatically.
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp import write  # noqa: E402
from sounds_a import SOUNDS  # noqa: E402
import sounds_b  # noqa: E402,F401  (registers more sounds)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")


def main():
    names = sys.argv[1:] or sorted(SOUNDS)
    for n in names:
        fn, loop, peak, rms = SOUNDS[n]
        t0 = time.time()
        x = fn()
        write(os.path.join(OUT, n + ".wav"), x, loop=loop, peak=peak, rms=rms)
        print(f"{n:22s} {x.shape[-1] / 44100:6.2f}s  {'loop' if loop else '    '}  {time.time() - t0:5.2f}s")


if __name__ == "__main__":
    main()
