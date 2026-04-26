import Foundation
@testable import EarTrainLib

// MARK: - MockAudioPlayer

/// Test double for AudioPlaying. Records calls for assertion.
final class MockAudioPlayer: AudioPlaying {

    // Recorded calls
    private(set) var playIntervalCalls: [(rootHz: Float, intervalHz: Float,
                                          noteDuration: TimeInterval, gap: TimeInterval)] = []
    private(set) var stopPlaybackCallCount = 0

    // Optional hook to simulate async delay or error on playback
    var playDelay: TimeInterval = 0

    func playInterval(rootHz: Float, intervalHz: Float,
                      noteDuration: TimeInterval, gap: TimeInterval) async {
        playIntervalCalls.append((rootHz, intervalHz, noteDuration, gap))
        if playDelay > 0 {
            try? await Task.sleep(for: .seconds(playDelay))
        }
    }

    func stopPlayback() {
        stopPlaybackCallCount += 1
    }

    // Convenience
    var lastCall: (rootHz: Float, intervalHz: Float,
                   noteDuration: TimeInterval, gap: TimeInterval)? {
        playIntervalCalls.last
    }
}

// MARK: - MockMicInput

/// Test double for MicListening. Lets tests script amplitude + pitch readings.
final class MockMicInput: AudioPlaying & MicListening {

    // MicListening
    var amplitude: Float = 0
    var detectedHz: Float = 0

    // AudioPlaying (no-op — ExerciseViewModel needs AudioPlaying & MicListening combined)
    private(set) var playIntervalCalls: [(rootHz: Float, intervalHz: Float,
                                          noteDuration: TimeInterval, gap: TimeInterval)] = []
    private(set) var stopPlaybackCallCount = 0

    func playInterval(rootHz: Float, intervalHz: Float,
                      noteDuration: TimeInterval, gap: TimeInterval) async {
        playIntervalCalls.append((rootHz, intervalHz, noteDuration, gap))
    }

    func stopPlayback() {
        stopPlaybackCallCount += 1
    }

    /// Simulate a note onset: set amplitude above threshold and a pitch reading.
    func simulateNote(hz: Float, amplitude: Float = 0.1) {
        self.detectedHz = hz
        self.amplitude  = amplitude
    }

    /// Simulate silence.
    func simulateSilence() {
        self.amplitude  = 0
        self.detectedHz = 0
    }
}
