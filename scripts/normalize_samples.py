#!/usr/bin/env python3
"""
normalize_samples.py — Perceptually-equal loudness normalization for EarTrain CI guitar samples.

Method
------
Uses ISO 226:2003 equal-loudness-level contours to compute a per-note frequency
correction, then adjusts each sample so all notes are perceived as equally loud
by a normal-hearing listener.

The perceived level of a sample at frequency f with RMS level L (dBFS) is:
    perceived = L - W(f)
where W(f) = Lp(f, N_ref) - Lp(1000, N_ref) is the extra dB that frequency f
needs to sound as loud as 1 kHz at reference phon level N_ref.

For each sample, the applied gain is:
    G = P_target - L + W(f)
where P_target is the median perceived level across all notes and timbres.

Clipping protection: gain is capped so peak stays ≤ PEAK_CEILING_DBFS.

Usage
-----
    python3 scripts/normalize_samples.py [--dry-run]

Input:  EarTrain/Sources/EarTrainLib/Samples/{timbre}/note_0XX.wav
Output: EarTrain/Sources/EarTrainLib/Samples_normalized/{timbre}/note_0XX.wav
        scripts/normalization_log.csv  (per-note gain table for audit)
"""

import argparse
import csv
import math
import os
import sys

import numpy as np
import soundfile as sf
from scipy.interpolate import interp1d

# ---------------------------------------------------------------------------
# ISO 226:2003 Table 1  — reference data for equal-loudness contours
# Columns: frequency (Hz), alpha_f, L_u (dB), T_f (dB)
# ---------------------------------------------------------------------------
ISO226_TABLE = [
    # f        αf       Lu      Tf
    (20,    0.532, -31.6,  78.5),
    (25,    0.506, -27.2,  68.7),
    (31.5,  0.480, -23.0,  59.5),
    (40,    0.455, -19.1,  51.1),
    (50,    0.432, -15.9,  44.0),
    (63,    0.409, -13.0,  37.5),
    (80,    0.387, -10.3,  31.5),
    (100,   0.367,  -8.1,  26.5),
    (125,   0.349,  -6.2,  22.1),
    (160,   0.330,  -4.5,  17.9),
    (200,   0.315,  -3.1,  14.4),
    (250,   0.301,  -2.0,  11.4),
    (315,   0.288,  -1.1,   8.6),
    (400,   0.276,  -0.4,   6.2),
    (500,   0.267,   0.0,   4.4),
    (630,   0.259,   0.3,   3.0),
    (800,   0.253,   0.5,   2.2),
    (1000,  0.250,   0.0,   2.4),
    (1250,  0.246,  -2.7,   3.5),
    (1600,  0.244,  -4.1,   1.7),
    (2000,  0.243,  -1.0,  -1.3),
    (2500,  0.243,   1.7,  -4.2),
    (3150,  0.243,   2.5,  -6.0),
    (4000,  0.242,   1.2,  -5.4),
    (5000,  0.242,  -2.1,  -1.5),
    (6300,  0.245,  -7.1,   6.0),
    (8000,  0.254, -11.2,  12.6),
    (10000, 0.271, -10.7,  13.9),
    (12500, 0.301,  -3.1,  12.3),
]

_freqs   = np.array([r[0] for r in ISO226_TABLE], dtype=float)
_alphas  = np.array([r[1] for r in ISO226_TABLE], dtype=float)
_lus     = np.array([r[2] for r in ISO226_TABLE], dtype=float)
_tfs     = np.array([r[3] for r in ISO226_TABLE], dtype=float)

# Build interpolators (log-frequency axis for better behaviour between points)
_log_f   = np.log10(_freqs)
_interp_alpha = interp1d(_log_f, _alphas, kind='cubic', fill_value='extrapolate')
_interp_lu    = interp1d(_log_f, _lus,    kind='cubic', fill_value='extrapolate')
_interp_tf    = interp1d(_log_f, _tfs,    kind='cubic', fill_value='extrapolate')


def iso226_spl(freq_hz: float, phons: float) -> float:
    """Return the SPL (dB) needed at `freq_hz` to produce `phons` loudness level.

    Uses ISO 226:2003 equation 1.
    """
    lf = math.log10(max(freq_hz, 20.0))
    af = float(_interp_alpha(lf))
    lu = float(_interp_lu(lf))
    tf = float(_interp_tf(lf))

    # ISO 226:2003 equation 1
    bf = (0.4 * 10.0 ** ((tf + lu) / 10.0 - 9.0)) ** af
    inner = 4.47e-3 * (10.0 ** (0.025 * phons) - 1.15) + bf
    if inner <= 0:
        return tf  # below threshold — clamp to hearing threshold
    lp = (10.0 / af) * math.log10(inner) - lu + 94.0
    return lp


