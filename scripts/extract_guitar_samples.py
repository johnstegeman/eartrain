#!/usr/bin/env python3
"""
extract_guitar_samples.py

Extracts per-note guitar WAV samples from FluidR3_GM.sf2 (or any GM soundfont)
for use in EarTrain CI.

Requirements:
    pip install pyfluidsynth
    brew install fluidsynth

Usage:
    python3 extract_guitar_samples.py /path/to/FluidR3_GM.sf2 ./output_samples

Output structure:
    output_samples/
        acoustic_steel/    note_040.wav, note_041.wav, ... note_081.wav
        clean_electric/    note_040.wav, ...
        overdrive/         note_040.wav, ...

FluidR3_GM download: https://github.com/musescore/MuseScore/tree/master/share/sound
or: https://member.keymusician.com/Member/FluidR3_GM/index.html
"""

import argparse
import os
import struct
import wave

# --- Configuration ---

# MIDI note range: E2 (40) to A5 (81)
# Covers all interval note values needed: root E2 to highest interval note from A4 root
MIDI_LOW  = 40
MIDI_HIGH = 81

# Note duration in seconds. 2.0s gives a clear attack + some sustain.
NOTE_DURATION_S = 2.0

# Velocity (0-127). 80 = medium-forte, natural guitar tone.
VELOCITY = 80

# GM program numbers (0-indexed) for the three timbres.
# FluidR3_GM uses General MIDI standard:
#   24 = Acoustic Guitar (Nylon)
#   25 = Acoustic Guitar (Steel)  <-- warm acoustic
#   27 = Electric Guitar (Clean)  <-- bright clean
#   29 = Overdriven Guitar        <-- harmonic-rich overdrive
TIMBRES = {
    "acoustic_steel": 25,
    "clean_electric": 27,
    "overdrive":      29,
}

# Output: mono 44100 Hz WAV (matches app's AVAudioEngine default)
SAMPLE_RATE = 44100
CHANNELS    = 1

# --- Main ---

def extract(sf2_path: str, output_dir: str) -> None:
    try:
        import fluidsynth
    except ImportError:
        print("ERROR: pyfluidsynth not installed. Run: pip install pyfluidsynth")
        raise

    os.makedirs(output_dir, exist_ok=True)

    fs = fluidsynth.Synth(samplerate=float(SAMPLE_RATE))
    sfid = fs.sfload(sf2_path)
    if sfid == -1:
        raise RuntimeError(f"Failed to load soundfont: {sf2_path}")

    total = len(TIMBRES) * (MIDI_HIGH - MIDI_LOW + 1)
    done  = 0

    for timbre_name, program in TIMBRES.items():
        timbre_dir = os.path.join(output_dir, timbre_name)
        os.makedirs(timbre_dir, exist_ok=True)

        fs.program_select(0, sfid, 0, program)

        for midi in range(MIDI_LOW, MIDI_HIGH + 1):
            filename = os.path.join(timbre_dir, f"note_{midi:03d}.wav")

            # Render note to PCM samples
            fs.noteon(0, midi, VELOCITY)
            samples = fs.get_samples(int(SAMPLE_RATE * NOTE_DURATION_S))
            fs.noteoff(0, midi)
            # Let release tail decay (200ms)
            tail = fs.get_samples(int(SAMPLE_RATE * 0.2))
            fs.noteoff(0, midi)

            # fluidsynth returns interleaved stereo; downmix to mono
            stereo = samples + tail
            mono = [int((stereo[i] + stereo[i+1]) / 2)
                    for i in range(0, len(stereo), 2)]

            # Write WAV
            with wave.open(filename, 'w') as wf:
                wf.setnchannels(CHANNELS)
                wf.setsampwidth(2)       # 16-bit
                wf.setframerate(SAMPLE_RATE)
                wf.writeframes(struct.pack(f'<{len(mono)}h', *mono))

            done += 1
            print(f"[{done:3d}/{total}] {timbre_name}/note_{midi:03d}.wav  "
                  f"(MIDI {midi}, program {program})")

    fs.delete()
    print(f"\nDone. {done} WAV files written to: {output_dir}")
    print(f"To use in app: copy {output_dir}/ into EarTrain/Resources/Samples/")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract guitar samples from a GM soundfont")
    parser.add_argument("sf2",        help="Path to .sf2 soundfont file (e.g. FluidR3_GM.sf2)")
    parser.add_argument("output_dir", help="Output directory for WAV files")
    args = parser.parse_args()
    extract(args.sf2, args.output_dir)
