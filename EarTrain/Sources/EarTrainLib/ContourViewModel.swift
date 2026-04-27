import AVFoundation
import SwiftUI

/// Drives the Contour Mode exercise ("Higher, Lower, or Same?").
///
/// Exercise loop:
///   1. App plays two notes sequentially.
///   2. User taps Higher / Lower / Same.
///   3. Immediate feedback → next pair.
///
/// Designed for CI users who are not yet ready for interval identification.
@MainActor
public final class ContourViewModel: ObservableObject, DifficultyAdjustable {

    // MARK: - Contour

    public enum Contour: Equatable, CaseIterable {
        case higher, lower, same

        public var label: String {
            switch self {
            case .higher: return "Higher"
            case .lower:  return "Lower"
            case .same:   return "Same"
            }
        }

        public var icon: String {
            switch self {
            case .higher: return "arrow.up"
            case .lower:  return "arrow.down"
            case .same:   return "equal"
            }
        }

        public var directionKey: String {
            switch self {
            case .higher: return "higher"
            case .lower:  return "lower"
            case .same:   return "same"
            }
        }
    }

    // MARK: - Phase

    public enum Phase: Equatable {
        case idle
        case playing
        case awaitingAnswer
        case result(correct: Bool, correctAnswer: Contour)
    }

    // MARK: - Published

    @Published public var phase: Phase = .idle
    @Published public var totalTrials: Int = 0
    @Published public var correctTrials: Int = 0

    /// 1 = easiest (wide gaps), 5 = hardest (narrow gaps).
    @Published public var difficultyLevel: Int = 3 {
        didSet { UserDefaults.standard.set(difficultyLevel, forKey: "difficultyLevel_contour") }
    }

    /// Non-nil when a session is running with a time limit. Counts down to 0.
    @Published public var timeRemainingSeconds: Int? = nil

    /// Becomes true (briefly) when the timer fires and the current trial has ended.
    /// The view observes this and calls its `endSession()` to show the summary sheet.
    @Published public var sessionExpired: Bool = false

    // MARK: - Audio

    private let audio: any AudioPlaying

    // MARK: - Difficulty

    /// Picks a semitone gap for the current difficulty with soft boundaries.
    ///
    /// Each level has a core zone (70%) that bleeds into adjacent levels (20% near, 10% far),
    /// so difficulty feels like a gradient rather than a hard wall.
    private func pickSemitones() -> Int {
        let zone = Int.random(in: 0..<10)
        switch difficultyLevel {
        case 1:  // Wide leaps (core 10-16), occasionally bleeds toward L2
            return zone < 7 ? Int.random(in: 10...16)
                 : zone < 9 ? Int.random(in:  6...9)
                 :             Int.random(in:  4...5)
        case 2:  // Large gaps (core 6-12), bleeds toward L1 and L3
            return zone < 7 ? Int.random(in:  6...12)
                 : zone < 9 ? Int.random(in: 13...16)
                 :             Int.random(in:  3...5)
        case 3:  // Mixed (core 4-9), bleeds toward L2 and L4
            return zone < 7 ? Int.random(in:  4...9)
                 : zone < 9 ? Int.random(in: 10...13)
                 :             Int.random(in:  2...3)
        case 4:  // Narrow (core 2-5), bleeds toward L3 and L5
            return zone < 7 ? Int.random(in:  2...5)
                 : zone < 9 ? Int.random(in:  6...9)
                 :             1
        default: // Half/whole steps (core 1-2), occasionally sneaks up
            return zone < 7 ? Int.random(in:  1...2)
                 : zone < 9 ? 3
                 :             Int.random(in:  4...5)
        }
    }

    /// Human-readable description for each difficulty level (1–5).
    public var difficultyDescriptions: [String] {
        [
            "Wide leaps — mostly 10+ semitones (easiest)",
            "Large gaps — mostly 6 to 12 semitones",
            "Mixed — 4 to 9 semitones (default)",
            "Narrow — mostly 2 to 5 semitones",
            "Half/whole steps — mostly 1 to 2 semitones (hardest)",
        ]
    }