# Reference SPL at 1 kHz for the chosen phon level.
# 70 phons is a comfortable instrument-listening level.
REFERENCE_PHONS = 70.0
SPL_1KHZ = iso226_spl(1000.0, REFERENCE_PHONS)  # = 70.0 dB by definition


def equal_loudness_correction(freq_hz: float) -> float:
    """Return W(f): dB of extra gain needed at `freq_hz` to sound as loud as 1 kHz.

    Positive  → needs boosting (low frequencies)
    Near zero → already roughly as loud as 1 kHz (mid frequencies)
    Negative  → needs attenuation (if louder than 1 kHz)
    """
    spl_f = iso226_spl(freq_hz, REFERENCE_PHONS)
    return spl_f - SPL_1KHZ


def midi_to_hz(midi: int) -> float:
    """Standard MIDI-to-Hz conversion."""
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def rms_dbfs(audio: np.ndarray) -> float:
    """RMS level in dBFS. Returns -96 for silence."""
    rms = float(np.sqrt(np.mean(audio.astype(np.float64) ** 2)))
    if rms < 1e-10:
        return -96.0
    return 20.0 * math.log10(rms)


def peak_dbfs(audio: np.ndarray) -> float:
    peak = float(np.max(np.abs(audio.astype(np.float64))))
    if peak < 1e-10:
        return -96.0
    return 20.0 * math.log10(peak)


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
REPO_ROOT     = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAMPLES_IN    = os.path.join(REPO_ROOT, "EarTrain", "Sources", "EarTrainLib", "Samples")
SAMPLES_OUT   = os.path.join(REPO_ROOT, "EarTrain", "Sources", "EarTrainLib", "Samples_normalized")
LOG_CSV       = os.path.join(REPO_ROOT, "scripts", "normalization_log.csv")

