import SwiftUI

/// Chromatic tuner — shows detected note, Hz, and cents deviation needle.
/// Enables the mic tap on appear and removes it on disappear, consistent
/// with the orange-dot policy: only claim the mic when this view is active.
public struct TunerView: View {
    @ObservedObject var audio: AudioEngineManager

    // In-tune steady-state: true after the note holds within ±10 cents for 0.8 s.
    @State private var inTuneSteady = false
    // Prevents the chime firing again until the note leaves and re-enters the zone.
    @State private var chimeFired = false
    @State private var chimeTask: Task<Void, Never>? = nil

    public init(audio: AudioEngineManager) {
        self.audio = audio
    }

    private var cents: Float {
        NoteConverter.centsDeviation(fromHz: audio.detectedHz)
    }

    private var isCurrentlyInTune: Bool {
        audio.detectedHz > 0 && abs(cents) <= 10
    }

    private var tuningColor: Color {
        guard audio.detectedHz > 0 else { return EarTrainColors.textDisabled }
        if inTuneSteady { return EarTrainColors.inTuneFlash }
        let a = abs(cents)
        if a <= 10 { return EarTrainColors.success }
        if a <= 25 { return EarTrainColors.accent }
        return EarTrainColors.error
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                noteCard
                gaugeCard
                levelCard
            }
            .padding(24)
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EarTrainColors.bg)
        .task { audio.enableMicTap() }
        .onDisappear { audio.disableMicTap() }
        .onChange(of: isCurrentlyInTune) { inTune in
            if inTune {
                chimeTask?.cancel()
                chimeTask = Task {
                    do {
                        try await Task.sleep(for: .seconds(0.8))
                        withAnimation(.easeIn(duration: 0.15)) { inTuneSteady = true }
                        if !chimeFired {
                            chimeFired = true
                            await audio.playInTuneChime()
                        }
                    } catch {}
                }
            } else {
                chimeTask?.cancel()
                withAnimation(.easeOut(duration: 0.2)) { inTuneSteady = false }
                chimeFired = false
            }
        }
    }

    // MARK: - Note card

    private var noteCard: some View {
        VStack(spacing: 6) {
            Text("TUNER")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(EarTrainColors.textSecondary)

            Text(audio.detectedHz > 0 ? audio.detectedNote : "--")
                .font(.system(size: 72, weight: .black))
                .foregroundColor(tuningColor)
                .monospacedDigit()
                .animation(.easeInOut(duration: 0.08), value: audio.detectedNote)
                .scaleEffect(inTuneSteady ? 1.10 : 1.0)
                .shadow(color: inTuneSteady ? EarTrainColors.inTuneFlash.opacity(0.6) : .clear,
                        radius: 12)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: inTuneSteady)
                .frame(minHeight: 84)

            Text(audio.detectedHz > 0
                 ? String(format: "%.1f Hz", audio.detectedHz)
                 : "-- Hz")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(EarTrainColors.textSecondary)
                .monospacedDigit()

            Group {
                if audio.detectedHz > 0 {
                    Text(abs(cents) <= 10 ? "In tune" : String(format: "%+.0f cents", cents))
                        .foregroundColor(tuningColor)
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    Text("Play a note on your guitar")
                        .foregroundColor(EarTrainColors.textDisabled)
                        .font(.system(size: 14))
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(EarTrainColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Gauge card

    private var gaugeCard: some View {
        VStack(spacing: 16) {
            Text("CENTS DEVIATION")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(EarTrainColors.textSecondary)

            TunerNeedle(cents: audio.detectedHz > 0 ? cents : nil)

            HStack {
                Text("−50")
                Spacer()
                Text("−25")
                Spacer()
                Text("0")
                Spacer()
                Text("+25")
                Spacer()
                Text("+50")
            }
            .font(.system(size: 11))
            .foregroundColor(EarTrainColors.textDisabled)
        }
        .padding(24)
        .background(EarTrainColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Level card

    private var levelCard: some View {
        VStack(spacing: 8) {
            Text("INPUT LEVEL")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(EarTrainColors.textSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(EarTrainColors.bg)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(levelBarColor)
                        .frame(width: geo.size.width * CGFloat(min(audio.amplitude * 4, 1)))
                        .animation(.linear(duration: 0.05), value: audio.amplitude)
                }
            }
            .frame(height: 8)
        }
        .padding(20)
        .background(EarTrainColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var levelBarColor: Color {
        audio.amplitude > 0.25 ? EarTrainColors.error
            : audio.amplitude > 0.08 ? EarTrainColors.success
            : EarTrainColors.textDisabled
    }
}

// MARK: - Needle gauge

private struct TunerNeedle: View {
    /// nil = no signal; needle parks at center at reduced opacity.
    let cents: Float?

    // Zones: red 0–25%, amber 25–40%, green 40–60%, amber 60–75%, red 75–100%.
    private static let zoneGradient = LinearGradient(
        stops: [
            .init(color: EarTrainColors.error.opacity(0.55),   location: 0.00),
            .init(color: EarTrainColors.error.opacity(0.55),   location: 0.25),
            .init(color: EarTrainColors.accent.opacity(0.65),  location: 0.40),
            .init(color: EarTrainColors.success.opacity(0.70), location: 0.50),
            .init(color: EarTrainColors.accent.opacity(0.65),  location: 0.60),
            .init(color: EarTrainColors.error.opacity(0.55),   location: 0.75),
            .init(color: EarTrainColors.error.opacity(0.55),   location: 1.00),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let needleOffset = offsetX(totalWidth: w)

            ZStack {
                // Color track
                Self.zoneGradient
                    .frame(height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // Center tick
                Rectangle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 1, height: h)

                // Needle
                Capsule()
                    .fill(Color.white)
                    .frame(width: 4, height: h)
                    .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                    .offset(x: needleOffset)
                    .animation(.spring(response: 0.14, dampingFraction: 0.75), value: needleOffset)
                    .opacity(cents != nil ? 1.0 : 0.22)
            }
        }
        .frame(height: 48)
    }

    /// Maps cents (−50…+50) to a ZStack offset relative to center.
    /// −50 → −halfWidth, 0 → 0, +50 → +halfWidth.
    private func offsetX(totalWidth: CGFloat) -> CGFloat {
        let c = cents.map { max(-50, min(50, $0)) } ?? 0
        return CGFloat(c / 50) * (totalWidth / 2)
    }
}
