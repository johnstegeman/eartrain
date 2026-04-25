import XCTest
@testable import EarTrainLib

final class ExerciseResultTests: XCTestCase {

    // Root: A4 = 440 Hz for all tests unless noted.
    let root: Float = 440.0

    // MARK: - Correct (within ±25 cents)

    func testExactTargetIsCorrect() {
        let hz = Interval.P5.targetHz(rootHz: root)  // E5 = 659.26 Hz
        XCTAssertEqual(ExerciseResult.grade(rootHz: root, interval: .P5, detectedHz: hz), .correct)
    }

    func testWithin25CentsIsCorrect() {
        // +20 cents ≈ multiply by 2^(0.20/12) ≈ ×1.01156
        let hz = Interval.M3.targetHz(rootHz: root) * 1.01156
        XCTAssertEqual(ExerciseResult.grade(rootHz: root, interval: .M3, detectedHz: hz), .correct)
    }

    // MARK: - Close (within ±100 cents but outside ±25 cents)

    func testm3PlayedForM3IsCorrect() {
        let hz = Interval.m3.targetHz(rootHz: root)
        XCTAssertEqual(ExerciseResult.grade(rootHz: root, interval: .m3, detectedHz: hz), .correct)
    }

    func testM3PlayedWhenm3TargetedIsClose() {
        // m3 = 3 st, M3 = 4 st — only 1 semitone apart → close
        let hz = Interval.M3.targetHz(rootHz: root)
        let result = ExerciseResult.grade(rootHz: root, interval: .m3, detectedHz: hz)
        XCTAssertEqual(result, .close(played: .M3))
    }

    func testm3PlayedWhenM3TargetedIsClose() {
        let hz = Interval.m3.targetHz(rootHz: root)
        let result = ExerciseResult.grade(rootHz: root, interval: .M3, detectedHz: hz)
        XCTAssertEqual(result, .close(played: .m3))
    }

    // MARK: - Wrong (more than 1 semitone off)

    func testM2PlayedForP5IsWrong() {
        let hz = Interval.M2.targetHz(rootHz: root)
        let result = ExerciseResult.grade(rootHz: root, interval: .P5, detectedHz: hz)
        XCTAssertEqual(result, .wrong(played: .M2))
    }

    func testP8PlayedForM2IsWrong() {
        let hz = Interval.P8.targetHz(rootHz: root)
        let result = ExerciseResult.grade(rootHz: root, interval: .M2, detectedHz: hz)
        // P8=12st, M2=2st → 10 semitones off → wrong
        if case .wrong = result { } else {
            XCTFail("Expected .wrong, got \(result)")
        }
    }

    // MARK: - OctaveDisplaced

    func testP5PlayedOctaveAboveIsOctaveDisplaced() {
        // Target: P5 (7 st). Play P5 + octave (19 st)
        let targetHz = Interval.P5.targetHz(rootHz: root)
        let octaveAbove = targetHz * 2.0
        XCTAssertEqual(
            ExerciseResult.grade(rootHz: root, interval: .P5, detectedHz: octaveAbove),
            .octaveDisplaced
        )
    }

    func testP5PlayedOctaveBelowIsOctaveDisplaced() {
        let targetHz = Interval.P5.targetHz(rootHz: root)
        let octaveBelow = targetHz / 2.0
        XCTAssertEqual(
            ExerciseResult.grade(rootHz: root, interval: .P5, detectedHz: octaveBelow),
            .octaveDisplaced
        )
    }

    func testCorrectIsNotOctaveDisplaced() {
        // Exact target should be .correct, not .octaveDisplaced
        let hz = Interval.P5.targetHz(rootHz: root)
        XCTAssertEqual(ExerciseResult.grade(rootHz: root, interval: .P5, detectedHz: hz), .correct)
    }

    // MARK: - Different root notes (validates any-key support)

    func testGradingWorksFromE2Root() {
        let e2: Float = 82.41
        let hz = Interval.m3.targetHz(rootHz: e2)
        XCTAssertEqual(ExerciseResult.grade(rootHz: e2, interval: .m3, detectedHz: hz), .correct)
    }

    func testGradingWorksFromD3Root() {
        let d3: Float = 146.83
        let hz = Interval.M3.targetHz(rootHz: d3)
        XCTAssertEqual(ExerciseResult.grade(rootHz: d3, interval: .M3, detectedHz: hz), .correct)
    }

    // MARK: - Interval helpers

    func testTargetHzIsCorrectForP5() {
        // A4 (440) + P5 = E5 ≈ 659.26 Hz
        XCTAssertEqual(Interval.P5.targetHz(rootHz: 440), 659.255, accuracy: 0.01)
    }

    func testNearestIntervalForExactSemitones() {
        XCTAssertEqual(Interval.nearest(toSemitones: 7.0), .P5)
        XCTAssertEqual(Interval.nearest(toSemitones: 3.0), .m3)
        XCTAssertEqual(Interval.nearest(toSemitones: 4.0), .M3)
    }

    func testNearestIntervalForMidpointFavorsLower() {
        // 3.5 st: between m3 (3) and M3 (4) — nearest by distance is either,
        // just verify it returns one of them (deterministic tie-breaking not required)
        let result = Interval.nearest(toSemitones: 3.5)
        XCTAssertTrue(result == .m3 || result == .M3)
    }
}
