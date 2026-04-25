import SwiftUI

/// Step 3 minimal test: open mic, detect pitch, display note name + Hz.
/// This will be replaced by HomeView in Phase 1.
public struct PitchMonitorView: View {
    @StateObject private var audio = AudioEngineManager()

    public init() {}

    public var body: some View {
        VStack(spacing: 32) {
            header
            pitchReadout
            amplitudeBar
            playIntervalButton
            keepAliveBadge
            if let err = audio.engineError {
                errorBanner(err)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { audio.start() }
        .onDisappear { audio.stop() }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 4) {
            Text("PITCH MONITOR")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(EarTrainColors.textSecondary)
            Text("Play a note on your guitar")
                .font(.system(size: 14))
                .foregroundColor(EarTrainColors.textSecondary)
        }
    }

    private var pitchReadout: some View {
        VStack(spacing: 8) {
            Text(audio.detectedNote)
                .font(.system(size: 72, weight: .black))
                .foregroundColor(EarTrainColors.textPrimary)
                .monospacedDigit()
                .animation(.none, value: audio.detectedNote)

            Text(audio.detectedHz > 0
                 ? String(format: "%.1f Hz", audio.detectedHz)
                 : "-- Hz")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(EarTrainColors.textSecondary)
                .monospacedDigit()
        }
        .frame(minWidth: 200)
        .padding(32)
        .background(EarTrainColors.surface)
        .cornerRadius(12)
    }

    private var amplitudeBar: some View {
        VStack(spacing: 8) {
            Text("INPUT LEVEL")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(EarTrainColors.textSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(EarTrainColors.surface)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(min(audio.amplitude * 4, 1)))
                        .animation(.linear(duration: 0.05), value: audio.amplitude)
                }
            }
            .frame(height: 8)
            .frame(maxWidth: 320)
        }
    }

    private var barColor: Color {
        audio.amplitude > 0.25 ? EarTrainColors.error
            : audio.amplitude > 0.08 ? EarTrainColors.success
            : EarTrainColors.textDisabled
    }

    // MARK: - Interval playback test (step 4)

    // Plays A4 → E5 (perfect fifth) as a quick audibility check.
    private var playIntervalButton: some View {
        Button {
            Task {
                await audio.intervalPlayer.playInterval(
                    rootHz: 440.0,    // A4
                    intervalHz: 659.25 // E5 — P5 above A4
                )
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: audio.intervalPlayer.isPlaying ? "speaker.wave.2.fill" : "play.circle")
                Text(audio.intervalPlayer.isPlaying ? "Playing…" : "Play A4 → E5 (P5)")
            }
            .font(.system(size: 14, weight: .semibold))
        }
        .buttonStyle(AccentButtonStyle())
        .disabled(audio.intervalPlayer.isPlaying)
    }

    // MARK: - CI Keep-alive indicator

    private var keepAliveBadge: some View {
        Toggle(isOn: $audio.keepAliveEnabled) {
            HStack(spacing: 6) {
                Circle()
                    .fill(audio.keepAliveActive ? EarTrainColors.success : EarTrainColors.textDisabled)
                    .frame(width: 7, height: 7)
                Text(audio.keepAliveActive
                     ? "CI keep-alive: active"
                     : "CI keep-alive: off")
                    .font(.system(size: 12))
                    .foregroundColor(EarTrainColors.textSecondary)
            }
        }
        .toggleStyle(.switch)
        .tint(EarTrainColors.success)
        .frame(maxWidth: 260)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .font(.system(size: 13))
        }
        .foregroundColor(EarTrainColors.error)
        .padding(12)
        .background(EarTrainColors.surface)
        .cornerRadius(8)
    }
}
