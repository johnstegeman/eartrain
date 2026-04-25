import XCTest
@testable import EarTrainLib

final class NoteConverterTests: XCTestCase {

    // MARK: - Known frequencies → expected note names

    func testA4() {
        XCTAssertEqual(NoteConverter.name(fromHz: 440.0), "A4")
    }

    func testA3() {
        XCTAssertEqual(NoteConverter.name(fromHz: 220.0), "A3")
    }

    func testMiddleC() {
        // C4 ≈ 261.63 Hz
        XCTAssertEqual(NoteConverter.name(fromHz: 261.63), "C4")
    }

    func testE4() {
        // E4 ≈ 329.63 Hz
        XCTAssertEqual(NoteConverter.name(fromHz: 329.63), "E4")
    }

    func testG4() {
        // G4 ≈ 392.00 Hz
        XCTAssertEqual(NoteConverter.name(fromHz: 392.00), "G4")
    }

    func testLowE2() {
        // Open low E string ≈ 82.41 Hz
        XCTAssertEqual(NoteConverter.name(fromHz: 82.41), "E2")
    }

    func testHighE4() {
        // Open high e string ≈ 329.63 Hz
        XCTAssertEqual(NoteConverter.name(fromHz: 329.63), "E4")
    }

    func testZeroHzReturnsPlaceholder() {
        XCTAssertEqual(NoteConverter.name(fromHz: 0), "--")
    }

    // MARK: - Cents deviation

    func testPerfectlyInTuneHasZeroCents() {
        let deviation = NoteConverter.centsDeviation(fromHz: 440.0)
        XCTAssertEqual(deviation, 0, accuracy: 0.01)
    }

    func testSharpDeviationIsPositive() {
        // Slightly above A4
        let deviation = NoteConverter.centsDeviation(fromHz: 445.0)
        XCTAssertGreaterThan(deviation, 0)
    }

    func testFlatDeviationIsNegative() {
        // Slightly below A4
        let deviation = NoteConverter.centsDeviation(fromHz: 435.0)
        XCTAssertLessThan(deviation, 0)
    }

    func testDeviationWithinOneSemitone() {
        // Any valid pitch should deviate by less than 50 cents from the nearest note
        let deviation = abs(NoteConverter.centsDeviation(fromHz: 450.0))
        XCTAssertLessThan(deviation, 50)
    }

    // MARK: - MIDI note numbers

    func testA4MidiNote() {
        XCTAssertEqual(NoteConverter.midiNote(fromHz: 440.0), 69)
    }

    func testC4MidiNote() {
        XCTAssertEqual(NoteConverter.midiNote(fromHz: 261.63), 60)
    }
}
