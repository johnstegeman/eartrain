# EarTrain CI — Build Learnings

Real observations from building and testing the app. Includes CI-specific findings,
audio engineering discoveries, and links to supporting research where available.

---

## CI Perception

### Contour difficulty has two separable axes: interval size and register/frequency

**Observed (2026-04-27):** User consistently got a specific note pair wrong (G#4 → F#5,
a 10-semitone / minor 7th ascending interval in the high register) even after multiple
replays. When told the note names, they recognized the pair was in a frequency range
that is subjectively confusing with their CI.

**Insight:** For CI users, contour errors have at least two independent root causes:
1. **Interval type** — large intervals (7–12 semitones) can be hard regardless of register
2. **Frequency/register** — specific frequency ranges may be poorly discriminated by their
   CI processor's channel mapping, making contour in those ranges hard at ANY interval size
3. **Combination** — large intervals specifically in a problematic frequency band

The Phase 1.7 bucket grid (semitone-gap-group × octave-band) is designed to disentangle
these. Aggregate error data should eventually allow Audie to say: "Your error rate on
large intervals in the high register is 73% vs 24% everywhere else — this is frequency-
map difficulty, not interval-type difficulty."

**For adaptive training:** Flagged note pairs (user-reported via "Flag as tricky") are a
strong prior signal. They should feed both the ContourSampler weights AND the per-bucket
error rate used by the mastery engine.

**Supporting research:** CI pitch discrimination thresholds average 7.6 semitones vs 1.1
for normal hearing (meta-analysis, PMC10603281). A 5-semitone natural breakpoint exists
for MMN cortical responses in CI users. Both suggest that frequency-channel crowding in
specific registers is a real clinical phenomenon, not user error.

---

### Pure sine tones sound "distorted" in the middle — this is expected CI perception

**Observed:** When playing a pure sine tone (e.g. A4 → E5 interval), the user reported
the tones sounded "a little distorted in the middle." After eliminating click artefacts
(hard amplitude cutoff → one-pole smoother), residual "distortion" remained that is
consistent across notes and not present in the audio signal itself.

**Conclusion:** This is CI perception of pure sine tones, not an audio engineering
problem. CIs process sound via electrode stimulation that approximates frequency channels
but has lower frequency resolution than normal hearing. A pure sine wave — by definition
the most spectrally "clean" signal — may be perceived as distorted or rough because it
stimulates only a narrow electrode channel with no harmonic context.

**Supporting research:**

From [Place-Pitch Interval Perception with a CI (PMC 2022)](https://pmc.ncbi.nlm.nih.gov/articles/PMC8915956/):
> "...cochlear implant listeners show degraded frequency discrimination compared to
> normal-hearing listeners, particularly for pure tones..."

From [Computer-based interval training for CI users, Frontiers 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9363605/):
> "Pure tone stimuli were used to eliminate timbre as a variable and isolate frequency
> discrimination..." (methodology note — published CI training studies deliberately use
> pure tones precisely because they isolate the frequency discrimination task, even
> though CI users may perceive them as unnatural)

**Implication for app design:**
- The "distortion" is perceptual, not a signal quality issue. Don't try to "fix" it by
  adding harmonics — that would reintroduce timbre as a variable in the training task.
- Individual variation is expected: some CI users may find pure tones easier to
  distinguish than complex tones; others may find them harder. Calibration (Phase 0)
  will surface this per user.
- The feedback audio cues (correct/close/wrong tones played after each response) should
  use large-interval contrasts, not subtle pitch differences, per the accessibility spec.

---

## Audio Engineering

### Hard amplitude cutoff produces audible clicks in sine oscillators

**Observed:** Setting `amplitude = 0` immediately at note end produced a click on every
note boundary (step 4 testing).

**Fix:** One-pole lowpass smoother on amplitude with 20ms time constant. Each audio
frame: `currentAmplitude += (targetAmplitude - currentAmplitude) * smoothingCoeff`.
Eliminates clicks on any amplitude change including note start, end, and frequency
transitions.

---

## Platform / Infrastructure

### SoundpipeAudioKit is incompatible with Swift 6.3

**Observed:** Building with SoundpipeAudioKit 5.7.4 under Swift 6.3 fails with:
`error: import of C++ module 'Soundpipe' appears within extern "C" language linkage specification`

**Root cause:** Swift 6.3 uses a stricter Clang that disallows C++ module imports inside
`extern "C"` blocks. SoundpipeAudioKit's Soundpipe C library headers do this.

**Fix:** Replaced `PitchTap` (SoundpipeAudioKit) with a custom normalized autocorrelation
pitch detector using `Accelerate/vDSP`. This is actually more appropriate for guitar
because autocorrelation finds the fundamental period regardless of harmonic strength,
whereas FFT peak-picking can lock onto overtones on low strings.

### SPM executables don't bring their window to the front on launch

**Observed:** First launch of the app showed the mic as active (permission granted, engine
running) but no visible window.

**Fix:** `NSApp.activate(ignoringOtherApps: true)` in `applicationDidFinishLaunching` via
`@NSApplicationDelegateAdaptor`. Required for any SwiftUI app running as a bare SPM
executable (no `.app` bundle).

### AVAudioEngine acts as CI Bluetooth keep-alive

**Observed / expected:** A running `AVAudioEngine` keeps the macOS audio session active,
which prevents CI Bluetooth stream suspension. The `IntervalPlayer`'s `AVAudioSourceNode`
outputs silent frames when not playing an interval, maintaining the audio session
continuously. This replicates the "silent YouTube video" workaround without user action.

**Status:** Validated on real CI Bluetooth device (2026-04-25). Stream stays active
during long silences with engine running. No "silent YouTube video" workaround needed.

---

## Pitch Detection

### Autocorrelation is more reliable than FFT for guitar on low strings

**Observed:** FFT peak-picking with a 4096-sample buffer at 44100 Hz gives ~10.77 Hz
per bin — too coarse to reliably identify low guitar strings (E2 = 82.41 Hz, A2 = 110 Hz).
Guitar also produces strong overtones that can push the FFT peak away from the fundamental.

**Fix:** Normalized autocorrelation with parabolic interpolation. Finds the fundamental
period directly (first significant peak in the ACF after the zero crossing), independent
of harmonic content. Validated accurate across the full guitar fretboard.
