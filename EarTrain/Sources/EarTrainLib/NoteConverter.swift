import Foundation

/// Pure functions for converting between Hz, MIDI note numbers, and note names.
/// Kept as free functions so they're trivially testable without any audio stack.
public enum NoteConverter {

    private static let names = ["C", "C#", "D", "D#", "E", "F",
                                "F#", "G", "G#", "A", "A#", "B"]

    /// Convert a frequency in Hz to the nearest MIDI note number.
    /// A4 = 440 Hz = MIDI 69.
    public static func midiNote(fromHz hz: Float) -> Int {
        Int(round(12 * log2(Double(hz) / 440.0) + 69))
    }

    /// Convert a MIDI note number to a display name like "A4" or "C#3".
    public static func name(fromMidi midi: Int) -> String {
        let octave = midi / 12 - 1
        let index = ((midi % 12) + 12) % 12
        return "\(names[index])\(octave)"
    }

    /// Convenience: Hz → display name.
    public static func name(fromHz hz: Float) -> String {
        guard hz > 0 else { return "--" }
        return name(fromMidi: midiNote(fromHz: hz))
    }

    /// Cents deviation of `hz` from the nearest equal-temperament pitch.
    /// Positive = sharp, negative = flat.
    public static func centsDeviation(fromHz hz: Float) -> Float {
        guard hz > 0 else { return 0 }
        let exactSemitones = 12 * log2(Double(hz) / 440.0) + 69
        let nearest = round(exactSemitones)
        return Float((exactSemitones - nearest) * 100)
    }
}