    public func lowerDifficulty() {
        difficultyLevel = max(1, difficultyLevel - 1)
    }

    public func raiseDifficulty() {
        difficultyLevel = min(5, difficultyLevel + 1)
    }

    // MARK: - Private

    private var correctContour: Contour = .higher
    private var rootHz: Float = 440
    private var secondHz: Float = 660
    private var semitones: Int = 7
    /// Counts replays on the current wrong answer; resets on each new trial.
    private var wrongReplayCount: Int = 0
    private let sampler = ContourSampler()
    private var currentTask: Task<Void, Never>?
    private var timerTask:   Task<Void, Never>?
    private var timerExpired = false
    private var logger: SessionLogger?
    private var sessionStartDate: Date? = nil

    // MARK: - Register rotation
    // Three equal-ish buckets across the playable MIDI range (40–72).
    // Low: E2–E3  |  Mid: F3–D4  |  High: Eb4–C5
    private static let registerBuckets: [(lo: Int, hi: Int)] = [
        (40, 52), (53, 62), (63, 72),
    ]
    /// Trial counts per register bucket; reset each session.
    private var registerTrialCounts = [0, 0, 0]
    /// Index of the register bucket used for the most recent trial (0=low,1=mid,2=high).
    private var lastRegisterBucket: Int = 1
    /// When non-nil, the rotation heavily favours this bucket (set by Audie's focus offer).
    public var focusedRegisterBucket: Int? = nil

    /// Human-readable name of the register used for the current trial.
    /// Pass this as `TrialContext.areaName` so Audie can spot problem areas.
    public var currentRegisterName: String {
        switch lastRegisterBucket {
        case 0:  return "the low register"
        case 2:  return "the high register"
        default: return "the middle register"
        }
    }

    /// Called when Audie's "focus area" offer is accepted.
    public func focusRegister(named name: String) {
        switch name {
        case "the low register":    focusedRegisterBucket = 0
        case "the high register":   focusedRegisterBucket = 2
        default:                    focusedRegisterBucket = 1
        }
    }

    /// Clears any active register focus (returns to normal rotation).
    public func clearRegisterFocus() {
        focusedRegisterBucket = nil
    }

    public var sessionDuration: TimeInterval {
        sessionStartDate.map { Date().timeIntervalSince($0) } ?? 0
    }

    public init(audio: any AudioPlaying) {
        self.audio = audio
        let saved = UserDefaults.standard.integer(forKey: "difficultyLevel_contour")
        if saved > 0 { difficultyLevel = saved }
    }

    // MARK: - Session lifecycle

    /// Begin a new session. `duration` starts the countdown timer if not `.open`.
    public func beginSession(duration: SessionDuration = .open) {
        logger?.endSession()
        logger = SessionLogger(primitive: "contour")
        sessionStartDate = Date()
        totalTrials   = 0
        correctTrials = 0
        timerExpired  = false
        sessionExpired = false
        registerTrialCounts = [0, 0, 0]

        timerTask?.cancel()
        if let minutes = duration.minutes {
            let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
            timerTask = Task { [weak self] in
                guard let self else { return }
                while Date() < endDate, !Task.isCancelled {
                    self.timeRemainingSeconds = max(0, Int(endDate.timeIntervalSince(Date())))
                    try? await Task.sleep(for: .seconds(1))
                }
                guard !Task.isCancelled else { return }
                self.timerExpired = true
                self.timeRemainingSeconds = 0
            }
        } else {
            timeRemainingSeconds = nil
        }
    }

    public func cancel() {
        timerTask?.cancel()
        timerTask = nil
        currentTask?.cancel()
        currentTask = nil
        logger?.endSession()
        logger = nil
        phase = .idle
        timeRemainingSeconds = nil
        timerExpired  = false
        sessionExpired = false
    }

    // MARK: - Control

