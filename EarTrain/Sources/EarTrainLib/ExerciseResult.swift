import Foundation

/// The result of a single exercise attempt.
/// Cases are checked in priority order — see `grade(rootHz:interval:detectedHz:)`.
public enum ExerciseResult: Equatable {
    /// Interval class matches (mod 12) but user played it in a different octave.
    /// e.g. played P5 an octave above or below the target.
    case octaveDisplaced

    /// Detected pitch within ±25 cents of target. Correct!
    case correct

    /// Within ±100 cents (1 semitone) but outside ±25 cents.
    /// Catches m3/M3 confusion: played the wrong interval but close.
    case close(played: Interval)

    /// More than 1 semitone off.
    case wrong(played: Interval)

    // MARK: - Grading

    /// Grade a detected pitch against the expected interval.
    ///
    /// Priority order (from DESIGN.md):
    /// 1. octaveDisplaced — interval class matches mod 12 AND deviation > 0.5 st (not just "correct")
    /// 2. correct         — within ±25 cents (0.25 st)
    /// 3. close           — within ±100 cents (1.0 st)
    /// 4. wrong           — everything else
    ///
    /// - Parameters:
    ///   - rootHz: The root note that was played by the app.
    ///   - interval: The target interval.
    ///   - detectedHz: The pitch detected from the guitar.
    public static func grade(rootHz: Float, interval: Interval, detectedHz: Float) -> ExerciseResult {
        guard detectedHz > 0, rootHz > 0 else { return .wrong(played: .M2) }

        // Semitone distance between detected pitch and root
        let detectedSt = 12 * log2(Double(detectedHz) / Double(rootHz))
        let targetSt   = Double(interval.semitones)
        let diff       = detectedSt - targetSt

        // 1. Octave-displaced check (before correct, to avoid misclassifying boundary cases).
        //    remainder of diff / 12, wrapped to [0, 6] so both +12 and -12 → 0.
        let rawMod  = diff.truncatingRemainder(dividingBy: 12)
        let centeredMod = min(abs(rawMod), 12 - abs(rawMod))
        if centeredMod < 0.5 && abs(diff) > 0.5 {
            return .octaveDisplaced
        }

        // 2. Correct — within ±25 cents
        if abs(diff) <= 0.25 {
            return .correct
        }

        // 3. Close — within ±100 cents (1 semitone).
        // Add a 0.5-cent epsilon to handle floating-point imprecision at the exact
        // 1-semitone boundary (e.g. m3 vs M3 computed via Float intermediate values).
        if abs(diff) <= 1.005 {
            return .close(played: Interval.nearest(toSemitones: detectedSt))
        }

        // 4. Wrong
        return .wrong(played: Interval.nearest(toSemitones: detectedSt))
    }
}
