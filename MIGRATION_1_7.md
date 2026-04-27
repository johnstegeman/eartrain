# Migration 1.7 — Mastery Engine + Weighted Sampler

**Status: PENDING**
**Depends on: MIGRATION_1_6.md complete** — specifically the `trials` table with `difficulty`,
`note1_midi`, `note2_midi`, and `semitone_gap` columns populated.

---

## Read first

- `MIGRATION_1_6.md` — must be complete before this migration begins
- `EarTrain/Sources/EarTrainLib/ProgressStore.swift` — `todayRecommendation`, mastery helpers added in 1.6
- `EarTrain/Sources/EarTrainLib/ContourViewModel.swift` — current sampling logic (`pickSemitones`, `pickRegisterRoot`)
- `EarTrain/Sources/EarTrainLib/HomeView.swift` — `todaysFocusCard`, `actionGrid`
- `EarTrain/Sources/EarTrainLib/SettingsView.swift` — where threshold controls go
- `LESSON_PRIMITIVES.md` — curriculum ladder and difficulty axes per primitive
- `DESIGN_SYSTEM.md` — "Home: multi-mode launcher" for the contour progress card layout

---

## What this migration delivers

1. **Mastery engine** — per-bucket (semitone-gap-group × octave-band) coverage check with
   configurable thresholds, recency window, and difficulty gate.
2. **Per-pair problem tracking** — sparse map of specific note pairs with low recent accuracy.
3. **Weighted sampler** in `ContourViewModel` — bad pairs get more reps.
4. **Configurable thresholds** — accuracy %, min trials, difficulty gate, all in Settings.
5. **Soft advance** — after 80 trials below the gate, offer "advance anyway" with "in-progress" marker.
6. **Difficulty is a floor, not a ceiling** — clearing the gate never stops the user from
   continuing at higher difficulty in Freeplay.
7. **JSON write path removal** — SessionLogger's parallel JSON write is deleted in this step.

---

## Background: mastery model

### The bucket grid

Contour mastery is measured across a 4×4 grid of (semitone-gap-group × octave-band) buckets.
Each bucket needs enough recent trials at sufficient accuracy and difficulty.

**Semitone gap groups:**
| Group key | Gaps | Difficulty signal |
|---|---|---|
| `gap_1_2` | 1–2 semitones | Hardest; CI natural breakpoint |
| `gap_3_4` | 3–4 semitones | Hard |
| `gap_5_6` | 5–6 semitones | Medium; ~5st is a natural CI breakpoint |
| `gap_7_12` | 7–12 semitones | Easiest |