    public func startExercise() {
        currentTask?.cancel()
        wrongReplayCount = 0
        phase = .playing
        let (root, second, st, contour) = generatePair()
        rootHz = root
        secondHz = second
        semitones = st
        correctContour = contour

        currentTask = Task {
            await audio.playInterval(
                rootHz: rootHz, intervalHz: secondHz,
                noteDuration: 1.2, gap: 0.35
            )
            guard !Task.isCancelled else { return }
            phase = .awaitingAnswer
        }
    }

    public func replayPair() {
        guard case .awaitingAnswer = phase else { return }
        currentTask?.cancel()
        phase = .playing
        currentTask = Task {
            await audio.playInterval(
                rootHz: rootHz, intervalHz: secondHz,
                noteDuration: 1.2, gap: 0.35
            )
            guard !Task.isCancelled else { return }
            phase = .awaitingAnswer
        }
    }

    /// Called by the view on each "Hear it again" tap for a wrong answer.
    /// Returns true when the replay threshold is reached and the view should
    /// ask the companion to reveal the note names.
    @discardableResult
    public func recordWrongReplay() -> Bool {
        wrongReplayCount += 1
        return wrongReplayCount >= 2
    }

    /// The names of the first and second notes played in the current pair.
    /// Nil outside of a result phase.
    public var currentNoteNames: (first: String, second: String)? {
        guard case .result = phase else { return nil }
        return (NoteConverter.name(fromHz: rootHz),
                NoteConverter.name(fromHz: secondHz))
    }

    /// Human-readable direction of the current pair based on playback order.
    public var currentDirectionText: String {
        switch correctContour {
        case .higher: return "higher"
        case .lower:  return "lower"
        case .same:   return "the same"
        }
    }

    /// MIDI numbers of the current pair, lower note first. Used for flagging.
    public var currentNoteMidiPair: (note1: Int, note2: Int) {
        (NoteConverter.midiNote(fromHz: min(rootHz, secondHz)),
         NoteConverter.midiNote(fromHz: max(rootHz, secondHz)))
    }

