# EarTrain CI — Development Plan

Generated: 2026-04-26
Branch: natural-agenda

Status key: `done` / `next` / `planned` / `future`

---

## Companion persona + app name `planned`

The app should feel like a warm, encouraging coach — not a sterile drill tool.

### App name candidates

The name should sound like a real person — approachable, directly connected to
ears/music/guitar, and easy to pronounce (important for CI users reading a screen).
Insider musical puns (solfège, etc.) ruled out; needs to be self-evident.

| Name | Connection | Notes |
|------|-----------|-------|
| **Lyra** | the lyre is the original string instrument; Lyra is a real name | Warm, musical without jargon |
| **Aria** | a vocal melody; also contains "ear"; real first name | Slightly feminine but works |
| **Cori** | subtle "cochlea" reference; real name, warm | CI-specific without being medical |
| **Audie** | "audio" + sounds like Audrey; direct hearing link | Friendly, self-evident |
| **Echo** | sound echo; Greek myth name | Works but Amazon Echo is very branded |

**Decision: Audie** — no existing App Store apps with this exact name, direct
audio/hearing connection, sounds like a friendly real person. ✓

### Onboarding — ask for a name `planned`

On first launch (after mic permission): a single friendly screen.
- "Hi! I'm [App Name]. What should I call you?" — text field, placeholder "Your name or nickname"
- Stored in UserDefaults as `userDisplayName`
- Never required — "Skip" option defaults to no personalisation
- Can be changed in Settings

### Companion feedback system `planned`

The app speaks in first person as [App Name]. Feedback is contextual — not every trial,
only at meaningful moments. Rules:

**Positive moments**
- Streak of 3+ correct in a row → short praise ("Nice streak, [name]!")
- Accuracy in a bucket crosses 80% for first time → celebration ("You cracked the Major 3rd!")
- Session accuracy ≥ 10% above personal best → "New record!"
- 10th session milestone, 100-trial milestone, 500-trial milestone

**Struggle moments** (trigger ≥ 3 wrong in a row, or session accuracy < 40%)
- Empathy first: "That one's tricky — [interval] trips up a lot of people."
- Offer a concrete action (one of):
  - "Want me to back the difficulty down a notch?" → lower difficulty automatically
  - "Let's go back to the teaching phase for this one." → replay teaching for that interval
  - "Sometimes a short break helps. Come back when you're ready." → suggest break
  - "Want to try the Contour or Identification mode for a bit?" → mode switch suggestion

**Transition moments**
- First session ever: "Let's start easy and build from here."
- Returning after ≥ 3 days away: "[Name], welcome back! Let's shake off the rust."
- End of session: summary + one personal observation ("Your P5 is getting solid.")

**Delivery rules**
- Plain English, no jargon (no "semitone," "MIDI," "register" in feedback copy)
- Max one feedback message per ~5 trials to avoid noise
- Messages vary — keep a pool of 3–5 variants per category, pick randomly
- Never interrupt playback; queue messages to show after the current trial resolves
- Feedback copy lives in a dedicated `FeedbackCopy.swift` (easy to edit/localise)
- Tone: warm, real, slightly casual — like a good private music tutor

### Implementation sketch `planned`

```
CompanionEngine (ObservableObject)
  - userName: String          ← from UserDefaults
  - @Published var pendingMessage: CompanionMessage?

struct CompanionMessage: Identifiable {
  var id = UUID()
  var text: String
  var action: CompanionAction?   // optional CTA button
}

enum CompanionAction {
  case lowerDifficulty
  case replayTeaching
  case suggestBreak
  case switchMode(AppMode)
}
```

`CompanionEngine` is owned by `AppSession` and injected where needed.
Each ViewModel notifies it after grading a trial. The engine decides whether
to surface a message based on streak state, session stats, and the last-message
timestamp.

---

## Current state

Three exercise primitives are built and working:
- `contour` — higher/lower/same, two-note discrimination
- `interval-id` — hear an interval, multiple-choice identification
- `interval-playback` — hear an interval, play it back on guitar

Core audio infrastructure is solid: autocorrelation pitch detection, sample playback,
CI Bluetooth keep-alive. See LEARNINGS.md for resolved issues.

Outstanding TODOs from TODOS.md carried into this plan below.

---

## Phase 0 — Polish Before Testing

### 0.1 — Sample volume normalization `done`

**Problem:** Low guitar notes (E2–B3) are significantly quieter than mid/high notes.
The current `gainFactor = 0.7` in `SamplePlayer` is a flat scalar — it does nothing to
correct inter-note loudness differences. Testing is impeded because quiet low notes sound
like errors rather than correct responses.

