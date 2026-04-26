import Foundation

/// AudioProtocols.swift
/// Clean dependency-injection boundaries for audio subsystems.
///
/// ViewModels depend on these protocols, not on AudioEngineManager directly.
/// This allows unit tests to inject mock implementations without touching
/// real hardware, and lets LessonRunner inject the same shared engine
/// into all primitive ViewModels.

// MARK: - Output

/// Playback-only interface. ContourViewModel, IdentificationViewModel,
/// and any future listen-only primitives take `any AudioPlaying`.
public protocol AudioPlaying: AnyObject {
    /// Play root note, gap, then interval note as configured tones.
    func playInterval(rootHz: Float, intervalHz: Float,
                      noteDuration: TimeInterval, gap: TimeInterval) async
    /// Stop all audio output immediately.
    func stopPlayback()
}

// MARK: - Input

/// Mic-reading interface. ExerciseViewModel and any future guitar-response
/// primitives take `any AudioPlaying & MicListening`.
public protocol MicListening: AnyObject {
    /// Current RMS amplitude from the mic tap (0–1 scale).
    var amplitude: Float { get }
    /// Most recently detected fundamental frequency in Hz. 0 when silent.
    var detectedHz: Float { get }
    /// Install the hardware mic tap and begin pitch detection.
    /// Call when entering a guitar-response exercise.
    func enableMicTap()
    /// Remove the hardware mic tap. Clears amplitude and detectedHz.
    /// Call when leaving a guitar-response exercise so the macOS
    /// microphone-in-use indicator (orange dot) is not shown unnecessarily.
    func disableMicTap()
}

// MARK: - Convenience defaults

public extension AudioPlaying {
    /// Convenience overload matching AudioEngineManager's defaults.
    func playInterval(rootHz: Float, intervalHz: Float) async {
        await playInterval(rootHz: rootHz, intervalHz: intervalHz,
                           noteDuration: 1.5, gap: 0.4)
    }
}

// MARK: - Conformance

/// AudioEngineManager satisfies both protocols — no additional implementation
/// needed since the methods and properties already exist with matching signatures.
extension AudioEngineManager: AudioPlaying, MicListening {}
