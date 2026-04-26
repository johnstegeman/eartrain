# EarTrain CI — Lesson Primitives

This document is the canonical reference for all exercise primitive types.
It drives: the `ExercisePrimitive` protocol implementations, the `.etplan` JSON schema,
and the set of steps available when authoring custom lesson plans.

**Status key:** `built` / `planned` / `future`

---

## Primitive Index

| type | status | input mode | description |
|------|--------|------------|-------------|
| `contour` | built | listen-only | Two notes: higher / lower / same |
| `interval-id` | built | listen-only | Hear an interval, identify it by name |
| `interval-playback` | built | guitar | Hear an interval, play it back |
| `pitch-match` | planned | listen-only | Single note: same as reference? yes/no |
| `sequence-playback` | planned | guitar | Hear a note sequence (3–8 notes), play it back |
| `scale-degree` | planned | listen-only | Hear a note in a key, identify scale degree |
| `cadence` | planned | listen-only | Hear a two-chord move, identify resolution type |
| `chord-quality` | planned | listen-only | Hear a chord, identify major/minor/dom7/min7 |
| `harmonic-interval` | planned | listen-only | Hear two simultaneous notes, identify the interval |
| `chord-progression` | future | listen-only | Hear a 2–4 chord progression, identify it |
| `mode-flavor` | future | listen-only | Hear a phrase, identify its tonal color |
| `call-response` | future | guitar | Hear a phrase, play a musical answer |

---

## Primitive Specifications

### `contour`
**What it trains:** Melodic direction — up, down, or same pitch.
The most fundamental pitch discrimination task; the research baseline for CI users.

**Exercise loop:**
1. App plays two notes sequentially
2. User taps: Higher / Lower / Same
3. Immediate feedback; next pair

**Step parameters:**
```json
{
  "type": "contour",
  "semitoneRange": [2, 12],
  "registers": ["low", "mid", "high"],
  "trials": 20,
  "passRate": 0.80
}
```
`semitoneRange`: [min, max] semitone gap between the two notes. Wider = easier.

**CI note:** Easiest CI task; use large `semitoneRange` for new users. Narrow to [1,3] as difficulty ramps.

---

### `interval-id`
**What it trains:** Recognizing what an interval *sounds like* — perceptual category formation.
Listening only; no guitar required. Teaches the sound before expecting playback.

**Exercise loop:**
1. App plays root + interval as guitar samples (or sine fallback)
2. User selects from a multiple-choice list of interval names
3. Immediate correct/incorrect feedback; option to replay

**Step parameters:**
```json
{
  "type": "interval-id",
  "focusIntervals": ["m3", "M3", "P5", "P8"],
  "foilStrategy": "adjacent",
  "registers": ["mid"],
  "trials": 16,
  "passRate": 0.75
}
```
`focusIntervals`: which intervals appear as correct answers and foils.
`foilStrategy`: how wrong-answer options are chosen — `"distant"` (far interval), `"adjacent"` (1 semitone away), `"random"`.

**CI note:** Start with `foilStrategy: "distant"` (P8 vs. M2); narrow toward `"adjacent"` as CI user improves.

---

### `interval-playback`
**What it trains:** Playing a heard interval on guitar. The core CI drill loop.
Requires mic/audio interface input.

**Exercise loop:**
1. App plays root + interval
2. User plays the interval on guitar
3. Pitch detection grades the response: correct / close / wrong / octaveDisplaced
4. Audio + visual feedback; fretboard hint optional

**Step parameters:**
```json
{
  "type": "interval-playback",
  "intervals": ["m3", "M3", "P5"],
  "registers": ["low", "mid"],
  "timbre": "acoustic",
  "showFretboardHint": true,
  "trials": 12,
  "streakToAdvance": 3
}
```
`timbre`: `"sine"` / `"acoustic"` / `"clean-electric"` / `"overdrive"` — overrides user setting for this step.
`showFretboardHint`: force hints on or off regardless of session setting.
`streakToAdvance`: advance after N consecutive correct (alternative to `passRate`).

---

### `pitch-match`
**What it trains:** Single-note same/different discrimination — the most atomic pitch task.
Pre-contour; useful for onboarding assessment and very early sessions.

**Exercise loop:**
1. App plays a reference note, then a comparison note
2. User taps: Same / Different
3. If "different": optionally show cents deviation

**Step parameters:**
```json
{
  "type": "pitch-match",
  "deviationCents": [0, 25, 50, 100],
  "registers": ["mid"],
  "trials": 10,
  "passRate": 0.80
}
```
`deviationCents`: pool of deviation values used for "different" trials. 0 = same pair. Mix determines difficulty.