**Octave bands** (derived from the lower note's MIDI number):
| Band key | MIDI range | Guitar range |
|---|---|---|
| `oct_2` | 28–39 | E2–B2 (very low) |
| `oct_3` | 40–51 | C3–B3 (low) |
| `oct_4` | 52–63 | C4–B4 (mid) |
| `oct_5` | 64–81 | C5–A5 (high) |

Total: 16 buckets. Each bucket independently needs to meet the mastery threshold.

### Required vs optional buckets

Not all 16 buckets are required by default. The **required set** covers what a typical user
should master. The `gap_1_2` group (1–2 semitones) is hard for CI users and is **optional
by default** — it contributes to the "personal mastery pursuit" indicator but doesn't block
advancement. All other gap groups across all octave bands are required.

This is configurable: the threshold knob for `gap_1_2` can be enabled in Settings.

### Mastery thresholds (all configurable in Settings)

| Setting key | Default | Range | Meaning |
|---|---|---|---|
| `mastery_accuracy` | 0.80 | 0.60–0.95 | Recent accuracy required per bucket |
| `mastery_min_trials` | 10 | 5–30 | Min trials per bucket |
| `mastery_min_difficulty` | 3 | 1–5 | Min difficulty level trials must reach |
| `mastery_recency_window` | 20 | 10–50 | Trials per bucket counted for recency |
| `mastery_require_gap_1_2` | false | bool | Whether 1–2 semitone buckets are required |
| `mastery_soft_advance_at` | 80 | 40–200 | Total trials before "advance anyway" prompt |

### Soft advance

After `mastery_soft_advance_at` total contour trials without hitting the mastery gate:
- Home shows: "Contour is still challenging. Keep working, or advance to the next stage.
  You can always return."
- Two buttons: **Keep Working** (dismiss, stay on contour) and **Advance Anyway**.
- If the user picks **Advance Anyway**: set `contour_advanced_early = true` in `app_state`.
  - The curriculum advances.
  - Home shows a secondary "Contour — in progress" card below the main recommendation.
  - The user can click it to return to Contour in Freeplay at any time.

### Difficulty is a floor

The difficulty gate (`mastery_min_difficulty = 3`) means "you must have practiced at difficulty 3."
It does **not** prevent the user from continuing at 4 or 5 after clearing the gate.
After the gate is cleared, Freeplay → Contour remains at whatever difficulty the VM had.
A separate "personal mastery" indicator on Home shows progress toward difficulty 5.

---

## Step 1 — Add mastery settings constants + UserDefaults helpers

**Goal:** Define all configurable threshold keys in one place. No UI yet — just the keys and
a settings accessor struct.

**Create:** `EarTrain/Sources/EarTrainLib/MasterySettings.swift`

```swift
import Foundation

/// Configurable mastery gate thresholds. Read from UserDefaults with defaults.
/// All keys are prefixed `mastery_` to avoid collisions.
public struct MasterySettings {

    public static var accuracyThreshold: Double {
        get { UserDefaults.standard.double(forKey: "mastery_accuracy").nonZero ?? 0.80 }
        set { UserDefaults.standard.set(newValue, forKey: "mastery_accuracy") }
    }
    public static var minTrialsPerBucket: Int {
        get { UserDefaults.standard.integer(forKey: "mastery_min_trials").nonZero ?? 10 }
        set { UserDefaults.standard.set(newValue, forKey: "mastery_min_trials") }
    }
    public static var minDifficulty: Int {
        get { UserDefaults.standard.integer(forKey: "mastery_min_difficulty").nonZero ?? 3 }
        set { UserDefaults.standard.set(newValue, forKey: "mastery_min_difficulty") }
    }
    public static var recencyWindow: Int {
        get { UserDefaults.standard.integer(forKey: "mastery_recency_window").nonZero ?? 20 }
        set { UserDefaults.standard.set(newValue, forKey: "mastery_recency_window") }
    }
    public static var requireGap1_2: Bool {
        get { UserDefaults.standard.bool(forKey: "mastery_require_gap_1_2") }
        set { UserDefaults.standard.set(newValue, forKey: "mastery_require_gap_1_2") }
    }
    public static var softAdvanceAt: Int {
        get { UserDefaults.standard.integer(forKey: "mastery_soft_advance_at").nonZero ?? 80 }
        set { UserDefaults.standard.set(newValue, forKey: "mastery_soft_advance_at") }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
private extension Double {
    var nonZero: Double? { self == 0.0 ? nil : self }
}
```

**Acceptance:** File compiles. `MasterySettings.accuracyThreshold` returns 0.80 on a fresh install.

---

## Step 2 — Create `MasteryEngine.swift`

**Goal:** Query the `trials` table to determine whether each (gap_group × octave_band) bucket
meets the mastery criteria. Return a structured result the recommendation system can act on.

**Create:** `EarTrain/Sources/EarTrainLib/MasteryEngine.swift`

```swift
import Foundation

/// Computes contour mastery state from the GRDB trials table.
///
/// Call `evaluate()` on a background thread; the result is a value type safe to pass to MainActor.
public struct MasteryEngine {

    // MARK: - Bucket definitions

    public static let gapGroups: [(key: String, range: ClosedRange<Int>)] = [
        ("gap_1_2",  1...2),
        ("gap_3_4",  3...4),
        ("gap_5_6",  5...6),
        ("gap_7_12", 7...12),
    ]

    public static func octaveBand(forMidi midi: Int) -> String {
        switch midi {
        case ..<40:  return "oct_2"
        case 40..<52: return "oct_3"
        case 52..<64: return "oct_4"
        default:      return "oct_5"
        }
    }

    public static func gapGroup(forSemitones gap: Int) -> String? {
        gapGroups.first { $0.range.contains(gap) }?.key
    }

    // MARK: - Result types

    public struct BucketResult {
        public let gapGroup:   String
        public let octaveBand: String
        public let trialsAtMinDiff: Int     // trials at difficulty ≥ minDifficulty
        public let recentAccuracy: Double?  // over last recencyWindow trials in this bucket
        public let meetsThreshold: Bool
        public let isRequired: Bool
    }

    public enum ContourMasteryState: Equatable {
        case notStarted
        case inProgress(bucketsMet: Int, bucketsRequired: Int, totalTrials: Int)
        case gateCleared          // all required buckets met; user may advance
        case advancedEarly        // user chose to advance before gate was cleared
    }

    // MARK: - Evaluation

    public static func evaluate() -> (state: ContourMasteryState, buckets: [BucketResult]) {
        // Check if user already advanced early
        if (try? AudieDatabase.shared.appStateValue(forKey: "contour_advanced_early")) == "true" {
            return (.advancedEarly, [])
        }

        let settings   = MasterySettings.self
        let window     = settings.recencyWindow
        let minDiff    = settings.minDifficulty
        let minTrials  = settings.minTrialsPerBucket
        let accuracy   = settings.accuracyThreshold
        let reqGap1_2  = settings.requireGap1_2

        // Total contour trials in DB
        let totalTrials = (try? AudieDatabase.shared.dbQueue.read { db in
            try Int.fetchOne(db,
                sql: "SELECT COUNT(*) FROM trials WHERE primitive = 'contour'") ?? 0
        }) ?? 0

        if totalTrials == 0 { return (.notStarted, []) }

        // Per-bucket analysis
        var results: [BucketResult] = []
        for gap in gapGroups {
            for band in ["oct_2", "oct_3", "oct_4", "oct_5"] {
                let result = evaluateBucket(
                    gapKey: gap.key, gapRange: gap.range, band: band,
                    window: window, minDiff: minDiff, minTrials: minTrials,
                    accuracy: accuracy, reqGap1_2: reqGap1_2)
                results.append(result)
            }
        }

        let required  = results.filter { $0.isRequired }
        let met       = required.filter { $0.meetsThreshold }

        if met.count == required.count {
            return (.gateCleared, results)
        }

        return (.inProgress(bucketsMet: met.count,
                            bucketsRequired: required.count,
                            totalTrials: totalTrials), results)
    }

    private static func evaluateBucket(
        gapKey: String, gapRange: ClosedRange<Int>, band: String,
        window: Int, minDiff: Int, minTrials: Int, accuracy: Double,
        reqGap1_2: Bool
    ) -> BucketResult {
        let isRequired = !(gapKey == "gap_1_2" && !reqGap1_2)

        // Octave band MIDI bounds
        let midiRange: ClosedRange<Int>
        switch band {
        case "oct_2": midiRange = 28...39
        case "oct_3": midiRange = 40...51
        case "oct_4": midiRange = 52...63
        default:      midiRange = 64...127
        }

        guard let rows = try? AudieDatabase.shared.dbQueue.read({ db -> [Row] in
            try Row.fetchAll(db, sql: """
                SELECT correct, difficulty FROM trials
                WHERE primitive = 'contour'
                  AND semitone_gap >= ? AND semitone_gap <= ?
                  AND note1_midi >= ? AND note1_midi <= ?
                ORDER BY ts DESC
                LIMIT ?
                """,
                arguments: [gapRange.lowerBound, gapRange.upperBound,
                            midiRange.lowerBound, midiRange.upperBound,
                            window * 2])  // fetch extra to filter by difficulty
        }) else {
            return BucketResult(gapGroup: gapKey, octaveBand: band,
                                trialsAtMinDiff: 0, recentAccuracy: nil,
                                meetsThreshold: false, isRequired: isRequired)
        }

        let atMinDiff = rows.filter { ($0["difficulty"] as Int) >= minDiff }
        let recentAtMinDiff = Array(atMinDiff.prefix(window))

        let trialsAtMinDiff = recentAtMinDiff.count
        let recentAcc: Double? = trialsAtMinDiff >= 5
            ? Double(recentAtMinDiff.filter { ($0["correct"] as Int) == 1 }.count) / Double(trialsAtMinDiff)
            : nil

        let meets = trialsAtMinDiff >= minTrials && (recentAcc ?? 0) >= accuracy

        return BucketResult(gapGroup: gapKey, octaveBand: band,
                            trialsAtMinDiff: trialsAtMinDiff,
                            recentAccuracy: recentAcc,
                            meetsThreshold: meets,
                            isRequired: isRequired)
    }
}
```

**Acceptance:** File compiles. `MasteryEngine.evaluate()` returns `.notStarted` for a fresh
install and `.inProgress` after a few trials.

---

## Step 3 — Create `ContourSampler.swift`

**Goal:** A weighted sampler that `ContourViewModel` uses instead of its current soft-rotation
logic. Bad (gap × octave-band) buckets and specific problem pairs get higher weight.

**Create:** `EarTrain/Sources/EarTrainLib/ContourSampler.swift`

```swift
import Foundation

/// Weighted sampler for contour note-pair selection.
///
/// Weights are inverse of recent accuracy: a bucket at 40% accuracy gets 2.5×
/// the weight of a bucket at 100% accuracy. Weights refresh every `refreshInterval`
/// trials so the sampler adapts without reading the DB on every trial.
public final class ContourSampler {

    private let refreshInterval = 10  // refresh weights every 10 trials
    private var trialsSinceRefresh = 0

    // (gapGroup, octaveBand) → weight
    private var bucketWeights: [(gapKey: String, gapRange: ClosedRange<Int>,
                                  octaveMidiRange: ClosedRange<Int>, weight: Double)] = []
    // (note1_midi, note2_midi) → extra weight multiplier (problem pairs)
    private var pairBoosts: [String: Double] = [:]

    public init() { refreshWeights() }

    /// Call after each trial to potentially refresh weights.
    public func recordTrial() {
        trialsSinceRefresh += 1
        if trialsSinceRefresh >= refreshInterval {
            refreshWeights()
            trialsSinceRefresh = 0
        }
    }

    /// Returns a (semitoneGap, rootMidi) pair sampled according to current weights.
    /// Falls back to uniform random if no weight data exists.
    public func sample(availableGapRange: ClosedRange<Int>,
                       availableMidiRange: ClosedRange<Int>) -> (gap: Int, rootMidi: Int) {
        // Filter to applicable buckets
        let applicable = bucketWeights.filter {
            !($0.gapRange.upperBound < availableGapRange.lowerBound ||
              $0.gapRange.lowerBound > availableGapRange.upperBound) &&
            !($0.octaveMidiRange.upperBound < availableMidiRange.lowerBound ||
              $0.octaveMidiRange.lowerBound > availableMidiRange.upperBound)
        }

        guard !applicable.isEmpty else {
            // Fallback: uniform random
            let gap = Int.random(in: availableGapRange)
            let root = Int.random(in: availableMidiRange)
            return (gap, root)
        }

        // Weighted random bucket selection
        let totalWeight = applicable.reduce(0.0) { $0 + $1.weight }
        var r = Double.random(in: 0..<totalWeight)
        var chosen = applicable.last!
        for b in applicable {
            r -= b.weight
            if r <= 0 { chosen = b; break }
        }

        // Sample gap and root within chosen bucket (clamped to available range)
        let gapRange = chosen.gapRange.clamped(to: availableGapRange)
        let midiRange = chosen.octaveMidiRange.clamped(to: availableMidiRange)
        let gap  = Int.random(in: gapRange)
        var root = Int.random(in: midiRange)

        // Apply problem-pair boost: if this (root, root+gap) is a problem pair, keep it;
        // otherwise try once to find a non-boosted pair (simple best-of-2 heuristic)
        let key = "\(root)-\(root+gap)"
        if pairBoosts[key] == nil {
            let alt = Int.random(in: midiRange)
            let altKey = "\(alt)-\(alt+gap)"
            if (pairBoosts[altKey] ?? 0) > (pairBoosts[key] ?? 0) { root = alt }
        }

        return (gap, root)
    }

    // MARK: - Weight refresh

    private func refreshWeights() {
        let window = MasterySettings.recencyWindow

        // Build bucket weights from DB
        var weights: [(gapKey: String, gapRange: ClosedRange<Int>,
                        octaveMidiRange: ClosedRange<Int>, weight: Double)] = []

        let octaves: [(key: String, range: ClosedRange<Int>)] = [
            ("oct_2", 28...39), ("oct_3", 40...51),
            ("oct_4", 52...63), ("oct_5", 64...81)
        ]

        for gap in MasteryEngine.gapGroups {
            for oct in octaves {
                let acc = (try? AudieDatabase.shared.dbQueue.read { db -> Double? in
                    guard let rows = try? Row.fetchAll(db, sql: """
                        SELECT correct FROM trials
                        WHERE primitive = 'contour'
                          AND semitone_gap >= ? AND semitone_gap <= ?
                          AND note1_midi >= ? AND note1_midi <= ?
                        ORDER BY ts DESC LIMIT ?
                        """,
                        arguments: [gap.range.lowerBound, gap.range.upperBound,
                                    oct.range.lowerBound, oct.range.upperBound, window]),
                          rows.count >= 3 else { return nil }
                    return Double(rows.filter { ($0["correct"] as Int) == 1 }.count) / Double(rows.count)
                }) ?? nil

                // Weight = inverse accuracy, clamped. Unseen buckets get weight 1.5 (slight priority).
                let weight: Double
                if let a = acc {
                    weight = max(0.1, min(5.0, 1.0 - a + 0.5))  // 0.5 baseline + error rate
                } else {
                    weight = 1.5
                }
                weights.append((gapKey: gap.key, gapRange: gap.range,
                                  octaveMidiRange: oct.range, weight: weight))
            }
        }

        bucketWeights = weights

        // Build pair boosts from problem pairs
        let problems = (try? AudieDatabase.shared.dbQueue.read { db -> [Row] in
            try Row.fetchAll(db, sql: """
                WITH recent AS (
                    SELECT note1_midi, note2_midi, correct,
                           ROW_NUMBER() OVER (PARTITION BY note1_midi, note2_midi ORDER BY ts DESC) rn
                    FROM trials WHERE primitive = 'contour'
                      AND note1_midi IS NOT NULL
                )
                SELECT note1_midi, note2_midi,
                       1.0 - AVG(CAST(correct AS REAL)) AS err
                FROM recent WHERE rn <= ?
                GROUP BY note1_midi, note2_midi HAVING COUNT(*) >= 5
                """, arguments: [window])
        }) ?? []

        pairBoosts = [:]
        for row in problems {
            let n1 = Int(row["note1_midi"] as Int64)
            let n2 = Int(row["note2_midi"] as Int64)
            let err = row["err"] as Double
            if err > 0.3 {
                pairBoosts["\(n1)-\(n2)"] = err
            }
        }
    }
}
```

**Acceptance:** File compiles. `ContourSampler().sample(availableGapRange: 3...8, availableMidiRange: 40...72)`
returns a valid (gap, rootMidi) tuple.

---

## Step 4 — Wire `ContourSampler` into `ContourViewModel`

**Goal:** Replace the current `pickSemitones()` / `pickRegisterRoot()` logic with the
weighted sampler.

**Files to modify:** `EarTrain/Sources/EarTrainLib/ContourViewModel.swift`

**Read the file first** to understand the current pair generation logic (`generatePair()`).
Then:

1. Add `private let sampler = ContourSampler()` as an instance property.

2. In the method that generates a pair (likely `generatePair()` or `runExercise()`), replace
   the current `pickSemitones()` + `pickRegisterRoot()` calls with:
   ```swift
   let availableGap = semitoneRange(forDifficulty: difficultyLevel)  // use existing difficulty→range mapping
   let availableMidi = 40...72  // guitar range for contour root note
   let (gap, rootMidi) = sampler.sample(availableGapRange: availableGap,
                                         availableMidiRange: availableMidi)
   let rootHz = midiToHz(rootMidi)
   ```

3. After each trial result is recorded (where `logContourTrial` is called), also call:
   ```swift
   sampler.recordTrial()
   ```

4. Keep the existing `semitoneRange(forDifficulty:)` helper (or adapt `pickSemitones()` to
   return the range for the current difficulty). The sampler needs the currently available
   gap range to stay within the VM's difficulty setting.

**Acceptance:**
- Build passes.
- In Freeplay → Contour, starting a session and running 10+ trials does not produce any crashes.
- After 15+ trials with a known bad pair (you can verify by checking the DB), that pair
  appears more frequently (verifiable by logging the sampled pairs to the console in debug).

---

## Step 5 — Update `ProgressStore.todayRecommendation` to use `MasteryEngine`

**Goal:** Replace the `hasContourMastery` property (added in the interim fix) with
`MasteryEngine.evaluate()` for the curriculum-ladder recommendation.

**Files to modify:** `EarTrain/Sources/EarTrainLib/ProgressStore.swift`

Replace the current `hasContourMastery` block in `todayRecommendation` with:

```swift
let masteryResult = MasteryEngine.evaluate()

switch masteryResult.state {
case .notStarted:
    return TodayRecommendation(
        mode: .contour,
        headline: "Start with Contour",
        reason: "Hearing whether a note goes up or down is the foundation. Start here.",
        cta: "Begin"
    )

case .inProgress(let met, let required, let total):
    let pct = total >= MasterySettings.softAdvanceAt ? " (advance option available)" : ""
    return TodayRecommendation(
        mode: .contour,
        headline: "Keep Building Contour",
        reason: "\(met) of \(required) coverage buckets cleared\(pct). Keep going.",
        cta: "Continue"
    )

case .advancedEarly:
    // Fall through to interval recommendation below, but Home will show a secondary
    // "Contour — in progress" card. See HomeView step 6.
    break

case .gateCleared:
    // Fall through to interval recommendation below.
    break
}

// Contour cleared or user advanced early — recommend interval identification
if stats.matrix.isEmpty {
    return TodayRecommendation(
        mode: .identification,
        headline: "Name the Intervals",
        reason: "Contour is solid. Now learn what each interval sounds like before playing it back.",
        cta: "Start"
    )
}

// Interval playback stage — confusion matrix targeting (existing logic, unchanged)
...
```

Also **remove** the old `hasContourMastery`, `contourTotalTrials`, and `contourOverallAccuracy`
properties that were added in the interim fix — `MasteryEngine` replaces them.

**Acceptance:**
- Fresh install: recommends Contour with "Begin" CTA.
- After some trials (not yet at gate): recommends Contour with "Keep Building" + bucket progress.
- After advancing early: falls through to interval stage.
- After gate cleared: falls through to interval stage.

---

## Step 6 — Soft advance UX in `HomeView`

**Goal:** Show the soft-advance prompt when total trials exceeds `softAdvanceAt` without
clearing the gate. Show the "Contour — in progress" secondary card when the user advanced early.

**Files to modify:** `EarTrain/Sources/EarTrainLib/HomeView.swift`

1. **Soft advance prompt** — in `todaysFocusCard`, when the recommendation is `.contour` and
   `MasteryEngine.evaluate().state` is `.inProgress` with `totalTrials >= MasterySettings.softAdvanceAt`:

   Add a secondary button below the main CTA:
   ```swift
   Button("This is hard — advance anyway?") {
       try? AudieDatabase.shared.setAppState("true", forKey: "contour_advanced_early")
       store.reload()  // trigger recommendation refresh
   }
   .font(.system(size: 12))
   .foregroundColor(EarTrainColors.textDisabled)
   .buttonStyle(.plain)
   ```

2. **In-progress secondary card** — when `MasteryEngine.evaluate().state == .advancedEarly`,
   show a compact secondary card below the main recommendation:
   ```swift
   if case .advancedEarly = masteryState {
       contourInProgressCard
   }
   ```

   Where `contourInProgressCard` is:
   ```swift
   private var contourInProgressCard: some View {
       HStack(spacing: 12) {
           Image(systemName: "arrow.triangle.2.circlepath")
               .foregroundColor(EarTrainColors.accent)
           VStack(alignment: .leading, spacing: 2) {
               Text("Contour — still in progress")
                   .font(.system(size: 13, weight: .semibold))
                   .foregroundColor(EarTrainColors.textPrimary)
               Text("Advanced early. Tap to return and keep working.")
                   .font(.system(size: 11))
                   .foregroundColor(EarTrainColors.textSecondary)
           }
           Spacer()
           Image(systemName: "arrow.right")
               .foregroundColor(EarTrainColors.textDisabled)
       }
       .padding(14)
       .background(EarTrainColors.surface)
       .clipShape(RoundedRectangle(cornerRadius: 10))
       .contentShape(Rectangle())
       .onTapGesture { activeMode = .freeplay }  // or .contour directly
   }
   ```

3. Compute `masteryState` once per body render:
   ```swift
   @State private var masteryState = MasteryEngine.evaluate()
   ```
   Refresh on `.onAppear` and when `store.objectWillChange` fires.

**Acceptance:**
- Before soft-advance threshold: no extra button in the card.
- After threshold: "This is hard — advance anyway?" appears as a subtle secondary option.
- After choosing advance: Home shows the next stage recommendation AND the "Contour in progress" card.
- Tapping the in-progress card goes to Freeplay.

---

## Step 7 — Settings UI for mastery thresholds

**Goal:** Add a "Mastery Gates" section to SettingsView exposing the configurable thresholds.

**Files to modify:** `EarTrain/Sources/EarTrainLib/SettingsView.swift`

Add a new settings section (after the existing sections):

```
MASTERY GATES

Accuracy required (per bucket)     [slider: 60%–95%, default 80%]
Min trials per bucket               [stepper: 5–30, default 10]
Min difficulty to count             [stepper: 1–5, default 3]
Recency window (trials)             [stepper: 10–50, default 20]
Require 1–2 semitone buckets        [toggle, default off]
"Advance anyway" after N trials     [stepper: 40–200, default 80]
```

Each control reads from / writes to the corresponding `MasterySettings` property.
Use `@State` vars initialized from `MasterySettings` statics, with `.onChange` to persist.

Below the controls, add a help text in `textDisabled` color:
> "These thresholds control when the curriculum advances. The difficulty gate is a floor —
> you can always keep working at higher difficulty in Freeplay."

**Acceptance:**
- Settings section renders without overflow.
- Changing the accuracy slider to 0.65, restarting the app, confirms `MasterySettings.accuracyThreshold == 0.65`.
- No crashes on any stepper value.

---

## Step 8 — Remove JSON write path from `SessionLogger`

**Goal:** Delete the parallel JSON write in `SessionLogger` now that GRDB is verified.

**Files to modify:** `EarTrain/Sources/EarTrainLib/SessionLogger.swift`

Delete:
- `writeSession()` private method
- `updateCumulative()` private method
- The calls to both in `endSession()`
- The `encoder` and `decoder` static properties (if no longer used elsewhere — verify with grep)

Keep:
- `CumulativeStats`, `TrialRecord`, `SessionRecord`, `ContourCounts`, `RegisterCounts` structs
  — `ProgressStore` still reads from `cumulative.json` as a legacy fallback until all users
  have migrated. Do not delete the Codable types.

**Acceptance:**
- Build passes.
- `~/Library/Application Support/Audie/sessions/` no longer gains new JSON files after a session.
- `cumulative.json` is no longer updated (stale but preserved for legacy reads).

---

## After all 8 steps

**Full verification:**
1. `swift build` → "Build complete!"
2. Fresh launch: Home recommends "Start with Contour".
3. Complete ~15 trials → Home shows "Keep Building Contour — X of Y buckets cleared".
4. After 80+ trials below gate: "advance anyway" button appears.
5. Advance early → Home shows next stage recommendation + "Contour — in progress" card.
6. Settings → Mastery Gates section visible with correct defaults.
7. No new JSON files written to `sessions/` after a session.

**Update docs:**
- Add `**Status: COMPLETE — landed [date].**` to this file.
- Update `MIGRATION_1_6.md` similarly.
- Mark both items in `TODOS.md` as done.

**What is NOT in scope:**
- Mastery engine for interval-id or interval-playback (same pattern, Phase 2+)
- Audiologist view
- LessonRunner
- `.etplan` parsing
