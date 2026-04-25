import Accelerate
import AVFoundation

/// Autocorrelation-based monophonic pitch detector.
///
/// Uses normalized autocorrelation with parabolic interpolation.  Handles guitar's
/// complex harmonic content better than FFT peak-picking, because the fundamental
/// period produces the first significant peak regardless of harmonic strength.
///
/// Target range: 50–2000 Hz (covers open low-E through ~3rd octave above open high-e).
public struct PitchDetector {

    public let sampleRate: Float

    /// Minimum autocorrelation peak height to accept as a valid pitch (0–1).
    public var confidenceThreshold: Float = 0.5

    // Lag bounds in samples for the target frequency range
    private var minLag: Int { max(1, Int(sampleRate / 2000)) }
    private var maxLag: Int { Int(sampleRate / 50) }

    public init(sampleRate: Float) {
        self.sampleRate = sampleRate
    }

    /// Analyse a buffer and return the detected pitch.
    /// - Returns: `(hz, confidence)` where confidence is the normalised ACF peak (0–1),
    ///   or `nil` if the signal is below the noise floor or no clear pitch is found.
    public func detect(buffer: AVAudioPCMBuffer) -> (hz: Float, confidence: Float)? {
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let n = Int(buffer.frameLength)
        guard n > maxLag * 2 else { return nil }

        // --- Noise floor check ---
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(n))
        guard rms > 0.01 else { return nil }

        // --- Normalised autocorrelation r(τ) = ACF(τ) / ACF(0) ---
        var r0: Float = 0
        vDSP_dotpr(channelData, 1, channelData, 1, &r0, vDSP_Length(n))
        guard r0 > 0 else { return nil }

        let lagCount = maxLag - minLag + 1
        var acf = [Float](repeating: 0, count: maxLag + 1)
        for lag in minLag...maxLag {
            var dot: Float = 0
            vDSP_dotpr(channelData, 1, channelData.advanced(by: lag), 1,
                       &dot, vDSP_Length(n - lag))
            acf[lag] = dot / r0
        }
        _ = lagCount  // suppress unused warning

        // --- Find first zero-crossing (required before looking for the fundamental peak) ---
        var searchStart = minLag
        for lag in minLag..<maxLag {
            if acf[lag] <= 0 {
                searchStart = lag
                break
            }
        }

        // --- Find the first local peak above threshold after the zero-crossing ---
        var bestLag = -1
        var bestValue: Float = -1
        for lag in (searchStart + 1)..<maxLag {
            let prev = acf[lag - 1]
            let curr = acf[lag]
            let next = acf[lag + 1]
            if curr > prev, curr >= next, curr > confidenceThreshold {
                bestLag = lag
                bestValue = curr
                break  // first peak = fundamental period
            }
        }
        guard bestLag > 0 else { return nil }

        // --- Parabolic interpolation for sub-sample period accuracy ---
        let y0 = bestLag > minLag     ? acf[bestLag - 1] : acf[bestLag]
        let y1 = acf[bestLag]
        let y2 = bestLag < maxLag - 1 ? acf[bestLag + 1] : acf[bestLag]
        let denom = 2 * (2 * y1 - y0 - y2)
        let shift = denom != 0 ? (y2 - y0) / denom : 0
        let refinedLag = Float(bestLag) + shift

        return (hz: sampleRate / refinedLag, confidence: bestValue)
    }
}