**CI note:** Even this can be challenging in certain registers for CI users. Good diagnostic primitive.

---

### `sequence-playback`
**What it trains:** Short melody echo — hear a sequence of notes, play it back.
Phase 2 in the roadmap; builds directly on `interval-playback` infrastructure.

**Exercise loop:**
1. App plays a 3–8 note sequence
2. User plays it back on guitar
3. Note-by-note accuracy feedback (correct / close / wrong per note)
4. Sequence can be replayed on demand

**Step parameters:**
```json
{
  "type": "sequence-playback",
  "noteCount": [3, 5],
  "scale": "pentatonic-minor",
  "registers": ["mid"],
  "timbre": "acoustic",
  "allowReplay": true,
  "trials": 6,
  "passRate": 0.67
}
```
`noteCount`: [min, max] notes in the generated sequence.
`scale`: constrains which notes appear — `"pentatonic-minor"`, `"pentatonic-major"`, `"blues"`, `"chromatic"`.
`allowReplay`: whether the user can hear the sequence again before playing.

---

### `scale-degree`
**What it trains:** Hearing a note *in tonal context* — which scale degree is it?
Bridges abstract interval knowledge to functional harmony and improvisation.

**Exercise loop:**
1. App plays a root/key drone or chord, then a single note
2. User identifies the scale degree (1, 2, 3, 4, 5, 6, 7 — or solfège)
3. Root is always audible during the task

**Step parameters:**
```json
{
  "type": "scale-degree",
  "key": "A",
  "scale": "pentatonic-minor",
  "focusDegrees": [1, 3, 5, 7],
  "droneType": "chord",
  "trials": 12,
  "passRate": 0.75
}
```
`focusDegrees`: which scale degrees appear in this step.
`droneType`: `"note"` (root only) or `"chord"` (I chord) — chord adds harmonic context.

**CI note:** The drone gives a tonal anchor that makes the task easier than pure interval ID. Good on-ramp to functional hearing.

---

### `cadence`
**What it trains:** Hearing harmonic direction and resolution — does this phrase land or ask a question?
Building block for chord progression recognition.

**Exercise loop:**
1. App plays a two-chord movement (e.g., V→I or V alone)
2. User identifies: Resolved (V→I) / Unresolved (V) / Lift (IV→I)
3. Start with binary (resolved vs. unresolved); expand to 3-way when ready

**Step parameters:**
```json
{
  "type": "cadence",
  "focusCadences": ["authentic", "half", "plagal"],
  "key": "A",
  "voicing": "guitar-open",
  "trials": 10,
  "passRate": 0.80
}
```
`focusCadences`: `"authentic"` (V→I), `"half"` (→V), `"plagal"` (IV→I), `"deceptive"` (V→vi).
`voicing`: `"guitar-open"`, `"guitar-barre"`, `"piano"` — timbre of the chord playback.

---

### `chord-quality`
**What it trains:** Hearing the color of a chord — major, minor, dominant, etc.
No guitar required; purely aural.

**Exercise loop:**
1. App plays a chord (arpeggiated or strummed)
2. User identifies the quality from options
3. Start with major vs. minor; add dom7/min7 as foils

**Step parameters:**
```json
{
  "type": "chord-quality",
  "focusQualities": ["major", "minor"],
  "foilCount": 2,
  "voicing": "guitar-open",
  "arpeggiate": true,
  "trials": 12,
  "passRate": 0.75
}
```
`focusQualities`: `"major"`, `"minor"`, `"dom7"`, `"min7"`, `"maj7"`, `"dim"`, `"aug"`.
`arpeggiate`: play notes sequentially (true) or simultaneously (false). Arpeggiated is easier for CI.

**CI note:** Simultaneous overtones are harder for CI users. Arpeggiate first; move to strummed as confidence builds.

---

### `harmonic-interval`
**What it trains:** Identifying an interval when both notes are heard simultaneously.
Guitar-specific: double stops and dyads are core technique vocabulary.

**Exercise loop:**
1. App plays two notes at the same time
2. User identifies the interval from multiple-choice options
3. Can replay; foil strategy same as `interval-id`

**Step parameters:**
```json
{
  "type": "harmonic-interval",
  "focusIntervals": ["P5", "m3", "M3"],
  "foilStrategy": "adjacent",
  "registers": ["mid"],
  "trials": 10,
  "passRate": 0.70
}
```
Same parameter set as `interval-id` — intentional, for plan-authoring consistency.