    /// Replay the pair after a wrong answer so the user can hear what they missed.
    /// Cancels the auto-advance countdown, plays the pair again, then restores the
    /// result badge and auto-advances after 2 seconds.
    public func replayAfterResult() {
        guard case .result = phase else { return }
        let savedPhase = phase
        currentTask?.cancel()
        phase = .playing
        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.audio.playInterval(
                rootHz: self.rootHz, intervalHz: self.secondHz,
                noteDuration: 1.2, gap: 0.35
            )
            guard !Task.isCancelled else { return }
            self.phase = savedPhase
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }
            if self.timerExpired {
                self.sessionExpired = true
            } else {
                self.startExercise()
            }
        }
    }

    /// Called by the view after each trial result.
    /// The `onResult` closure delivers the correct/wrong signal to CompanionEngine.
    public func answer(_ contour: Contour, onResult: ((Bool) -> Void)? = nil) {
        guard case .awaitingAnswer = phase else { return }
        let correct = contour == correctContour
        totalTrials  += 1
        if correct { correctTrials += 1 }
        phase = .result(correct: correct, correctAnswer: correctContour)
        let n1 = NoteConverter.midiNote(fromHz: min(rootHz, secondHz))
        let n2 = NoteConverter.midiNote(fromHz: max(rootHz, secondHz))
        logger?.logContourTrial(rootHz: rootHz, semitones: semitones,
                                direction: correctContour.directionKey, correct: correct,
                                difficulty: difficultyLevel,
                                note1Midi: n1, note2Midi: n2)
        sampler.recordTrial()
        onResult?(correct)

        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self else { return }
            let delay: TimeInterval = correct ? 1.5 : 3.0
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            if self.timerExpired {
                self.sessionExpired = true
            } else {
                self.startExercise()
            }
        }
    }

    // MARK: - Pair generation

    private func generatePair() -> (Float, Float, Int, Contour) {
        let roll = Int.random(in: 0..<10)
        let contour: Contour
        switch roll {
        case 0..<4: contour = .higher
        case 4..<8: contour = .lower
        default:    contour = .same
        }

        // For "same" pairs use a fixed gap of 0 — sampler is only used for higher/lower
        if contour == .same {
            let rootMidi = pickRegisterRoot(in: 40...72)
            let hz = midiToHz(rootMidi)
            return (hz, hz, 0, .same)
        }

        // Use the weighted sampler for higher/lower pairs.
        // The sampler returns (gap, lowerNoteMidi) — the lower of the two notes.
        let gapRange  = semitoneRange(forDifficulty: difficultyLevel)
        let midiRange: ClosedRange<Int>
        if let focused = focusedRegisterBucket, focused < Self.registerBuckets.count {
            let b = Self.registerBuckets[focused]
            midiRange = max(40, b.lo)...min(70, b.hi)
        } else {
            midiRange = 40...70
        }
        let (gap, lowerMidi) = sampler.sample(availableGapRange: gapRange,
                                               availableMidiRange: midiRange)

        // Derive root and second based on contour direction
        let rootMidi: Int
        switch contour {
        case .higher: rootMidi = lowerMidi               // root is lower; second is higher
        case .lower:  rootMidi = min(lowerMidi + gap, 81) // root is higher; second is lower
        case .same:   rootMidi = lowerMidi                // handled above but kept for exhaustiveness
        }

        // Track register for CompanionEngine
        let buckets = Self.registerBuckets
        if let idx = buckets.indices.first(where: { rootMidi >= buckets[$0].lo && rootMidi <= buckets[$0].hi }) {
            lastRegisterBucket = idx
            registerTrialCounts[idx] += 1
        }

        let rootHz = midiToHz(rootMidi)
        let secondHz: Float
        switch contour {
        case .higher: secondHz = midiToHz(rootMidi + gap)
        case .lower:  secondHz = midiToHz(rootMidi - gap)
        case .same:   secondHz = rootHz
        }

        return (rootHz, secondHz, gap, contour)
    }

    /// The gap range available at a given difficulty level.
    /// This gives the sampler the correct search space while keeping difficulty semantics.
    private func semitoneRange(forDifficulty level: Int) -> ClosedRange<Int> {
        switch level {
        case 1:  return 6...16
        case 2:  return 4...14
        case 3:  return 2...11
        case 4:  return 1...7
        default: return 1...3
        }
    }

    /// Picks a root MIDI note from `allowedRange`, weighted toward whichever register
    /// bucket has seen the fewest trials this session. If `focusedRegisterBucket` is set,
    /// that bucket gets 5× weight to create a strong but not exclusive focus.
    private func pickRegisterRoot(in allowedRange: ClosedRange<Int>) -> Int {
        let buckets = Self.registerBuckets
        let maxCount = registerTrialCounts.max() ?? 0

        // Base weight = (maxCount - thisCount + 1) for buckets overlapping allowedRange.
        var weights: [Int] = (0..<3).map { i in
            let intersectLo = max(buckets[i].lo, allowedRange.lowerBound)
            let intersectHi = min(buckets[i].hi, allowedRange.upperBound)
            guard intersectLo <= intersectHi else { return 0 }
            return maxCount - registerTrialCounts[i] + 1
        }

        // If a focus bucket is active, boost it strongly (5×).
        if let focused = focusedRegisterBucket, focused < weights.count, weights[focused] > 0 {
            weights[focused] *= 5
        }

        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return Int.random(in: allowedRange) }

        var roll = Int.random(in: 0..<totalWeight)
        var chosen = 0
        for (i, w) in weights.enumerated() {
            if roll < w { chosen = i; break }
            roll -= w
        }

        lastRegisterBucket = chosen
        registerTrialCounts[chosen] += 1
        let intersectLo = max(buckets[chosen].lo, allowedRange.lowerBound)
        let intersectHi = min(buckets[chosen].hi, allowedRange.upperBound)
        return Int.random(in: intersectLo...intersectHi)
    }

    private func midiToHz(_ midi: Int) -> Float {
        Float(440.0 * pow(2.0, Double(midi - 69) / 12.0))
    }
}