**Approach — offline normalization script (preferred):**
Add `scripts/normalize_samples.py` that runs once on the raw WAV files:
- Measure RMS (or LUFS) of each `note_0XX.wav` per timbre
- Compute a target level (e.g., −20 dBFS RMS) based on the mid-register notes
  where perceived loudness for normal hearing is natural
- Apply a per-file gain so all notes land at the same perceived loudness
- Overwrite the WAV files in `EarTrain/Resources/Samples/`

This approach bakes normalization into the assets. No runtime overhead, no per-note
gain map to maintain in `SamplePlayer`.

**Future adaptive extension:** Per-user loudness calibration (CI users may have
different equal-loudness curves). Deferred. The offline normalization is the baseline
for normal hearing; adaptive per-user adjustment is layered on top later.

**Files touched:** `scripts/normalize_samples.py` (new), WAV assets regenerated.
No Swift changes needed unless we want to expose a master volume control in Settings.

---

## Phase 1 — Complete the Core Interval Trainer

### 1.1 — Protocol extraction for testability `done`
Extract `AudioPlaying` and `MicListening` protocols from `AudioEngineManager`.
Required before unit tests and lesson architecture.

```swift
protocol AudioPlaying { func playInterval(...) async; func stop() }
protocol MicListening  { var amplitude: Float { get }; var detectedHz: Float { get } }
```

Unblocks: ExerciseViewModel tests (see 1.2), LessonRunner (see Phase 2).

### 1.2 — ExerciseViewModel pitch detection unit tests `done`
Unit tests for the two-note detection pipeline in `ExerciseViewModel` lines 96–188:
`waitForStableNote()`, `waitForSilence()`, stability window, 10s timeout, 25-cent spread.
Inject `MockAudioPlayer` and `MockMicInput` via extracted protocols.
**Depends on:** 1.1

### 1.3 — Confusion matrix + ProgressView `done`
Log every trial to `[Interval: [Register: [ExerciseResult]]]`.
ProgressView shows interval × register heatmap (green→red) with per-cell drill-down.
Cells with < 5 trials shown muted. Session-by-session accuracy trend line.
Persist to `~/Library/Application Support/EarTrain/sessions/` + `cumulative.json`.

### 1.4 — HomeView + Session Start Sheet `planned`
HomeView: quick stats, Start Session CTA, Drill My Misses shortcut (greyed until
5 trials/bucket).
Session Start Sheet: duration grid (5/10/20/30/custom min), mode toggle
(Standard / Drill My Misses), settings summary row.

### 1.5 — End of Session screen `planned`
Stats grid: accuracy this session / delta vs. previous / cumulative time.
Top 2–3 confusion buckets surfaced. "View Progress" / "Start Another Session" CTAs.
12-hour milestone banner when cumulative time crosses threshold.

### 1.6 — Settings expansion `planned`
Root note, active interval set, register range, input device selector,
CI keep-alive toggle (on by default), fretboard hint level, pitch tolerance,
audio buffer size (Advanced), feedback delay (correct: 2s, wrong: 4s).

### 1.7 — Drill My Misses `planned`
Reads `cumulative.json`. Eligibility: ≥ 5 trials, error rate > 30%.
Ranks (interval, register) buckets by error rate. Generates a weighted session.
Available from HomeView and Session Start Sheet.

### 1.8 — TunerView `planned`
Chromatic tuner. Detected note name, Hz readout, cents deviation needle (±50 cents).
Green ≤ ±10 cents, amber ≤ ±25 cents, red > ±25 cents.
Nav order: Tune → Practice → Progress → Settings.

### 1.9 — Onboarding assessment `planned`
~48-question calibration. Listening-only mode. Covers 8 intervals × 3 registers.
Progressive difficulty: maximally different intervals first (P8 vs M2), narrowing
toward similar pairs (m3 vs M3). Seeds confusion matrix before first drill session.
"Here's what we learned" summary screen after completion.
Skip option: app starts cold with no prior data.

---

## Phase 2 — Lesson Architecture + New Primitives

### 2.0 — Adaptive difficulty engine `planned`

Track per-bucket difficulty level alongside the confusion matrix. Lessons start easy
and get harder as the user succeeds; if error rate climbs past a threshold the difficulty
steps back down.

**Two axes of difficulty per primitive:**

| Primitive | Easier | Harder |
|-----------|--------|--------|
| `contour` | Wide semitone gap (12), few foil options | Narrow gap (2–3), harder register |
| `interval-id` | `foilStrategy: "distant"` | `foilStrategy: "adjacent"` |
| `interval-playback` | Hints on, generous tolerance | Hints off, tight tolerance |
| Future primitives | Fewer choices, distant foils | More choices, adjacent foils |