TIMBRES       = ["acoustic_steel", "clean_electric", "overdrive"]
MIDI_LOW      = 40   # E2
MIDI_HIGH     = 81   # A5
PEAK_CEILING  = -1.0  # dBFS — headroom to prevent clipping


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true",
                        help="Compute gains and print log without writing files")
    args = parser.parse_args()

    # ------------------------------------------------------------------
    # Pass 1: load every sample, measure RMS + equal-loudness correction
    # ------------------------------------------------------------------
    print("Pass 1: measuring levels …")
    records = []  # list of dicts

    for timbre in TIMBRES:
        timbre_dir = os.path.join(SAMPLES_IN, timbre)
        if not os.path.isdir(timbre_dir):
            print(f"  WARNING: {timbre_dir} not found — skipping")
            continue

        for midi in range(MIDI_LOW, MIDI_HIGH + 1):
            fname = f"note_{midi:03d}.wav"
            fpath = os.path.join(timbre_dir, fname)
            if not os.path.isfile(fpath):
                print(f"  WARNING: {fpath} missing — skipping")
                continue

            audio, sr = sf.read(fpath, dtype='float32', always_2d=False)
            freq      = midi_to_hz(midi)
            w_f       = equal_loudness_correction(freq)
            actual_rms = rms_dbfs(audio)
            actual_peak = peak_dbfs(audio)
            perceived  = actual_rms - w_f   # perceived level (relative to 1 kHz ref)

            records.append(dict(
                timbre=timbre,
                midi=midi,
                freq=freq,
                fname=fname,
                fpath=fpath,
                audio=audio,
                sr=sr,
                w_f=w_f,
                actual_rms=actual_rms,
                actual_peak=actual_peak,
                perceived=perceived,
            ))

    if not records:
        print("ERROR: no samples found.")
        sys.exit(1)

    # ------------------------------------------------------------------
    # Choose target perceived level = median across all samples.
    # Using median (not mean) to be robust against outlier samples.
    # ------------------------------------------------------------------
    all_perceived = [r['perceived'] for r in records]
    p_target = float(np.median(all_perceived))
    print(f"\nPerceived level stats (dBFS equiv at 1 kHz):")
    print(f"  min    = {min(all_perceived):.1f} dBFS")
    print(f"  median = {p_target:.1f} dBFS  ← target")
    print(f"  max    = {max(all_perceived):.1f} dBFS")
    print(f"  spread = {max(all_perceived) - min(all_perceived):.1f} dB")

    # Print ISO 226 correction for a few anchor notes for transparency
    print(f"\nISO 226 correction at {REFERENCE_PHONS:.0f} phons (positive = needs boost):")
    for m in [40, 45, 52, 57, 64, 69, 76, 81]:
        f = midi_to_hz(m)
        w = equal_loudness_correction(f)
        note_names = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B']
        name = note_names[m % 12] + str(m // 12 - 1)
        print(f"  MIDI {m:2d} ({name:4s}, {f:6.1f} Hz): W = {w:+.1f} dB")

    # ------------------------------------------------------------------
    # Pass 2: compute per-sample gain, check for clipping
    # ------------------------------------------------------------------
    print("\nPass 2: computing gains …")
    clipped = 0
    for r in records:
        # Ideal gain to hit perceived target
        ideal_gain = p_target - r['perceived']  # = p_target - actual_rms + w_f
        # Clipping cap: ensure peak + gain <= PEAK_CEILING
        headroom   = PEAK_CEILING - r['actual_peak']
        gain       = min(ideal_gain, headroom)
        if gain < ideal_gain:
            clipped += 1
        r['ideal_gain'] = ideal_gain
        r['applied_gain'] = gain
        r['new_rms']  = r['actual_rms'] + gain
        r['new_peak'] = r['actual_peak'] + gain
        r['new_perceived'] = r['new_rms'] - r['w_f']

    if clipped:
        print(f"  {clipped} sample(s) gain-capped to avoid clipping (peak ceiling {PEAK_CEILING} dBFS)")

    new_perceived = [r['new_perceived'] for r in records]
    print(f"\nAfter normalization, perceived level spread:")
    print(f"  min = {min(new_perceived):.1f} dBFS")
    print(f"  max = {max(new_perceived):.1f} dBFS")
    print(f"  spread = {max(new_perceived) - min(new_perceived):.1f} dB  (was {max(all_perceived) - min(all_perceived):.1f} dB)")

    # ------------------------------------------------------------------
    # Write CSV log
    # ------------------------------------------------------------------
    with open(LOG_CSV, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=[
            'timbre','midi','note','freq_hz','w_f_db',
            'orig_rms_dbfs','orig_peak_dbfs',
            'ideal_gain_db','applied_gain_db',
            'new_rms_dbfs','new_peak_dbfs','new_perceived_dbfs'
        ])
        writer.writeheader()
        note_names = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B']
        for r in records:
            note = note_names[r['midi'] % 12] + str(r['midi'] // 12 - 1)
            writer.writerow(dict(
                timbre=r['timbre'],
                midi=r['midi'],
                note=note,
                freq_hz=f"{r['freq']:.2f}",
                w_f_db=f"{r['w_f']:.2f}",
                orig_rms_dbfs=f"{r['actual_rms']:.2f}",
                orig_peak_dbfs=f"{r['actual_peak']:.2f}",
                ideal_gain_db=f"{r['ideal_gain']:.2f}",
                applied_gain_db=f"{r['applied_gain']:.2f}",
                new_rms_dbfs=f"{r['new_rms']:.2f}",
                new_peak_dbfs=f"{r['new_peak']:.2f}",
                new_perceived_dbfs=f"{r['new_perceived']:.2f}",
            ))
    print(f"\nLog written to {LOG_CSV}")

    if args.dry_run:
        print("\n[dry-run] No files written.")
        return

    # ------------------------------------------------------------------
    # Pass 3: apply gain and write normalized files
    # ------------------------------------------------------------------
    print("\nPass 3: writing normalized files …")
    written = 0
    for r in records:
        out_dir = os.path.join(SAMPLES_OUT, r['timbre'])
        os.makedirs(out_dir, exist_ok=True)
        out_path = os.path.join(out_dir, r['fname'])

        gain_linear = 10.0 ** (r['applied_gain'] / 20.0)
        normalized  = r['audio'] * gain_linear

        # Write as 32-bit float WAV (lossless, same as input)
        sf.write(out_path, normalized, r['sr'], subtype='FLOAT')
        written += 1

    print(f"  Wrote {written} files to {SAMPLES_OUT}/")
    print("\nDone.")


if __name__ == "__main__":
    main()
