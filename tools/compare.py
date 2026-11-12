"""Compare the two ways of muting the bass on songs bassless has already separated.

    python tools/compare.py ~/Music/bassless/<song> [...]

"resum" adds the drums, vocals and other stems back together (what most
separation tools hand you as the no-bass track); "subtract" is the original
minus the bass stem (what bassless writes). Both are compared with the original
per frequency band, before bassless applies its final peak attenuation.
Needs numpy, scipy and soundfile.
"""

import argparse
import os

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfiltfilt

BANDS = [(40, 250, "40-250 Hz"), (300, 4000, "300 Hz-4 kHz"), (1000, 8000, "1-8 kHz")]


def power(x):
    return float(np.mean(np.square(x, dtype=np.float64)))


def db(ratio):
    return 10 * np.log10(ratio + 1e-30)


def band(x, sr, lo, hi):
    return sosfiltfilt(butter(8, [lo, hi], btype="band", fs=sr, output="sos"), x, axis=0)


def compare(folder):
    stems_dir = os.path.join(folder, ".stems")
    if not os.path.isdir(os.path.join(stems_dir, "htdemucs_ft")):
        print(f"\n{folder}: no htdemucs_ft stems (run bassless with a bass, drums, vocals or other stem first)")
        return
    ref, sr = sf.read(os.path.join(stems_dir, "reference.wav"), always_2d=True)
    # bassless separates the song at half level (see the script); scale the stems back.
    settings_file = os.path.join(stems_dir, "htdemucs_ft", "settings")
    settings = open(settings_file).read() if os.path.exists(settings_file) else ""
    scale = 2.0 if "input=half" in settings else 1.0
    stems = {}
    for name in ("bass", "drums", "vocals", "other"):
        data, rate = sf.read(os.path.join(stems_dir, "htdemucs_ft", f"{name}.wav"), always_2d=True)
        if rate != sr or data.shape[1] != ref.shape[1]:
            raise SystemExit(f"{name}.wav is {rate} Hz x {data.shape[1]}, reference is {sr} Hz x {ref.shape[1]}")
        stems[name] = data * scale
    n = min(len(ref), *(len(s) for s in stems.values()))
    longest = max(len(ref), *(len(s) for s in stems.values()))
    if longest - n > 0:
        print(f"  note: lengths differ by {longest - n} samples, compared the first {n}")
    ref = ref[:n]
    stems = {k: v[:n] for k, v in stems.items()}
    resum = stems["drums"] + stems["vocals"] + stems["other"]
    subtract = ref - stems["bass"]

    print(f"\n{os.path.basename(os.path.normpath(folder))} ({n / sr:.0f} s)")
    if power(ref) == 0:
        print("  the original is silent, nothing to compare")
        return
    print(f"  four stems summed vs original: off by {db(power(ref - sum(stems.values())) / power(ref)):+.1f} dB")
    print(f"  peak of the subtracted track: {np.abs(subtract).max():.3f} (original {np.abs(ref).max():.3f})")
    print(f"  {'band':14s} {'level change':>22s}   {'difference from original':>26s}")
    print(f"  {'':14s} {'resum':>10s} {'subtract':>11s}   {'resum':>12s} {'subtract':>13s}")
    for lo, hi, label in BANDS:
        try:
            o, r, s = band(ref, sr, lo, hi), band(resum, sr, lo, hi), band(subtract, sr, lo, hi)
        except ValueError:  # sosfiltfilt needs a minimum length
            print(f"  {label:14s} too short to filter")
            continue
        po = power(o)
        if po == 0:
            print(f"  {label:14s} nothing in this band in the original")
            continue
        print(f"  {label:14s} {db(power(r) / po):+9.2f}  {db(power(s) / po):+10.2f}   "
              f"{db(power(o - r) / po):+11.1f}  {db(power(o - s) / po):+12.1f}  dB")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("folders", nargs="+", help="bassless output folders (with .stems/)")
    for folder in parser.parse_args().folders:
        compare(folder)


if __name__ == "__main__":
    main()