**Difficulty level per bucket (stored in cumulative.json):**
- Level 1–5 integer; starts at 1; increases after `streakToAdvance` consecutive correct
- Steps back after `streakToFail` consecutive wrong (default 3)
- Level is per-(interval, register) bucket so a user can be at level 4 for P5/mid
  but level 1 for m3/low

**Wiring:** `LessonRunner` reads difficulty level from `ProgressStore` when configuring
each step's parameters. Free-play interval trainer also adapts: after 3 consecutive correct
in a bucket, the next trial in that bucket gets narrower tolerance.

### 2.1 — LessonRunner + ExercisePrimitive protocol `planned`
Extract lesson orchestration from freeplay tab. LessonRunner holds all ViewModels,
sequences steps, handles pass/fail/repeat logic, exposes `@Published var currentPrimitive`.
See DESIGN.md "Config-Driven Lesson Plan Architecture" for full spec.

### 2.2 — .etplan file type `planned`
UTI registration (`com.eartrain.etplan`), `.onOpenURL` handler in WindowGroup,
plan preview modal (name/author/description/step summary), LessonPlanValidator.
Bundled starter plans: `beginner-ci.etplan`, `intermediate.etplan`.

### 2.3 — New primitive: `pitch-match` `planned`
Single-note same/different discrimination. Pre-contour; onboarding assessment entry point.
Listen-only, multiple-choice (Same / Different). See LESSON_PRIMITIVES.md.

### 2.4 — New primitive: `scale-degree` `planned`
Hear a note against a key drone/chord; identify scale degree (1–7).
Bridges interval knowledge to functional harmony.

### 2.5 — New primitive: `cadence` `planned`
Two-chord move; identify resolved (V→I), unresolved (→V), or lift (IV→I).
On-ramp to chord progression recognition.

### 2.6 — New primitive: `chord-quality` `planned`
Hear a chord (arpeggiated first, then strummed); identify major/minor/dom7/min7.
Start with binary major vs. minor; expand foil set as confidence builds.
Arpeggiate by default — simultaneous overtones are harder for CI.

### 2.7 — New primitive: `harmonic-interval` `planned`
Two simultaneous notes; identify interval. Guitar-specific (double stops, dyads).
More demanding than melodic interval-id. Sequence after interval-id mastery.

### 2.8 — Sequence playback (melody echo) `planned`
3–8 note sequence; user plays it back; note-by-note feedback.
Phase 2 milestone. Shares pitch detection pipeline from interval-playback.
See LESSON_PRIMITIVES.md `sequence-playback`.

---

## Phase 3 — Advanced Primitives + Audiologist View

### 3.1 — New primitive: `chord-progression` `future`
2–4 chord sequence; identify Roman numeral pattern (I–IV–V, blues, ii–V–I, etc.).
Requires chord playback infrastructure (not yet built).

### 3.2 — New primitive: `mode-flavor` `future`
4–8 note phrase; identify tonal color (major / minor / blues / Dorian / Mixolydian).
Start binary; expand set gradually.

### 3.3 — New primitive: `call-response` `future`
App plays a 2–4 note "call"; user plays any musical answer.
Graded in-key vs. out-of-key. Musical freedom within key constraints.

### 3.4 — Audiologist / teacher view `future`
Separate window (File → "Open Session Data…"). NSOpenPanel for patient data folder.
Confusion matrix heatmap. CSV + JSON bundle export.
Sandbox entitlements required (see TODOS.md).

### 3.5 — Research export `future`
CSV: one row per trial (timestamp, interval, register, rootHz, detectedHz, result).
JSON bundle: raw session files + cumulative summary.
Surface from audiologist view's Export button.

---

## Phase 4 — Future Ideas

- Blues lick practice (curated lick library + echo loop)
- Improv feedback over backing track (in-key vs. out-of-key detection)
- Adaptive per-user loudness calibration (extension of Phase 0.1 normalization baseline)
- CI processor-specific customization (Cochlear / MED-EL / Advanced Bionics)
- Light mode UI
- Mac App Store distribution

---

## Primitive readiness summary

| primitive | status | phase |
|-----------|--------|-------|
| `contour` | done | — |
| `interval-id` | done | — |
| `interval-playback` | done | — |
| `pitch-match` | planned | 2.3 |
| `scale-degree` | planned | 2.4 |
| `cadence` | planned | 2.5 |
| `chord-quality` | planned | 2.6 |
| `harmonic-interval` | planned | 2.7 |
| `sequence-playback` | planned | 2.8 |
| `chord-progression` | future | 3.1 |
| `mode-flavor` | future | 3.2 |
| `call-response` | future | 3.3 |

Full parameter schemas and exercise loop specs: see LESSON_PRIMITIVES.md.