**CI note:** More perceptually demanding than `interval-id` (two simultaneous frequencies). Sequence: `interval-id` → `harmonic-interval` on the same interval set.

---

### `chord-progression`
**What it trains:** Identifying common functional harmonic patterns by ear.
The practical payoff of cadence + chord quality training.

**Exercise loop:**
1. App plays a 2–4 chord sequence in a key
2. User identifies the Roman numeral pattern from options (e.g., I–IV–V, I–vi–IV–V)
3. Can include common progressions: blues (I–IV–V), pop (I–V–vi–IV), jazz ii–V–I

**Step parameters:**
```json
{
  "type": "chord-progression",
  "focusProgressions": ["I-IV-V", "I-vi-IV-V", "ii-V-I"],
  "key": "A",
  "voicing": "guitar-open",
  "tempo": 80,
  "trials": 8,
  "passRate": 0.75
}
```
`focusProgressions`: named progressions drawn from a defined library.
`tempo`: BPM for chord playback (slower = easier).

---

### `mode-flavor`
**What it trains:** Recognizing the tonal color of a scale or phrase — not by name but by feel.
Practical for knowing "this wants pentatonic minor" when jamming.

**Exercise loop:**
1. App plays a short melodic phrase (4–8 notes) in a mode
2. User identifies the flavor: Major / Minor / Blues / Dorian / Mixolydian / etc.
3. Start binary (major vs. minor); expand gradually

**Step parameters:**
```json
{
  "type": "mode-flavor",
  "focusModes": ["major", "minor", "blues"],
  "phraseLength": [4, 6],
  "trials": 10,
  "passRate": 0.75
}
```
`focusModes`: `"major"`, `"minor"`, `"pentatonic-major"`, `"pentatonic-minor"`, `"blues"`, `"dorian"`, `"mixolydian"`.

---

### `call-response`
**What it trains:** Playing a musical *answer* to a heard phrase — not echo, but dialogue.
Develops improvisational vocabulary and phrase-level musical thinking.

**Exercise loop:**
1. App plays a 2–4 note "call" phrase
2. User plays any musical response on guitar (same length or free)
3. App grades: detected notes are in-key (pass) or out-of-key (flag)
4. No single "correct" answer — musical freedom within key constraints

**Step parameters:**
```json
{
  "type": "call-response",
  "key": "A",
  "scale": "pentatonic-minor",
  "callLength": [2, 4],
  "responseLengthBeats": 4,
  "gradingMode": "in-key",
  "trials": 8,
  "passRate": 0.75
}
```
`gradingMode`: `"in-key"` (pass if all detected notes are diatonic) or `"free"` (no grading, review only).

---

## Step Advancement Fields (all primitives)

Exactly one of `passRate`, `streakToAdvance`, or neither (fixed trial count) must be set.

| field | type | meaning |
|-------|------|---------|
| `trials` | Int | Number of attempts (window size for passRate; total for fixed) |
| `passRate` | Float | Advance when correct/total ≥ value over last `trials` |
| `streakToAdvance` | Int | Advance after N consecutive correct |
| `onPass` | String | `"next"` (default) |
| `onFail` | String | `"repeat"` (default) |

---

## .etplan Step Type Values

```
"contour"            built
"interval-id"        built
"interval-playback"  built
"pitch-match"        planned
"sequence-playback"  planned
"scale-degree"       planned
"cadence"            planned
"chord-quality"      planned
"harmonic-interval"  planned
"chord-progression"  future
"mode-flavor"        future
"call-response"      future
```

Unknown `type` values encountered at parse time: `LessonPlanValidator` rejects the plan
with a descriptive error before the preview modal. Never silently skip unknown steps.

---

## Recommended Curriculum Ladder

```
pitch-match              ← atomic same/different
    ↓
contour                  ← melodic direction
    ↓
interval-id              ← perceptual category formation (listen only)
    ↓
interval-playback        ← guitar response (core CI drill)
    ↓
scale-degree             ← tonal context
    ↓
harmonic-interval        ← simultaneous dyads
    ↓
cadence                  ← harmonic direction
    ↓
chord-quality            ← chord color
    ↓
chord-progression        ← functional patterns
    ↓
mode-flavor              ← tonal color of phrases
    ↓
sequence-playback        ← melody echo (Phase 2)
    ↓
call-response            ← improvisational dialogue
```

Steps can be combined and reordered freely in custom `.etplan` files.
The ladder above represents the recommended difficulty progression for CI users.
